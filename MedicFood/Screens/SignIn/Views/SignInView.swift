import SwiftUI

struct SignInView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(UserSession.self) private var session

    @State private var viewModel: SignInViewModel?
    @FocusState private var focusedField: Field?

    private enum Field { case name, email, password }

    var body: some View {
        // The ViewModel is built from the environment on first render, so the
        // view stays constructible in previews and tests.
        let model = viewModel ?? SignInViewModel(services: services)

        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(spacing: 14) {
                    if model.mode == .signUp {
                        LabelledField(
                            title: "Name",
                            text: Binding(get: { model.name }, set: { model.name = $0 }),
                            systemImage: "person",
                            contentType: .name
                        )
                        .focused($focusedField, equals: .name)
                    }

                    LabelledField(
                        title: "Email",
                        text: Binding(get: { model.credentials.email }, set: { model.credentials.email = $0 }),
                        systemImage: "envelope",
                        contentType: .emailAddress,
                        keyboard: .emailAddress
                    )
                    .focused($focusedField, equals: .email)

                    LabelledField(
                        title: "Password",
                        text: Binding(get: { model.credentials.password }, set: { model.credentials.password = $0 }),
                        systemImage: "lock",
                        contentType: .password,
                        isSecure: true
                    )
                    .focused($focusedField, equals: .password)
                }

                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                }

                submitButton(model)

                Button(model.mode.switchPrompt) {
                    withAnimation { model.toggleMode() }
                }
                .font(.subheadline)
                .padding(.top, 4)

                hint
            }
            .padding(24)
        }
        .background(Theme.Colors.background)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { viewModel = model }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
            Text("MedicFood")
                .font(.title.bold())
            Text("Never miss a dose")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 32)
        .padding(.bottom, 8)
    }

    private func submitButton(_ model: SignInViewModel) -> some View {
        Button {
            focusedField = nil
            Task {
                // The ViewModel returns a result; the *view* decides what that
                // means for navigation. That is the MVVM contract.
                if let profile = await model.submit() {
                    session.signIn(profile)
                }
            }
        } label: {
            HStack {
                if model.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text(model.mode.callToAction).bold()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canSubmit)
    }

    /// The mock backend accepts anything well-formed, and saying so beats
    /// leaving someone guessing at a login screen with no account.
    private var hint: some View {
        Text("Running on sample data — any email and a 6-character password will sign you in.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
    }
}

#Preview {
    SignInView()
        .environment(ServiceContainer.mock())
        .environment(UserSession())
}
