import SwiftUI

/// Add or edit a medicine — manually, from a scan (`prefill`) or editing.
struct AddMedicineView: View {
    @Environment(ServiceContainer.self) private var services

    var editing: Medicine?
    var prefill: MedicinePrefill?
    /// `true` when presented as a sheet (shows Cancel); `false` when pushed
    /// (the navigation back button is used instead).
    var isModal = true
    /// Called after a successful save instead of dismissing, so the scan flow
    /// can move on to the next medicine.
    var onSaved: (() -> Void)?

    @State private var model: AddMedicineViewModel?

    var body: some View {
        Group {
            if let model {
                AddMedicineForm(model: model, isModal: isModal, onSaved: onSaved)
            } else {
                Theme.Colors.page.ignoresSafeArea()
            }
        }
        .onAppear {
            if model == nil {
                model = AddMedicineViewModel(services: services, editing: editing, prefill: prefill)
            }
        }
    }
}

private struct AddMedicineForm: View {
    @Bindable var model: AddMedicineViewModel
    let isModal: Bool
    let onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            medicineSection
            imagesSection
            shorthandSection
            frequencySection
            timesSection
            foodSection
            courseSection
            notesSection
            voiceSection
            statusSection
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Colors.page.ignoresSafeArea())
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!model.canSave)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    private func save() {
        Task {
            guard await model.save() else { return }
            // Let "Saved successfully" be seen before leaving.
            try? await Task.sleep(for: .milliseconds(700))
            if let onSaved { onSaved() } else { dismiss() }
        }
    }

    // MARK: Sections

    private var medicineSection: some View {
        Section("Medicine") {
            TextField("Medicine name", text: $model.name)
                .textInputAutocapitalization(.words)
            TextField("Dosage, e.g. 500 mg", text: $model.dosage)
                .autocorrectionDisabled()
            Picker("Form", selection: $model.form) {
                ForEach(MedicineForm.allCases, id: \.self) { form in
                    Label(form.displayName, systemImage: form.symbolName).tag(form)
                }
            }
        }
        .listRowBackground(Theme.Colors.cardSurface)
    }

    private var imagesSection: some View {
        Section("Medicine Images") {
            MedicineImageSlot(title: "Prescription", image: $model.prescriptionImage, usesDocumentScanner: true)
            MedicineImageSlot(title: "Front", image: $model.frontImage)
            MedicineImageSlot(title: "Back", image: $model.backImage)
        }
        .listRowBackground(Theme.Colors.cardSurface)
    }

    private var shorthandSection: some View {
        Section {
            HStack {
                TextField("e.g. 1-0-1, BD, TID", text: $model.shorthand)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Apply") { model.applyPrescriptionShorthand() }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
                    .disabled(model.shorthand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Prescription instructions")
        } footer: {
            Text("Type what the doctor wrote. 1-0-1 is morning and night; BD twice daily; TID three times. You can still change every time below.")
        }
        .listRowBackground(Theme.Colors.cardSurface)
    }

    private var frequencySection: some View {
        Section("Frequency") {
            Picker("How often", selection: $model.frequency) {
                ForEach(AddMedicineViewModel.Frequency.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            if model.frequency == .everyHours {
                Stepper("Every \(model.everyHours) hours", value: $model.everyHours, in: 4...12)
                DatePicker("First dose", selection: $model.firstDose, displayedComponents: .hourAndMinute)
            }
        }
        .listRowBackground(Theme.Colors.cardSurface)
    }

    private var timesSection: some View {
        Section {
            ForEach(model.sortedSlots, id: \.self) { slot in
                HStack {
                    Button {
                        model.toggle(slot)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: model.isSelected(slot) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(model.isSelected(slot) ? Theme.Colors.primary : Theme.Colors.decorative)
                            Label(slot.displayName, systemImage: slot.symbolName)
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityLabel("\(slot.displayName), \(model.isSelected(slot) ? "selected" : "not selected")")

                    Spacer()

                    if model.isSelected(slot) {
                        DatePicker(
                            "\(slot.displayName) time",
                            selection: Binding(
                                get: { model.time(for: slot) },
                                set: { model.setTime($0, for: slot) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                }
            }
        } header: {
            Text("When to take")
        } footer: {
            Text(model.dosesPerDaySummary)
        }
        .listRowBackground(Theme.Colors.cardSurface)
    }

    private var foodSection: some View {
        Section("Food instructions") {
            Picker("Take", selection: $model.foodInstruction) {
                ForEach(FoodInstruction.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
        }
        .listRowBackground(Theme.Colors.cardSurface)
    }

    private var courseSection: some View {
        Section {
            DatePicker("Start date", selection: $model.startDate, displayedComponents: .date)

            Picker("Duration", selection: $model.durationUnit) {
                ForEach(AddMedicineViewModel.DurationUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            if model.durationUnit != .ongoing {
                Stepper(
                    "\(model.durationValue) \(model.durationUnit == .weeks ? "week" : "day")\(model.durationValue == 1 ? "" : "s")",
                    value: $model.durationValue,
                    in: 1...365
                )
            }
        } header: {
            Text("Course")
        } footer: {
            Text(model.durationSummary)
        }
        .listRowBackground(Theme.Colors.cardSurface)
    }

    private var notesSection: some View {
        Section("Additional instructions") {
            TextField("Anything to remember", text: $model.instructions, axis: .vertical)
                .lineLimit(3...6)
        }
        .listRowBackground(Theme.Colors.cardSurface)
    }

    private var voiceSection: some View {
        Section("Voice Recording") {
            VoiceRecordingView(voice: model.voice)
        }
        .listRowBackground(Theme.Colors.cardSurface)
    }

    @ViewBuilder
    private var statusSection: some View {
        if let status = model.statusMessage {
            Section {
                HStack(spacing: 10) {
                    if model.isSaving { ProgressView() } else { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.taken) }
                    Text(status).font(.subheadline.weight(.semibold))
                }
                if let warning = model.notificationWarning {
                    Text(warning).font(.footnote).foregroundStyle(Theme.Colors.skipped)
                }
            }
        }
        if let error = model.errorMessage {
            Section { ErrorBanner(message: error) }
        } else if let hint = model.validationHint {
            Section { Text(hint).font(.footnote).foregroundStyle(Theme.Colors.textSecondary) }
        }
    }
}

#Preview {
    NavigationStack { AddMedicineView() }
        .environment(ServiceContainer.mock())
}
