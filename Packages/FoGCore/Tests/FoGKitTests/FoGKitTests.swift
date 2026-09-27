import FoGCore
import Foundation
import XCTest
@testable import FoGKit

final class FoGKitTests: XCTestCase {
    func testHapticThenAudioEscalates() {
        let s = CueScheduler(settings: CueSettings(bpm: 120, mode: .hapticThenAudio, escalateAfterSec: 4))
        XCTAssertEqual(s.intervalSec, 0.5, accuracy: 1e-12)
        XCTAssertFalse(s.beat(7).audio)
        XCTAssertTrue(s.beat(8).audio)
        XCTAssertTrue(s.beat(0).haptic)
        XCTAssertTrue(s.beat(0).accent)
        XCTAssertFalse(s.beat(1).accent)
    }

    func testHapticOnlyNeverPlaysSound() {
        let s = CueScheduler(settings: CueSettings(mode: .haptic))
        XCTAssertFalse((0..<200).contains { s.beat($0).audio })
    }

    func testNextBeatIndex() {
        let s = CueScheduler(settings: CueSettings(bpm: 60))
        XCTAssertEqual(s.nextBeatIndex(after: 0), 1)
        XCTAssertEqual(s.nextBeatIndex(after: 2.5), 3)
    }

    func testBPMClampedAndRecommended() {
        XCTAssertEqual(CueSettings(bpm: 300).bpm, 140)
        XCTAssertEqual(CadencePolicy.recommendedBPM(cadenceStepsPerMin: 104, offsetPercent: 10), 114)
        XCTAssertEqual(CadencePolicy.recommendedBPM(cadenceStepsPerMin: 100, offsetPercent: -10), 90)
        XCTAssertEqual(CadencePolicy.recommendedBPM(cadenceStepsPerMin: nil), 100)
        XCTAssertEqual(CadencePolicy.recommendedBPM(cadenceStepsPerMin: 20), 100)
    }

    func testSyncMessageRoundTrip() throws {
        let e = FoGEventRecord(start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 1006),
                               source: .automatic, endReason: .walkingResumed, peakScore: 0.9)
        for m: SyncMessage in [.eventEnded(e), .settings(CueSettings(bpm: 96)), .label(id: e.id, label: .falseAlarm)] {
            XCTAssertEqual(try SyncMessage.decode(m.encoded()), m)
        }
    }

    func testCalibrationUploadRoundTrip() {
        let f = WindowFeatures(tEnd: 3, locoPower: 0.01, freezePower: 0.002, freezeIndex: 0.2, dominantFreq: 1.75)
        XCTAssertEqual(CalibrationUpload(recordedAt: Date(), cadenceStepsPerMin: 100, features: [f]).features, [f])
    }

    func testDailySummary() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = Date(timeIntervalSince1970: 86_400 * 10)
        let events = [
            FoGEventRecord(start: d, end: d.addingTimeInterval(4), source: .automatic, label: .realFreeze),
            FoGEventRecord(start: d.addingTimeInterval(60), end: d.addingTimeInterval(70), source: .manual, label: .realFreeze),
            FoGEventRecord(start: d.addingTimeInterval(120), end: d.addingTimeInterval(126), source: .automatic, label: .falseAlarm),
        ]
        let s = Summaries.daily(events, calendar: cal)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].cues, 3)
        XCTAssertEqual(s[0].manual, 1)
        XCTAssertEqual(s[0].medianDurationSec, 6)
        XCTAssertEqual(s[0].falseAlarmShare!, 1.0 / 3.0, accuracy: 1e-12)
    }
}
