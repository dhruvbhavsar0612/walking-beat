import FoGCore
import FoGKit
import SwiftUI

@main
struct FoGCuePhoneApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.onboarded { MainTabs() } else { OnboardingView() }
            }
            .environmentObject(model)
            .dynamicTypeSize(.large ... .accessibility3)
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "sun.max") }
            EventLogView().tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            AboutView().tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}

// MARK: Onboarding

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var step = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            switch step {
            case 0:
                page(icon: "figure.walk", title: "A walking beat when feet feel stuck",
                     text: "When a freeze is detected, or when the Help button on the watch is pressed, the watch taps a steady beat on the wrist and can play a sound. Stepping in time with a beat helps many people with Parkinson's start walking again.")
            case 1:
                page(icon: "exclamationmark.shield", title: "Important",
                     text: "This is a research prototype, not a medical device. It will sometimes miss a freeze and sometimes start the beat when not needed. It does not detect falls or call for help. Keep using your usual walking aids and follow your care team's advice.")
            default:
                page(icon: "applewatch", title: "Set up the beat",
                     text: "On the watch, open the app and tap \"Set up my beat\", then walk normally for 2 minutes. The watch learns this person's normal walking so it does not mistake it for a freeze, and sets the beat to their own step rate.")
            }
            Spacer()
            Button {
                if step < 2 { step += 1 } else {
                    Task { await model.requestNotificationPermission() }
                    model.onboarded = true
                }
            } label: {
                Text(step == 1 ? "I understand" : step < 2 ? "Next" : "Finish")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func page(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 64)).foregroundStyle(.tint).accessibilityHidden(true)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(text).font(.title3).multilineTextAlignment(.center)
        }
    }
}

// MARK: Today

struct TodayView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: model.watchReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                        Text(model.watchReachable ? "Watch connected" : "Watch not in range")
                    }
                    .font(.title3)
                }
                Section("Today") {
                    stat("Beats started", model.today?.cues ?? 0)
                    stat("Help button used", model.today?.manual ?? 0)
                    stat("Confirmed freezes", model.today?.confirmedFreezes ?? 0)
                    stat("Not needed", model.today?.falseAlarms ?? 0)
                    if let d = model.today?.medianDurationSec {
                        LabeledContent("Typical beat length", value: "\(Int(d.rounded())) s").font(.title3)
                    }
                }
                Section("Last 7 days") {
                    ForEach(model.summaries.prefix(7), id: \.day) { s in
                        LabeledContent(s.day.formatted(.dateTime.weekday(.wide).day().month())) {
                            Text("\(s.cues) beats")
                        }
                    }
                    if model.summaries.isEmpty { Text("No events yet.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(model.settings.patientName.isEmpty ? "Walking beat" : model.settings.patientName)
        }
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        LabeledContent(title) { Text("\(value)").font(.title2.bold()) }.font(.title3)
    }
}

// MARK: Log

struct EventLogView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.events.isEmpty {
                    Text("Events from the watch will appear here.").foregroundStyle(.secondary)
                }
                ForEach(model.events) { e in
                    EventRow(event: e)
                }
                .onDelete { idx in model.delete(Set(idx.map { model.events[$0].id })) }
            }
            .navigationTitle("Log")
            .toolbar {
                ShareLink(item: model.exportCSV()) { Label("Export for doctor", systemImage: "square.and.arrow.up") }
            }
        }
    }
}

struct EventRow: View {
    @EnvironmentObject var model: AppModel
    let event: FoGEventRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: event.source == .manual ? "hand.tap.fill" : "waveform.path.ecg")
                Text(event.start.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                Spacer()
                if let d = event.durationSec { Text("\(Int(d.rounded())) s").foregroundStyle(.secondary) }
            }
            Text(event.source == .manual ? "Help button" : "Detected automatically").font(.subheadline)
            if event.source == .automatic {
                HStack {
                    labelButton("Real freeze", .realFreeze, .green)
                    labelButton("Not needed", .falseAlarm, .gray)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func labelButton(_ title: String, _ label: EventLabel, _ tint: Color) -> some View {
        Button(title) { model.setLabel(event.id, event.label == label ? .unlabeled : label) }
            .buttonStyle(.bordered)
            .tint(event.label == label ? tint : .secondary)
            .accessibilityAddTraits(event.label == label ? .isSelected : [])
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var preview = MetronomePreview()

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name (optional)", text: $model.settings.patientName)
                }
                Section {
                    Stepper(value: $model.settings.bpm, in: CueSettings.bpmRange, step: 2) {
                        Text("\(model.settings.bpm) beats per minute").font(.title3)
                    }
                    Button(preview.playing ? "Stop preview" : "Hear and feel this beat") { preview.toggle(bpm: model.settings.bpm) }
                } header: { Text("Beat") } footer: {
                    Text("Best set by the watch's 2-minute setup walk, which matches this person's own step rate.")
                }
                Section("How the beat is given") {
                    Picker("Cue", selection: $model.settings.mode) {
                        ForEach(CueMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    if model.settings.mode != .haptic {
                        Picker("Sound", selection: $model.settings.audioStyle) {
                            ForEach(AudioStyle.allCases) { Text($0.title).tag($0) }
                        }
                        Slider(value: $model.settings.volume, in: 0.2...1) { Text("Volume") }
                    }
                }
                Section {
                    Toggle("Detect freezes automatically", isOn: $model.settings.autoDetectEnabled)
                    Picker("Sensitivity", selection: $model.settings.sensitivity) {
                        ForEach(SensitivityProfile.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: model.settings.sensitivity) { model.settings.personalConfig = nil }
                } header: { Text("Detection") } footer: {
                    Text("\"Fewest false alarms\" is recommended to start. The Help button on the watch always works, even with detection off. Changing sensitivity clears the personal setup; repeat the setup walk afterwards.")
                }
                Section {
                    Toggle("Study recording", isOn: $model.settings.studyRecordingEnabled)
                    ForEach(model.studyFiles, id: \.self) { url in
                        ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "doc.text") }
                    }
                } header: { Text("Research") } footer: {
                    Text("Only for supervised studies. Saves the watch's movement measurements during walks so the detector can be checked and improved for this person. No audio or location is recorded.")
                }
                Section("Alerts") {
                    Toggle("Notify this phone when the beat starts", isOn: $model.settings.caregiverAlertsEnabled)
                }
                if let c = model.lastCalibration {
                    Section("Last setup walk") {
                        LabeledContent("Date", value: c.recordedAt.formatted(date: .abbreviated, time: .shortened))
                        if let cad = c.cadenceStepsPerMin { LabeledContent("Step rate", value: "\(Int(cad)) per min") }
                        LabeledContent("Personalised", value: model.settings.personalConfig == nil ? "No" : "Yes")
                    }
                }
            }
            .navigationTitle("Settings")
            .onDisappear { preview.stop() }
        }
    }
}

// MARK: About

struct AboutView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Why a beat helps") {
                    Text("Freezing of gait affects roughly 4 in 10 people with Parkinson's. A steady external rhythm, heard or felt, gives the brain a timing signal to step to, and has been shown in trials to improve walking and reduce freezing.")
                }
                Section("How detection works") {
                    Text("The watch measures wrist movement. When someone who was just walking suddenly stops stepping and the movement changes to fast trembling, and this lasts more than a moment, the beat starts. It stops by itself when walking resumes. The current detector was developed on public data from leg-worn sensors and is still being validated on the wrist.")
                }
                Section("Limits") {
                    Text("Detection can miss freezes, especially when starting to walk, and can occasionally start the beat when not needed. Marking each event as \"Real freeze\" or \"Not needed\" helps improve it. This app is not a medical device.")
                }
                Section("Key research") {
                    Text("Nieuwboer et al., RESCUE trial, JNNP 2007")
                    Text("Bächlin et al., IEEE TITB 2010")
                    Text("Moore et al., J Neurosci Methods 2008")
                    Text("Ginis et al., Ann Phys Rehabil Med 2018")
                    Text("Salomon et al., Nature Communications 2024")
                }
            }
            .navigationTitle("About")
        }
    }
}
