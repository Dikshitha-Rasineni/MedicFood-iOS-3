import SwiftUI

struct ProfileView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(ServiceContainer.self) private var services
    @Environment(UserSession.self) private var session

    @State private var viewModel: ProfileViewModel?
    @State private var isConfirmingSignOut = false
    @State private var didCopyCode = false

    var body: some View {
        let model = viewModel ?? ProfileViewModel(services: services)

        SettingsPage(title: "Profile") {
            if let profile = session.profile {
                identity(profile)

                if appServices.isDemo {
                    NoticeCard(
                        symbol: "play.circle.fill",
                        text: "You are in the demo. Everything here is sample data, and nothing is saved.",
                        tint: Theme.Colors.skipped
                    )
                }

                if let code = profile.shareCode {
                    shareCode(code)
                }
            }

            SettingsSection(
                title: "Notifications",
                footer: model.isNearNotificationLimit
                    // Surfacing the cap matters: past 64 pending notifications
                    // iOS silently drops the rest, and this is the only place
                    // it would ever be visible.
                    ? "You are at the iOS limit for scheduled reminders. MedicFood keeps a rolling window and tops it up each time you open the app, so later doses are still covered."
                    : "MedicFood schedules a rolling window of upcoming doses and refreshes it each time you open the app."
            ) {
                SettingsRow(
                    symbol: model.notificationsAuthorized ? "bell.fill" : "bell.slash.fill",
                    title: "Reminders",
                    tint: model.notificationsAuthorized ? Theme.Colors.primary : Theme.Colors.missed
                ) {
                    SettingsValue(text: model.notificationSummary)
                }

                if !model.notificationsAuthorized {
                    SettingsDivider()
                    SettingsButtonRow(symbol: "bell.badge.fill", title: "Turn on reminders") {
                        Task { await model.requestNotificationAccess() }
                    }
                }
            }

            SettingsSection {
                SettingsNavigationRow(symbol: "gearshape.fill", title: "Settings") { SettingsView() }
                SettingsDivider()
                SettingsNavigationRow(symbol: "questionmark.circle.fill", title: "Help and support") { HelpSupportView() }
                SettingsDivider()
                SettingsNavigationRow(symbol: "lock.shield.fill", title: "Privacy and security") { PrivacySecurityView() }
            }

            SettingsSection {
                SettingsButtonRow(
                    symbol: "rectangle.portrait.and.arrow.right",
                    title: "Sign out",
                    tint: Theme.Colors.missed
                ) {
                    isConfirmingSignOut = true
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task {
                    await model.signOut()
                    session.signOut()
                    // Leaving the demo restores whatever AppConfig.backend
                    // selects, so signing out of it lands on a real sign-in
                    // screen rather than a second demo session.
                    appServices.leaveDemo()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your scheduled reminders will be cancelled.")
        }
        .task {
            viewModel = model
            await model.refresh()
        }
    }

    // MARK: - Header

    /// Avatar, name, email — on the brand gradient rather than a plain row, so
    /// the screen opens with the person rather than with a list.
    private func identity(_ profile: UserProfile) -> some View {
        HStack(spacing: 14) {
            Text(profile.initials)
                .font(Theme.Typography.numeral(22))
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 56, height: 56)
                .background(.white)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(Theme.Typography.cardTitle)
                    .tracking(Theme.Typography.cardTitleTracking)
                    .foregroundStyle(.white)
                Text(profile.email)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Theme.Colors.primary, Theme.Colors.brand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
    }

    /// The share code, set in monospace and copyable.
    ///
    /// It is read out over a phone call, so the characters have to be
    /// unambiguous and spaced — and tapping to copy beats retyping it.
    private func shareCode(_ code: String) -> some View {
        SettingsSection(
            title: "Caretaker",
            footer: "Give this code to a caretaker so they can follow your schedule."
        ) {
            Button {
                UIPasteboard.general.string = code
                withAnimation(Theme.Motion.statusChange) { didCopyCode = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(Theme.Motion.statusChange) { didCopyCode = false }
                }
            } label: {
                SettingsRow(symbol: "qrcode", title: "Share code") {
                    HStack(spacing: 8) {
                        Text(code)
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Image(systemName: didCopyCode ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(didCopyCode ? Theme.Colors.taken : Theme.Colors.decorative)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .buttonStyle(PressableCardStyle())
        }
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .environment(AppServices())
        .environment(ServiceContainer.mock())
        .environment(UserSession())
}
