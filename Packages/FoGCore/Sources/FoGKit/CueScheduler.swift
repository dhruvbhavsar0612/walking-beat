import Foundation

/// Which outputs fire on a beat. Pure logic so the escalation policy is unit-tested; the watch's
/// CueEngine only turns these into haptics and audio.
public struct BeatOutput: Equatable, Sendable {
    public let index: Int
    public let offsetSec: Double
    public let haptic: Bool
    public let audio: Bool
    public let accent: Bool
}

public struct CueScheduler: Sendable {
    public let settings: CueSettings
    public let beatsPerBar = 4

    public init(settings: CueSettings) { self.settings = settings }

    public var intervalSec: Double { 60.0 / Double(settings.bpm) }

    public func beat(_ index: Int) -> BeatOutput {
        let offset = Double(index) * intervalSec
        let audio: Bool
        switch settings.mode {
        case .haptic: audio = false
        case .audio: audio = true
        case .hapticThenAudio: audio = offset >= settings.escalateAfterSec - 1e-9
        }
        return BeatOutput(index: index, offsetSec: offset, haptic: true, audio: audio, accent: index % beatsPerBar == 0)
    }

    /// Index of the next beat strictly after `elapsed` seconds from cue start.
    public func nextBeatIndex(after elapsed: Double) -> Int {
        max(0, Int((elapsed / intervalSec).rounded(.down)) + 1)
    }
}

/// Cue tempo from measured cadence. Studies cue at the patient's comfortable cadence, commonly
/// within about -10%..+10% of baseline; the caregiver can shift it with `offsetPercent`.
public enum CadencePolicy {
    public static func recommendedBPM(cadenceStepsPerMin: Double?, offsetPercent: Double = 0) -> Int {
        guard let c = cadenceStepsPerMin, c.isFinite, c > 30 else { return 100 }
        let bpm = Int((c * (1 + offsetPercent / 100)).rounded())
        return min(max(bpm, CueSettings.bpmRange.lowerBound), CueSettings.bpmRange.upperBound)
    }
}

public struct DaySummary: Equatable, Sendable {
    public let day: Date
    public let cues: Int
    public let manual: Int
    public let confirmedFreezes: Int
    public let falseAlarms: Int
    public let medianDurationSec: Double?

    public var falseAlarmShare: Double? {
        let labelled = confirmedFreezes + falseAlarms
        return labelled > 0 ? Double(falseAlarms) / Double(labelled) : nil
    }
}

public enum Summaries {
    public static func daily(_ events: [FoGEventRecord], calendar: Calendar = .current) -> [DaySummary] {
        let groups = Dictionary(grouping: events) { calendar.startOfDay(for: $0.start) }
        return groups.keys.sorted(by: >).map { day in
            let es = groups[day]!
            let durations = es.compactMap(\.durationSec).sorted()
            let median: Double? = durations.isEmpty ? nil
                : durations.count % 2 == 1 ? durations[durations.count / 2]
                : (durations[durations.count / 2 - 1] + durations[durations.count / 2]) / 2
            return DaySummary(day: day, cues: es.count, manual: es.filter { $0.source == .manual }.count,
                              confirmedFreezes: es.filter { $0.label == .realFreeze }.count,
                              falseAlarms: es.filter { $0.label == .falseAlarm }.count,
                              medianDurationSec: median)
        }
    }
}
