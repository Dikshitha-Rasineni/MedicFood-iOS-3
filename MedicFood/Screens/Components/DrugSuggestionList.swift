import SwiftUI

/// The autocomplete dropdown under a search box.
///
/// Each line is what the user could be typing: a drug, or a brand name with the
/// drug it belongs to underneath. The part already typed is set bold so the
/// eye finds what is *left* to type.
struct DrugSuggestionList: View {
    var suggestions: [DrugSuggestion]
    var query: String
    var onSelect: (DrugSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.Colors.decorative.opacity(0.28))
                        .frame(height: 1)
                        .padding(.leading, 46)
                }
                Button {
                    onSelect(suggestion)
                } label: {
                    SuggestionRow(suggestion: suggestion, query: query)
                }
                .buttonStyle(PressableCardStyle())
            }
        }
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }
}

private struct SuggestionRow: View {
    let suggestion: DrugSuggestion
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.subtitle == nil ? "magnifyingglass" : "tag")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(highlighted(suggestion.title))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let subtitle = suggestion.subtitle {
                    Text("Brand of \(subtitle)")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.85))
                }
            }

            Spacer(minLength: 8)

            // The same "fill this in" arrow the system keyboard uses.
            Image(systemName: "arrow.up.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.decorative)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func highlighted(_ title: String) -> AttributedString {
        var text = AttributedString(title)
        let typed = query.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty,
           let range = text.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].font = .system(size: 16, weight: .bold)
        }
        return text
    }
}
