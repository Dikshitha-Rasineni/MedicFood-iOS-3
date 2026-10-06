import SwiftUI

/// Shared visual language, so a colour, a type style or a corner radius is
/// defined once.
///
/// This is design system **v2** — the green palette set by the team, with the
/// contrast corrections that the raw palette needed. Every colour in the app
/// resolves through here; nothing is hardcoded in a view.
enum Theme {

    // MARK: - Colour

    enum Colors {

        // The palette as handed over.
        static let page        = Color(hex: 0xE8F5E9)   // page background
        static let surface     = Color(hex: 0xC8E6C9)   // badges, secondary fills
        static let cardSurface = Color.white            // cards, logo plate
        static let primary     = Color(hex: 0x2E7D32)   // filled buttons, secondary text
        static let brand       = Color(hex: 0x4CAF50)   // accent, progress fill
        static let decorative  = Color(hex: 0x81C784)   // never text, never a lone icon

        static let textPrimary   = Color(hex: 0x1B5E20)
        static let textSecondary = Color(hex: 0x2E7D32)

        /// Legacy names, kept so the screens the rest of the team owns keep
        /// compiling. They now resolve to the v2 palette.
        static let accent     = primary
        static let background = page
        static let card       = cardSurface

        // MARK: Status
        //
        // Deliberately outside the green scale. A missed dose must not look
        // like a taken one, and an all-green palette cannot say "missed" —
        // in a medication app that is a safety property, not a style choice.

        static let taken   = Color(hex: 0x2E7D32)
        /// Amber, 5.02:1 on white — passes as label text *and* as a filled
        /// bar. An earlier darker value passed contrast but read as brown once
        /// it was drawn at chart size.
        static let skipped = Color(hex: 0xB45309)
        static let missed  = Color(hex: 0xC62828)
        static let snoozed = skipped
        static let pending = textSecondary

        /// Adherence figures read as a grade, so colour them like one.
        ///
        /// Four steps that stay distinguishable as *large filled shapes*, not
        /// just as text: deep green, brand green, amber, red. These get drawn
        /// as bars on the Progress tab, where a colour chosen only for label
        /// contrast turns muddy.
        static func adherence(_ rate: Double) -> Color {
            switch rate {
            case 0.9...:    taken
            case 0.7..<0.9: brand
            case 0.5..<0.7: skipped
            default:        missed
            }
        }
    }

    // MARK: - Type
    //
    // Display / Text / Rounded split. Rounded carries every numeral — counts,
    // times, percentages — which is what stops a health app reading like a
    // spreadsheet. Negative tracking on everything large; hard Bold-against-
    // Regular contrast with nothing in between.

    enum Typography {
        /// 40 Bold, -2% — greetings and the splash wordmark.
        static let display = Font.system(size: 40, weight: .bold)
        /// 28 Bold, -1.5% — screen titles.
        static let screenTitle = Font.system(size: 28, weight: .bold)
        /// 19 Semibold, -1% — card titles.
        static let cardTitle = Font.system(size: 19, weight: .semibold)
        static let body = Font.system(size: 16, weight: .regular)
        static let caption = Font.system(size: 14, weight: .regular)
        /// 12 Semibold uppercase, +8% tracking.
        static let sectionLabel = Font.system(size: 12, weight: .semibold)

        /// Numerals: rounded, bold, tabular so digits don't jitter as they change.
        static func numeral(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        // Tracking is expressed in points at the size it applies to.
        static let displayTracking: CGFloat     = -0.8
        static let screenTitleTracking: CGFloat = -0.42
        static let cardTitleTracking: CGFloat   = -0.19
        static let sectionTracking: CGFloat     = 0.96
    }

    // MARK: - Geometry

    enum Metrics {
        static let cornerRadius: CGFloat = 14
        static let cardPadding: CGFloat = 16
        static let rowSpacing: CGFloat = 12
        static let pageMargin: CGFloat = 16
        static let controlHeight: CGFloat = 52
        static let shadow = (color: Color.black.opacity(0.06), radius: CGFloat(12), y: CGFloat(2))

    }

    /// Motion, in one place so screens feel like one app.
    enum Motion {
        static let cardAppear = Animation.spring(response: 0.5, dampingFraction: 0.82)
        static let statusChange = Animation.spring(response: 0.35, dampingFraction: 0.75)
        static let ringSpin = Animation.linear(duration: 1.2).repeatForever(autoreverses: false)
    }
}

// MARK: - System chrome

extension Theme {
    /// Bring UIKit-backed chrome onto the palette.
    ///
    /// `navigationTitle` renders through `UINavigationBar`, which keeps its own
    /// black label and translucent grey no matter what SwiftUI is doing — so
    /// every pushed screen had a black title sitting above green content.
    /// Called once at launch.
    @MainActor
    static func applySystemAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(Colors.page)
        navigation.shadowColor = .clear

        let title = [NSAttributedString.Key.foregroundColor: UIColor(Colors.textPrimary)]
        navigation.titleTextAttributes = title
        navigation.largeTitleTextAttributes = title

        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = UIColor(Colors.primary)

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = .white
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

// MARK: - Reusable text styles

extension View {
    /// A 12pt uppercase section label with wide tracking.
    func sectionLabelStyle() -> some View {
        self.font(Theme.Typography.sectionLabel)
            .tracking(Theme.Typography.sectionTracking)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.textPrimary)
    }

    /// The card treatment used everywhere: white, r14, one soft shadow.
    func cardSurface(cornerRadius: CGFloat = Theme.Metrics.cornerRadius) -> some View {
        self.background(Theme.Colors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: Theme.Metrics.shadow.color,
                radius: Theme.Metrics.shadow.radius,
                y: Theme.Metrics.shadow.y
            )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension DoseOutcome {
    var tint: Color {
        switch self {
        case .taken:   Theme.Colors.taken
        case .skipped: Theme.Colors.skipped
        case .missed:  Theme.Colors.missed
        }
    }

    var symbolName: String {
        switch self {
        case .taken:   "checkmark.circle.fill"
        case .skipped: "arrow.uturn.right.circle.fill"
        case .missed:  "xmark.circle.fill"
        }
    }
}
