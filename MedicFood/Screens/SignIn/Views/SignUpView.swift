import SwiftUI

/// Create a MedicFood account.
///
/// Its own screen rather than extra fields on the sign-in form. It asks for
/// four things, and the password is confirmed — a typo in a field you cannot
/// read locks someone out of their own medicine schedule, and recovering from
/// that needs an email round trip this app does not yet have.
struct SignUpView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// Called once the account exists and the session is live, so the flow can
    /// unwind rather than leaving a dead "back to sign in" screen behind.
    var onSignedUp: () -> Void

    @State private var viewModel: SignInViewModel?
    @FocusState private var focusedField: Field?

    private enum Field { case name, email, password, confirm }

    var body: some View {
        let model = viewModel ?? SignInViewModel(services: services, mode: .signUp)

        ScrollView {
            VStack(spacing: 20) {
                AuthHeader(
                    title: "Create account",
                    subtitle: "Your medicines, on every device you use"
                )
                .padding(.top, 12)
                .padding(.bottom, 4)

                StaggeredAppear(index: 1) {
                    VStack(spacing: 14) {
                        LabelledField(
                            title: "Name",
                            text: Binding(get: { model.name }, set: { model.name = $0 }),
                            systemImage: "person",
                            contentType: .name
                        )
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)

                        LabelledField(
                            title: "Email",
                            text: Binding(get: { model.credentials.email }, set: { model.credentials.email = $0 }),
                            systemImage: "envelope",
                            contentType: .emailAddress,
                            keyboard: .emailAddress
                        )
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                    }
                }

                StaggeredAppear(index: 2) {
                    VStack(alignment: .leading, spacing: 14) {
                        LabelledField(
                            title: "Password",
                            text: Binding(get: { model.credentials.password }, set: { model.credentials.password = $0 }),
                            systemImage: "lock",
                            contentType: .newPassword,
                            isSecure: true
                        )
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)

                        LabelledField(
                            title: "Confirm password",
                            text: Binding(get: { model.confirmPassword }, set: { model.confirmPassword = $0 }),
                            systemImage: "lock.rotation",
                            contentType: .newPassword,
                            isSecure: true
                        )
                        .focused($focusedField, equals: .confirm)
                        .submitLabel(.go)

                        // Shown while typing rather than on submit, so it is
                        // fixed before the button is ever reached.
                        if model.passwordMismatch {
                            Label("Those passwords do not match.", systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.missed)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            Text("At least six characters.")
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .transition(.opacity)
                        }
                    }
                }

                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                StaggeredAppear(index: 3) {
                    AuthSubmitButton(
                        title: "Create account",
                        isLoading: model.isSubmitting,
                        isEnabled: model.canSubmit
                    ) {
                        submit(model)
                    }
                }

                StaggeredAppear(index: 4) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text("Sign in")
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.primary)
                        }
                        .font(Theme.Typography.caption)
                    }
                    .buttonStyle(PressableCardStyle())
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .animation(Theme.Motion.statusChange, value: model.errorMessage)
            .animation(Theme.Motion.statusChange, value: model.passwordMismatch)
        }
        .background(Theme.Colors.page)
        .scrollDismissesKeyboard(.interactively)
        // No navigation title: the header below it already says "Create
        // account", and showing it twice makes the screen look like it
        // scrolled wrong. The back chevron is the only chrome needed.
        .navigationBarTitleDisplayMode(.inline)
        .onSubmit(focus)
        .onAppear { viewModel = model }
    }

    private func focus() {
        switch focusedField {
        case .name:     focusedField = .email
        case .email:    focusedField = .password
        case .password: focusedField = .confirm
        case .confirm:  if let viewModel { submit(viewModel) }
        case .none:     break
        }
    }

    private func submit(_ model: SignInViewModel) {
        focusedField = nil
        Task {
            if let profile = await model.submit() {
                withAnimation(Theme.Motion.cardAppear) {
                    session.signIn(profile)
                }
                onSignedUp()
            }
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView(onSignedUp: {})
            .environment(ServiceContainer.mock())
            .environment(UserSession())
    }
}
