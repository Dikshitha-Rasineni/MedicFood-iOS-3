import SwiftUI

/// Everything about one medicine, with edit, reminder settings and deactivate.
struct MedicineDetailView: View {
    let medicine: Medicine
    let model: MedicineListViewModel

    @Environment(ServiceContainer.self) private var services

    @State private var isEditing = false
    @State private var food: MedicineFoodViewModel?
    @State private var voice = VoiceController()
    @State private var previewImage: UIImage?
    @State private var testMessage: String?

    /// The list's latest copy, so toggles reflect immediately.
    private var current: Medicine {
        model.medicines.first { $0.id == medicine.id } ?? medicine
    }

    var body: some View {
        let item = current

        List {
            Section {
                HStack(spacing: 14) {
                    MedicineThumbnail(fileName: item.frontImagePath ?? item.backImagePath, form: item.form, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.title3.weight(.bold))
                        Text(item.dosage).foregroundStyle(Theme.Colors.textSecondary)
                        if !item.isActive {
                            Text("Inactive").font(.caption.weight(.semibold)).foregroundStyle(Theme.Colors.skipped)
                        }
                    }
                }
            }
            .listRowBackground(Theme.Colors.cardSurface)

            Section {
                LabeledContent("Dosage", value: item.dosage)
                LabeledContent("Form", value: item.form.displayName)
                LabeledContent("Frequency", value: item.frequencyDescription)
                LabeledContent("Times", value: item.exactTimesDescription)
                LabeledContent("Food", value: item.foodInstruction.displayName)
            }
            .listRowBackground(Theme.Colors.cardSurface)

            Section("Course") {
                LabeledContent("Started", value: item.startDate.formatted(date: .abbreviated, time: .omitted))
                if let end = item.endDate {
                    LabeledContent("Ends", value: end.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Duration", value: "\(item.durationDays ?? 0) days")
                } else {
                    LabeledContent("Ends", value: "Ongoing")
                }
            }
            .listRowBackground(Theme.Colors.cardSurface)

            if let instructions = item.instructions, !instructions.isEmpty {
                Section("Instructions") { Text(instructions) }
                    .listRowBackground(Theme.Colors.cardSurface)
            }

            foodSection(item)

            imagesSection(item)

            if voice.hasRecording {
                Section("Voice recording") {
                    Button {
                        voice.togglePlayback()
                    } label: {
                        Label(
                            voice.isPlaying ? "Pause recording" : "Play recording  \(VoiceController.format(voice.duration))",
                            systemImage: voice.isPlaying ? "pause.circle.fill" : "play.circle.fill"
                        )
                    }
                }
                .listRowBackground(Theme.Colors.cardSurface)
            }

            Section {
                Toggle("Reminders", isOn: Binding(
                    get: { current.isReminderOn },
                    set: { value in Task { await model.setReminders(value, for: current) } }
                ))

                Button("Change reminder times") { isEditing = true }

                Button("Test reminder") {
                    Task {
                        await model.testReminder(for: current)
                        testMessage = "A test reminder will arrive in about 5 seconds. Leave the app or lock your phone to see the notification buttons."
                    }
                }
            } header: {
                Text("Reminder settings")
            } footer: {
                Text(testMessage ?? "Turning reminders off keeps the medicine on your list but stops notifications.")
            }
            .listRowBackground(Theme.Colors.cardSurface)

            Section {
                Toggle("Active", isOn: Binding(
                    get: { current.isActive },
                    set: { value in Task { await model.setActive(value, for: current) } }
                ))
                Button("Delete medicine", role: .destructive) {
                    Task { await model.delete(current) }
                }
            } footer: {
                Text("Deactivate to pause this medicine without losing it.")
            }
            .listRowBackground(Theme.Colors.cardSurface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.page.ignoresSafeArea())
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { AddMedicineView(editing: current) }
        }
        .fullScreenCover(isPresented: Binding(get: { previewImage != nil }, set: { if !$0 { previewImage = nil } })) {
            if let previewImage { ImagePreview(image: previewImage) }
        }
        .onAppear { voice.load(fileName: item.voiceFilePath) }
        .onDisappear { voice.stopPlayback() }
        .onChange(of: isEditing) { _, isPresented in
            if !isPresented { Task { await model.load() } }
        }
    }

    // MARK: - Food and drink

    /// What to eat and what to avoid with this medicine.
    ///
    /// The whole point of the app, and until now it lived only on a separate
    /// screen the user had to search by hand. The name is normalised before
    /// lookup — see `DrugNameNormalizer` — because a prescription and the
    /// catalogue spell the same drug differently.
    @ViewBuilder
    private func foodSection(_ item: Medicine) -> some View {
        Section {
            switch food?.state ?? .idle {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.Colors.primary)
                    Text("Checking food interactions…")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

            case .found(let interactions, let matched):
                ForEach(interactions) { interaction in
                    FoodInteractionRow(interaction: interaction)
                }
                Text("Matched “\(matched)” in the medicines database.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.8))

            case .none(let searched):
                Label(
                    "No food interactions recorded for “\(searched)”.",
                    systemImage: "checkmark.circle"
                )
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            case .failed(let message):
                // Never shown as "no interactions": saying a drug is fine with
                // food because a lookup failed is the dangerous failure here.
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.missed)
            }
        } header: {
            Text("Food and drink")
        } footer: {
            Text("General information only. Always follow your doctor or pharmacist.")
        }
        .listRowBackground(Theme.Colors.cardSurface)
        .task(id: item.id) {
            let model = food ?? MedicineFoodViewModel(services: services)
            food = model
            await model.load(for: item)
        }
    }

    @ViewBuilder
    private func imagesSection(_ item: Medicine) -> some View {
        let entries: [(String, String?)] = [
            ("Prescription", item.prescriptionImagePath),
            ("Front", item.frontImagePath),
            ("Back", item.backImagePath)
        ]
        let available = entries.compactMap { entry -> (String, UIImage)? in
            MediaStore.image(named: entry.1).map { (entry.0, $0) }
        }

        if !available.isEmpty {
            Section("Images") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(available, id: \.0) { title, image in
                            Button {
                                previewImage = image
                            } label: {
                                VStack(spacing: 6) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text(title).font(.caption)
                                }
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Preview \(title) image")
                        }
                    }
                }
            }
            .listRowBackground(Theme.Colors.cardSurface)
        }
    }
}

/// One food interaction, as severity + food + effect.
///
/// Severity is an icon and a word as well as a colour — a colour-only warning
/// disappears in greyscale and for a colourblind reader, which is not
/// acceptable for "do not drink alcohol with this".
struct FoodInteractionRow: View {
    let interaction: FoodInteraction

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(interaction.food)
                        .font(Theme.Typography.body.weight(.medium))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(interaction.severity.displayName)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.14))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                }

                Text(interaction.effect)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var symbol: String {
        switch interaction.severity {
        case .avoid:   "xmark.octagon.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .minor:   "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch interaction.severity {
        case .avoid:   Theme.Colors.missed
        case .caution: Theme.Colors.skipped
        case .minor:   Theme.Colors.taken
        }
    }
}
