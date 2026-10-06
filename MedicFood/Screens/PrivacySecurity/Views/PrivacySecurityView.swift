import SwiftUI

/// What the app stores and where it goes.
struct PrivacySecurityView: View {
    var body: some View {
        List {
            Section {
                Text("This is health data, and it is treated as such.")
                    .font(.subheadline.weight(.medium))
            }

            Section("What is stored on this device") {
                bullet("Your medicines, doses and schedule")
                bullet("Which doses you marked taken, skipped or missed")
                bullet("Your name and email, so you stay signed in")
            }

            Section("What leaves this device") {
                bullet("Nothing, unless you link a caretaker")
                bullet("If you link one, they see your schedule and adherence — nothing else")
                bullet("Drug searches go to public medicines databases and are not tied to your account")
            }

            Section {
                Link(destination: AppConfig.Support.privacyPolicy) {
                    Label("Privacy policy", systemImage: "arrow.up.right.square")
                }
                Link(destination: AppConfig.Support.termsOfUse) {
                    Label("Terms of use", systemImage: "arrow.up.right.square")
                }
            }

            Section {
                Text("You can remove a caretaker at any time from the Caretaker screen, which stops all sharing immediately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 7)
            Text(text)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
    }
}

#Preview {
    NavigationStack { PrivacySecurityView() }
}
