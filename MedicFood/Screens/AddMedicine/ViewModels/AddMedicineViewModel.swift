import UIKit
import Observation

/// Drives the add / edit medicine form.
///
/// One form serves manual entry, the scan flow (pre-filled through
/// `MedicinePrefill`) and editing. Typing what the doctor wrote ("1-0-1",
/// "BD") fills the schedule in through `PrescriptionParser`; every resulting
/// dose time can still be changed by hand.
@MainActor
@Observable
final class AddMedicineViewModel {

    enum Frequency: String, CaseIterable, Identifiable {
        case once, twice, three, four, everyHours, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .once:       "Once daily"
            case .twice:      "Twice daily"
            case .three:      "Three times daily"
            case .four:       "Four times daily"
            case .everyHours: "Every X hours"
            case .custom:     "Custom"
            }
        }

        var doses: Int? {
            switch self {
            case .once: 1
            case .twice: 2
            case .three: 3
            case .four: 4
            case .everyHours, .custom: nil
            }
        }

        static func matching(count: Int) -> Frequency {
            switch count {
            case 1: .once
            case 2: .twice
            case 3: .three
            case 4: .four
            default: .custom
            }
        }
    }

    enum DurationUnit: String, CaseIterable, Identifiable {
        case days, weeks, ongoing
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    // MARK: Form state

    var name = ""
    var dosage = ""
    var form: MedicineForm = .tablet
    var foodInstruction: FoodInstruction = .anyTime
    var instructions = ""
    var startDate = Calendar.current.startOfDay(for: .now)
    var shorthand = ""

    private(set) var slots: Set<DoseSlot> = [.morning]
    /// Exact time for each selected slot. Always has an entry for every slot.
    private(set) var times: [DoseSlot: Date] = [.morning: AddMedicineViewModel.date(for: .morning)]

    var frequency: Frequency = .once {
        didSet { if frequency != oldValue { applyFrequency() } }
    }
    var everyHours = 8 {
        didSet { if frequency == .everyHours { applyEveryHours() } }
    }
    var firstDose = AddMedicineViewModel.date(for: .morning) {
        didSet { if frequency == .everyHours { applyEveryHours() } }
    }

    var durationUnit: DurationUnit = .days
    var durationValue = 7

    var prescriptionImage: UIImage?
    var frontImage: UIImage?
    var backImage: UIImage?
    let voice = VoiceController()

    // MARK: Status

    private(set) var isSaving = false
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    private(set) var notificationWarning: String?

    // MARK: Dependencies and editing state

    private let medicines: MedicineServicing
    private let notifications: NotificationScheduling?
    private let original: Medicine?
    private let isFromPrescription: Bool
    private var isSyncingFrequency = false

    private var loadedPrescription: UIImage?
    private var loadedFront: UIImage?
    private var loadedBack: UIImage?

    init(
        medicines: MedicineServicing,
        notifications: NotificationScheduling? = nil,
        editing medicine: Medicine? = nil,
        prefill: MedicinePrefill? = nil
    ) {
        self.medicines = medicines
        self.notifications = notifications
        self.original = medicine
        self.isFromPrescription = prefill != nil

        if let medicine {
            name = medicine.name
            dosage = medicine.dosage
            form = medicine.form
            foodInstruction = medicine.foodInstruction
            instructions = medicine.instructions ?? ""
            startDate = medicine.startDate
            slots = Set(medicine.slots)
            times = Dictionary(uniqueKeysWithValues: medicine.slots.map {
                ($0, Self.date(from: medicine.timeComponents(for: $0)))
            })
            syncFrequency()

            if let days = medicine.durationDays {
                if days % 7 == 0 { durationUnit = .weeks; durationValue = days / 7 }
                else { durationUnit = .days; durationValue = days }
            } else {
                durationUnit = .ongoing
            }

            loadedPrescription = MediaStore.image(named: medicine.prescriptionImagePath)
            loadedFront = MediaStore.image(named: medicine.frontImagePath)
            loadedBack = MediaStore.image(named: medicine.backImagePath)
            prescriptionImage = loadedPrescription
            frontImage = loadedFront
            backImage = loadedBack
            voice.load(fileName: medicine.voiceFilePath)
        } else if let prefill {
            name = prefill.name
            dosage = prefill.dosage
            form = prefill.form
            foodInstruction = prefill.food
            shorthand = prefill.shorthand
            if !prefill.shorthand.trimmingCharacters(in: .whitespaces).isEmpty {
                applyPrescriptionShorthand()
            }
            if let days = DurationParser.days(from: prefill.durationText), !prefill.durationText.isEmpty {
                if days >= 7 && days % 7 == 0 { durationUnit = .weeks; durationValue = days / 7 }
                else { durationUnit = .days; durationValue = max(days, 1) }
            }
            prescriptionImage = prefill.prescriptionImage
            voice.load(fileName: prefill.voiceFileName)
        }
    }

    convenience init(services: ServiceContainer, editing medicine: Medicine? = nil, prefill: MedicinePrefill? = nil) {
        self.init(
            medicines: services.medicines,
            notifications: services.notifications,
            editing: medicine,
            prefill: prefill
        )
    }

    var isEditing: Bool { original != nil }
    var title: String { isEditing ? "Edit medicine" : "Add medicine" }

    // MARK: Validation

    var validationHint: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the medicine name." }
        if dosage.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the dosage, e.g. 500 mg." }
        if slots.isEmpty { return "Pick at least one time to take it." }
        return nil
    }

    var canSave: Bool { validationHint == nil && !isSaving }

    // MARK: Schedule

    var sortedSlots: [DoseSlot] {
        // Stable (default-time) order, so rows don't jump while a time is edited.
        DoseSlot.allCases.sorted()
    }

    func isSelected(_ slot: DoseSlot) -> Bool { slots.contains(slot) }

    func time(for slot: DoseSlot) -> Date { times[slot] ?? Self.date(for: slot) }

    func setTime(_ date: Date, for slot: DoseSlot) { times[slot] = date }

    func toggle(_ slot: DoseSlot) {
        if slots.contains(slot) {
            slots.remove(slot)
            times[slot] = nil
        } else {
            slots.insert(slot)
            times[slot] = Self.date(for: slot)
        }
        syncFrequency()
    }

    var dosesPerDaySummary: String {
        guard !slots.isEmpty else { return "Pick at least one time" }
        let list = sortedSlots.filter { slots.contains($0) }.map {
            "\($0.displayName) \(time(for: $0).formatted(date: .omitted, time: .shortened))"
        }
        return "\(slots.count)× daily · " + list.joined(separator: ", ")
    }

    /// Read the doctor's shorthand and fill in the schedule. Times the user
    /// already set are kept; new slots get their default.
    func applyPrescriptionShorthand() {
        let text = shorthand.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        setSlots(PrescriptionParser.slots(from: text))
        syncFrequency()

        let food = PrescriptionParser.foodInstruction(from: text)
        if food != .anyTime { foodInstruction = food }
    }

    private func setSlots(_ newSlots: [DoseSlot]) {
        let keep = times
        slots = Set(newSlots)
        times = Dictionary(uniqueKeysWithValues: newSlots.map { ($0, keep[$0] ?? Self.date(for: $0)) })
    }

    private func syncFrequency() {
        isSyncingFrequency = true
        frequency = Frequency.matching(count: slots.count)
        isSyncingFrequency = false
    }

    private func applyFrequency() {
        guard !isSyncingFrequency else { return }
        switch frequency {
        case .once, .twice, .three, .four:
            setSlots(PrescriptionParser.defaultSlots(forDosesPerDay: frequency.doses ?? 1))
        case .everyHours:
            applyEveryHours()
        case .custom:
            break
        }
    }

    /// Spread doses `everyHours` apart from `firstDose`.
    ///
    /// Each generated time is attached to the nearest unused named slot and
    /// its exact time overridden, so "every 6 hours from 6:00" becomes four
    /// doses at 6:00, 12:00, 18:00 and 0:00. At most seven doses a day, which
    /// is the number of named slots the schedule model supports.
    private func applyEveryHours() {
        let hours = max(everyHours, 4)
        let count = min(24 / hours, DoseSlot.allCases.count)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: firstDose)
        let start = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)

        var available = DoseSlot.allCases
        var newTimes: [DoseSlot: Date] = [:]
        for index in 0..<count {
            let minute = (start + index * hours * 60) % 1440
            guard let slot = available.min(by: { distance(minute, defaultMinutes($0)) < distance(minute, defaultMinutes($1)) }) else { break }
            available.removeAll { $0 == slot }
            newTimes[slot] = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
        }
        slots = Set(newTimes.keys)
        times = newTimes
    }

    private func defaultMinutes(_ slot: DoseSlot) -> Int {
        (slot.defaultTime.hour ?? 0) * 60 + (slot.defaultTime.minute ?? 0)
    }

    private func distance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b)
        return min(d, 1440 - d)
    }

    private func minutes(for slot: DoseSlot) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time(for: slot))
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: Course

    var durationDays: Int? {
        switch durationUnit {
        case .days:    max(durationValue, 1)
        case .weeks:   max(durationValue, 1) * 7
        case .ongoing: nil
        }
    }

    var endDate: Date? {
        durationDays.flatMap { Calendar.current.date(byAdding: .day, value: $0 - 1, to: startDate) }
    }

    var durationSummary: String {
        guard let days = durationDays, let end = endDate else {
            return "Ongoing — reminders continue until you stop them."
        }
        let fmt = { (d: Date) in d.formatted(date: .abbreviated, time: .omitted) }
        return "Started \(fmt(startDate)) · Ends \(fmt(end)) · \(days) day\(days == 1 ? "" : "s")"
    }

    // MARK: Saving

    func save() async -> Bool {
        if let hint = validationHint {
            errorMessage = hint
            return false
        }
        guard !isSaving else { return false }

        isSaving = true
        errorMessage = nil
        notificationWarning = nil
        statusMessage = "Saving..."
        defer { isSaving = false }

        var medicine = original ?? Medicine(name: "", dosage: "", slots: [.morning])
        medicine.name = name.trimmingCharacters(in: .whitespaces)
        medicine.dosage = dosage.trimmingCharacters(in: .whitespaces)
        medicine.form = form
        medicine.slots = slots.sorted()
        medicine.customTimes = slots.sorted().map { slot in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time(for: slot))
            return DoseTime(slot: slot, hour: parts.hour ?? 8, minute: parts.minute ?? 0)
        }
        medicine.foodInstruction = foodInstruction
        let notes = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        medicine.instructions = notes.isEmpty ? nil : notes
        medicine.startDate = Calendar.current.startOfDay(for: startDate)
        medicine.durationDays = durationDays
        if isFromPrescription { medicine.isFromPrescription = true }

        medicine.prescriptionImagePath = persist(prescriptionImage, original: loadedPrescription, existing: original?.prescriptionImagePath, prefix: "rx")
        medicine.frontImagePath = persist(frontImage, original: loadedFront, existing: original?.frontImagePath, prefix: "front")
        medicine.backImagePath = persist(backImage, original: loadedBack, existing: original?.backImagePath, prefix: "back")
        voice.stopRecording()
        voice.stopPlayback()
        medicine.voiceFilePath = voice.fileName

        do {
            try await medicines.save(medicine)
        } catch {
            statusMessage = nil
            errorMessage = (error as? APIError)?.errorDescription ?? "Unable to save the medicine. Please try again."
            return false
        }

        await scheduleReminders()
        statusMessage = "Saved successfully"
        return true
    }

    private func scheduleReminders() async {
        guard let notifications else { return }
        let granted = await notifications.requestAuthorization()
        await ReminderScheduler.refresh(medicines: medicines, notifications: notifications)
        if !granted {
            notificationWarning = "Notifications are turned off, so reminders won't appear. Turn them on in Settings."
        }
    }

    private func persist(_ image: UIImage?, original: UIImage?, existing: String?, prefix: String) -> String? {
        guard let image else {
            MediaStore.delete(existing)
            return nil
        }
        if image === original, existing != nil { return existing }
        MediaStore.delete(existing)
        return MediaStore.saveImage(image, prefix: prefix)
    }

    // MARK: Date helpers

    static func date(for slot: DoseSlot) -> Date { date(from: slot.defaultTime) }

    static func date(from components: DateComponents) -> Date {
        Calendar.current.date(
            bySettingHour: components.hour ?? 8,
            minute: components.minute ?? 0,
            second: 0,
            of: .now
        ) ?? .now
    }
}
