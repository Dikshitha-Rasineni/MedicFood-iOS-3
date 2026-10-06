import SwiftUI

/// First-run introduction.
///
/// Three pages, skippable. It exists because the app asks for notification
/// permission early, and a permission prompt with no explanation gets denied.
struct FeatureTourView: View {

    @AppStorage("medicfood.hasSeenFeatureTour") private var hasSeenTour = false
    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let message: String
    }

    private let pages = [
        Page(
            symbol: "text.viewfinder",
            title: "Add your prescription",
            message: "Type what the doctor wrote — including 1-0-1 shorthand — and MedicFood works out when each dose is due."
        ),
        Page(
            symbol: "bell.badge",
            title: "Get reminded on time",
            message: "Reminders arrive when a dose is due. Mark it taken, skip it, or snooze straight from the notification."
        ),
        Page(
            symbol: "person.2",
            title: "Let someone check in",
            message: "Share a six-character code and a family member can see how you are getting on."
        ),
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 18) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 72))
                            .foregroundStyle(Theme.Colors.accent)
                        Text(item.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(item.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page)

            Button(page == pages.count - 1 ? "Get started" : "Next") {
                if page == pages.count - 1 {
                    hasSeenTour = true
                } else {
                    withAnimation { page += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)

            Button("Skip") { hasSeenTour = true }
                .font(.subheadline)
                .padding(.vertical, 12)
        }
        .background(Theme.Colors.background)
    }
}

#Preview {
    FeatureTourView()
}
