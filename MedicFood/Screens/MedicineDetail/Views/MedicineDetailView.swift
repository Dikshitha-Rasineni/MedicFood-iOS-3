import SwiftUI

/// Everything about one medicine, with edit, reminder settings and deactivate.
struct MedicineDetailView: View {
    let medicine: Medicine
    let model: MedicineListViewModel

    @State private var isEditing = false
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
