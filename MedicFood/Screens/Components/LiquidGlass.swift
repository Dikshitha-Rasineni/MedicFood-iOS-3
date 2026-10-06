import SwiftUI

/// Liquid Glass, with a fallback.
///
/// `glassEffect` is iOS 26 only, but the project deploys to iOS 17 — raising
/// the target to 26 would drop every device the team actually tests on. So the
/// effect is applied where it exists and a translucent material stands in
/// where it doesn't. Both read as a floating surface; only one refracts.
///
/// Use it for surfaces that *float over* content — a pinned bar, an overlay
/// card. Ordinary cards use `.cardSurface()` instead, because glass over a
/// solid page just looks like a muddy white.
struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.Metrics.cornerRadius
    var tint: Color?
    var isInteractive: Bool = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                glass,
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
                .background(.ultraThinMaterial)
                .background(tint?.opacity(0.12) ?? Theme.Colors.cardSurface.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.08), radius: 14, y: 4)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if isInteractive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    /// A floating glass surface. See `LiquidGlassBackground` for when to use it.
    func liquidGlass(
        cornerRadius: CGFloat = Theme.Metrics.cornerRadius,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(LiquidGlassBackground(
            cornerRadius: cornerRadius,
            tint: tint,
            isInteractive: interactive
        ))
    }
}

/// A button that presses like a physical thing: a small scale and a softening,
/// spring-damped both ways. Used on every tappable card.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
