import AVFoundation
import Combine
import CoreMotion
import FoGCore
import FoGKit
import Foundation
import os
import UIKit

private let diagLog = os.Logger(subsystem: "com.example.fogcue", category: "PhoneDetection")

/// Codable mirror of the demo_meta.json bundled with the app (snake_case JSON, decoded the
/// same way the parity fixtures are: convertFromSnakeCase).
private struct DemoMeta: Decodable {
    let recording: String
    let dataset: String?
    let segmentStartS: Double
    let sampleRate: Double
    let events: [DemoEvent]
    let detectorConfig: DetectorConfig?
    struct DemoEvent: Decodable {
        let onsetT: Double
        let confirmedT: Double
        let endT: Double
    }
}

/// Beat cueing on the phone itself, for when no watch is paired. Audio + haptics from the
/// handheld device. One class serves three jobs so event journaling has a single path:
/// - manual beat (always available)
/// - automatic detection in walk mode (CMMotionManager at 64 Hz -> the same FoGCore pipeline
///   the watch runs; a phone in a trouser pocket is the closest consumer stand-in for the
///   thigh placement the model was trained and validated on)
/// - the 2-minute setup walk (calibration windows + CMPedometer cadence, same math as watch)
/// iOS only permits high-rate motion sampling while the app is active, so detection runs in
/// the foreground; an active cue's audio keeps playing if the screen locks (background audio).
@MainActor
final class PhoneDetectionService: ObservableObject {
    enum Mode: Equatable {
        case idle
        case manualBeat
        case walkMode(active: Bool) // active = automatic detection running
        case calibrating
    }

    enum Event {
        case cueStarted(DetectedFreeze)
        case cueEnded(DetectedFreeze, CueEndReason)
        case manualBeatStarted(id: UUID)
        case manualBeatEnded(id: UUID, start: Date, end: Date, endReason: CueEndReason)
        case calibrationFinished(ok: Bool, cadence: Double?, windows: [WindowFeatures])
        case unavailable(String)
    }

    /// Maps pipeline-relative time (feature tEnd/confirmedT) to absolute time.
    func absoluteTime(for t: Double) -> Date { startedAt.addingTimeInterval(t) }

    static let sampleRate = 64.0
    static let calibrationSec: Double = 120

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var calibrationProgress: Double = 0
    @Published private(set) var beatActive = false
    /// Distinct completion signal fired by the service itself — the view never has to catch
    /// a progress tick to know the walk is done.
    @Published private(set) var calibrationResult: (ok: Bool, cadence: Double?)?

    /// Live gait-window count during the setup walk so the screen can show collecting progress.
    @Published private(set) var gaitWindowCount = 0
    /// Total accelerometer samples received since pipeline start — 0 means the sensor is
    /// delivering nothing (almost always denied Motion & Fitness permission).
    @Published private(set) var sensorSampleCount = 0
    /// Live per-window diagnostics for the setup-walk screen: shows what the pipeline sees.
    @Published private(set) var windowsEmitted = 0
    @Published private(set) var lastDominantFreq: Double = 0
    @Published private(set) var lastLocoPower: Double = 0
    @Published private(set) var lastFreezeIndex: Double = 0
    /// Last detector probability (0-1) — the live "how freeze-like does this look" number.
    @Published private(set) var lastProb: Double = 0
    /// Last failure that aborted a start attempt — surfaced in the UI, never silent.
    @Published private(set) var lastError: String?
    /// The detector configuration actually in use (profile + personal overrides) — shown in
    /// the walk-mode meter so sensitivity changes are verifiable, not invisible.
    @Published private(set) var activeConfig: DetectorConfig?
    @Published private(set) var activeProfileName: String = ""

    var onEvent: ((Event) -> Void)?
    var settings = CueSettings()
    /// User cue-delay preference applied on top of the profile's confirmSec (nil = default).
    var confirmOverride: Double? = nil

    var isAvailable: Bool { motion.isAccelerometerAvailable }

    private let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private let audio = PhoneCueAudio()
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)
    private var beatTimer: Timer?

    private var window: SlidingWindow?
    private var detector: FoGDetector?
    private var startedAt = Date()
    private var lastT = 0.0

    private var calibrationStart: Date?
    private var calibrationWindows: [WindowFeatures] = []
    private var cadenceSamples: [Double] = []

    private var manualEventId: UUID?
    private var manualStart: Date?
    private var calibrationProgressTimer: Timer?

    // MARK: Manual beat (always available, no watch needed)

    func startManualBeat() {
        guard !beatActive else { return }
        if mode != .calibrating { mode = .manualBeat }
        beatActive = true
        playBeatLoop()
        let id = UUID()
        manualEventId = id
        manualStart = Date()
        onEvent?(.manualBeatStarted(id: id))
    }

    func stopManualBeat(endReason: CueEndReason = .manual) {
        guard manualEventId != nil else { return }
        stopBeatSounds()
        let id = manualEventId!, start = manualStart!
        onEvent?(.manualBeatEnded(id: id, start: start, end: Date(), endReason: endReason))
        manualEventId = nil
        manualStart = nil
        if mode == .manualBeat { mode = .idle }
    }

    // MARK: Walk mode (automatic detection in the foreground)

    func startWalkMode() {
        guard isAvailable else { onEvent?(.unavailable("Motion sensor unavailable")); return }
        guard let profiles = try? DetectorProfiles.bundled() else {
            onEvent?(.unavailable("Detector model missing"))
            return
        }
        var overrides = settings.personalConfig
        if let o = confirmOverride {
            var cfg = overrides ?? profiles.config(for: settings.sensitivity)
            cfg.confirmSec = o
            overrides = cfg
        }
        let detector = try? profiles.makeDetector(profile: settings.sensitivity, overrides: overrides)
        activeConfig = detector?.cfg
        activeProfileName = settings.personalConfig != nil ? "personalised" : settings.sensitivity.rawValue
        Task { @MainActor [weak self] in
            self?.startPipeline(detector: detector)
        }
        mode = .walkMode(active: detector != nil)
        // Self-testing in a pocket requires the screen to stay on: iOS suspends motion
        // sampling when the app is locked. Reset on exit.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopWalkMode() {
        endAutomaticCue(reason: .manual)
        stopPipeline()
        UIApplication.shared.isIdleTimerDisabled = false
        activeConfig = nil
        activeProfileName = ""
        if case .walkMode = mode { mode = .idle }
    }

    // MARK: Setup walk

    func startSetupWalk() {
        diagLog.info("startSetupWalk enter: isAvailable=\(self.isAvailable) deviceMotionAvailable=\(self.motion.isDeviceMotionAvailable) mode=\(String(describing: self.mode))")
        if mode == .calibrating { // restart-safe: a stale abandoned walk must not block a new one
            diagLog.info("startSetupWalk: cancelling stale calibration first")
            cancelSetupWalk()
        }
        lastError = nil
        guard motion.isAccelerometerAvailable || motion.isDeviceMotionAvailable else {
            lastError = "No motion sensor is available to this app right now."
            diagLog.error("startSetupWalk ABORT: no accelerometer and no device motion")
            onEvent?(.unavailable(lastError!))
            return
        }
        calibrationStart = Date()
        calibrationWindows = []
        cadenceSamples = []
        calibrationProgress = 0
        mode = .calibrating
        if CMPedometer.isCadenceAvailable() {
            // First call surfaces the system Motion permission prompt; harmless if already granted.
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let c = data?.currentCadence?.doubleValue, c > 0 else { return }
                Task { @MainActor [weak self] in self?.cadenceSamples.append(c * 60) }
            }
        }
        // Motion permission also needs a moment of approval on first use; start sampling after
        // the run loop settles so we never mutate published state inside a view update.
        Task { @MainActor [weak self] in
            self?.startPipeline(detector: nil) // features only, exactly like the watch's setup walk
            self?.startProgressTimer()
        }
    }

    private func startProgressTimer() {
        calibrationProgressTimer?.invalidate()
        calibrationProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.calibrationStart else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.calibrationProgress = min(0.999, elapsed / Self.calibrationSec) // completion is event-driven, not percent-triggered
                if elapsed >= Self.calibrationSec {
                    self.calibrationProgress = 1
                    self.finishSetupWalk()
                }
            }
        }
    }

    func cancelSetupWalk() {
        guard mode == .calibrating else { return }
        calibrationProgressTimer?.invalidate()
        calibrationProgressTimer = nil
        pedometer.stopUpdates()
        stopPipeline()
        calibrationWindows = []
        calibrationStart = nil
        calibrationProgress = 0
        gaitWindowCount = 0
        mode = .idle
    }

    /// Runs the watch's identical Calibration.calibrate on the collected windows and returns
    /// (ok, cadence). Mutates settings: personal detector config + recommended BPM.
    @discardableResult
    func finishSetupWalk() -> (ok: Bool, cadence: Double?) {
        guard mode == .calibrating, let start = calibrationStart,
              Date().timeIntervalSince(start) >= Self.calibrationSec - 2 else { return (false, nil) }
        calibrationProgressTimer?.invalidate()
        calibrationProgressTimer = nil
        pedometer.stopUpdates()
        stopPipeline()
        let cadence: Double? = cadenceSamples.isEmpty ? nil : {
            let s = cadenceSamples.sorted()
            return s[s.count / 2]
        }()
        calibrationStart = nil
        mode = .idle
        defer {
            calibrationWindows = []
            calibrationProgress = 0
            gaitWindowCount = 0
        }
        guard let profiles = try? DetectorProfiles.bundled() else {
            calibrationResult = (false, cadence)
            onEvent?(.calibrationFinished(ok: false, cadence: cadence, windows: []))
            return (false, cadence)
        }
        let base = profiles.config(for: settings.sensitivity)
        let result = Calibration.calibrate(walk: calibrationWindows, base: base, model: profiles.model)
        if result.ok {
            settings.personalConfig = result.config
            if let c = cadence {
                // RAS evidence (EVIDENCE_LOG E7): cueing ~10% above preferred cadence reduced
                // freezing most reliably. Personalise, then nudge above their own rhythm.
                settings.bpm = CadencePolicy.recommendedBPM(cadenceStepsPerMin: c, offsetPercent: 10)
            }
        }
        calibrationResult = (result.ok, cadence)
        onEvent?(.calibrationFinished(ok: result.ok, cadence: cadence, windows: windowsSnapshot))
        return (result.ok, cadence)
    }

    private var windowsSnapshot: [WindowFeatures] { calibrationWindows }

    /// True when the current walk is a demo replay of recorded patient data.
    @Published private(set) var demoActive = false
    /// Relative replay time in seconds (for the demo progress readout).
    @Published private(set) var demoElapsed: Double = 0
    private var demoSamples: [AccelSample]?
    private var demoIndex = 0
    private var demoTimer: Timer?
    private var demoSegmentStart = 0.0

    /// Replays a recorded patient freeze segment (Daphnet S02R02 thigh sensor) through the
    /// IDENTICAL live pipeline — same windows, detector, gates, cue engine, journaling.
    func startDemoReplay() {
        guard !beatActive else { return }
        guard let metaURL = Bundle.main.url(forResource: "demo_meta", withExtension: "json"),
              let csvURL = Bundle.main.url(forResource: "demo_segment", withExtension: "csv") else {
            lastError = "Demo data missing from app bundle."
            return
        }
        guard let profiles = try? DetectorProfiles.bundled() else {
            lastError = "Detector model missing"
            return
        }
        // The reference configuration from the research pipeline guarantees the same outcome
        // the parity test verifies on this exact segment (personal overrides not applied so
        // the demo always shows the published behavior).
        var demoConfig = DetectorConfig()
        var recording = "patient recording"
        if let data = try? Data(contentsOf: metaURL),
           let meta = try? DetectorProfiles.decoder().decode(DemoMeta.self, from: data) {
            if let dc = meta.detectorConfig { demoConfig = dc }
            recording = meta.recording
            demoSegmentStart = meta.segmentStartS
        }
        guard let detector = try? FoGDetector(config: demoConfig, model: profiles.model) else {
            lastError = "Could not build demo detector"
            return
        }
        do {
            let text = try String(contentsOf: csvURL, encoding: .utf8)
            demoSamples = try text.split(separator: "\n").map { line in
                let c = line.split(separator: ",").map { Double($0)! }
                return AccelSample(x: c[0], y: c[1], z: c[2])
            }
        } catch {
            lastError = "Demo data unreadable: \(error.localizedDescription)"
            return
        }
        self.detector = detector
        self.window = SlidingWindow(windowSec: demoConfig.windowSec, hopSec: demoConfig.hopSec, sampleRate: Self.sampleRate)
        startedAt = Date()
        lastT = 0
        windowsEmitted = 0
        gaitWindowCount = 0
        demoIndex = 0
        demoElapsed = 0
        demoActive = true
        lastError = nil
        demoTimer?.invalidate()
        // Real-time pacing: 16 samples every 250 ms = 64 Hz, exactly like walk mode.
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.demoTick() }
        }
        if let t = demoTimer { RunLoop.main.add(t, forMode: .common) }
        mode = .walkMode(active: true)
        diagLog.info("demo replay started")
    }

    private func demoTick() {
        guard let samples = demoSamples, demoIndex < samples.count else {
            stopDemoReplay(endReason: .timeout)
            return
        }
        let end = min(demoIndex + 4, samples.count) // 4 samples per 250 ms tick = 64 Hz
        for i in demoIndex..<end { processRaw(samples[i]) }
        demoIndex = end
        demoElapsed = Double(demoIndex) / Self.sampleRate
    }

    func stopDemoReplay(endReason: CueEndReason = .manual) {
        demoTimer?.invalidate()
        demoTimer = nil
        endAutomaticCue(reason: endReason)
        stopPipeline()
        demoSamples = nil
        demoActive = false
        demoElapsed = 0
        if case .walkMode = mode { mode = .idle }
        diagLog.info("demo replay stopped")
    }

    /// process() without the sensorSampleCount increment (demo samples are not phone samples).
    private func processRaw(_ s: AccelSample) {
        guard let f = window?.push(s) else { return }
        windowsEmitted += 1
        lastDominantFreq = f.dominantFreq
        lastLocoPower = f.locoPower
        lastFreezeIndex = f.freezeIndex
        lastT = f.tEnd
        guard var d = detector else { return }
        let out = d.update(f)
        detector = d
        switch out {
        case .cueStarted(let e):
            beatActive = true
            playBeatLoop()
            onEvent?(.cueStarted(e))
        case .cueEnded(let e):
            stopBeatSounds()
            onEvent?(.cueEnded(e, e.endReason ?? .timeout))
        case .none: break
        }
    }

    // MARK: Pipeline

    private func startPipeline(detector newDetector: FoGDetector?) {
        stopPipeline()
        let cfg = newDetector?.cfg ?? DetectorConfig()
        detector = newDetector
        startedAt = Date()
        lastT = 0
        window = SlidingWindow(windowSec: cfg.windowSec, hopSec: cfg.hopSec, sampleRate: Self.sampleRate)
        sensorSampleCount = 0
        windowsEmitted = 0
        gaitWindowCount = 0
        motion.accelerometerUpdateInterval = 1.0 / Self.sampleRate
        if motion.isAccelerometerAvailable {
            motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
                guard let self, let a = data?.acceleration else { return }
                Task { @MainActor [weak self] in
                    self?.process(AccelSample(x: a.x, y: a.y, z: a.z))
                }
            }
            diagLog.info("pipeline started: raw accelerometer source (detector=\(newDetector != nil))")
        } else if motion.isDeviceMotionAvailable {
            // Fallback: userAcceleration is gravity-removed acceleration in G — actually the
            // closer match to the gravity-free Daphnet acc_g data the model was trained on.
            motion.deviceMotionUpdateInterval = 1.0 / Self.sampleRate
            motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
                guard let self, let u = data?.userAcceleration else { return }
                Task { @MainActor [weak self] in
                    self?.process(AccelSample(x: u.x, y: u.y, z: u.z))
                }
            }
            diagLog.info("pipeline started: device-motion userAcceleration source (detector=\(newDetector != nil))")
        } else {
            diagLog.error("pipeline NOT started: no motion source available")
            onEvent?(.unavailable("No motion source available"))
        }
    }

    private func stopPipeline() {
        motion.stopAccelerometerUpdates()
        window = nil
        detector = nil
    }

    private func process(_ s: AccelSample) {
        sensorSampleCount += 1
        guard let f = window?.push(s) else { return }
        windowsEmitted += 1
        lastDominantFreq = f.dominantFreq
        lastLocoPower = f.locoPower
        lastFreezeIndex = f.freezeIndex
        if windowsEmitted % 4 == 0 {
            diagLog.info("walk windows=\(self.windowsEmitted) freq=\(f.dominantFreq, format: .fixed(precision: 2)) loco=\(f.locoPower, format: .exponential(precision: 2)) fi=\(f.freezeIndex, format: .fixed(precision: 2)) gait=\(self.gaitWindowCount)")
        }
        lastT = f.tEnd
        guard var d = detector else {
            if mode == .calibrating {
                calibrationWindows.append(f)
                let cfg = DetectorConfig()
                if Calibration.gaitLike(f, cfg) { gaitWindowCount += 1 }
            }
            return
        }
        let out = d.update(f)
        detector = d
        lastProb = d.lastScore
        if windowsEmitted % 4 == 0 {
            diagLog.info("walk windows=\(self.windowsEmitted) freq=\(f.dominantFreq, format: .fixed(precision: 2)) loco=\(f.locoPower, format: .exponential(precision: 2)) fi=\(f.freezeIndex, format: .fixed(precision: 2)) prob=\(d.lastScore, format: .fixed(precision: 2)) gait=\(self.gaitWindowCount)")
        }
        switch out {
        case .cueStarted(let e):
            beatActive = true
            playBeatLoop()
            onEvent?(.cueStarted(e))
        case .cueEnded(let e):
            stopBeatSounds()
            onEvent?(.cueEnded(e, e.endReason ?? .timeout))
        case .none: break
        }
    }

    private func endAutomaticCue(reason: CueEndReason) {
        guard let d = detector, let active = d.activeFreeze else { return }
        var mutable = d
        _ = mutable.stopManually(at: lastT)
        detector = mutable
        stopBeatSounds()
        onEvent?(.cueEnded(active, reason))
    }

    // MARK: Beat sounds & haptics

    /// Timer-driven beat: one click + one haptic per beat at the configured tempo.
    /// Audio click via AVAudioPlayer, haptic via UIImpactFeedbackGenerator (works while the
    /// app is active; iOS pauses timers when suspended — a documented limitation).
    private func playBeatLoop() {
        audio.prepare(style: settings.audioStyle, volume: Float(settings.volume))
        haptic.prepare()
        beatTimer?.invalidate()
        beatTimer = Timer.scheduledTimer(withTimeInterval: 60.0 / Double(max(settings.bpm, 1)), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.beatActive else { return }
                self.audio.tick()
                self.haptic.impactOccurred(intensity: 1)
            }
        }
        if let t = beatTimer { RunLoop.main.add(t, forMode: .common) }
        audio.tick() // first beat immediately
        haptic.impactOccurred(intensity: 1)
    }

    private func stopBeatSounds() {
        audio.stop()
        beatTimer?.invalidate()
        beatTimer = nil
        beatActive = false
    }

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        q.name = "fogcue.phone"
        return q
    }()
}

/// Metronome audio for cueing from the phone speaker. Honors the caregiver's sound style
/// (metronome click / soft drum / spoken count) and volume — previously the phone always
/// played the same click regardless of settings (a real gap vs the watch's CueEngine).
final class PhoneCueAudio {
    private var player: AVAudioPlayer?
    private var synthesizer = AVSpeechSynthesizer()
    private var style: AudioStyle = .metronome
    private var volume: Float = 0.8
    private var beatNumber = 0
    private let numberWords = ["one", "two", "three", "four"]

    func prepare(style: AudioStyle, volume: Float) {
        self.style = style
        self.volume = volume
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        switch style {
        case .voiceCount: break // speech, no WAV player
        default:
            let wav: Data = style == .drum ? Self.drumWAV() : MetronomePreview.clickWAV()
            player = try? AVAudioPlayer(data: wav)
            player?.volume = volume
            player?.prepareToPlay()
        }
    }

    /// One beat per call; the beat timer drives tempo.
    func tick() {
        switch style {
        case .voiceCount:
            let word = numberWords[beatNumber % numberWords.count]
            let u = AVSpeechUtterance(string: word)
            u.volume = volume
            u.rate = 0.5
            synthesizer.speak(u)
        default:
            player?.currentTime = 0
            player?.play()
        }
        beatNumber += 1
    }

    func stop() {
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 120 Hz decaying thump — a "soft drum" beat, distinct from the 1 kHz click.
    static func drumWAV(sampleRate: Int = 44_100) -> Data {
        let n = sampleRate / 8 // 125 ms
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            let v = Int16(sin(2 * .pi * 120 * t) * exp(-t / 0.04) * 0.9 * Double(Int16.max))
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
}
