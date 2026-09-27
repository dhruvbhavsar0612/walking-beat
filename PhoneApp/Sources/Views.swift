import FoGCore
import FoGKit
import SwiftUI

@main
struct FoGCuePhoneApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var phoneBeat = PhoneBeatHost()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.onboarded { MainTabs() } else { OnboardingView() }
            }
            .environmentObject(model)
            .environmentObject(phoneBeat)
            .dynamicTypeSize(.large ... .accessibility3)
            .onAppear { phoneBeat.attach(model) }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            if model.role == .caregiver {
                TodayView().tabItem { Label("Today", systemImage: "sun.max") }
                EventLogView().tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                AboutView().tabItem { Label("About", systemImage: "info.circle") }
            } else {
                MyBeatView().tabItem { Label("My beat", systemImage: "metronome") }
                HowItView().tabItem { Label("Help", systemImage: "questionmark.circle") }
                CaregiverModeView().tabItem { Label("Caregiver", systemImage: "person.2") }
            }
        }
    }
}

/// Small tab that hands the device back to caregiver presentation. Always visible in patient
/// mode so nobody gets stuck; the watch (or caregiver's phone) still runs everything.
struct CaregiverModeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "person.2").font(.system(size: 64)).foregroundStyle(.tint)
                Text("Setting things up?").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("Switch to the full caregiver app for settings, the freeze journal, and doctor export. You can switch back any time.")
                    .font(.title3).multilineTextAlignment(.center)
                Button {
                    model.role = .caregiver
                } label: {
                    Text("Use the caregiver app").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }.padding(24)
            .navigationTitle("Caregiver")
        }
    }
}

// MARK: Onboarding

/// Wizard: story → honest limits → role → watch check → guided setup walk → tempo → done.
/// One idea per screen, plain language, always a big Next. Radiobutton-free; role choice is
/// two large tappable cards (elder-friendly), not a picker.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var step = 0
    @State private var agreedLimits = false

    var body: some View {
        VStack(spacing: 24) {
            progress
            ScrollView {
                switch step {
                case 0: intro
                case 1: limits
                case 2: rolePick
                case 3: watchCheck
                case 4:// SetupWalkPage kept for future watch-first flow; phone uses interactive progress
                    NavigationLink { SetupWalkProgressView() } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "figure.walk.circle.fill").font(.system(size: 56)).foregroundStyle(.tint)
                            Text("Start the setup walk").font(.title3.bold())
                            Text("2 minutes, this phone, no watch needed").font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    .buttonStyle(.bordered)
                case 5: tempoPage
                default: done
                }
            }
            navButtons
        }
        .padding(24)
        .onAppear { step = min(max(step, 0), 6) }
    }

    private var progress: some View {
        ProgressView(value: Double(step), total: 6)
            .accessibilityLabel("Setup progress")
    }

    private var intro: some View {
        page(icon: "figure.walk", title: "A beat to walk to",
             text: "When walking suddenly feels stuck — feet glued to the floor — a steady beat on the watch helps many people with Parkinson's start stepping again. The beat follows this person's own step rate, and the watch can start it by itself when a freeze is noticed.") {
            Text("No false-alarm surprises: every automatic cue starts as quiet wrist taps. Sound only joins if the freeze continues.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground)).cornerRadius(12)
        }
    }

    private var limits: some View {
        page(icon: "exclamationmark.shield", title: "What this app does NOT do",
             text: "This is a research prototype, not a medical device.\n\nIt will sometimes miss a freeze, and sometimes start the beat when it was not needed. It does not detect falls and does not call for help.\n\nKeep using walking aids and your care team's advice. Always tap the big Help button on the watch whenever you need the beat — it works every time.") {
            Toggle(isOn: $agreedLimits) {
                Text("I understand, and I still want to set it up").font(.headline)
            }
            .padding(.vertical, 6)
        }
    }

    private var rolePick: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2").font(.system(size: 64)).foregroundStyle(.tint)
            Text("Who will use this phone?").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Both can share it any time — this only changes what you see.").font(.title3).multilineTextAlignment(.center)
            Button { model.role = .caregiver; withAnimation { step = 3 } } label: { roleCard("I am a family member or caregiver", subtitle: "I will set things up and follow how often freezing happens", icon: "person.2.fill") }
            Button { model.role = .patient; withAnimation { step = 3 } } label: { roleCard("I am the person walking", subtitle: "I will use the watch; keep this phone simple", icon: "figure.walk.motion") }
        }
        .padding(.vertical, 8)
    }

    private func roleCard(_ title: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title)
            Text(title).font(.title3.bold()).multilineTextAlignment(.leading)
            Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(Color(.secondarySystemBackground)).cornerRadius(16)
        .padding(.vertical, 4)
    }

    private var watchCheck: some View {
        page(icon: "applewatch", title: model.watchReachable ? "Watch connected" : "This phone can run the beat",
             text: model.watchReachable
                ? "Good. The watch will detect freezes and tap the beat automatically during walks."
                : "No watch needed. This phone can run the beat, detect freezing in walk mode (keep it in a pocket), and do the setup walk. If a watch is paired later, everything moves to the wrist automatically.") {
            Text("Either device keeps the same journal on this phone.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var tempoPage: some View {
        TempoSetupPage(mode: .onboarding)
    }

    private var done: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(.green)
            Text("Ready to walk").font(.largeTitle.bold())
            Text(model.role == .caregiver
                 ? "When walking (especially turns and doorways — the tricky spots), the patient opens the watch app and starts walk mode. The beat handles the rest."
                 : "Before a walk, open the watch app and tap the big Start button. If you feel stuck, tap Help — the beat starts right away.")
                .font(.title3).multilineTextAlignment(.center)
            if model.role == .caregiver {
                Text("You can come back to Settings any time to adjust the beat or share the journal with the doctor.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var navButtons: some View {
        Group {
            if step < 6 {
                HStack(spacing: 16) {
                    if step > 0 && step != 2 {
                        Button("Back") { withAnimation { step = max(step - 1, 0) } }
                            .frame(minHeight: 56)
                    }
                    Button(step == 1 ? "Continue" : step == 4 ? "Walk start" : step == 5 ? "Set my beat" : "Next") {
                        withAnimation { step = min(step + 1, 6) }
                    }
                    .disabled(step == 1 && !agreedLimits)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Button("Finish") {
                    Task { await model.requestNotificationPermission() }
                    model.onboarded = true
                }
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 60)
                .buttonStyle(.borderedProminent)
                Button("Back") { withAnimation { step = 5 } }
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
    }

    private func page(icon: String, title: String, text: String, @ViewBuilder content: () -> some View = { EmptyView() }) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 64)).foregroundStyle(.tint).accessibilityHidden(true)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(text).font(.title3).multilineTextAlignment(.leading)
            content()
        }
    }

}

// MARK: Setup walk page (shared)

/// Guides the caregiver/patient through the 2-minute walk that measures cadence, and listens
/// for the result arriving from the watch.
struct SetupWalkPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.walk.circle.fill").font(.system(size: 64)).foregroundStyle(.tint)
            Text("The setup walk").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(model.role == .patient
                 ? "On the watch, tap \"Set up my beat\", then walk the way you normally walk. Keep going until it says done."
                 : "On the watch, tap \"Set up my beat\", then walk with them for 2 minutes at their normal pace. This is how the watch learns their step rate and sets a safe freeze threshold.")
                .font(.title3).multilineTextAlignment(.center)
            if let c = model.lastCalibration {
                Label("Walk recorded: \(Int(c.cadenceStepsPerMin ?? 0)) steps per minute", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(.green).padding(.top, 8)
                Button("Redo later in Settings") { } // noop, guidance only
                    .font(.callout)
            } else {
                Label("Waiting for the watch to finish…", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.headline).foregroundStyle(.secondary).padding(.top, 8)
            }
            Spacer()
            Text("You can skip and adjust the beat by hand now; redo the walk any time in Settings — a personal setup makes false alarms much less likely.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(.vertical, 12)
    }
}

// MARK: Tempo setup (evidence-anchored)

/// Caregiver picks tempo relative to the measured walking cadence. 110% is pre-selected —
/// trials found cueing ~10% above preferred cadence reduced freezing most reliably
/// (Arias & Cudeiro 2010; RAS review). Without a setup walk yet, falls back to a manual beat.
struct TempoSetupPage: View {
    enum Mode { case onboarding, settings }
    let mode: Mode
    @EnvironmentObject var model: AppModel
    @StateObject private var preview = MetronomePreview()

    private var cadence: Double? { model.lastCalibration?.cadenceStepsPerMin }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "metronome").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Set the beat").font(.largeTitle.bold()).multilineTextAlignment(.center)
            if let c = cadence {
                Text("Setup walk measured \(Int(c)) steps per minute.").font(.title3).multilineTextAlignment(.center)
                Picker("Speed", selection: Binding(
                    get: { Self.nearestPercent(model.settings.bpm, cadence: c) },
                    set: { pct in model.settings.bpm = Self.bpm(for: pct, cadence: c) })) {
                    Text("90%").tag(90); Text("100%").tag(100); Text("110%").tag(110)
                }
                .pickerStyle(.segmented)
                Text(pctCaption).font(.callout).foregroundStyle(.secondary)
            } else {
                Text(mode == .onboarding
                     ? "No setup walk yet — drag to choose a comfortable beat for now; the walk will fine-tune it."
                     : "Do the setup walk (Settings → Setup walk) to anchor the beat to their own step rate.").font(.title3)
                Stepper(value: $model.settings.bpm, in: CueSettings.bpmRange, step: 2) {
                    Text("\(model.settings.bpm) beats per minute").font(.title3)
                }
            }
            Button(preview.playing ? "Stop" : "Hear and feel this beat") { preview.toggle(bpm: model.settings.bpm) }
                .buttonStyle(.borderedProminent)
            Text("In trials, a beat about 10% faster than the person's natural walking reduced freezing best. A beat that feels rushed should be turned down — comfort wins.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(24).onDisappear { preview.stop() }
    }

    private var pctCaption: String {
        switch Self.nearestPercent(model.settings.bpm, cadence: cadence!) {
        case 90: "A little slower than normal walking. Calmest option."
        case 100: "Exactly their own walking rhythm."
        default: "Trials found this slightly-quicker beat reduced freezing the most."
        }
    }

    static func nearestPercent(_ bpm: Int, cadence: Double) -> Int {
        [90, 100, 110].min(by: { abs(Double(bpm) - Double(cadence) * Double($0) / 100) < abs(Double(bpm) - Double(cadence) * Double($1) / 100) }) ?? 110
    }
    static func bpm(for pct: Int, cadence: Double) -> Int {
        max(CueSettings.bpmRange.lowerBound, min(CueSettings.bpmRange.upperBound, Int((cadence * Double(pct) / 100).rounded())))
    }
}

private extension TempoSetupPage { // path title helper
    var title: String { mode == .onboarding ? "Set the beat" : "Tempo" }
}

// MARK: Patient tabs

struct MyBeatView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var phoneBeat: PhoneBeatHost

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 10) {
                        Image(systemName: model.watchReachable ? "applewatch.radiowaves.left.and.right" : "iphone.radiowaves.left.and.right")
                            .font(.title2)
                        Text(model.watchReachable ? "Watch ready" : "Beat runs on this phone").font(.title3)
                    }.padding(.top, 8)

                    if phoneBeat.service.beatActive {
                        VStack(spacing: 16) {
                            Image(systemName: "metronome.fill").font(.system(size: 56)).foregroundStyle(.tint)
                            Text("Beat playing — step in time").font(.headline)
                            Button {
                                switch phoneBeat.service.mode {
                                case .manualBeat: phoneBeat.service.stopManualBeat()
                                case .walkMode: phoneBeat.service.stopWalkMode()
                                default: break
                                }
                            } label: {
                                Text("Stop the beat").font(.title3.bold())
                                    .frame(maxWidth: .infinity, minHeight: 72)
                            }
                            .buttonStyle(.borderedProminent).tint(.red)
                        }
                    } else {
                        // Manual help — always available.
                        Button {
                            phoneBeat.service.startManualBeat()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "metronome").font(.largeTitle)
                                Text("Help me walk").font(.title.bold())
                                Text("start the rhythm on this phone").font(.callout)
                            }
                            .frame(maxWidth: .infinity, minHeight: 96)
                        }
                        .buttonStyle(.borderedProminent)

                        // Walk mode: automatic detection on the phone (pocket placement).
                        NavigationLink {
                            PhoneWalkModeView()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "figure.walk").font(.largeTitle)
                                Text("Walk mode").font(.title3.bold())
                                Text("detect freezes here — keep the phone in a pocket").font(.callout)
                            }
                            .frame(maxWidth: .infinity, minHeight: 84)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!phoneBeat.service.isAvailable)
                    }

                    VStack(spacing: 12) {
                        Text("\(model.today?.cues ?? 0)").font(.system(size: 72, weight: .bold))
                        Text(model.today?.cues == 1 ? "beat helped today" : "beats helped today").foregroundStyle(.secondary)
                    }.padding(.vertical, 16)
                    Text("With the watch, walk mode counts automatically. Here, pressing the button counts too.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let c = model.lastCalibration, let cad = c.cadenceStepsPerMin {
                        LabeledContent("Your walking rhythm", value: "\(Int(cad)) steps/min").font(.title3).padding(.horizontal)
                    }
                }.padding(.horizontal)
            }
            .navigationTitle("Walking Beat")
        }
    }
}

/// Phone-side walk mode: foreground automatic detection using the same FoGCore pipeline the
/// watch runs. A phone in a pocket is the placement our model was validated on (thigh data).
struct PhoneWalkModeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var phoneBeat: PhoneBeatHost
    @Environment(\.dismiss) private var dismiss
    @State private var showStopConfirm = false

    private var service: PhoneDetectionService { phoneBeat.service }

    var body: some View {
        VStack(spacing: 24) {
            switch service.mode {
            case .idle:
                VStack(spacing: 16) {
                    Image(systemName: "figure.walk.circle").font(.system(size: 64)).foregroundStyle(.tint)
                    Text("Walk mode").font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text("Put this phone in a pocket (not a loose hand), then start. It listens for a sudden stop-and-tremble while walking and starts the beat if one happens. Keep the screen on while walking.")
                        .font(.title3).multilineTextAlignment(.center)
                    Button {
                        service.settings = model.settings
                        service.startWalkMode()
                    } label: {
                        Text("Start walk mode").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .walkMode(let active):
                VStack(spacing: 20) {
                    Image(systemName: active ? "waveform.path.ecg" : "waveform.slash").font(.system(size: 56)).foregroundStyle(active ? .green : .secondary)
                    Text(active ? "Listening while you walk" : "Detection unavailable").font(.title2.bold())
                    if service.beatActive {
                        Text("Beat playing — step in time; it stops itself when walking resumes").font(.headline).multilineTextAlignment(.center)
                        Button {
                            service.stopWalkMode()
                        } label: {
                            Text("Stop the beat").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 72)
                        }
                        .buttonStyle(.borderedProminent).tint(.red)
                    } else {
                        Text("Keep the phone in a pocket. Turn it off before sitting down — it only watches while walking.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Button(role: .destructive) {
                        showStopConfirm = true
                    } label: {
                        Text("End walk mode").frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                }
            default: EmptyView()
            }
            Spacer()
        }
        .padding(24)
        .navigationTitle("Walk mode")
        .navigationBarTitleDisplayMode(.inline)
        .alert("End walk mode?", isPresented: $showStopConfirm) {
            Button("End", role: .destructive) { service.stopWalkMode(); dismiss() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Automatic detection and its beat stop now; the Help button always stays available.")
        }
        .onDisappear {
            if case .walkMode = service.mode { service.stopWalkMode() }
        }
    }
}

/// Guided 2-minute setup walk on the phone: collects the same calibration windows and cadence
/// the watch's setup walk does, then runs the identical Calibration.calibrate.
struct SetupWalkProgressView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var phoneBeat: PhoneBeatHost
    @Environment(\.dismiss) private var dismiss
    @State private var resultMessage: String?

    private var service: PhoneDetectionService { phoneBeat.service }

    var body: some View {
        VStack(spacing: 20) {
            if let msg = resultMessage {
                Image(systemName: msg.contains("recorded") ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .font(.system(size: 64))
                    .foregroundStyle(msg.contains("recorded") ? Color.green : Color.orange)
                Text(msg).font(.title3).multilineTextAlignment(.center)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent).frame(minHeight: 56)
            } else {
                Image(systemName: "figure.walk.circle.fill").font(.system(size: 64)).foregroundStyle(.tint)
                Text("Walk normally for 2 minutes").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("Swing your arm naturally or keep the phone in a pocket — a steady, walking pace is what registers. Holding the phone still will not.")
                    .font(.title3).multilineTextAlignment(.center)
                ProgressView(value: service.calibrationProgress)
                    .accessibilityLabel("Setup walk progress")
                Text("\(Int(service.calibrationProgress * 120)) of 120 seconds")
                    .font(.callout).foregroundStyle(.secondary)
                // Live sampling proof: shows collection is working moment to moment.
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: service.gaitWindowCount > 0 ? "waveform.path.ecg" : "waveform.slash")
                            .foregroundStyle(service.gaitWindowCount > 0 ? Color.green : Color.orange)
                        Text(service.gaitWindowCount > 0
                             ? "Walk detected — \(service.gaitWindowCount) gait samples"
                             : "Waiting for steady walking…")
                            .font(.callout)
                    }
                    if service.sensorSampleCount == 0 && service.calibrationProgress > 0.03 {
                        VStack(spacing: 8) {
                            Label("No motion data is arriving.", systemImage: "exclamationmark.shield.fill")
                                .font(.callout.bold()).foregroundStyle(.red)
                            Text("Motion & Fitness permission is probably off. Enable it, then try again.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.callout.bold())
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    // Numeric diagnostics: what the pipeline actually sees (sampled live).
                    if let err = service.lastError {
                        Label(err, systemImage: "xmark.octagon.fill")
                            .font(.callout.bold()).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 4) {
                        Text("mode \(String(describing: service.mode))")
                            .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        Text("samples \(service.sensorSampleCount) · windows \(service.windowsEmitted) · gait \(service.gaitWindowCount)")
                            .font(.caption.monospacedDigit())
                        Text(String(format: "freq %.2f Hz · loco %.5f · FI %.2f", service.lastDominantFreq, service.lastLocoPower, service.lastFreezeIndex))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text("expected: freq 0.6–2.6 Hz, loco > 0.00025")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                }
                Button(role: .destructive) {
                    service.cancelSetupWalk(); dismiss()
                } label: { Text("Cancel").frame(minHeight: 52) }
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(24)
        .navigationTitle("Setup walk")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if service.mode != .calibrating && resultMessage == nil {
                service.settings = model.settings
                Task { // defer so we never trigger sensors/state changes during view update
                    service.startSetupWalk()
                }
            }
        }
        .onChange(of: service.calibrationProgress) { progress in
            // Completion is now fired by the service (calibrationResult publisher).
            let _ = progress
        }
        .onReceive(service.$calibrationResult) { result in
            guard let result, resultMessage == nil else { return }
            if result.ok {
                let cad = result.cadence.map { " at \(Int($0)) steps per minute" } ?? ""
                resultMessage = "Walk recorded\(cad). The beat and thresholds are personalised."
                if let upload = phoneBeat.lastCalibration {
                    model.receive(SyncMessage.calibrationSamples(upload))
                }
            } else {
                resultMessage = "Not enough steady walking was detected. Try again at a normal, unhurried pace."
            }
        }
    }
}

struct HowItView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("When you feel stuck") {
                    Text("Look at your watch and press the big Help button. The beat begins right away — step in time with it, one foot per tap.")
                }
                Section("How the automatic side works") {
                    Text("During walk mode, the watch watches for the stuck moment and starts the same beat. Every start begins quietly (wrist taps).")
                }
                Section("If the beat started by itself") {
                    Text("It will stop on its own when you walk again. If it started by mistake, tap Stop. Nothing bad happened.")
                }
            }
            .navigationTitle("Help")
        }
    }
}

// MARK: Today (caregiver)

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

// MARK: Log (caregiver)

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

// MARK: Settings (caregiver)

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showTempoTuner = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name (optional)", text: $model.settings.patientName)
                }
                Section {
                    NavigationLink("Tune the beat") { TempoSetupPage(mode: .settings) }
                    LabeledContent("Now", value: "\(model.settings.bpm) beats per minute")
                } header: { Text("Beat") } footer: {
                    Text("Anchored to their own step rate from the setup walk. In trials, about 10% above normal walking reduced freezing the most; comfort comes first — lower it if it feels rushed.")
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
                Section("Setup walk") {
                    NavigationLink("Redo setup walk on this phone") { SetupWalkProgressView() }
                    if let c = model.lastCalibration {
                        LabeledContent("Last walk", value: c.recordedAt.formatted(date: .abbreviated, time: .shortened))
                        if let cad = c.cadenceStepsPerMin { LabeledContent("Step rate", value: "\(Int(cad)) per min") }
                        LabeledContent("Personalised", value: model.settings.personalConfig == nil ? "No" : "Yes")
                    }
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
                Section("App") {
                    Picker("This phone belongs to", selection: $model.role) {
                        Text("The person walking").tag(AppRole.patient)
                        Text("Family / caregiver").tag(AppRole.caregiver)
                    }
                    Text("Switch roles any time; data is shared either way.").font(.callout).foregroundStyle(.secondary)
                }
                Section("Share") {
                    ShareLink(item: model.exportCSV()) { Label("Freeze journal (CSV) for the doctor", systemImage: "square.and.arrow.up") }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: About

struct AboutView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Why a beat helps") {
                    Text("Freezing of gait affects roughly 4 in 10 people with Parkinson's. A steady external rhythm, heard or felt, gives the brain a timing signal to step to, and trials have shown it improves walking and reduces freezing. The strongest results came from a beat a little quicker than natural walking — about 10% faster.")
                }
                Section("How detection works") {
                    Text("The watch measures wrist movement. When someone who was just walking suddenly stops stepping and the movement changes to fast trembling, and this lasts more than a moment, the beat starts. It stops by itself when walking resumes. The current detector was developed on public data from leg-worn sensors and is still being validated on the wrist.")
                }
                Section("Limits") {
                    Text("Detection can miss freezes, especially when starting to walk, and can occasionally start the beat when not needed. Marking each event as \"Real freeze\" or \"Not needed\" helps improve it. This app is not a medical device.")
                    Text("Full limitation register: see docs/LIMITATIONS.md in the project repository.")
                }
                Section("Key research") {
                    Text("Nieuwboer et al., RESCUE trial, JNNP 2007")
                    Text("Arias & Cudeiro, PLoS One 2010 (cueing at 110% cadence)")
                    Text("Bächlin et al., IEEE TITB 2010")
                    Text("Moore et al., J Neurosci Methods 2008")
                    Text("Salomon et al., Nature Communications 2024")
                    Text("Evidence map: docs/EVIDENCE_LOG.md in the project repository.")
                }
            }
            .navigationTitle("About")
        }
    }
}
