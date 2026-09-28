import CoreML
import CoreMotion
import SwiftUI

/// Standalone A/B app: teammate's random-forest FoG model via Core ML.
/// Deliberately shares no code with the main Walking Beat app so the two apps can be
/// compared without any coupling. Follows the teammate's test order:
///   Step 1: hardcoded fake features -> verify model loads and predicts.
///   Step 2: live CoreMotion accelerometer, 2 s windows at 64 Hz, magnitude scaled to the
///           Daphnet unit range (baseline ~1000-1150), features -> FOGDetector prediction.
@main
struct FoGMLApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

@MainActor
final class MLTester: ObservableObject {
    enum Phase { case idle, sanityTesting, sanityResult, live }
    @Published var phase: Phase = .idle
    @Published var sanityText: String = ""
    @Published var sanityOK: Bool?

    // Live
    @Published var liveOn = false
    @Published var windowCount = 0
    @Published var lastLabel: Int?
    @Published var lastFeatures: FOGFeatures?
    @Published var verdictFreeze = false
    @Published var freezeWindowCount = 0
    private let motion = CMMotionManager()
    private var ring: [Double] = []
    private var recent: [Int] = []
    private var model: FOGDetector?
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: Step 1 — hardcoded sanity test (values in the Daphnet-derived unit range)

    func runSanityTest() {
        phase = .sanityTesting
        sanityText = ""
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self else { return }
            do {
                let model = try FOGDetector(configuration: MLModelConfiguration())
                self.model = model
                // Plausible "trembling" values: high freeze index, strong freeze power.
                let out = try model.prediction(
                    freeze_index: 6.5, energy: 1_800_000, variance: 900_000, rms: 1_150,
                    entropy: 1.9, loco_power: 120_000, freeze_power: 780_000)
                let label = out.freeze_prediction
                let proba = out.classProbability[1]
                self.sanityOK = true
                self.sanityText = "Model loaded and predicted. Label: \(label)\n"
                    + (proba.map { String(format: "P(freeze) = %.2f", $0) } ?? "")
                self.phase = .sanityResult
            } catch {
                self.sanityOK = false
                self.sanityText = "FAILED: \(error.localizedDescription)"
                self.phase = .sanityResult
            }
        }
    }

    // MARK: Step 2 — live accelerometer

    func startLive() {
        guard motion.isAccelerometerAvailable else {
            sanityText = "Accelerometer unavailable"
            return
        }
        liveOn = true
        phase = .live
        ring = []
        recent = []
        windowCount = 0
        freezeWindowCount = 0
        verdictFreeze = false
        if model == nil { model = try? FOGDetector(configuration: MLModelConfiguration()) }
        motion.accelerometerUpdateInterval = 1.0 / 64.0
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            self.append(mag: FOGFeatureExtractor.magnitude(x: a.x, y: a.y, z: a.z))
        }
    }

    func stopLive() {
        motion.stopAccelerometerUpdates()
        liveOn = false
        phase = .sanityResult
    }

    private func append(mag: Double) {
        ring.append(mag)
        guard ring.count >= 128 else { return }
        let window = Array(ring.suffix(128))
        ring.removeAll(keepingCapacity: true)
        guard let model else { return }
        let features = FOGFeatureExtractor.extractFeatures(window: window)
        let out = try? model.prediction(
            freeze_index: features.freezeIndex, energy: features.energy,
            variance: features.variance, rms: features.rms, entropy: features.entropy,
            loco_power: features.locoPower, freeze_power: features.freezePower)
        guard let out else { return }
        windowCount += 1
        lastLabel = Int(out.freeze_prediction)
        lastFeatures = features
        recent.append(Int(out.freeze_prediction))
        if recent.count > 6 { recent.removeFirst() }
        let wasFreeze = verdictFreeze
        verdictFreeze = recent.filter { $0 == 1 }.count >= 3
        if verdictFreeze { freezeWindowCount += 1 }
        if verdictFreeze != wasFreeze { haptic.impactOccurred(intensity: 1) }
    }
}

struct ContentView: View {
    @StateObject private var tester = MLTester()

    var body: some View {
        NavigationStack {
            Form {
                Section("Model: random forest (Core ML)") {
                    Button(tester.phase == .sanityTesting ? "Testing…" : "Step 1: test model with hardcoded features") {
                        tester.runSanityTest()
                    }
                    if !tester.sanityText.isEmpty {
                        Text(tester.sanityText)
                            .font(.callout)
                            .foregroundStyle(tester.sanityOK == true ? Color.green : (tester.sanityOK == false ? Color.red : Color.primary))
                    }
                }
                Section("Step 2: live accelerometer (phone in pocket)") {
                    Button(tester.liveOn ? "Stop live" : "Start live") {
                        tester.liveOn ? tester.stopLive() : tester.startLive()
                    }
                    if tester.liveOn {
                        LabeledContent("Windows analyzed", value: "\(tester.windowCount)")
                        HStack {
                            Image(systemName: tester.verdictFreeze ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                .foregroundStyle(tester.verdictFreeze ? Color.red : Color.green)
                            Text(tester.verdictFreeze ? "FREEZE predicted" : "No freeze predicted")
                                .font(.headline)
                        }
                        LabeledContent("Last label", value: tester.lastLabel.map { "\($0)" } ?? "–")
                        if let f = tester.lastFeatures {
                            Text(String(format: "FI %.2f · loco %.0f · freeze %.0f · entropy %.2f",
                                        f.freezeIndex, f.locoPower, f.freezePower, f.entropy))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text("\(tester.freezeWindowCount) freeze windows so far")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Baseline note: raw CoreMotion is in g (~1.0); Daphnet training units are ~1000-1150, so magnitudes are scaled by 1000 (per FOGFeatureExtractor).")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("About") }
            }
            .navigationTitle("Walking Beat ML")
        }
    }
}
