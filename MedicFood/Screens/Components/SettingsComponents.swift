import SwiftUI

/// The building blocks for every list-shaped screen — Settings, Profile, Help,
/// Privacy.
///
/// Those screens were built on `List`/`Form`, which paints iOS's own grey
/// `.insetGrouped` background and ignores the palette entirely. Next to the
/// green dashboard they read as a different app. These rebuild the same
/// grouped-row shape on `Theme`, so a row looks the same wherever it appears
/// and the page keeps its background.
///
/// Rows are divided by a hairline *inset past the icon column*, the way a
/// system list does it — that alignment is most of what makes a grouped list
/// look deliberate rather than like stacked boxes.

// MARK: - Section

/// A titled group of rows on one card, with an optional explanatory footer.
struct SettingsSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .sectionLabelStyle()
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(Theme.Colors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
            .shadow(
                color: Theme.Metrics.shadow.color,
                radius: Theme.Metrics.shadow.radius,
                y: Theme.Metrics.shadow.y
            )

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }
}

/// The hairline between rows. Inset to clear the icon column so the text edges
/// line up down the card.
struct SettingsDivider: View {
    var inset: CGFloat = 52

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.decorative.opacity(0.28))
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// MARK: - Rows

/// The icon treatment shared by every row: a tinted rounded square, never a
/// bare glyph. One consistent optical weight down the column.
struct SettingsIcon: View {
    var symbol: String
    var tint: Color = Theme.Colors.primary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// A plain row: icon, title, optional subtitle, optional trailing value.
struct SettingsRow<Trailing: View>: View {
    var symbol: String
    var title: String
    var subtitle: String?
    var tint: Color = Theme.Colors.primary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(symbol: String, title: String, subtitle: String? = nil, tint: Color = Theme.Colors.primary) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

/// A read-only value on the right, e.g. "Version — 1.0 (1)".
struct SettingsValue: View {
    var text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.8))
    }
}

/// The chevron that marks a row as going somewhere.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Colors.decorative)
    }
}

/// A row that pushes another screen.
struct SettingsNavigationRow<Destination: View>: View {
    var symbol: String
    var title: String
    var subtitle: String?
    var tint: Color = Theme.Colors.primary
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRow(symbol: symbol, title: title, subtitle: subtitle, tint: tint) {
                SettingsChevron()
            }
        }
        .buttonStyle(PressableCardStyle())
    }
}

/// A row that performs an action in place.
struct SettingsButtonRow: View {
    var symbol: String
    var title: String
    var subtitle: String?
    var tint: Color = Theme.Colors.primary
    var showsChevron: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRow(symbol: symbol, title: title, subtitle: subtitle, tint: tint) {
                if showsChevron { SettingsChevron() }
            }
        }
        .buttonStyle(PressableCardStyle())
    }
}

/// A row carrying a switch.
struct SettingsToggleRow: View {
    var symbol: String
    var title: String
    var subtitle: String?
    var tint: Color = Theme.Colors.primary
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(symbol: symbol, title: title, subtitle: subtitle, tint: tint) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.Colors.primary)
        }
    }
}

/// An external link row, marked with the out-of-app glyph.
struct SettingsLinkRow: View {
    var symbol: String
    var title: String
    var url: URL

    var body: some View {
        Link(destination: url) {
            SettingsRow(symbol: symbol, title: title) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.decorative)
            }
        }
        .buttonStyle(PressableCardStyle())
    }
}

// MARK: - Prose

/// A bulleted line of explanatory text inside a card.
struct BulletRow: View {
    var text: String
    var tint: Color = Theme.Colors.brand

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
                .padding(.top, 7)

            Text(text)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

/// A highlighted statement — the one sentence a screen leads with.
struct NoticeCard: View {
    var symbol: String
    var text: String
    var tint: Color = Theme.Colors.primary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)

            Text(text)
                .font(Theme.Typography.body.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        // A tinted wash over the green page turns muddy — an amber at 10%
        // reads olive, a red reads brown. Theme warns about exactly this. So
        // the card stays white and the tint appears only where it is a solid
        // shape: the icon, and a bar down the leading edge.
        .background(
            ZStack(alignment: .leading) {
                Theme.Colors.cardSurface
                Rectangle().fill(tint).frame(width: 3)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
        .shadow(
            color: Theme.Metrics.shadow.color,
            radius: Theme.Metrics.shadow.radius,
            y: Theme.Metrics.shadow.y
        )
    }
}

/// The standard page wrapper for these screens: a large title, the palette's
/// background, and consistent margins.
struct SettingsPage<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(title)
                    .font(Theme.Typography.screenTitle)
                    .tracking(Theme.Typography.screenTitleTracking)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, 8)

                content
            }
            .padding(.horizontal, Theme.Metrics.pageMargin)
            .padding(.bottom, 32)
        }
        .background(Theme.Colors.page)
        .scrollIndicators(.hidden)
    }
}
