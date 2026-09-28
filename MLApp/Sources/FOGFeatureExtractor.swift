import Accelerate
import CoreML

/// Mirrors the Python extract_features() function exactly.
/// Input: 128 accelerometer MAGNITUDE readings (2 seconds at 64Hz),
/// where magnitude = sqrt(x*x + y*y + z*z) for each sample.
/// IMPORTANT: raw CoreMotion values are in units of "g" (baseline ~1.0).
/// The training data (Daphnet) used units where baseline ~1000-1150.
/// Multiply CoreMotion magnitude by 1000 before calling this function,
/// UNLESS you have re-verified a different scaling factor.

struct FOGFeatures {
    let freezeIndex: Double
    let energy: Double
    let variance: Double
    let rms: Double
    let entropy: Double
    let locoPower: Double
    let freezePower: Double

    var asDictionary: [String: Double] {
        [
            "freeze_index": freezeIndex,
            "energy": energy,
            "variance": variance,
            "rms": rms,
            "entropy": entropy,
            "loco_power": locoPower,
            "freeze_power": freezePower,
        ]
    }
}

final class FOGFeatureExtractor {

    static let fs: Double = 64.0
    static let locomotorBand: ClosedRange<Double> = 0.5...3.0
    static let freezeBand: ClosedRange<Double> = 3.0...8.0

    /// Computes power spectral energy in a given frequency band using FFT (via Accelerate/vDSP).
    private static func bandPower(signal: [Double], band: ClosedRange<Double>) -> Double {
        let n = signal.count
        var realIn = signal.map { Float($0) }
        var imagIn = [Float](repeating: 0.0, count: n)

        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Double(n))), FFTRadix(kFFTRadix2)) else {
            return 0.0
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var splitComplex = DSPSplitComplex(realp: &realIn, imagp: &imagIn)
        let log2n = vDSP_Length(log2(Double(n)))
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        var magnitudes = [Float](repeating: 0.0, count: n / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n / 2))

        var power: Double = 0.0
        for i in 0..<(n / 2) {
            let freq = Double(i) * fs / Double(n)
            if band.contains(freq) {
                power += Double(magnitudes[i])
            }
        }
        return power
    }

    static func extractFeatures(window: [Double]) -> FOGFeatures {
        // Pad/truncate to nearest power of 2 for FFT (128 samples is already 2^7, ideal)
        let n = window.count

        let locoPower = bandPower(signal: window, band: locomotorBand)
        let freezePower = bandPower(signal: window, band: freezeBand)
        let freezeIndex = locoPower > 0 ? freezePower / locoPower : 0.0

        let energy = window.reduce(0.0) { $0 + $1 * $1 } / Double(n)
        let mean = window.reduce(0.0, +) / Double(n)
        let variance = window.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n)
        let rms = sqrt(window.reduce(0.0) { $0 + $1 * $1 } / Double(n))

        // Histogram-based entropy, matching np.histogram(bins=10) + scipy.stats.entropy
        let minVal = window.min() ?? 0
        let maxVal = window.max() ?? 1
        let binCount = 10
        let binWidth = (maxVal - minVal) / Double(binCount)
        var histogram = [Int](repeating: 0, count: binCount)
        for value in window {
            var binIndex = binWidth > 0 ? Int((value - minVal) / binWidth) : 0
            binIndex = min(max(binIndex, 0), binCount - 1)
            histogram[binIndex] += 1
        }
        let total = Double(window.count)
        var entropyValue = 0.0
        for count in histogram {
            let p = Double(count) / total + 1e-9
            entropyValue -= p * log(p)
        }

        return FOGFeatures(
            freezeIndex: freezeIndex,
            energy: energy,
            variance: variance,
            rms: rms,
            entropy: entropyValue,
            locoPower: locoPower,
            freezePower: freezePower
        )
    }

    /// Accelerometer magnitude = sqrt(x^2 + y^2 + z^2), then rescaled to match training data units.
    static func magnitude(x: Double, y: Double, z: Double, scaleFactor: Double = 1000.0) -> Double {
        return sqrt(x * x + y * y + z * z) * scaleFactor
    }
}

// Example usage once FOGDetector.mlmodel is added to the Xcode project:
//
// let rawWindow: [Double] = ... // 128 magnitude readings, already scaled
// let features = FOGFeatureExtractor.extractFeatures(window: rawWindow)
// let model = try FOGDetector(configuration: MLModelConfiguration())
// let prediction = try model.prediction(
//     freeze_index: features.freezeIndex,
//     energy: features.energy,
//     variance: features.variance,
//     rms: features.rms,
//     entropy: features.entropy,
//     loco_power: features.locoPower,
//     freeze_power: features.freezePower
// )
// print(prediction.freeze_prediction) // 1 = freeze, 0 = no freeze
