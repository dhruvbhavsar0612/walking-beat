import Foundation

/// Personal calibration from a guided normal walk. Port of `research/fogdetect/calibration.py`.
public enum Calibration {
    public static let minWalkWindows = 20
    public static let probCap = 0.97

    public struct Result: Equatable, Sendable {
        public let config: DetectorConfig
        public let ok: Bool
        public let gaitWindows: Int
    }

    static func gaitLike(_ f: WindowFeatures, _ cfg: DetectorConfig) -> Bool {
        f.dominantFreq >= cfg.walkFreqMin && f.dominantFreq <= cfg.walkFreqMax && f.locoPower >= cfg.walkPowerMin * 0.25
    }

    public static func calibrate(walk: [WindowFeatures], base: DetectorConfig, model: LogisticModel?,
                                 scorePercentile: Double = 99, probMargin: Double = 0.05,
                                 fiMargin: Double = 1.25, powerFraction: Double = 0.3) -> Result {
        var fz = ContextFeaturizer()
        var loco: [Double] = []
        var scores: [Double] = []
        for f in walk {
            let ctx = fz.push(f)
            guard gaitLike(f, base) else { continue }
            loco.append(f.locoPower)
            if base.useModel, let model { scores.append(model.prob(ctx)) } else { scores.append(f.freezeIndex) }
        }
        guard scores.count >= minWalkWindows else { return Result(config: base, ok: false, gaitWindows: scores.count) }
        var cfg = base
        cfg.walkPowerMin = max(base.walkPowerMin * 0.25, powerFraction * percentile(loco, 50))
        let top = percentile(scores, scorePercentile)
        if base.useModel {
            cfg.probThreshold = min(probCap, max(base.probThreshold, top + probMargin))
        } else {
            cfg.fiThreshold = max(base.fiThreshold, fiMargin * top)
        }
        return Result(config: cfg, ok: true, gaitWindows: scores.count)
    }

    /// Linear-interpolated percentile, identical to numpy's default.
    public static func percentile(_ values: [Double], _ q: Double) -> Double {
        precondition(!values.isEmpty)
        let s = values.sorted()
        let pos = q / 100.0 * Double(s.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }
}
