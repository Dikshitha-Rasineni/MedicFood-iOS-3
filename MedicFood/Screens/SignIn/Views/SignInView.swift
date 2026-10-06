import SwiftUI

/// Sign in with the account used on the Android app.
///
/// Sign-up lives on its own screen (`SignUpView`) rather than behind a mode
/// toggle here, so this form asks for exactly two things and nothing shifts
/// under the keyboard as fields appear and disappear.
struct SignInView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(ServiceContainer.self) private var services
    @Environment(UserSession.self) private var session

    /// Pushed by `AuthFlowView` — the view decides navigation, not the model.
    var onCreateAccount: () -> Void

    @State private var viewModel: SignInViewModel?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        let model = viewModel ?? SignInViewModel(services: services, mode: .signIn)

        ScrollView {
            VStack(spacing: 20) {
                AuthHeader(title: "MedicFood", subtitle: "Never miss a dose")
                    .padding(.top, 28)
                    .padding(.bottom, 4)

                StaggeredAppear(index: 1) {
                    VStack(spacing: 14) {
                        LabelledField(
                            title: "Email",
                            text: Binding(get: { model.credentials.email }, set: { model.credentials.email = $0 }),
                            systemImage: "envelope",
                            contentType: .emailAddress,
                            keyboard: .emailAddress
                        )
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)

                        LabelledField(
                            title: "Password",
                            text: Binding(get: { model.credentials.password }, set: { model.credentials.password = $0 }),
                            systemImage: "lock",
                            contentType: .password,
                            isSecure: true
                        )
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                    }
                }

                StaggeredAppear(index: 2) {
                    HStack {
                        Spacer()
                        Button("Forgot password?") {
                            focusedField = nil
                            Task { await model.sendPasswordReset() }
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.Colors.primary)
                        .disabled(!model.canResetPassword)
                        .opacity(model.canResetPassword ? 1 : 0.5)
                    }
                }

                if let sent = model.resetMessage {
                    NoticeCard(symbol: "envelope.badge.fill", text: sent)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                StaggeredAppear(index: 3) {
                    AuthSubmitButton(
                        title: "Sign in",
                        isLoading: model.isSubmitting,
                        isEnabled: model.canSubmit
                    ) {
                        submit(model)
                    }
                }

                StaggeredAppear(index: 4) {
                    Button(action: onCreateAccount) {
                        HStack(spacing: 4) {
                            Text("New here?")
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text("Create an account")
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.primary)
                        }
                        .font(Theme.Typography.caption)
                    }
                    .buttonStyle(PressableCardStyle())
                }

                StaggeredAppear(index: 5) { demoSection }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .animation(Theme.Motion.statusChange, value: model.errorMessage)
            .animation(Theme.Motion.statusChange, value: model.resetMessage)
        }
        .background(Theme.Colors.page)
        .scrollDismissesKeyboard(.interactively)
        .onSubmit(focus)
        .onAppear { viewModel = model }
    }

    // MARK: - Demo

    /// A way into the app with no account at all.
    ///
    /// Separated by a rule and set in the secondary style, because it is an
    /// escape hatch rather than the thing most people should press. Entering
    /// the demo also swaps the service stack to sample data — see
    /// `AppServices.enterDemo`.
    private var demoSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                line
                Text("or")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                line
            }

            Button {
                let profile = appServices.enterDemo()
                withAnimation(Theme.Motion.cardAppear) {
                    session.signInToDemo(profile)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle")
                    Text("Explore the demo").fontWeight(.semibold)
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.primary)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
                        .fill(Theme.Colors.surface)
                )
            }
            .buttonStyle(PressableCardStyle())

            Text("Sample data, no account needed. Nothing you do is saved.")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var line: some View {
        Rectangle()
            .fill(Theme.Colors.decorative.opacity(0.5))
            .frame(height: 1)
    }

    // MARK: - Actions

    private func focus() {
        switch focusedField {
        case .email: focusedField = .password
        case .password: if let viewModel { submit(viewModel) }
        case .none: break
        }
    }

    private func submit(_ model: SignInViewModel) {
        focusedField = nil
        Task {
            // The model returns a result; the view decides what it means.
            if let profile = await model.submit() {
                withAnimation(Theme.Motion.cardAppear) {
                    session.signIn(profile)
                }
            }
        }
    }
}

#Preview {
    SignInView(onCreateAccount: {})
        .environment(AppServices())
        .environment(ServiceContainer.mock())
        .environment(UserSession())
}
