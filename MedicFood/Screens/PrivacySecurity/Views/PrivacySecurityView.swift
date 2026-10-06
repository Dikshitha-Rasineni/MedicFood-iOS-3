import SwiftUI

/// What the app stores and where it goes.
struct PrivacySecurityView: View {
    var body: some View {
        SettingsPage(title: "Privacy") {
            NoticeCard(
                symbol: "lock.shield.fill",
                text: "This is health data, and it is treated as such."
            )

            SettingsSection(title: "What is stored on this device") {
                BulletRow(text: "Your medicines, doses and schedule")
                BulletRow(text: "Which doses you marked taken, skipped or missed")
                BulletRow(text: "Your name and email, so you stay signed in")
            }

            SettingsSection(title: "What leaves this device") {
                BulletRow(text: "Nothing, unless you link a caretaker")
                BulletRow(text: "If you link one, they see your schedule and adherence — nothing else")
                BulletRow(text: "Drug searches go to public medicines databases and are not tied to your account")
            }

            SettingsSection(title: "Documents") {
                SettingsLinkRow(
                    symbol: "doc.text.fill",
                    title: "Privacy policy",
                    url: AppConfig.Support.privacyPolicy
                )
                SettingsDivider()
                SettingsLinkRow(
                    symbol: "doc.plaintext.fill",
                    title: "Terms of use",
                    url: AppConfig.Support.termsOfUse
                )
            }

            Text("You can remove a caretaker at any time from the Care screen, which stops all sharing immediately.")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { PrivacySecurityView() }
}
