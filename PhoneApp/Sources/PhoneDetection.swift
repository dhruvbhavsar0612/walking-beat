import AVFoundation
import Combine
import CoreMotion
import FoGCore
import FoGKit
import Foundation
import os
import UIKit

private let diagLog = os.Logger(subsystem: "com.example.fogcue", category: "PhoneDetection")

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
    /// Last failure that aborted a start attempt — surfaced in the UI, never silent.
    @Published private(set) var lastError: String?

    var onEvent: ((Event) -> Void)?
    var settings = CueSettings()

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
        let detector = try? profiles.makeDetector(profile: settings.sensitivity, overrides: settings.personalConfig)
        Task { @MainActor [weak self] in
            self?.startPipeline(detector: detector)
        }
        mode = .walkMode(active: detector != nil)
    }

    func stopWalkMode() {
        endAutomaticCue(reason: .manual)
        stopPipeline()
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
            if let c = cadence { settings.bpm = CadencePolicy.recommendedBPM(cadenceStepsPerMin: c) }
        }
        calibrationResult = (result.ok, cadence)
        onEvent?(.calibrationFinished(ok: result.ok, cadence: cadence, windows: windowsSnapshot))
        return (result.ok, cadence)
    }

    private var windowsSnapshot: [WindowFeatures] { calibrationWindows }

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
        audio.prepare()
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

/// Metronome audio for cueing from the phone speaker; click synthesis shared with the
/// caregiver preview so no audio assets ship.
final class PhoneCueAudio {
    private var player: AVAudioPlayer?

    func prepare() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if player == nil {
            player = try? AVAudioPlayer(data: MetronomePreview.clickWAV())
            player?.prepareToPlay()
        }
    }

    /// One click per call; the beat timer drives tempo.
    func tick() {
        player?.currentTime = 0
        player?.play()
    }

    func stop() {
        player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
