import FoGKit
import HealthKit
import SwiftUI
import WatchKit

@main
struct FoGCueWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @StateObject private var coordinator = FreezeCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
                .task {
                    delegate.coordinator = coordinator
                    await coordinator.requestPermissions()
                }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    weak var coordinator: FreezeCoordinator?

    func handleActiveWorkoutRecovery() {
        HKHealthStore().recoverActiveWorkoutSession { session, _ in
            guard let session else { return }
            DispatchQueue.main.async { self.coordinator?.workout.recover(session) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var c: FreezeCoordinator

    var body: some View {
        if c.activeEvent != nil {
            CueActiveView()
        } else if let e = c.pendingLabel {
            LabelPromptView(event: e)
        } else if c.mode == .calibrating {
            CalibrationView()
        } else {
            HomeView()
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var c: FreezeCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Button {
                    c.mode == .monitoring ? c.stopMonitoring() : c.startMonitoring()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: c.mode == .monitoring ? "figure.walk.motion" : "figure.walk")
                            .font(.system(size: 30, weight: .bold))
                        Text(c.mode == .monitoring ? "Watching.\nTap to stop" : "Start walk")
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 90)
                }
                .tint(c.mode == .monitoring ? .green : .blue)
                .accessibilityHint("Starts or stops freeze detection")

                Button(action: c.manualCue) {
                    Label("Help me walk", systemImage: "metronome.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .tint(.orange)
                .accessibilityHint("Starts the walking beat right now")

                if c.mode == .idle {
                    Button("Set up my beat") { c.startCalibration() }
                        .font(.footnote)
                }
                if let msg = c.calibrationMessage ?? c.errorMessage {
                    Text(msg).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Text("\(c.settings.bpm) beats/min · \(c.settings.sensitivity.title)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CueActiveView: View {
    @EnvironmentObject var c: FreezeCoordinator
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(.orange)
                .frame(width: 70, height: 70)
                .scaleEffect(pulse ? 1.15 : 0.85)
                .animation(.easeInOut(duration: 60.0 / Double(c.settings.bpm)).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
                .accessibilityHidden(true)
            Text("Step with the beat")
                .font(.title3.bold())
            Button(role: .destructive, action: c.stopCue) {
                Text("Stop")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }
}

struct LabelPromptView: View {
    @EnvironmentObject var c: FreezeCoordinator
    let event: FoGEventRecord

    var body: some View {
        VStack(spacing: 8) {
            Text("Were you stuck?")
                .font(.title3.bold())
            HStack {
                Button { c.label(event, .realFreeze) } label: {
                    Text("Yes").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
                }
                .tint(.green)
                Button { c.label(event, .falseAlarm) } label: {
                    Text("No").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
                }
                .tint(.gray)
            }
            Button("Skip") { c.pendingLabel = nil }
                .font(.footnote)
        }
        .task {
            try? await Task.sleep(for: .seconds(20))
            if c.pendingLabel?.id == event.id { c.pendingLabel = nil }
        }
    }
}

struct CalibrationView: View {
    @EnvironmentObject var c: FreezeCoordinator

    var body: some View {
        VStack(spacing: 10) {
            Text("Walk normally")
                .font(.title3.bold())
            Text("Keep walking at your usual pace for 2 minutes.")
                .font(.footnote)
                .multilineTextAlignment(.center)
            ProgressView(value: c.calibrationProgress)
                .tint(.blue)
            Button("Cancel", role: .cancel) { c.cancelCalibration() }
        }
    }
}
