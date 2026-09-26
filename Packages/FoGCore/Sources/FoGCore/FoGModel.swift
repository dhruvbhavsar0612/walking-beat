import Foundation

/// Streaming context vector. Port of `ContextFeaturizer` in `research/fogdetect/model.py`.
public struct ContextFeaturizer: Sendable {
    public static let logEps = 1e-6
    public static let baselineWindows = 20
    public static let lags = [2, 4, 8]
    public static let featureCount = 5 + 2 * lags.count

    private var history: [(lp: Double, fi: Double)] = []

    public init() {}

    public mutating func reset() { history.removeAll() }

    public mutating func push(_ f: WindowFeatures) -> [Double] {
        let lp = log10(f.locoPower + Self.logEps)
        let fp = log10(f.freezePower + Self.logEps)
        let fi = fp - lp
        history.append((lp, fi))
        if history.count > Self.baselineWindows + 1 { history.removeFirst() }
        let recentMax = history.map(\.lp).max() ?? lp
        var v = [lp, fp, fi, f.dominantFreq, lp - recentMax]
        let n = history.count
        for lag in Self.lags {
            let past = n > lag ? history[n - 1 - lag] : history[0]
            v.append(past.lp)
            v.append(past.fi)
        }
        return v
    }
}

/// Standardised logistic regression exported from Python (`LogisticModel.to_dict`).
public struct LogisticModel: Codable, Sendable, Equatable {
    public let featureNames: [String]
    public let mean: [Double]
    public let std: [Double]
    public let weights: [Double]
    public let bias: Double

    public init(featureNames: [String], mean: [Double], std: [Double], weights: [Double], bias: Double) {
        self.featureNames = featureNames
        self.mean = mean
        self.std = std
        self.weights = weights
        self.bias = bias
    }

    public func prob(_ x: [Double]) -> Double {
        precondition(x.count == weights.count, "feature vector length mismatch")
        var z = bias
        for i in 0..<x.count { z += (x[i] - mean[i]) / std[i] * weights[i] }
        return 1.0 / (1.0 + exp(-z))
    }
}
