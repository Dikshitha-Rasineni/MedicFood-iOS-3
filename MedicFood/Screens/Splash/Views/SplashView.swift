import SwiftUI

/// The splash: brand moment and real loading screen.
///
/// It holds for at least 2.5s while the session restores and the medicine
/// cache warms, so the ring is not a decoration — it is showing actual work.
struct SplashView: View {
    /// Called once loading has finished *and* the minimum hold has elapsed.
    /// A failure does not call it — the user stays here with "Try again".
    var onFinished: () -> Void = {}

    @Environment(ServiceContainer.self) private var services
    @Environment(UserSession.self) private var session

    @State private var viewModel: SplashViewModel?
    @State private var markIsIn = false
    @State private var wordmarkIsIn = false
    @State private var ringIsIn = false
    @State private var partnerIsIn = false

    private var hasFailed: Bool {
        if case .failed = viewModel?.phase { return true }
        return false
    }

    var body: some View {
        ZStack {
            Theme.Colors.page.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                LogoPlate(isSpinning: !hasFailed, ringIsIn: ringIsIn)
                    .scaleEffect(markIsIn ? 1 : 0.85)
                    .opacity(markIsIn ? 1 : 0.4)

                Spacer().frame(height: 32)

                Text("MedicFood")
                    .font(Theme.Typography.display)
                    .tracking(Theme.Typography.displayTracking)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if !hasFailed {
                    Spacer().frame(height: 8)
                    Text("Never miss a dose")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .transition(.opacity)
                }

                Spacer()
            }
            .opacity(wordmarkIsIn ? 1 : 0)
            .offset(y: wordmarkIsIn ? 0 : 8)

            // The partner mark sits at the foot, out of the brand stack.
            if !hasFailed {
                VStack {
                    Spacer()
                    PartnerMark()
                        .padding(.bottom, 60)
                }
                // Fades in last, and never before the brand. Ungated it was
                // visible on the very first frame, so the splash opened as a
                // blank green screen showing only the partner's seal.
                .opacity(partnerIsIn ? 1 : 0)
                .transition(.opacity)
            }

            if case .failed(let message) = viewModel?.phase {
                VStack {
                    Spacer()
                    FailureCard(message: message) {
                        Task {
                        await viewModel?.retry(session: session)
                        if viewModel?.phase == .ready { onFinished() }
                    }
                    }
                    .padding(.horizontal, Theme.Metrics.pageMargin)
                    .padding(.bottom, 72)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.cardAppear, value: hasFailed)
        .task {
            let model = viewModel ?? SplashViewModel(services: services)
            viewModel = model

            withAnimation(.easeOut(duration: 0.5)) { markIsIn = true }
            withAnimation(.easeOut(duration: 0.45).delay(0.15)) { wordmarkIsIn = true }
            withAnimation(.easeOut(duration: 0.3).delay(0.3)) { ringIsIn = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.45)) { partnerIsIn = true }

            await model.start(session: session)
            if model.phase == .ready { onFinished() }
        }
    }
}

// MARK: - The mark on its plate, inside the ring

/// The logo always sits on a white ground.
///
/// Not decoration: the mark is five hues, none of them in the palette, and its
/// mint cross measures 1.36:1 against the page. On white it at least has a
/// defined edge and matches the app icon.
private struct LogoPlate: View {
    let isSpinning: Bool
    let ringIsIn: Bool

    @State private var angle: Angle = .degrees(-30)

    private let plate: CGFloat = 140
    private let ring: CGFloat = 188

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Theme.Colors.brand.opacity(0.2), lineWidth: 6)
                .frame(width: ring - 6, height: ring - 6)

            // The 270° gradient arc that does the spinning.
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    AngularGradient(
                        colors: isSpinning
                            ? [Theme.Colors.decorative, Theme.Colors.brand, Theme.Colors.primary]
                            : [Theme.Colors.decorative.opacity(0.5)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: ring - 6, height: ring - 6)
                .rotationEffect(angle)
                .opacity(ringIsIn ? 1 : 0)

            Circle()
                .fill(Theme.Colors.cardSurface)
                .frame(width: plate, height: plate)
                .shadow(color: Theme.Colors.textPrimary.opacity(0.10), radius: 20, y: 4)

            // `LogoMark` is the trimmed artwork the design ships. `Logo` is
            // the same mark on a canvas that is 46% transparent padding, which
            // renders at barely half the requested size.
            Image(.logoMark)
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
        }
        .frame(width: ring, height: ring)
        .onChange(of: isSpinning, initial: true) { _, spinning in
            if spinning {
                withAnimation(Theme.Motion.ringSpin) { angle = .degrees(330) }
            } else {
                withAnimation(.easeOut(duration: 0.4)) { angle = .degrees(-30) }
            }
        }
    }
}

// MARK: - Partner mark

private struct PartnerMark: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(.logoSmall)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .frame(width: 44, height: 44)
                .background(Theme.Colors.cardSurface, in: Circle())
                .shadow(color: Theme.Colors.textPrimary.opacity(0.08), radius: 12, y: 2)

            Text("SRM Institute of Science and Technology")
                .sectionLabelStyle()
        }
    }
}

// MARK: - Failure

/// Shown when the medicine fetch fails.
///
/// Floating over the brand stack, so it gets glass rather than a flat card.
private struct FailureCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Colors.missed)
                Text("Couldn't load your medicines")
                    .font(Theme.Typography.cardTitle)
                    .tracking(Theme.Typography.cardTitleTracking)
                    .foregroundStyle(Theme.Colors.missed)
            }

            Spacer().frame(height: 6)

            Text("Check your connection. Your saved reminders still work offline.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 16)

            Button(action: retry) {
                Text("Try again")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Metrics.controlHeight)
                    .background(
                        Theme.Colors.primary,
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
                    )
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityHint(message)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: Theme.Metrics.cornerRadius)
    }
}

#Preview {
    SplashView()
        .environment(ServiceContainer.mock())
        .environment(UserSession())
}
