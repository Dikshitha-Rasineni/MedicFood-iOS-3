import SwiftUI

/// App preferences.
struct SettingsView: View {
    @Environment(ServiceContainer.self) private var services

    @AppStorage("settings.reminderSound") private var reminderSound = true
    @AppStorage("settings.shareWithCaretaker") private var shareWithCaretaker = true
    @AppStorage("settings.analytics") private var analyticsEnabled = false

    @State private var viewModel: ProfileViewModel?

    var body: some View {
        let model = viewModel ?? ProfileViewModel(services: services)

        List {
            Section {
                HStack {
                    Label("Permission", systemImage: model.notificationsAuthorized ? "bell.fill" : "bell.slash")
                    Spacer()
                    Text(model.notificationsAuthorized ? "Allowed" : "Not allowed")
                        .foregroundStyle(.secondary)
                }

                if !model.notificationsAuthorized {
                    Button("Turn on reminders") {
                        Task { await model.requestNotificationAccess() }
                    }
                }

                Toggle("Sound", isOn: $reminderSound)

                LabeledContent("Scheduled", value: "\(model.pendingReminderCount)")
            } header: {
                Text("Reminders")
            } footer: {
                Text("iOS allows \(AppConfig.Reminders.iosPendingLimit) scheduled reminders per app. MedicFood keeps the soonest \(AppConfig.Reminders.windowSize) registered and refreshes them each time you open it, so a long prescription is still covered.")
            }

            Section {
                Toggle("Share my adherence with my caretaker", isOn: $shareWithCaretaker)
                Toggle("Send anonymous usage data", isOn: $analyticsEnabled)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Your medicine data stays on this device unless you turn on caretaker sharing.")
            }

            Section("About") {
                LabeledContent("Version", value: "\(AppConfig.version) (\(AppConfig.build))")
                NavigationLink("Help and support") { HelpSupportView() }
                NavigationLink("Privacy and security") { PrivacySecurityView() }
            }
        }
        .navigationTitle("Settings")
        .task {
            viewModel = model
            await model.refresh()
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(ServiceContainer.mock())
}
