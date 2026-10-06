import SwiftUI

/// Home A — the launcher.
///
/// The layout the documentation describes: a banner and two big entry points,
/// with the medication itself one tap away. Kept alongside `DashboardView`
/// (Home B) so the team can see both running and choose; whichever loses gets
/// deleted rather than left to rot.
struct HomeLauncherView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(UserSession.self) private var session

    @State private var viewModel: HomeLauncherViewModel?

    var body: some View {
        let model = viewModel ?? HomeLauncherViewModel(services: services)

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    marks
                    greeting(model)
                    PromoBanner(reminderCount: model.todaysDoseCount)

                    Text("For you")
                        .sectionLabelStyle()
                        .padding(.top, 2)

                    NavigationLink {
                        PrescriptionScannerView()
                    } label: {
                        ActionCardLabel(
                            title: "Scan Prescription",
                            subtitle: "Use the camera or gallery to read a prescription",
                            symbol: "doc.viewfinder"
                        )
                    }
                    .buttonStyle(PressableCardStyle())

                    NavigationLink {
                        IdentifyMedicineView()
                    } label: {
                        ActionCardLabel(
                            title: "Identify a Medicine",
                            subtitle: "Photograph a pack to see what it is and what to eat",
                            symbol: "pills.circle"
                        )
                    }
                    .buttonStyle(PressableCardStyle())

                    NavigationLink {
                        AddMedicineView(isModal: false)
                    } label: {
                        ActionCardLabel(
                            title: "Add Medicine",
                            subtitle: "Enter a medicine yourself, no prescription needed",
                            symbol: "plus.circle"
                        )
                    }
                    .buttonStyle(PressableCardStyle())

                    NavigationLink {
                        DrugFoodInteractionView()
                    } label: {
                        ActionCardLabel(
                            title: "Check Drug-Food Interactions",
                            subtitle: "See what to eat or avoid with a medicine",
                            symbol: "fork.knife"
                        )
                    }
                    .buttonStyle(PressableCardStyle())

                    NavigationLink {
                        DashboardView()
                    } label: {
                        ActionCardLabel(
                            title: "Set Medication Reminder",
                            subtitle: "See today's doses and add a new reminder",
                            symbol: "alarm"
                        )
                    }
                    .buttonStyle(PressableCardStyle())

                    NavigationLink {
                        AdherenceView()
                    } label: {
                        ActionCardLabel(
                            title: "Adherence",
                            subtitle: "See how many doses you have taken",
                            symbol: "chart.bar"
                        )
                    }
                    .buttonStyle(PressableCardStyle())

                    if let error = model.errorMessage {
                        ErrorBanner(message: error)
                    }
                }
                .padding(.horizontal, Theme.Metrics.pageMargin)
                .padding(.top, 10)
                .padding(.bottom, model.upNext == nil ? 24 : 110)
            }
            .scrollIndicators(.hidden)

            // Floats over the content, so it gets glass rather than a flat card.
            if let upNext = model.upNext {
                UpNextBar(upNext: upNext)
                    .padding(.horizontal, Theme.Metrics.pageMargin)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.Colors.page.ignoresSafeArea())
        .navigationBarHidden(true)
        .animation(Theme.Motion.cardAppear, value: model.upNext)
        .task {
            viewModel = model
            await model.load()
        }
    }

    // MARK: Header

    /// Both marks sit on white circles. The brand mark is five hues and none
    /// of them are in the palette — on the page tint it has no clean edge.
    private var marks: some View {
        HStack {
            Image(.logoMark)
                .resizable()
                .scaledToFit()
                .frame(width: 27, height: 27)
                .frame(width: 36, height: 36)
                .background(Theme.Colors.cardSurface, in: Circle())
                .shadow(color: Theme.Colors.textPrimary.opacity(0.08), radius: 12, y: 2)
                .accessibilityLabel("MedicFood")

            Spacer()

            Image(.logoSmall)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .frame(width: 36, height: 36)
                .background(Theme.Colors.cardSurface, in: Circle())
                .shadow(color: Theme.Colors.textPrimary.opacity(0.08), radius: 12, y: 2)
                .accessibilityLabel("SRM Institute of Science and Technology")
        }
    }

    private func greeting(_ model: HomeLauncherViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(model.greeting(for: session.profile?.name))
                .font(Theme.Typography.display)
                .tracking(Theme.Typography.displayTracking)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Banner

private struct PromoBanner: View {
    let reminderCount: Int

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Stay UpToDate with your medicines")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.44)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 8)

                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(reminderCount)")
                        .font(Theme.Typography.numeral(22))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(reminderCount == 1 ? "reminder set for today" : "reminders set for today")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.surface)
                }
            }

            BannerGlyph()
                .frame(width: 76, height: 76)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.Colors.brand, Theme.Colors.primary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
        )
        .shadow(color: Theme.Metrics.shadow.color, radius: Theme.Metrics.shadow.radius, y: Theme.Metrics.shadow.y)
    }
}

/// A capsule and a dot — a tablet, abstracted. Shapes rather than an asset.
private struct BannerGlyph: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.16))
            Capsule()
                .fill(Color.white)
                .frame(width: 22, height: 50)
                .rotationEffect(.degrees(28))
                .offset(x: -10, y: -6)
            Circle()
                .fill(Theme.Colors.surface)
                .frame(width: 20, height: 20)
                .offset(x: 15, y: 15)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Action cards

private struct ActionCardLabel: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 48, height: 48)
                .background(Theme.Colors.surface, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .tracking(Theme.Typography.cardTitleTracking)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.Colors.brand)
        }
        .padding(20)
        .cardSurface()
    }
}

// MARK: - Up next

private struct UpNextBar: View {
    let upNext: HomeLauncherViewModel.UpNext

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 34, height: 34)
                .background(Theme.Colors.surface, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Next up")
                    .font(Theme.Typography.sectionLabel)
                    .tracking(Theme.Typography.sectionTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textSecondary)

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(upNext.medicineName)
                        .font(Theme.Typography.cardTitle)
                        .tracking(Theme.Typography.cardTitleTracking)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Text(upNext.scheduledAt.formatted(date: .omitted, time: .shortened))
                        .font(Theme.Typography.numeral(19))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .liquidGlass(cornerRadius: Theme.Metrics.cornerRadius)
    }
}

#Preview {
    NavigationStack { HomeLauncherView() }
        .environment(ServiceContainer.mock())
        .environment(UserSession())
}
