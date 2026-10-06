import SwiftUI

/// Chart and statistic marks, shared by Progress, the dashboard and Care.
///
/// Two rules these follow, because the old versions broke both:
///
/// 1. **Height and colour do not encode the same thing.** Colouring each bar by
///    its own value double-encodes what the bar length already says and burns
///    the one free channel. Bars are a single hue; colour is spent only on the
///    days that fall short, which is the thing worth finding.
/// 2. **A status is never colour alone.** Every status figure ships with an
///    icon and a word, so it survives colourblindness, greyscale print and a
///    glance.

// MARK: - Ring

/// A circular progress mark for a single rate.
///
/// Used instead of a bar for the headline figure: it reads as a whole/part at a
/// glance and gives the number somewhere to live.
struct ProgressRing<Label: View>: View {
    var rate: Double
    var lineWidth: CGFloat = 12
    var size: CGFloat = 132
    /// Generic over its label, the way a SwiftUI container is. An earlier
    /// version stored `AnyView` with `@ViewBuilder` on it, which is a builder
    /// attribute on a concrete boxed type — it compiled and then crashed in
    /// `initializeWithCopy`.
    @ViewBuilder var label: Label

    /// Animated separately so the ring sweeps on appear rather than snapping.
    @State private var animatedRate: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surface, lineWidth: lineWidth)

            // Nothing is drawn at zero. A round line cap on a zero-length
            // trim leaves a single coloured dot at twelve o'clock, which reads
            // as a rendering glitch rather than as "none yet".
            if rate > 0 {
                Circle()
                    .trim(from: 0, to: animatedRate)
                    .stroke(
                        Theme.Colors.adherence(rate),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    // Start at twelve o'clock, not three.
                    .rotationEffect(.degrees(-90))
            }

            label
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) {
                animatedRate = rate
            }
        }
        .onChange(of: rate) { _, new in
            withAnimation(Theme.Motion.statusChange) { animatedRate = new }
        }
    }
}

// MARK: - Status chip

/// A status as icon + word + colour, never colour on its own.
struct StatusChip: View {
    var symbol: String
    var text: String
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Stat tile

/// One figure with its name and a status mark.
///
/// Replaces a row of "label … number" lines. Four of these in a grid are
/// scannable in a way four stacked rows are not.
struct StatTile: View {
    var symbol: String
    var title: String
    var count: Int
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
            }

            // The figure wears ink, not the series colour — the icon beside it
            // already carries the identity.
            Text("\(count)")
                .font(Theme.Typography.numeral(26))
                .foregroundStyle(Theme.Colors.textPrimary)
                .contentTransition(.numericText())
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
    }
}

// MARK: - Bars

/// One day of a bar chart.
struct DayColumn: Identifiable {
    var id: Date { date }
    var date: Date
    var rate: Double
    var hasDoses: Bool
    /// Marked when the day fell short — the only thing colour is spent on.
    var isShortfall: Bool
}

/// A compact daily bar chart.
///
/// Hand-drawn rather than Swift Charts: one fewer framework, and it renders the
/// same on every supported iOS version.
struct DailyBars: View {
    var columns: [DayColumn]
    var showsWeekdays: Bool
    var height: CGFloat = 96

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(columns) { column in
                    bar(for: column)
                }
            }
            .frame(height: height, alignment: .bottom)
            .overlay(alignment: .bottom) {
                // A hairline baseline, one shade off the surface. Solid, never
                // dashed — a dashed rule reads as a threshold.
                Rectangle()
                    .fill(Theme.Colors.decorative.opacity(0.4))
                    .frame(height: 1)
            }

            if showsWeekdays {
                HStack(spacing: 3) {
                    ForEach(columns) { column in
                        Text(column.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.75))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func bar(for column: DayColumn) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(fill(for: column))
                // A day with no doses is a gap in the record, not a zero — it
                // gets a flat tick rather than an empty column that reads as a
                // missed day.
                .frame(height: column.hasDoses ? max(5, column.rate * height) : 3)
        }
        .frame(maxWidth: .infinity)
    }

    private func fill(for column: DayColumn) -> Color {
        guard column.hasDoses else { return Theme.Colors.decorative.opacity(0.35) }
        // One hue for the series; the status colour appears only where the day
        // fell short, so the eye goes straight to what needs attention.
        return column.isShortfall ? Theme.Colors.missed.opacity(0.85) : Theme.Colors.brand
    }
}
