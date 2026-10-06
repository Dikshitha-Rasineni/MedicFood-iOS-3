import SwiftUI

/// Scan a prescription, read it, review the medicines, then continue.
struct PrescriptionScannerView: View {
    @Environment(ServiceContainer.self) private var services
    @State private var model: PrescriptionScannerViewModel?

    var body: some View {
        Group {
            if let model {
                ScannerContent(model: model)
            } else {
                Theme.Colors.page.ignoresSafeArea()
            }
        }
        .onAppear {
            if model == nil { model = PrescriptionScannerViewModel(services: services) }
        }
    }
}

private struct ScannerContent: View {
    @Bindable var model: PrescriptionScannerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                imageCard
                readButton
                dictationCard

                if model.image == nil && !model.hasRead {
                    Button("Or type the prescription instead") { model.startTyping() }
                        .font(.subheadline.weight(.semibold))
                }

                if model.isProcessing { processingCard }
                if let notice = model.aiNotice {
                    NoticeCard(symbol: "info.circle.fill", text: notice, tint: Theme.Colors.skipped)
                }
                if let error = model.errorMessage { ErrorBanner(message: error) }
                if model.hasRead || !model.extractedText.isEmpty { textCard }
                if !model.drafts.isEmpty { reviewCard }

                voiceCard
            }
            .padding(.horizontal, Theme.Metrics.pageMargin)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .aiConsentAlert(model.consent)
        .background(Theme.Colors.page.ignoresSafeArea())
        .navigationTitle("Scan Prescription")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") { model.beginAddFlow() }
                    .disabled(!model.canContinue)
            }
        }
        .navigationDestination(item: $model.addSeed) { seed in
            AddMedicineView(prefill: seed, isModal: false, onSaved: { model.advance() })
        }
        .onChange(of: model.isFinished) { _, finished in
            if finished { dismiss() }
        }
    }

    // MARK: Pieces

    private var imageCard: some View {
        Card {
            MedicineImageSlot(
                title: "Prescription",
                image: $model.image,
                usesDocumentScanner: true
            )
        }
    }

    private var readButton: some View {
        Button {
            Task { await model.readPrescription() }
        } label: {
            Label("Read Prescription", systemImage: "text.viewfinder")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.controlHeight)
                .foregroundStyle(.white)
                .background(
                    model.canRead ? Theme.Colors.primary : Theme.Colors.decorative,
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
                )
        }
        .disabled(!model.canRead)
    }

    private var processingCard: some View {
        Card {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading prescription...").font(.subheadline.weight(.semibold))
                    Text("Extracting medicines...").font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Say the medicines instead of photographing a page.
    private var dictationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Say it instead").sectionLabelStyle()

                Button {
                    Task { await model.toggleDictation() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.dictation.isListening ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 26))
                            .symbolEffect(.pulse, isActive: model.dictation.isListening)
                        Text(model.dictation.isListening ? "Listening. Tap when you are done" : "Tap and say your medicines")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(model.dictation.isListening ? .white : Theme.Colors.primary)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metrics.controlHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
                            .fill(model.dictation.isListening ? Theme.Colors.primary : Theme.Colors.surface)
                    )
                }
                .buttonStyle(PressableCardStyle())
                .disabled(model.isProcessing)
                .animation(Theme.Motion.statusChange, value: model.dictation.isListening)

                if model.dictation.isListening {
                    // The words appear as they are said, so a misheard drug
                    // name is visible before anything is done with it.
                    Text(model.dictation.transcript.isEmpty ? "Go ahead, I am listening..." : model.dictation.transcript)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("For example: \"Metformin 500 mg twice a day after food for 30 days, and vitamin D once a week.\" You can correct the words before saving.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if case .blocked(let message) = model.dictation.state {
                    ErrorBanner(message: message)
                }
            }
        }
    }

    private var textCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Read prescription").sectionLabelStyle()

                TextField(
                    "Amoxicillin 500mg 1-0-1 after food",
                    text: $model.extractedText,
                    axis: .vertical
                )
                .lineLimit(4...12)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.Colors.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("One medicine per line. Fix anything the scan got wrong, then extract again. MedicFood understands 1-0-1, BD, TID and QID.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Button("Extract medicines") { Task { await model.extractFromText() } }
                    .font(.subheadline.weight(.semibold))
                    .disabled(model.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Extracted medicines").sectionLabelStyle()
            Text("Check before saving. Tap the circle to include or exclude a medicine; every field can be edited.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            // Said every time, because it is true every time: whoever read it,
            // a misread dose is a medication error and only the person holding
            // the prescription can catch it.
            if let source = model.readSource {
                Label(
                    source == .gemini
                        ? "Read with Gemini AI. Check each one against your prescription."
                        : "Read on this device. Check each one against your prescription.",
                    systemImage: source == .gemini ? "sparkles" : "iphone"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.primary)
            }

            ForEach($model.drafts) { $draft in
                DraftRow(draft: $draft)
            }
        }
    }

    private var voiceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Voice Recording").sectionLabelStyle()
                VoiceRecordingView(voice: model.voice)
            }
        }
    }
}

private struct DraftRow: View {
    @Binding var draft: PrescriptionScannerViewModel.DraftMedicine

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    draft.isSelected.toggle()
                } label: {
                    Image(systemName: draft.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(draft.isSelected ? Theme.Colors.primary : Theme.Colors.decorative)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(draft.isSelected ? "Included. Tap to exclude." : "Excluded. Tap to include.")

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Medicine name", text: $draft.name)
                        .font(.body.weight(.semibold))
                    HStack {
                        TextField("Dosage", text: $draft.dosage)
                        TextField("1-0-1, BD…", text: $draft.shorthand)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .font(.subheadline)

                    Text([draft.dosage, draft.summary].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .opacity(draft.isSelected ? 1 : 0.5)
        }
    }
}

#Preview {
    NavigationStack { PrescriptionScannerView() }
        .environment(ServiceContainer.mock())
}
