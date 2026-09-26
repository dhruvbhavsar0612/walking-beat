import FoGCore
import Foundation

/// Writes every analysis window (features + detector score) to CSV during walk mode when study
/// recording is on. Together with the labelled event log this is the wrist dataset needed to
/// retrain and validate the thigh-trained model on the watch (see docs/VALIDATION.md).
final class FeatureRecorder {
    private(set) var url: URL
    private var handle: FileHandle?
    private let startedAt: Date

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
        let name = "windows-\(Int(startedAt.timeIntervalSince1970)).csv"
        url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("unix_time,t_end,loco_power,freeze_power,freeze_index,dominant_freq,score,phase\n".utf8))
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    func append(_ f: WindowFeatures, score: Double, phase: DetectorPhase) {
        let ts = startedAt.timeIntervalSince1970 + f.tEnd
        let line = String(format: "%.2f,%.2f,%.8g,%.8g,%.6g,%.3f,%.4f,%@\n",
                          ts, f.tEnd, f.locoPower, f.freezePower, f.freezeIndex, f.dominantFreq, score, phase.rawValue)
        handle?.write(Data(line.utf8))
    }

    func close() -> URL {
        try? handle?.close()
        handle = nil
        return url
    }
}
