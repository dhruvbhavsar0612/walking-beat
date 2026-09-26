import CoreMotion
import FoGCore
import Foundation

/// Accelerometer -> sliding window -> detector, confined to one serial queue.
/// The detector was validated at 64 Hz on Daphnet, so the watch samples at the same rate.
final class DetectionPipeline {
    static let sampleRate = 64.0

    enum Output {
        case cueStarted(DetectedFreeze, Date)
        case cueEnded(DetectedFreeze, Date)
        case calibrationWindow(WindowFeatures)
        case recordingFinished(URL)
    }

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        q.name = "fogcue.detection"
        return q
    }()

    private var window: SlidingWindow?
    private var detector: FoGDetector?
    private var startedAt = Date()
    private var calibrating = false
    private var recorder: FeatureRecorder?
    private var lastT = 0.0

    var onOutput: ((Output) -> Void)?

    var isAvailable: Bool { motion.isAccelerometerAvailable }

    /// `detector == nil` runs in calibration-only mode (no cues).
    func start(detector: FoGDetector?, calibrating: Bool, record: Bool = false) {
        stop()
        let cfg = detector?.cfg ?? DetectorConfig()
        queue.addOperation { [self] in
            window = SlidingWindow(windowSec: cfg.windowSec, hopSec: cfg.hopSec, sampleRate: Self.sampleRate)
            self.detector = detector
            self.calibrating = calibrating
            startedAt = Date()
            recorder = record ? FeatureRecorder(startedAt: startedAt) : nil
            lastT = 0
        }
        motion.accelerometerUpdateInterval = 1.0 / Self.sampleRate
        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            self.process(AccelSample(x: a.x, y: a.y, z: a.z))
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        queue.addOperation { [self] in
            if var d = detector, d.activeFreeze != nil {
                d.stopManually(at: lastT)
                detector = d
            }
            window = nil
            detector = nil
            if let r = recorder {
                recorder = nil
                emit(.recordingFinished(r.close()))
            }
        }
    }

    /// Patient pressed Stop on an automatic cue: tell the detector so it enters refractory.
    func stopActiveCue() {
        queue.addOperation { [self] in
            guard var d = detector, let ended = d.stopManually(at: lastT) else { return }
            detector = d
            emit(.cueEnded(ended, date(ended.endT ?? lastT)))
        }
    }

    private func process(_ s: AccelSample) {
        guard let window, let f = window.push(s) else { return }
        lastT = f.tEnd
        if calibrating { emit(.calibrationWindow(f)) }
        guard var d = detector else {
            recorder?.append(f, score: .nan, phase: .monitoring)
            return
        }
        let out = d.update(f)
        detector = d
        recorder?.append(f, score: d.lastScore, phase: d.phase)
        switch out {
        case .cueStarted(let e): emit(.cueStarted(e, date(e.confirmedT)))
        case .cueEnded(let e): emit(.cueEnded(e, date(e.endT ?? f.tEnd)))
        case .none: break
        }
    }

    private func date(_ t: Double) -> Date { startedAt.addingTimeInterval(t) }

    private func emit(_ o: Output) {
        DispatchQueue.main.async { [weak self] in self?.onOutput?(o) }
    }
}
