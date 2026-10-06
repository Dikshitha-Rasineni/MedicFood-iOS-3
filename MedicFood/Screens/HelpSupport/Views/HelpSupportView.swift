import SwiftUI

/// Static help content.
struct HelpSupportView: View {

    private struct Question: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private let questions: [Question] = [
        Question(
            question: "What does 1-0-1 mean?",
            answer: "It is how doses are written on many prescriptions: morning-afternoon-night. 1-0-1 means one dose in the morning and one at night, with none in the afternoon. MedicFood reads this for you when you add a prescription."
        ),
        Question(
            question: "Why didn't a reminder appear?",
            answer: "Check that reminders are allowed in Settings. iOS also limits how many reminders an app can schedule at once, so MedicFood keeps the soonest ones registered and refreshes them each time you open the app — open it every few days during a long course."
        ),
        Question(
            question: "What is the difference between skipping and snoozing?",
            answer: "Snoozing moves the reminder later and changes nothing else. Skipping records that you did not take that dose, and it counts against your adherence figure."
        ),
        Question(
            question: "How do I let someone check on me?",
            answer: "Your Profile screen shows a six-character share code. Give it to whoever is looking after you and they enter it on their Caretaker screen."
        ),
        Question(
            question: "Can I change a dose I already recorded?",
            answer: "Yes. Tap Undo on the dose in your Today list."
        ),
    ]

    @State private var expanded: UUID?

    var body: some View {
        SettingsPage(title: "Help") {
            SettingsSection(title: "Common questions") {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SettingsDivider(inset: 14) }
                    FAQRow(
                        question: item.question,
                        answer: item.answer,
                        isExpanded: expanded == item.id
                    ) {
                        withAnimation(Theme.Motion.cardAppear) {
                            // Accordion: opening one closes the other, so the
                            // list never becomes a wall of text to scroll past.
                            expanded = expanded == item.id ? nil : item.id
                        }
                    }
                }
            }

            SettingsSection(title: "Get in touch") {
                SettingsLinkRow(
                    symbol: "envelope.fill",
                    title: AppConfig.Support.email,
                    url: URL(string: "mailto:\(AppConfig.Support.email)")!
                )
            }

            NoticeCard(
                symbol: "stethoscope",
                text: "MedicFood gives reminders and general information. It is not medical advice. Always follow your doctor or pharmacist.",
                tint: Theme.Colors.skipped
            )
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One question, with its answer revealed in place.
///
/// Built here rather than with `DisclosureGroup`, which draws its own chevron
/// and spacing and cannot be brought onto the palette.
private struct FAQRow: View {
    var question: String
    var answer: String
    var isExpanded: Bool
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    Text(question)
                        .font(Theme.Typography.body.weight(.medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Colors.primary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())

            if isExpanded {
                Text(answer)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}

#Preview {
    NavigationStack { HelpSupportView() }
}
