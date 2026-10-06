import SwiftUI

/// One dose, as a card.
///
/// Three states, and each one says what happened three ways — colour, symbol
/// and word — so nothing depends on colour alone. A missed dose that reads as
/// taken is the failure mode worth designing against here.
struct DoseRow: View {
    let item: DashboardViewModel.DoseItem
    let model: DashboardViewModel

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.dose.medicine.name)
                        .font(Theme.Typography.cardTitle)
                        .tracking(Theme.Typography.cardTitleTracking)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.dose.scheduledAt.formatted(date: .omitted, time: .shortened))
                    .font(Theme.Typography.numeral(16))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if let outcome = item.outcome {
                Spacer().frame(height: 8)
                OutcomeBadge(outcome: outcome, recordedAt: item.recordedAt) {
                    Task { await model.clearOutcome(for: item) }
                }
            } else if item.isDue {
                Spacer().frame(height: 10)
                actions
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(alignment: .leading) {
            // A missed dose gets a red edge as well as a red word.
            if item.outcome == .missed {
                Rectangle()
                    .fill(Theme.Colors.missed)
                    .frame(width: 3)
            }
        }
        .cardSurface()
        .opacity(item.outcome == .taken ? 0.72 : 1)
        .animation(Theme.Motion.statusChange, value: item.outcome)
        .scaleEffect(isRevealed ? 1 : 0.97)
        .opacity(isRevealed ? 1 : 0)
        .onAppear { withAnimation(Theme.Motion.cardAppear) { isRevealed = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var subtitle: String {
        "\(item.dose.medicine.dosage) — \(item.dose.medicine.foodInstruction.displayName)"
    }

    private var accessibilitySummary: String {
        let state = item.outcome.map { "\($0.displayName)." } ?? "Not yet actioned."
        return "\(item.dose.medicine.name), \(subtitle). \(state)"
    }

    private var actions: some View {
        HStack(spacing: 8) {
            ActionButton(title: "Taken", tint: Theme.Colors.taken, isFilled: true) {
                Task { await model.record(.taken, for: item) }
            }
            ActionButton(title: "Missed", tint: Theme.Colors.missed) {
                Task { await model.record(.missed, for: item) }
            }
            ActionButton(title: "Snooze", tint: Theme.Colors.snoozed) {
                Task { await model.snooze(item) }
            }
        }
    }
}

// MARK: - Action buttons

private struct ActionButton: View {
    let title: String
    let tint: Color
    var isFilled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isFilled ? .white : tint)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isFilled ? tint : Theme.Colors.cardSurface)
                        .overlay {
                            if !isFilled {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(tint, lineWidth: 1)
                            }
                        }
                }
        }
        .buttonStyle(PressableCardStyle())
    }
}

// MARK: - Outcome badge

/// What happened, once it has happened. Tappable to undo — someone who
/// mis-taps "Missed" on their own medication should not be stuck with it.
private struct OutcomeBadge: View {
    let outcome: DoseOutcome
    let recordedAt: Date?
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: undo) {
                HStack(spacing: 6) {
                    Image(systemName: outcome.symbolName)
                        .font(.system(size: 13, weight: .bold))
                    Text(label)
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(outcome == .taken ? Theme.Colors.textPrimary : outcome.tint)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background {
                    if outcome == .taken {
                        Capsule().fill(Theme.Colors.surface)
                    } else {
                        Capsule()
                            .fill(Theme.Colors.cardSurface)
                            .overlay { Capsule().strokeBorder(outcome.tint, lineWidth: 1) }
                    }
                }
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityHint("Double tap to undo")

            if outcome == .missed {
                Text("Take now?")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }

    private var label: String {
        guard outcome == .taken, let recordedAt else { return outcome.displayName }
        return "Taken \(recordedAt.formatted(date: .omitted, time: .shortened))"
    }
}
