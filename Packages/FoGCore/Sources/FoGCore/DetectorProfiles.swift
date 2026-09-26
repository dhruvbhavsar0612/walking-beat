import Foundation

public enum SensitivityProfile: String, Codable, CaseIterable, Sendable, Identifiable {
    case conservative, balanced, responsive
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .conservative: "Fewest false alarms"
        case .balanced: "Balanced"
        case .responsive: "Catch more freezes"
        }
    }
}

/// Model + per-profile detector settings produced by `research/evaluate.py`.
public struct DetectorProfiles: Codable, Sendable {
    public let source: String
    public let model: LogisticModel
    public let profiles: [String: DetectorConfig]

    public func config(for profile: SensitivityProfile) -> DetectorConfig {
        profiles[profile.rawValue] ?? DetectorConfig()
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    public static func load(from data: Data) throws -> DetectorProfiles {
        try decoder().decode(DetectorProfiles.self, from: data)
    }

    /// The profiles bundled with the package.
    public static func bundled() throws -> DetectorProfiles {
        guard let url = Bundle.module.url(forResource: "detector_profiles", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: Data(contentsOf: url))
    }

    public func makeDetector(profile: SensitivityProfile, overrides: DetectorConfig? = nil) throws -> FoGDetector {
        try FoGDetector(config: overrides ?? config(for: profile), model: model)
    }
}
