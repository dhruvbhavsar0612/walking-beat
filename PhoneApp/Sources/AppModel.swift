import FoGCore
import FoGKit
import Foundation
import UserNotifications
import WatchConnectivity

/// Who is holding the phone right now. Only changes presentation, never data.
enum AppRole: String {
    case patient
    case caregiver
}

extension Notification.Name {
    /// Phone app's own beat (no watch needed): "start the rhythm right now".
    static let startPhoneBeat = Notification.Name("fogcue.startPhoneBeat")
    /// Stop the phone-side beat.
    static let stopPhoneBeat = Notification.Name("fogcue.stopPhoneBeat")
}

/// Phone-only cueing fallback: when no watch is paired/in range, the phone itself taps and
/// plays the beat, and still logs the event so the journal stays complete. Detection stays
/// watch-only; this covers the "Help me walk" path everywhere.
@MainActor
final class PhoneBeatController: ObservableObject {
    @Published private(set) var active = false
    private let preview = MetronomePreview()
    private var startedAt: Date?
    private var eventId: UUID?
    private weak var model: AppModel?

    func attach(_ model: AppModel) { self.model = model }

    func toggle() {
        active ? stop() : start()
    }

    func start() {
        guard let model else { return }
        let id = UUID()
        eventId = id
        startedAt = Date()
        active = true
        let e = FoGEventRecord(id: id, start: startedAt!, source: .manual)
        model.receive(SyncMessage.eventStarted(e)) // journal + caregiver alert path, same as watch
        preview.start(bpm: model.settings.bpm)
    }

    func stop(endReason: CueEndReason = .manual) {
        guard active, let model, let id = eventId, let start = startedAt else { return }
        preview.stop()
        active = false
        let end = Date()
        var e = FoGEventRecord(id: id, start: start, end: end, source: .manual, endReason: endReason)
        e.label = model.events.first(where: { $0.id == id })?.label ?? .unlabeled
        model.receive(SyncMessage.eventEnded(e))
        eventId = nil
        startedAt = nil
    }
}

/// Phone-side state: settings authored by the caregiver, the event log, and alerts.
@MainActor
final class AppModel: NSObject, ObservableObject {
    @Published var settings: CueSettings {
        didSet { if settings != oldValue { persistSettings(); pushSettings() } }
    }
    @Published private(set) var events: [FoGEventRecord] = []
    @Published private(set) var watchReachable = false
    @Published private(set) var lastCalibration: CalibrationUpload?
    @Published private(set) var studyFiles: [URL] = []
    @Published var onboarded: Bool {
        didSet { UserDefaults.standard.set(onboarded, forKey: "fogcue.onboarded") }
    }
    /// Presentation role chosen at onboarding. Same device & data either way; this only
    /// filters tabs, wording and setup guidance. Caregivers do the setup; the patient
    /// mostly interacts with the watch.
    @Published var role: AppRole {
        didSet { UserDefaults.standard.set(role.rawValue, forKey: "fogcue.role") }
    }

    private let eventsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("events.json")
    private static let settingsKey = "fogcue.settings"
    static let studyDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("study", isDirectory: true)
    private var applyingRemote = false

    override init() {
        if let d = UserDefaults.standard.data(forKey: Self.settingsKey), let s = try? JSONDecoder().decode(CueSettings.self, from: d) {
            settings = s
        } else {
            settings = CueSettings()
        }
        onboarded = UserDefaults.standard.bool(forKey: "fogcue.onboarded")
        role = AppRole(rawValue: UserDefaults.standard.string(forKey: "fogcue.role") ?? "") ?? .caregiver
        super.init()
        loadEvents()
        refreshStudyFiles()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var summaries: [DaySummary] { Summaries.daily(events) }
    var today: DaySummary? { summaries.first { Calendar.current.isDateInToday($0.day) } }

    func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func setLabel(_ id: UUID, _ label: EventLabel) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        events[i].label = label
        saveEvents()
    }

    func delete(_ ids: Set<UUID>) {
        events.removeAll { ids.contains($0.id) }
        saveEvents()
    }

    /// Plain CSV the caregiver can hand to a neurologist or physiotherapist.
    func exportCSV() -> URL {
        let f = ISO8601DateFormatter()
        var rows = ["start,end,duration_s,source,end_reason,label"]
        for e in events.sorted(by: { $0.start < $1.start }) {
            rows.append([f.string(from: e.start), e.end.map { f.string(from: $0) } ?? "", e.durationSec.map { String(format: "%.1f", $0) } ?? "",
                         e.source.rawValue, e.endReason?.rawValue ?? "", e.label.rawValue].joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("freeze-log.csv")
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func refreshStudyFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.studyDir, includingPropertiesForKeys: nil)) ?? []
        studyFiles = files.filter { $0.pathExtension == "csv" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: Persistence

    private func persistSettings() {
        if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: Self.settingsKey) }
    }

    private func loadEvents() {
        guard let d = try? Data(contentsOf: eventsURL), let e = try? JSONDecoder().decode([FoGEventRecord].self, from: d) else { return }
        events = e.sorted { $0.start > $1.start }
    }

    private func saveEvents() {
        if let d = try? JSONEncoder().encode(events) { try? d.write(to: eventsURL, options: [.atomic, .completeFileProtection]) }
    }

    // MARK: Sync

    private func pushSettings() {
        guard !applyingRemote, WCSession.default.activationState == .activated,
              let data = try? SyncMessage.settings(settings).encoded() else { return }
        try? WCSession.default.updateApplicationContext([SyncMessage.key: data])
    }

    func receive(_ m: SyncMessage) {
        switch m {
        case .settings(let s):
            applyingRemote = true
            settings = s
            applyingRemote = false
        case .eventStarted(let e):
            upsert(e)
            if settings.caregiverAlertsEnabled { notify(e, started: true) }
        case .eventEnded(let e):
            upsert(e)
        case .label(let id, let label):
            setLabel(id, label)
        case .calibrationSamples(let u):
            lastCalibration = u
        }
    }

    private func upsert(_ e: FoGEventRecord) {
        if let i = events.firstIndex(where: { $0.id == e.id }) {
            var merged = e
            if events[i].label != .unlabeled { merged.label = events[i].label }
            events[i] = merged
        } else {
            events.insert(e, at: 0)
        }
        saveEvents()
    }

    private func notify(_ e: FoGEventRecord, started: Bool) {
        let content = UNMutableNotificationContent()
        let who = settings.patientName.isEmpty ? "Walking beat" : "\(settings.patientName): walking beat"
        content.title = who
        content.body = e.source == .manual ? "The Help button was pressed." : "A possible freeze was detected and the beat started."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: e.id.uuidString, content: content, trigger: nil))
    }
}

extension AppModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.watchReachable = reachable
                self.pushSettings()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async { MainActor.assumeIsolated { self.watchReachable = reachable } }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let d = userInfo[SyncMessage.key] as? Data, let m = try? SyncMessage.decode(d) else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.receive(m) } }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        try? FileManager.default.createDirectory(at: AppModel.studyDir, withIntermediateDirectories: true)
        let dest = AppModel.studyDir.appendingPathComponent(file.fileURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: file.fileURL, to: dest)
        DispatchQueue.main.async { MainActor.assumeIsolated { self.refreshStudyFiles() } }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
