import SwiftUI
import Observation

/// Holds the dose whose reminder should be shown in-app.
///
/// The notification delegate sets this when a reminder arrives while the app is
/// open, or when the user taps a reminder; `MainTabView` presents the sheet.
@MainActor
@Observable
final class ReminderPresenter {
    static let shared = ReminderPresenter()
    var current: Dose?

    func show(doseID: String) {
        Task {
            guard let router = NotificationDelegate.shared.router,
                  let dose = try? await router.dose(withID: doseID) else { return }
            current = dose
        }
    }
}

/// The in-app "Time for your medicine" alert.
struct MedicationReminderSheet: View {
    let dose: Dose

    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var voice = VoiceController()
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Time for your medicine")
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)

                MedicineThumbnail(
                    fileName: dose.medicine.frontImagePath,
                    form: dose.medicine.form,
                    size: 140
                )

                VStack(spacing: 4) {
                    Text(dose.medicine.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(dose.medicine.dosage)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("\(dose.scheduledAt.formatted(date: .omitted, time: .shortened)) · \(dose.medicine.form.displayName)")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if dose.medicine.foodInstruction != .anyTime {
                        Text(dose.medicine.foodInstruction.displayName)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                if voice.hasRecording {
                    Button {
                        voice.togglePlayback()
                    } label: {
                        Label(voice.isPlaying ? "Pause voice recording" : "Play voice recording",
                              systemImage: voice.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(Theme.Colors.primary)
                            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                VStack(spacing: 12) {
                    actionButton("TAKEN", fill: Theme.Colors.taken, text: .white) { await record(.taken) }
                    actionButton("SNOOZE", fill: Theme.Colors.surface, text: Theme.Colors.textPrimary) { await snooze() }
                    actionButton("DISMISSED", fill: Theme.Colors.cardSurface, text: Theme.Colors.skipped, border: Theme.Colors.skipped) { await record(.skipped) }
                }
                .disabled(isWorking)
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Colors.page.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear { voice.load(fileName: dose.medicine.voiceFilePath) }
        .onDisappear { voice.stopPlayback() }
    }

    private func actionButton(
        _ title: String,
        fill: Color,
        text: Color,
        border: Color? = nil,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.controlHeight)
                .foregroundStyle(text)
                .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if let border {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(border, lineWidth: 1.5)
                    }
                }
        }
    }

    private func record(_ outcome: DoseOutcome) async {
        isWorking = true
        try? await services.adherence.record(outcome, for: dose)
        await services.notifications.cancel(doseID: dose.id)
        dismiss()
    }

    private func snooze() async {
        isWorking = true
        await services.notifications.snooze(dose, byMinutes: NotificationService.snoozeMinutes)
        dismiss()
    }
}
