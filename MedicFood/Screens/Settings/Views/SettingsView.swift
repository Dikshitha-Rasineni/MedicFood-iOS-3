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

        SettingsPage(title: "Settings") {
            SettingsSection(
                title: "Reminders",
                footer: "iOS allows \(AppConfig.Reminders.iosPendingLimit) scheduled reminders per app. MedicFood keeps the soonest \(AppConfig.Reminders.windowSize) registered and refreshes them each time you open it, so a long prescription is still covered."
            ) {
                SettingsRow(
                    symbol: model.notificationsAuthorized ? "bell.fill" : "bell.slash.fill",
                    title: "Permission",
                    // The status is the point of this row, so it carries the
                    // colour: a denied permission means no reminders at all.
                    tint: model.notificationsAuthorized ? Theme.Colors.primary : Theme.Colors.missed
                ) {
                    SettingsValue(text: model.notificationsAuthorized ? "Allowed" : "Not allowed")
                }

                if !model.notificationsAuthorized {
                    SettingsDivider()
                    SettingsButtonRow(
                        symbol: "bell.badge.fill",
                        title: "Turn on reminders",
                        subtitle: "Opens Settings so you can allow notifications"
                    ) {
                        Task { await model.requestNotificationAccess() }
                    }
                }

                SettingsDivider()
                SettingsToggleRow(symbol: "speaker.wave.2.fill", title: "Sound", isOn: $reminderSound)

                SettingsDivider()
                SettingsRow(symbol: "calendar", title: "Scheduled") {
                    SettingsValue(text: "\(model.pendingReminderCount)")
                }
            }

            SettingsSection(
                title: "Privacy",
                footer: "Your medicine data stays on this device unless you turn on caretaker sharing."
            ) {
                SettingsToggleRow(
                    symbol: "person.2.fill",
                    title: "Share with my caretaker",
                    subtitle: "They see your schedule and adherence",
                    isOn: $shareWithCaretaker
                )
                SettingsDivider()
                SettingsToggleRow(
                    symbol: "chart.bar.fill",
                    title: "Send anonymous usage data",
                    isOn: $analyticsEnabled
                )
            }

            SettingsSection(title: "About") {
                SettingsRow(symbol: "info.circle.fill", title: "Version") {
                    SettingsValue(text: "\(AppConfig.version) (\(AppConfig.build))")
                }
                SettingsDivider()
                SettingsNavigationRow(symbol: "questionmark.circle.fill", title: "Help and support") {
                    HelpSupportView()
                }
                SettingsDivider()
                SettingsNavigationRow(symbol: "lock.shield.fill", title: "Privacy and security") {
                    PrivacySecurityView()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
