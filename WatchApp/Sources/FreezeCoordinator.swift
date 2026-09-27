import FoGCore
import FoGKit
import Foundation

/// Owns the watch-side state: walk mode, active cue, the post-cue "Was that a freeze?" prompt,
/// and calibration. All UI reads from here.
@MainActor
final class FreezeCoordinator: ObservableObject {
    enum Mode: Equatable { case idle, monitoring, calibrating }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var activeEvent: FoGEventRecord?
    @Published var pendingLabel: FoGEventRecord?
    @Published private(set) var settings: CueSettings
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var calibrationMessage: String?
    @Published private(set) var errorMessage: String?

    let workout = WorkoutSessionManager()
    let cue = CueEngine()
    private let pipeline = DetectionPipeline()
    private let sync = WatchSync()
    private let profiles: DetectorProfiles?
    private var calibrationWindows: [WindowFeatures] = []
    private var calibrationStart: Date?
    private let pedometer = CadenceMeter()

    static let calibrationSec = 120.0
    private static let settingsKey = "fogcue.settings"

    init() {
        profiles = try? DetectorProfiles.bundled()
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let s = try? JSONDecoder().decode(CueSettings.self, from: data) {
            settings = s
        } else {
            settings = CueSettings()
        }
        if profiles == nil { errorMessage = "Detector files missing. Only the Help button will work." }
        pipeline.onOutput = { [weak self] out in MainActor.assumeIsolated { self?.handle(out) } }
        sync.onMessage = { [weak self] msg in MainActor.assumeIsolated { self?.handle(msg) } }
        sync.activate()
    }

    func requestPermissions() async {
        await workout.requestAuthorization()
    }

    // MARK: Walk mode

    func startMonitoring() {
        guard mode == .idle else { return }
        workout.start()
        mode = .monitoring
        pipeline.start(detector: settings.autoDetectEnabled ? makeDetector() : nil, calibrating: false,
                       record: settings.studyRecordingEnabled)
    }

    func stopMonitoring() {
        endCue(reason: .manual)
        pipeline.stop()
        workout.stop()
        mode = .idle
    }

    private func makeDetector() -> FoGDetector? {
        guard let profiles else { return nil }
        return try? profiles.makeDetector(profile: settings.sensitivity, overrides: settings.personalConfig)
    }

    // MARK: Cues

    /// "Help me walk" button: always available, no detection involved.
    func manualCue() {
        guard activeEvent == nil else { return }
        begin(FoGEventRecord(start: Date(), source: .manual))
    }

    /// Stop button on the cue screen.
    func stopCue() {
        if activeEvent?.source == .automatic {
            pipeline.stopActiveCue()
        } else {
            endCue(reason: .manual)
        }
    }

    private func begin(_ record: FoGEventRecord) {
        activeEvent = record
        pendingLabel = nil
        cue.start(settings)
        sync.send(.eventStarted(record))
    }

    private func endCue(reason: CueEndReason, at date: Date = Date(), peak: Double? = nil) {
        guard var e = activeEvent else { return }
        cue.stop()
        e.end = date
        e.endReason = reason
        if let peak { e.peakScore = peak }
        activeEvent = nil
        sync.send(.eventEnded(e))
        if e.source == .automatic { pendingLabel = e }
    }

    func label(_ record: FoGEventRecord, _ label: EventLabel) {
        pendingLabel = nil
        sync.send(.label(id: record.id, label: label))
    }

    private func handle(_ out: DetectionPipeline.Output) {
        switch out {
        case .cueStarted(let f, let date):
            guard activeEvent == nil else { return }
            begin(FoGEventRecord(start: date, source: .automatic, peakScore: f.peakScore))
        case .cueEnded(let f, let date):
            guard activeEvent?.source == .automatic else { return }
            endCue(reason: f.endReason ?? .timeout, at: date, peak: f.peakScore)
        case .calibrationWindow(let w):
            calibrationWindows.append(w)
            if let start = calibrationStart {
                calibrationProgress = min(1, Date().timeIntervalSince(start) / Self.calibrationSec)
                if calibrationProgress >= 1 { finishCalibration() }
            }
        case .recordingFinished(let url):
            sync.sendFile(url)
        }
    }

    // MARK: Calibration (guided 2-minute normal walk)

    func startCalibration() {
        guard mode == .idle else { return }
        calibrationWindows = []
        calibrationProgress = 0
        calibrationMessage = nil
        calibrationStart = Date()
        workout.start()
        pedometer.start()
        mode = .calibrating
        pipeline.start(detector: nil, calibrating: true)
    }

    func cancelCalibration() {
        pipeline.stop()
        pedometer.stop()
        workout.stop()
        mode = .idle
    }

    private func finishCalibration() {
        pipeline.stop()
        let cadence = pedometer.stop()
        workout.stop()
        mode = .idle
        guard let profiles else { return }
        let base = profiles.config(for: settings.sensitivity)
        let result = Calibration.calibrate(walk: calibrationWindows, base: base, model: profiles.model)
        var s = settings
        if result.ok {
            s.personalConfig = result.config
            if let cadence {
                // Same 110% evidence-anchored tempo as the phone path (EVIDENCE_LOG E7).
                s.bpm = CadencePolicy.recommendedBPM(cadenceStepsPerMin: cadence, offsetPercent: 10)
            }
            calibrationMessage = "Done. Beat set to \(s.bpm) per minute."
        } else {
            calibrationMessage = "Not enough walking was detected. Please try again and walk at a normal pace."
        }
        apply(s, broadcast: true)
        sync.send(.calibrationSamples(CalibrationUpload(recordedAt: Date(), cadenceStepsPerMin: cadence, features: calibrationWindows)))
    }

    // MARK: Settings

    private func handle(_ m: SyncMessage) {
        if case .settings(let s) = m { apply(s, broadcast: false) }
    }

    private func apply(_ s: CueSettings, broadcast: Bool) {
        settings = s
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
        if broadcast { sync.send(.settings(s)) }
        if mode == .monitoring {
            pipeline.start(detector: s.autoDetectEnabled ? makeDetector() : nil, calibrating: false,
                           record: s.studyRecordingEnabled)
        }
    }
}
