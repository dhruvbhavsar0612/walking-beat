import CoreMotion
import Foundation

/// Measures the patient's comfortable walking cadence during calibration; the cue tempo is set
/// from it, following the RAS practice of cueing at (or near) the person's own cadence.
final class CadenceMeter {
    private let pedometer = CMPedometer()
    private var start: Date?
    private var samples: [Double] = []

    func start(now: Date = Date()) {
        samples = []
        start = now
        guard CMPedometer.isCadenceAvailable() else { return }
        pedometer.startUpdates(from: now) { [weak self] data, _ in
            guard let c = data?.currentCadence?.doubleValue, c > 0 else { return }
            DispatchQueue.main.async { self?.samples.append(c * 60) }
        }
    }

    /// Returns the median cadence in steps per minute, if any was measured.
    @discardableResult
    func stop() -> Double? {
        pedometer.stopUpdates()
        guard !samples.isEmpty else { return nil }
        let s = samples.sorted()
        return s[s.count / 2]
    }
}
