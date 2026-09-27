import FoGCore
import XCTest

/// Diagnostic for the phone setup-walk "0 gait samples" report: replays REAL thigh-worn
/// patient data (the same fixture the parity tests use) through the exact pipeline the phone
/// runs — SlidingWindow at 64 Hz -> gaitLike filter -> Calibration.calibrate — and prints the
/// feature distributions. If gaitLike passes on this data on the Mac, the logic is sound and
/// the device-side sensor path is the problem. If it fails, the thresholds are the bug.
final class GaitFilterDiagnosticsTests: XCTestCase {
    func testRealThighDataPassesGaitFilter() throws {
        // Load the full samples.csv from its committed chunks (same as DetectorParityTests).
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FoGCoreTests
            .appendingPathComponent("Fixtures")
        let parts = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("samples.csv.part") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var csv = ""
        for p in parts { csv += try String(contentsOf: p, encoding: .utf8) }
        let lines = csv.split(separator: "\n")
        XCTAssertGreaterThan(lines.count, 10_000, "expected a long recording")
        let samples = try lines.map { line -> AccelSample in
            let c = line.split(separator: ",").map { Double($0)! }
            return AccelSample(x: c[0], y: c[1], z: c[2])
        }
        print("DIAG samples loaded:", samples.count)

        // Identical to PhoneDetectionService.startSetupWalk path:
        let window = SlidingWindow(windowSec: 3.0, hopSec: 0.5, sampleRate: 64.0)
        let cfg = DetectorConfig()
        var gait = 0, total = 0
        var freqs: [Double] = [], locos: [Double] = [], fis: [Double] = []
        var walkWindows: [WindowFeatures] = []
        for s in samples {
            if let f = window.push(s) {
                total += 1
                freqs.append(f.dominantFreq)
                locos.append(f.locoPower)
                fis.append(f.freezeIndex)
                if Calibration.gaitLike(f, cfg) {
                    gait += 1
                    walkWindows.append(f)
                }
            }
        }
        print("DIAG windows total:", total)
        print("DIAG gaitLike passed:", gait, "of", total)
        func stats(_ v: [Double]) -> String {
            guard !v.isEmpty else { return "empty" }
            let s = v.sorted()
            let p = { (q: Double) in s[min(s.count - 1, Int(q / 100 * Double(s.count - 1)))] }
            return String(format: "min=%.4g p5=%.4g p50=%.4g p95=%.4g max=%.4g", s[0], p(5), p(50), p(95), s.last!)
        }
        print("DIAG dominantFreq:", stats(freqs))
        print("DIAG locoPower:", stats(locos))
        print("DIAG freezeIndex:", stats(fis))
        print("DIAG walkFreqMin/max:", cfg.walkFreqMin, cfg.walkFreqMax, "walkPowerMin:", cfg.walkPowerMin)

        let result = Calibration.calibrate(walk: walkWindows, base: cfg, model: nil)
        print("DIAG calibrate ok:", result.ok, "gaitWindows:", result.gaitWindows)
        XCTAssertGreaterThan(total, 100, "pipeline should emit many windows")
        XCTAssertGreaterThan(gait, 20, "REAL walking data must pass the gait filter — if this fails, thresholds are the bug")
        XCTAssertTrue(result.ok, "calibration should succeed on real walking data")
    }
}
