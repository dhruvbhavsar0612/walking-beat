import Foundation
import XCTest
@testable import FoGCore

/// Safety properties on synthetic signals: things that must never cue, and a clear freeze that must.
final class DetectorBehaviourTests: XCTestCase {
    let fs = 64.0

    /// Walking-like signal: step-frequency sway plus a weaker harmonic, like thigh acceleration.
    func walking(_ seconds: Double, stepHz: Double = 1.8, amp: Double = 0.35) -> [AccelSample] {
        (0..<Int(seconds * fs)).map { i in
            let t = Double(i) / fs
            let s = amp * sin(2 * .pi * stepHz * t) + 0.12 * amp * sin(2 * .pi * 2 * stepHz * t)
            return AccelSample(x: s, y: 1.0 + 0.5 * s, z: 0.3 * s)
        }
    }

    /// Trembling in place: 5 Hz leg shaking, no stepping.
    func trembling(_ seconds: Double, amp: Double = 0.25) -> [AccelSample] {
        (0..<Int(seconds * fs)).map { i in
            let t = Double(i) / fs
            let s = amp * sin(2 * .pi * 5.5 * t)
            return AccelSample(x: s, y: 1.0 + 0.6 * s, z: 0.4 * s)
        }
    }

    func still(_ seconds: Double) -> [AccelSample] {
        (0..<Int(seconds * fs)).map { i in AccelSample(x: 0.001 * sin(Double(i)), y: 1.0, z: 0.0) }
    }

    func ruleConfig(requireWalk: Bool = true) -> DetectorConfig {
        var c = DetectorConfig()
        c.useModel = false
        c.fiThreshold = 2.0
        c.requirePriorWalking = requireWalk
        return c
    }

    func replay(_ samples: [AccelSample], _ cfg: DetectorConfig) throws -> [DetectedFreeze] {
        let sw = SlidingWindow(windowSec: cfg.windowSec, hopSec: cfg.hopSec, sampleRate: fs)
        var det = try FoGDetector(config: cfg, model: nil)
        var last = 0.0
        for s in samples {
            if let f = sw.push(s) { det.update(f); last = f.tEnd }
        }
        det.finish(at: last)
        return det.events
    }

    func testNeverCuesWhileStandingStillOrSitting() throws {
        XCTAssertTrue(try replay(still(120), ruleConfig(requireWalk: false)).isEmpty)
    }

    func testNeverCuesDuringContinuousNormalWalking() throws {
        XCTAssertTrue(try replay(walking(180), ruleConfig()).isEmpty)
    }

    func testWalkThenStopQuietlyDoesNotCue() throws {
        XCTAssertTrue(try replay(walking(20) + still(30), ruleConfig()).isEmpty)
    }

    func testTrembleWithoutPriorWalkingDoesNotCueWhenGateOn() throws {
        XCTAssertTrue(try replay(still(10) + trembling(10), ruleConfig()).isEmpty)
    }

    func testFreezeAfterWalkingCuesAndEndsWhenWalkingResumes() throws {
        let events = try replay(walking(20) + trembling(8) + walking(20), ruleConfig())
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertGreaterThan(e.confirmedT, 20)
        XCTAssertLessThan(e.confirmedT, 20 + 5, "cue should start within 5 s of freeze onset")
        XCTAssertEqual(e.endReason, .walkingResumed)
    }

    func testBriefTremorShorterThanConfirmationDoesNotCue() throws {
        var cfg = ruleConfig()
        cfg.confirmSec = 3.0
        XCTAssertTrue(try replay(walking(20) + trembling(0.5) + walking(20), cfg).isEmpty)
    }

    func testCueTimesOut() throws {
        var cfg = ruleConfig()
        cfg.maxCueSec = 10
        let events = try replay(walking(20) + trembling(40), cfg)
        XCTAssertEqual(events.first?.endReason, .timeout)
    }

    func testManualStop() throws {
        let cfg = ruleConfig()
        let sw = SlidingWindow(windowSec: cfg.windowSec, hopSec: cfg.hopSec, sampleRate: fs)
        var det = try FoGDetector(config: cfg, model: nil)
        var started = false
        for s in walking(20) + trembling(10) {
            if let f = sw.push(s), case .cueStarted = det.update(f) { started = true; break }
        }
        XCTAssertTrue(started)
        XCTAssertEqual(det.stopManually(at: 30)?.endReason, .manual)
        XCTAssertEqual(det.phase, .refractory)
    }

    func testModelModeRequiresModel() {
        XCTAssertThrowsError(try FoGDetector(config: DetectorConfig(), model: nil))
    }

    func testBundledProfilesLoad() throws {
        let p = try DetectorProfiles.bundled()
        XCTAssertEqual(p.model.weights.count, ContextFeaturizer.featureCount)
        for profile in SensitivityProfile.allCases {
            XCTAssertNotNil(p.profiles[profile.rawValue])
            XCTAssertNoThrow(try p.makeDetector(profile: profile))
        }
    }

    func testPercentileMatchesNumpy() {
        XCTAssertEqual(Calibration.percentile([1, 2, 3, 4], 50), 2.5, accuracy: 1e-12)
        XCTAssertEqual(Calibration.percentile([1, 2, 3, 4, 5], 99), 4.96, accuracy: 1e-12)
    }
}
