import FoGCore
import Foundation

public enum CueMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Wrist taps only. Discreet; a false alarm costs almost nothing.
    case haptic
    /// Wrist taps first, then an audible beat if the freeze continues. Default.
    case hapticThenAudio
    /// Audible beat and taps from the first beat.
    case audio

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .haptic: "Taps on the wrist"
        case .hapticThenAudio: "Taps, then sound if needed"
        case .audio: "Sound and taps"
        }
    }
}

public enum AudioStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case metronome, drum, voiceCount
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .metronome: "Metronome click"
        case .drum: "Soft drum"
        case .voiceCount: "Spoken \"one, two\""
        }
    }
}

public struct CueSettings: Codable, Equatable, Sendable {
    public var bpm: Int
    public var mode: CueMode
    public var audioStyle: AudioStyle
    public var escalateAfterSec: Double
    public var volume: Double
    public var sensitivity: SensitivityProfile
    public var autoDetectEnabled: Bool
    public var caregiverAlertsEnabled: Bool
    /// Log every analysis window during walk mode and send it to the phone (for the wrist study).
    public var studyRecordingEnabled: Bool
    /// Detector settings personalised by calibration; nil means use the bundled profile.
    public var personalConfig: DetectorConfig?
    public var patientName: String

    public static let bpmRange = 60...140

    public init(bpm: Int = 100, mode: CueMode = .hapticThenAudio, audioStyle: AudioStyle = .metronome,
                escalateAfterSec: Double = 4, volume: Double = 0.8, sensitivity: SensitivityProfile = .conservative,
                autoDetectEnabled: Bool = true, caregiverAlertsEnabled: Bool = true, studyRecordingEnabled: Bool = false,
                personalConfig: DetectorConfig? = nil, patientName: String = "") {
        self.bpm = min(max(bpm, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
        self.mode = mode
        self.audioStyle = audioStyle
        self.escalateAfterSec = escalateAfterSec
        self.volume = volume
        self.sensitivity = sensitivity
        self.autoDetectEnabled = autoDetectEnabled
        self.caregiverAlertsEnabled = caregiverAlertsEnabled
        self.studyRecordingEnabled = studyRecordingEnabled
        self.personalConfig = personalConfig
        self.patientName = patientName
    }
}

public enum EventSource: String, Codable, Sendable {
    case automatic
    case manual
}

public enum EventLabel: String, Codable, CaseIterable, Sendable {
    case unlabeled
    case realFreeze
    case falseAlarm
}

public struct FoGEventRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date?
    public var source: EventSource
    public var endReason: CueEndReason?
    public var peakScore: Double
    public var label: EventLabel

    public init(id: UUID = UUID(), start: Date, end: Date? = nil, source: EventSource, endReason: CueEndReason? = nil,
                peakScore: Double = 0, label: EventLabel = .unlabeled) {
        self.id = id
        self.start = start
        self.end = end
        self.source = source
        self.endReason = endReason
        self.peakScore = peakScore
        self.label = label
    }

    public var durationSec: Double? { end.map { $0.timeIntervalSince(start) } }
}

/// Everything exchanged between watch and phone over WatchConnectivity, as one Codable envelope.
public enum SyncMessage: Codable, Equatable, Sendable {
    case settings(CueSettings)
    case eventStarted(FoGEventRecord)
    case eventEnded(FoGEventRecord)
    case label(id: UUID, label: EventLabel)
    case calibrationSamples(CalibrationUpload)

    public static let key = "fogcue.message"

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> SyncMessage { try JSONDecoder().decode(SyncMessage.self, from: data) }
}

/// Window features recorded on the watch during the guided calibration walk.
public struct CalibrationUpload: Codable, Equatable, Sendable {
    public var recordedAt: Date
    public var cadenceStepsPerMin: Double?
    public var windows: [[Double]]

    public init(recordedAt: Date, cadenceStepsPerMin: Double?, features: [WindowFeatures]) {
        self.recordedAt = recordedAt
        self.cadenceStepsPerMin = cadenceStepsPerMin
        windows = features.map { [$0.tEnd, $0.locoPower, $0.freezePower, $0.freezeIndex, $0.dominantFreq] }
    }

    public var features: [WindowFeatures] {
        windows.compactMap { w in
            w.count == 5 ? WindowFeatures(tEnd: w[0], locoPower: w[1], freezePower: w[2], freezeIndex: w[3], dominantFreq: w[4]) : nil
        }
    }
}
