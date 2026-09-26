import Foundation
import XCTest
@testable import FoGCore

/// Replays a real Daphnet thigh segment and checks the Swift port against Python golden output
/// (`research/export_fixtures.py`). If these fail, the watch is not running the validated detector.
final class DetectorParityTests: XCTestCase {
    struct Expected: Decodable {
        let sampleRate: Double
        let modelConfig: DetectorConfig
        let ruleConfig: DetectorConfig
        let features: [[Double]]
        let modelScores: [Double]
        let modelEvents: [Event]
        let ruleEvents: [Event]
        let calibration: Cal

        struct Event: Decodable {
            let onsetT: Double
            let confirmedT: Double
            let endT: Double?
            let endReason: String?
        }

        struct Cal: Decodable {
            let windows: Int
            let ok: Bool
            let probThreshold: Double
            let walkPowerMin: Double
        }
    }

    static var expected: Expected!
    static var samples: [AccelSample] = []
    static var profiles: DetectorProfiles!

    override class func setUp() {
        super.setUp()
        let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
        expected = try! DetectorProfiles.decoder().decode(Expected.self, from: Data(contentsOf: dir.appendingPathComponent("expected.json")))
        let csv = try! String(contentsOf: dir.appendingPathComponent("samples.csv"), encoding: .utf8)
        samples = csv.split(separator: "\n").map { line in
            let v = line.split(separator: ",").map { Double($0)! }
            return AccelSample(x: v[0], y: v[1], z: v[2])
        }
        profiles = try! DetectorProfiles.bundled()
    }

    private func streamFeatures(_ cfg: DetectorConfig) -> [WindowFeatures] {
        let sw = SlidingWindow(windowSec: cfg.windowSec, hopSec: cfg.hopSec, sampleRate: Self.expected.sampleRate)
        return Self.samples.compactMap { sw.push($0) }
    }

    private func assertClose(_ a: Double, _ b: Double, rel: Double = 1e-6, _ msg: String) {
        let tol = max(1e-12, rel * max(abs(a), abs(b)))
        XCTAssertLessThanOrEqual(abs(a - b), tol, "\(msg): swift=\(a) python=\(b)")
    }

    func testFeaturesMatchPython() {
        let feats = streamFeatures(Self.expected.modelConfig)
        XCTAssertEqual(feats.count, Self.expected.features.count)
        for (f, e) in zip(feats, Self.expected.features) {
            assertClose(f.tEnd, e[0], "t_end")
            assertClose(f.locoPower, e[1], "loco")
            assertClose(f.freezePower, e[2], "freeze")
            assertClose(f.freezeIndex, e[3], rel: 1e-5, "fi")
            XCTAssertEqual(f.dominantFreq, e[4], accuracy: 1e-9, "dominant freq at t=\(f.tEnd)")
        }
    }

    func testModelScoresAndEventsMatchPython() throws {
        let feats = streamFeatures(Self.expected.modelConfig)
        var det = try FoGDetector(config: Self.expected.modelConfig, model: Self.profiles.model)
        var scores: [Double] = []
        for f in feats {
            det.update(f)
            scores.append(det.lastScore)
        }
        det.finish(at: feats.last!.tEnd)
        for (s, e) in zip(scores, Self.expected.modelScores) { XCTAssertEqual(s, e, accuracy: 1e-6) }
        assertEvents(det.events, Self.expected.modelEvents)
    }

    func testRuleModeEventsMatchPython() throws {
        let feats = streamFeatures(Self.expected.ruleConfig)
        var det = try FoGDetector(config: Self.expected.ruleConfig, model: nil)
        feats.forEach { det.update($0) }
        det.finish(at: feats.last!.tEnd)
        assertEvents(det.events, Self.expected.ruleEvents)
    }

    func testCalibrationMatchesPython() {
        let feats = Array(streamFeatures(Self.expected.modelConfig).prefix(Self.expected.calibration.windows))
        let r = Calibration.calibrate(walk: feats, base: Self.expected.modelConfig, model: Self.profiles.model)
        XCTAssertEqual(r.ok, Self.expected.calibration.ok)
        XCTAssertEqual(r.config.probThreshold, Self.expected.calibration.probThreshold, accuracy: 1e-6)
        XCTAssertEqual(r.config.walkPowerMin, Self.expected.calibration.walkPowerMin, accuracy: 1e-9)
    }

    private func assertEvents(_ got: [DetectedFreeze], _ want: [Expected.Event], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.count, want.count, "event count", file: file, line: line)
        for (g, w) in zip(got, want) {
            XCTAssertEqual(g.onsetT, w.onsetT, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(g.confirmedT, w.confirmedT, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(g.endT ?? -1, w.endT ?? -1, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(g.endReason?.rawValue, w.endReason, file: file, line: line)
        }
    }
}
