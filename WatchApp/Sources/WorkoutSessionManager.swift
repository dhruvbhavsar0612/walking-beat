import Foundation
import HealthKit

/// Keeps the app running with the screen off. watchOS only grants continuous background motion
/// sampling to apps with an active HKWorkoutSession. Workouts are discarded on stop so walk
/// sessions do not add fake exercise to the patient's Activity rings.
final class WorkoutSessionManager: NSObject, ObservableObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
    }

    func start() {
        guard session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .walking
        config.locationType = .unknown
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            s.delegate = self
            session = s
            builder = b
            let now = Date()
            s.startActivity(with: now)
            b.beginCollection(withStart: now) { _, _ in }
            isRunning = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        session?.end()
    }

    /// Called from the app delegate if watchOS relaunched us mid-session (crash, update).
    func recover(_ recovered: HKWorkoutSession) {
        session = recovered
        builder = recovered.associatedWorkoutBuilder()
        recovered.delegate = self
        isRunning = true
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        builder?.endCollection(withEnd: date) { [weak self] _, _ in
            self?.builder?.discardWorkout()
            DispatchQueue.main.async {
                self?.session = nil
                self?.builder = nil
                self?.isRunning = false
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
            self.session = nil
            self.builder = nil
            self.isRunning = false
        }
    }
}
