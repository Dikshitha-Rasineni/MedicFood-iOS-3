import SwiftUI

struct ProfileView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(ServiceContainer.self) private var services
    @Environment(UserSession.self) private var session

    @State private var viewModel: ProfileViewModel?
    @State private var isConfirmingSignOut = false

    var body: some View {
        let model = viewModel ?? ProfileViewModel(services: services)

        List {
            if let profile = session.profile {
                Section {
                    HStack(spacing: 14) {
                        Text(profile.initials)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Theme.Colors.accent)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.headline)
                            Text(profile.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let code = profile.shareCode {
                    Section {
                        LabeledContent("Share code", value: code)
                            .font(.body.monospaced())
                    } header: {
                        Text("Caretaker")
                    } footer: {
                        Text("Give this code to a caretaker so they can follow your schedule.")
                    }
                }
            }

            Section {
                HStack {
                    Label("Reminders", systemImage: model.notificationsAuthorized ? "bell.fill" : "bell.slash")
                    Spacer()
                    Text(model.notificationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !model.notificationsAuthorized {
                    Button("Turn on reminders") {
                        Task { await model.requestNotificationAccess() }
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                if model.isNearNotificationLimit {
                    // Surfacing the cap matters: past 64 pending notifications
                    // iOS silently drops the rest, and this is the only place
                    // it would ever be visible.
                    Text("You are at the iOS limit for scheduled reminders. MedicFood keeps a rolling window and tops it up each time you open the app, so later doses are still covered.")
                } else {
                    Text("MedicFood schedules a rolling window of upcoming doses and refreshes it each time you open the app.")
                }
            }

            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                NavigationLink {
                    HelpSupportView()
                } label: {
                    Label("Help and support", systemImage: "questionmark.circle")
                }
                NavigationLink {
                    PrivacySecurityView()
                } label: {
                    Label("Privacy and security", systemImage: "lock.shield")
                }
            }

            Section {
                Button("Sign out", role: .destructive) {
                    isConfirmingSignOut = true
                }
            }
        }
        .navigationTitle("Profile")
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
}

#Preview {
    NavigationStack { ProfileView() }
        .environment(ServiceContainer.mock())
        .environment(UserSession())
}
