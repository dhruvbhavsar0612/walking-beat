import Foundation

/// Spectral features of one analysis window. Port of `research/fogdetect/features.py`.
public struct WindowFeatures: Equatable, Sendable {
    public let tEnd: Double
    public let locoPower: Double
    public let freezePower: Double
    public let freezeIndex: Double
    public let dominantFreq: Double

    public var totalPower: Double { locoPower + freezePower }

    public init(tEnd: Double, locoPower: Double, freezePower: Double, freezeIndex: Double, dominantFreq: Double) {
        self.tEnd = tEnd
        self.locoPower = locoPower
        self.freezePower = freezePower
        self.freezeIndex = freezeIndex
        self.dominantFreq = dominantFreq
    }
}

public struct AccelSample: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Direct DFT over only the 0.5-8 Hz bins, summed across axes (rotation-invariant by Parseval).
/// Precomputes the Hann window and twiddle factors once per (window length, sample rate).
public final class FeatureExtractor {
    public static let locoBand = (low: 0.5, high: 3.0)
    public static let freezeBand = (low: 3.0, high: 8.0)
    static let eps = 1e-9

    public let windowLength: Int
    public let sampleRate: Double
    private let hann: [Double]
    private let bins: [Int]
    private let freqs: [Double]
    private let cosTable: [[Double]]
    private let sinTable: [[Double]]
    private let locoMask: [Bool]
    private let freezeMask: [Bool]

    public init(windowLength n: Int, sampleRate fs: Double) {
        precondition(n > 0 && fs > 0)
        windowLength = n
        sampleRate = fs
        hann = (0..<n).map { 0.5 - 0.5 * cos(2.0 * Double.pi * Double($0) / Double(n)) }
        let df = fs / Double(n)
        let kMin = Int((Self.locoBand.low / df - 1e-9).rounded(.up))
        let kMax = Int((Self.freezeBand.high / df + 1e-9).rounded(.down))
        bins = kMin <= kMax ? Array(kMin...kMax) : []
        freqs = bins.map { Double($0) * df }
        cosTable = bins.map { k in (0..<n).map { cos(2.0 * Double.pi * Double(k) * Double($0) / Double(n)) } }
        sinTable = bins.map { k in (0..<n).map { sin(2.0 * Double.pi * Double(k) * Double($0) / Double(n)) } }
        locoMask = freqs.map { $0 >= Self.locoBand.low - 1e-9 && $0 < Self.locoBand.high - 1e-9 }
        freezeMask = freqs.map { $0 >= Self.freezeBand.low - 1e-9 && $0 <= Self.freezeBand.high + 1e-9 }
    }

    public func features(_ window: [AccelSample], tEnd: Double) -> WindowFeatures {
        precondition(window.count == windowLength, "window length mismatch")
        let n = Double(windowLength)
        var mx = 0.0, my = 0.0, mz = 0.0
        for s in window { mx += s.x; my += s.y; mz += s.z }
        mx /= n; my /= n; mz /= n
        var xs = [Double](repeating: 0, count: windowLength)
        var ys = xs, zs = xs
        for i in 0..<windowLength {
            xs[i] = (window[i].x - mx) * hann[i]
            ys[i] = (window[i].y - my) * hann[i]
            zs[i] = (window[i].z - mz) * hann[i]
        }

        var loco = 0.0, freeze = 0.0
        var domFreq = 0.0, domPower = -Double.infinity
        for b in 0..<bins.count {
            let c = cosTable[b], s = sinTable[b]
            var reX = 0.0, imX = 0.0, reY = 0.0, imY = 0.0, reZ = 0.0, imZ = 0.0
            for i in 0..<windowLength {
                reX += c[i] * xs[i]; imX += s[i] * xs[i]
                reY += c[i] * ys[i]; imY += s[i] * ys[i]
                reZ += c[i] * zs[i]; imZ += s[i] * zs[i]
            }
            let p = (reX * reX + imX * imX + reY * reY + imY * imY + reZ * reZ + imZ * imZ) / (n * n)
            if locoMask[b] {
                loco += p
                if p > domPower { domPower = p; domFreq = freqs[b] }
            }
            if freezeMask[b] { freeze += p }
        }
        return WindowFeatures(tEnd: tEnd, locoPower: loco, freezePower: freeze,
                              freezeIndex: freeze / (loco + Self.eps), dominantFreq: domFreq)
    }
}

/// Buffers a live sample stream and emits one `WindowFeatures` every hop, exactly like
/// `sliding_features` in Python: first window after `windowLength` samples, then every `hopLength`.
public final class SlidingWindow {
    public let extractor: FeatureExtractor
    public let hopLength: Int
    private var ring: [AccelSample]
    private var head = 0
    private(set) public var sampleCount = 0

    public init(windowSec: Double, hopSec: Double, sampleRate: Double) {
        let n = Int((windowSec * sampleRate).rounded())
        extractor = FeatureExtractor(windowLength: n, sampleRate: sampleRate)
        hopLength = max(1, Int((hopSec * sampleRate).rounded()))
        ring = Array(repeating: AccelSample(x: 0, y: 0, z: 0), count: n)
    }

    public func reset() {
        head = 0
        sampleCount = 0
    }

    public func push(_ s: AccelSample) -> WindowFeatures? {
        ring[head] = s
        head = (head + 1) % ring.count
        sampleCount += 1
        let n = extractor.windowLength
        guard sampleCount >= n, (sampleCount - n) % hopLength == 0 else { return nil }
        let window = Array(ring[head...] + ring[..<head])
        return extractor.features(window, tEnd: Double(sampleCount) / extractor.sampleRate)
    }
}
