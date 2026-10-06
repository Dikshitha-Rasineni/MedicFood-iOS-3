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

    var body: some View {
        List {
            Section("Common questions") {
                ForEach(questions) { item in
                    DisclosureGroup(item.question) {
                        Text(item.answer)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }

            Section("Get in touch") {
                Link(destination: URL(string: "mailto:\(AppConfig.Support.email)")!) {
                    Label(AppConfig.Support.email, systemImage: "envelope")
                }
            }

            Section {
                Text("MedicFood gives reminders and general information. It is not medical advice. Always follow your doctor or pharmacist.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { HelpSupportView() }
}
