import Foundation

/// Mirrors `DetectorConfig` in `research/fogdetect/detector.py`. JSON uses the Python snake_case keys.
public struct DetectorConfig: Codable, Sendable, Equatable {
    public var windowSec = 3.0
    public var hopSec = 0.5
    public var walkPowerMin = 0.001
    public var walkFiMax = 2.0
    public var walkFreqMin = 0.6
    public var walkFreqMax = 2.6
    public var minWalkSec = 3.0
    public var armTimeoutSec = 5.0
    public var fiThreshold = 3.0
    public var probThreshold = 0.7
    public var standPowerMin = 0.001
    public var confirmSec = 1.5
    public var maxGapHops = 1
    public var resumeWalkSec = 2.0
    public var stillEndSec = 3.0
    public var maxCueSec = 30.0
    public var refractorySec = 3.0
    public var requirePriorWalking = true
    public var useModel = true

    public init() {}
}

public enum DetectorPhase: String, Codable, Sendable {
    case monitoring, candidate, cueing, refractory
}

public enum CueEndReason: String, Codable, Sendable {
    case walkingResumed = "walking_resumed"
    case still
    case timeout
    case manual
}

public struct DetectedFreeze: Equatable, Sendable {
    public var onsetT: Double
    public var confirmedT: Double
    public var endT: Double?
    public var endReason: CueEndReason?
    public var peakScore: Double
}

public enum DetectorOutput: Equatable, Sendable {
    case none
    case cueStarted(DetectedFreeze)
    case cueEnded(DetectedFreeze)
}

public enum DetectorError: Error {
    case modelRequired
}

/// Multi-gate streaming FoG detector. Line-for-line port of `FoGDetector` in Python; the parity
/// test (`DetectorParityTests`) replays Python golden fixtures to keep the two identical.
public struct FoGDetector: Sendable {
    public private(set) var cfg: DetectorConfig
    public let model: LogisticModel?
    private var featurizer = ContextFeaturizer()

    public private(set) var phase: DetectorPhase = .monitoring
    public private(set) var lastScore = 0.0
    public private(set) var events: [DetectedFreeze] = []
    private var walkRun = 0.0
    private var lastSustainedWalkT = -Double.infinity
    private var candidateStart = 0.0
    private var candidateRun = 0.0
    private var gapHops = 0
    private var stillRun = 0.0
    private var refractoryUntil = -Double.infinity
    private var active: DetectedFreeze?

    public init(config: DetectorConfig, model: LogisticModel?) throws {
        if config.useModel && model == nil { throw DetectorError.modelRequired }
        cfg = config
        self.model = model
    }

    public var activeFreeze: DetectedFreeze? { active }

    func isWalking(_ f: WindowFeatures) -> Bool {
        f.locoPower >= cfg.walkPowerMin && f.freezeIndex <= cfg.walkFiMax
            && f.dominantFreq >= cfg.walkFreqMin && f.dominantFreq <= cfg.walkFreqMax
    }

    mutating func score(_ f: WindowFeatures) -> Double {
        let ctx = featurizer.push(f)
        if cfg.useModel, let model { return model.prob(ctx) }
        return f.freezeIndex
    }

    func evidence(_ f: WindowFeatures, _ s: Double) -> Bool {
        let threshold = cfg.useModel ? cfg.probThreshold : cfg.fiThreshold
        return s >= threshold && f.totalPower >= cfg.standPowerMin
    }

    func armed(_ t: Double) -> Bool {
        guard cfg.requirePriorWalking else { return true }
        return (t - lastSustainedWalkT) <= cfg.armTimeoutSec
    }

    @discardableResult
    public mutating func update(_ f: WindowFeatures) -> DetectorOutput {
        let t = f.tEnd
        let hop = cfg.hopSec
        let walking = isWalking(f)
        let s = score(f)
        lastScore = s
        let freezeLike = evidence(f, s)

        walkRun = walking ? walkRun + hop : 0
        if walkRun >= cfg.minWalkSec { lastSustainedWalkT = t }

        if phase == .refractory && t >= refractoryUntil { phase = .monitoring }

        switch phase {
        case .monitoring:
            if freezeLike && armed(t) {
                phase = .candidate
                candidateStart = t
                candidateRun = hop
                gapHops = 0
                return maybeConfirm(t, s)
            }
            return .none
        case .candidate:
            if freezeLike {
                candidateRun += hop
                gapHops = 0
                return maybeConfirm(t, s)
            }
            gapHops += 1
            if gapHops > cfg.maxGapHops || walking {
                phase = .monitoring
                candidateRun = 0
            }
            return .none
        case .cueing:
            guard var a = active else { return .none }
            a.peakScore = max(a.peakScore, s)
            active = a
            let quiet = f.totalPower < cfg.standPowerMin
            stillRun = quiet ? stillRun + hop : 0
            if walkRun >= cfg.resumeWalkSec {
                let ended = end(t, .walkingResumed)
                lastSustainedWalkT = t
                return .cueEnded(ended)
            } else if stillRun >= cfg.stillEndSec {
                return .cueEnded(end(t, .still))
            } else if t - a.confirmedT >= cfg.maxCueSec {
                return .cueEnded(end(t, .timeout))
            }
            return .none
        case .refractory:
            return .none
        }
    }

    private mutating func maybeConfirm(_ t: Double, _ s: Double) -> DetectorOutput {
        if candidateRun + 1e-9 < cfg.confirmSec { return .none }
        let freeze = DetectedFreeze(onsetT: candidateStart - cfg.hopSec, confirmedT: t, endT: nil, endReason: nil, peakScore: s)
        active = freeze
        events.append(freeze)
        phase = .cueing
        stillRun = 0
        return .cueStarted(freeze)
    }

    private mutating func end(_ t: Double, _ reason: CueEndReason) -> DetectedFreeze {
        var a = active!
        a.endT = t
        a.endReason = reason
        if let i = events.lastIndex(where: { $0.confirmedT == a.confirmedT }) { events[i] = a }
        active = nil
        phase = .refractory
        refractoryUntil = t + cfg.refractorySec
        candidateRun = 0
        return a
    }

    /// Patient or caregiver tapped Stop.
    @discardableResult
    public mutating func stopManually(at t: Double) -> DetectedFreeze? {
        guard phase == .cueing, active != nil else { return nil }
        return end(t, .manual)
    }

    /// Closes an open cue at end of stream (used by offline replay).
    public mutating func finish(at t: Double) {
        if active != nil { _ = end(t, .timeout) }
    }
}
