import Foundation
import Observation

/// Drives the splash screen.
///
/// It restores the session, warms the medicine cache and asks for notification
/// permission the first time. Routing is not its job — `RootView` switches on
/// `UserSession.state`, so there is no navigation stack to get out of sync.
///
/// No SwiftUI import: this is the MVVM rule the project keeps.
@MainActor
@Observable
final class SplashViewModel {

    /// What the splash is showing.
    enum Phase: Equatable {
        case loading
        case failed(String)
        case ready
    }

    private(set) var phase: Phase = .loading

    /// The splash holds for at least this long even when the data arrives
    /// sooner. Long enough for the ring to complete two turns and read as
    /// deliberate; short enough not to feel broken.
    static let minimumHold: Duration = .milliseconds(2500)

    private let medicines: MedicineServicing
    private let notifications: NotificationScheduling
    private let defaults: UserDefaults
    private static let askedKey = "medicfood.hasAskedForNotifications"

    init(
        medicines: MedicineServicing,
        notifications: NotificationScheduling,
        defaults: UserDefaults = .standard
    ) {
        self.medicines = medicines
        self.notifications = notifications
        self.defaults = defaults
    }

    convenience init(services: ServiceContainer) {
        self.init(medicines: services.medicines, notifications: services.notifications)
    }

    /// Restore the session and warm the cache, holding the screen for at least
    /// `minimumHold`.
    ///
    /// Asking for notifications on first launch rather than at sign-up is
    /// deliberate: a medication app is useless without reminders, so the prompt
    /// should not wait until the user has already lost interest.
    ///
    /// The session is restored even if the medicine fetch fails — saved
    /// reminders keep working offline, and stranding someone on a splash
    /// because the network is down would be worse than showing a stale list.
    func start(session: UserSession) async {
        phase = .loading
        let began = ContinuousClock.now

        await session.restore()

        if !defaults.bool(forKey: Self.askedKey) {
            defaults.set(true, forKey: Self.askedKey)
            _ = await notifications.requestAuthorization()
        }

        do {
            _ = try await medicines.medicines()
        } catch {
            await holdRemainder(since: began)
            phase = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
            return
        }

        await holdRemainder(since: began)
        phase = .ready
    }

    func retry(session: UserSession) async {
        await start(session: session)
    }

    /// Sleep out whatever is left of the minimum hold.
    private func holdRemainder(since began: ContinuousClock.Instant) async {
        let elapsed = ContinuousClock.now - began
        guard elapsed < Self.minimumHold else { return }
        try? await Task.sleep(for: Self.minimumHold - elapsed)
    }
}
