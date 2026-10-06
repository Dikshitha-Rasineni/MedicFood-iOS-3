import SwiftUI

/// People this user is looking after.
struct CaretakerView: View {
    @Environment(ServiceContainer.self) private var services

    @State private var viewModel: CaretakerViewModel?
    @State private var isPresentingLinkSheet = false

    var body: some View {
        let model = viewModel ?? CaretakerViewModel(services: services)

        ZStack {
            Theme.Colors.page
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: - Header
                HStack(alignment: .top, spacing: 14) {

                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Theme.Colors.primary.opacity(0.12))

                        Image(systemName: "person.2.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.Colors.primary)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {

                        Text("Caretaker Dashboard")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Manage your family members and dependents")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Metrics.pageMargin)
                .padding(.top, 12)
                .padding(.bottom, 16)

                // MARK: - Content
                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                        .padding(.horizontal, Theme.Metrics.pageMargin)
                        .padding(.bottom, 8)
                }

                if model.isEmpty {

                    Spacer()

                    EmptyStateView(
                        symbol: "person.2",
                        title: "Not looking after anyone yet",
                        message: "Ask for their six-character share code and enter it to follow their schedule.",
                        actionTitle: "Enter a share code",
                        action: { isPresentingLinkSheet = true }
                    )

                    Spacer()

                } else {

                    ScrollView(showsIndicators: false) {

                        LazyVStack(alignment: .leading, spacing: 20) {

                            if !model.needingAttention.isEmpty {

                                CaretakerSection(
                                    title: "Needs attention",
                                    symbol: "exclamationmark.triangle.fill",
                                    tint: Theme.Colors.skipped
                                ) {
                                    ForEach(model.needingAttention) { patient in
                                        NavigationLink {
                                            PatientDetailView(patient: patient, model: model)
                                        } label: {
                                            PatientCard(patient: patient)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            let others = model.patients.filter { !$0.isFallingBehind }
                            if !others.isEmpty {

                                CaretakerSection(
                                    title: "Doing well",
                                    symbol: "checkmark.circle.fill",
                                    tint: Theme.Colors.primary
                                ) {
                                    ForEach(others) { patient in
                                        NavigationLink {
                                            PatientDetailView(patient: patient, model: model)
                                        } label: {
                                            PatientCard(patient: patient)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Metrics.pageMargin)
                        .padding(.bottom, 100)
                    }
                }
            }

            // MARK: - Floating Action Button
            VStack {
                Spacer()
                HStack {
                    Spacer()

                    Button {
                        isPresentingLinkSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Theme.Colors.primary,
                                        Theme.Colors.primary.opacity(0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                            .shadow(
                                color: Theme.Colors.primary.opacity(0.35),
                                radius: 10,
                                y: 5
                            )
                    }
                }
                .padding(.trailing, Theme.Metrics.pageMargin)
                .padding(.bottom, 24)
            }
        }
        .navigationBarHidden(true)
        .refreshable { await model.load() }
        .sheet(isPresented: $isPresentingLinkSheet) {
            LinkPatientSheet(model: model)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .task {
            viewModel = model
            await model.load()
        }
    }
}


// MARK: - Section Container

private struct CaretakerSection<Content: View>: View {

    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {

        VStack(alignment: .leading, spacing: 10) {

            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)

            VStack(spacing: 12) {
                content
            }
        }
    }
}


// MARK: - Patient Card

private struct PatientCard: View {

    let patient: LinkedPatient

    private var adherenceTint: Color {
        Theme.Colors.adherence(patient.adherenceRate)
    }

    private var dayProgress: Double {
        patient.dosesToday == 0 ? 0 : Double(patient.takenToday) / Double(patient.dosesToday)
    }

    var body: some View {

        VStack(spacing: 12) {

            HStack(alignment: .center, spacing: 14) {

                // The avatar is identity, so it stays one colour. Colouring it
                // by adherence made the same person change colour week to week.
                Text(patient.initials)
                    .font(Theme.Typography.numeral(16))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.Colors.primary, in: Circle())

                VStack(alignment: .leading, spacing: 3) {

                    Text(patient.name)
                        .font(Theme.Typography.cardTitle)
                        .tracking(Theme.Typography.cardTitleTracking)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Text("\(patient.takenToday) of \(patient.dosesToday) taken today")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if let last = patient.lastActive {
                        Text("Active \(last.timeAgoDescription)")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.75))
                    }
                }

                Spacer(minLength: 8)

                // A small ring carries the rate; the numeral inside it stays in
                // ink, so the colour is on the mark rather than on the text.
                ProgressRing(rate: patient.adherenceRate, lineWidth: 5, size: 46) {
                    Text("\(Int(patient.adherenceRate * 100))")
                        .font(Theme.Typography.numeral(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.decorative)
            }

            // Today at a glance, under the summary it describes.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.surface)
                    Capsule()
                        .fill(adherenceTint)
                        .frame(width: max(2, geo.size.width * dayProgress))
                }
            }
            .frame(height: 6)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
        .shadow(
            color: Theme.Metrics.shadow.color,
            radius: Theme.Metrics.shadow.radius,
            y: Theme.Metrics.shadow.y
        )
    }
}


// MARK: - Patient Detail Screen

private struct PatientDetailView: View {

    let patient: LinkedPatient
    let model: CaretakerViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingRemove = false
    @State private var isRemoving = false

    private var adherenceTint: Color {
        Theme.Colors.adherence(patient.adherenceRate)
    }

    var body: some View {

        ScrollView(showsIndicators: false) {

            VStack(spacing: 20) {

                // MARK: - Profile Summary
                VStack(spacing: 12) {

                    Text(patient.initials)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(adherenceTint, in: Circle())

                    Text(patient.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("\(Int(patient.adherenceRate * 100))% adherence")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(adherenceTint)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                // MARK: - Stats Card
                VStack(alignment: .leading, spacing: 14) {

                    DetailRow(
                        symbol: "checkmark.circle",
                        label: "Taken today",
                        value: "\(patient.takenToday) of \(patient.dosesToday)"
                    )

                    if let last = patient.lastActive {
                        DetailRow(
                            symbol: "clock",
                            label: "Last active",
                            value: last.timeAgoDescription
                        )
                    }

                    if patient.isFallingBehind {
                        DetailRow(
                            symbol: "exclamationmark.triangle.fill",
                            label: "Status",
                            value: "Needs attention",
                            tint: Theme.Colors.skipped
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Theme.Colors.cardSurface,
                    in: RoundedRectangle(cornerRadius: 20)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.Colors.primary.opacity(0.08), lineWidth: 1)
                )

                Spacer(minLength: 20)

                // MARK: - Remove Action
                Button(role: .destructive) {
                    isConfirmingRemove = true
                } label: {
                    HStack {
                        if isRemoving {
                            ProgressView()
                                .tint(.red)
                        } else {
                            Image(systemName: "person.badge.minus")
                            Text("Remove \(patient.name)")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Color.red.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                }
                .disabled(isRemoving)
            }
            .padding(Theme.Metrics.pageMargin)
        }
        .background(Theme.Colors.page.ignoresSafeArea())
        .navigationTitle(patient.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove \(patient.name)?",
            isPresented: $isConfirmingRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    isRemoving = true
                    await model.unlink(patient)
                    isRemoving = false
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop seeing their schedule and adherence. They can share their code with you again later if needed.")
        }
    }
}


private struct DetailRow: View {

    let symbol: String
    let label: String
    let value: String
    var tint: Color = Theme.Colors.primary

    var body: some View {
        HStack(spacing: 10) {

            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}


// MARK: - Link Dependent Sheet

private struct LinkPatientSheet: View {

    let model: CaretakerViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isCodeFieldFocused: Bool

    var body: some View {

        VStack(alignment: .leading, spacing: 20) {

            Text("Link dependent")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 8) {

                TextField(
                    "Dependent code",
                    text: Binding(
                        get: { model.enteredCode },
                        set: { model.enteredCode = $0.uppercased() }
                    )
                )
                .font(.system(size: 18, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isCodeFieldFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                )

                Text("Enter the code provided by your dependent")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if let error = model.errorMessage {
                ErrorBanner(message: error)
            }

            Spacer(minLength: 0)

            HStack {

                Button("Cancel") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Colors.primary)

                Spacer()

                Button {
                    Task {
                        await model.link()
                        if model.errorMessage == nil {
                            dismiss()
                        }
                    }
                } label: {
                    Group {
                        if model.isLinking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Link Dependent")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(height: 20)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        Theme.Colors.primary.opacity(model.canLink ? 1 : 0.4),
                        in: Capsule()
                    )
                }
                .disabled(!model.canLink)
            }
        }
        .padding(24)
        .background(Theme.Colors.page)
        .onAppear {
            isCodeFieldFocused = true
        }
    }
}


#Preview {
    NavigationStack { CaretakerView() }
        .environment(ServiceContainer.mock())
}
