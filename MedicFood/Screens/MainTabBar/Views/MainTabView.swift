import SwiftUI

/// The app's main navigation.
///
/// Five tabs, each owning its own `NavigationStack`, so a push in one does not
/// disturb another. The Flutter version used imperative `Navigator.push`
/// throughout with no route table, which is why its back stack was hard to
/// reason about.
struct MainTabView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminders = ReminderPresenter.shared

    init() {
        // An opaque white tab bar, so content never shows through it.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            NavigationStack {
                HomeLauncherView()
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                MedicineListView()
            }
            .tabItem { Label("Medicines", systemImage: "pills") }

            NavigationStack {
                AdherenceView()
            }
            .tabItem { Label("Progress", systemImage: "chart.bar") }

            NavigationStack {
                CaretakerView()
            }
            .tabItem { Label("Care", systemImage: "person.2") }

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Theme.Colors.primary)
        .sheet(item: Binding(get: { reminders.current }, set: { reminders.current = $0 })) { dose in
            MedicationReminderSheet(dose: dose)
        }
        .task {
            _ = await services.notifications.requestAuthorization()
            await ReminderScheduler.refresh(medicines: services.medicines, notifications: services.notifications)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await ReminderScheduler.refresh(medicines: services.medicines, notifications: services.notifications) }
        }
        .onAppear {
            // Give the notification delegate a way to reach the live services,
            // so a reminder tapped from outside the app can record a dose.
            NotificationDelegate.shared.router = NotificationActionRouter(services: services)
        }
    }
}

#Preview {
    MainTabView()
        .environment(ServiceContainer.mock())
        .environment(UserSession())
}
