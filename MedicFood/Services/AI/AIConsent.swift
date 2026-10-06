import SwiftUI
import Observation

/// Whether the user has agreed to have their photos and words read by Gemini.
///
/// A prescription photo is health data, and using Gemini means it leaves the
/// phone. That is the user's decision, not the app's — so nothing is sent until
/// they have said yes, and a "no" is remembered rather than asked again.
struct AIConsentStore {

    enum Decision: String {
        case undecided, allowed, declined
    }

    static let key = "medicfood.ai.consent"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var decision: Decision {
        get { defaults.string(forKey: Self.key).flatMap(Decision.init(rawValue:)) ?? .undecided }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }
}

/// Decides, for one request, whether to use the AI, ask first, or stay on the
/// device — and holds the question while the user answers it.
@MainActor
@Observable
final class AIConsentPrompt {

    /// Drives the alert.
    var isPresented = false

    private let store: AIConsentStore
    private var withAI: (() async -> Void)?
    private var onDevice: (() async -> Void)?

    init(store: AIConsentStore = AIConsentStore()) {
        self.store = store
    }

    /// Runs `withAI` when a model is available and the user has agreed, asks
    /// when they have not yet been asked, and otherwise runs `onDevice`.
    ///
    /// The model being unavailable is not a reason to ask: there is nothing to
    /// consent to, and the question would be about a feature that is not there.
    func gate(
        ai: MedicineAIServicing,
        withAI: @escaping () async -> Void,
        onDevice: @escaping () async -> Void
    ) async {
        guard ai.isAvailable else { return await onDevice() }

        switch store.decision {
        case .allowed:
            await withAI()
        case .declined:
            await onDevice()
        case .undecided:
            self.withAI = withAI
            self.onDevice = onDevice
            isPresented = true
        }
    }

    func allow() {
        store.decision = .allowed
        isPresented = false
        resume(using: withAI)
    }

    func decline() {
        store.decision = .declined
        isPresented = false
        resume(using: onDevice)
    }

    private func resume(using action: (() async -> Void)?) {
        let pending = action
        withAI = nil
        onDevice = nil
        guard let pending else { return }
        Task { await pending() }
    }
}

extension View {
    /// The consent question, worded for what is about to be sent.
    func aiConsentAlert(_ prompt: AIConsentPrompt) -> some View {
        modifier(AIConsentAlert(prompt: prompt))
    }
}

private struct AIConsentAlert: ViewModifier {
    @Bindable var prompt: AIConsentPrompt

    func body(content: Content) -> some View {
        content.alert("Read this with Gemini AI?", isPresented: $prompt.isPresented) {
            Button("Allow") { prompt.allow() }
            Button("Use This Device Instead", role: .cancel) { prompt.decline() }
        } message: {
            Text("Gemini reads photos and text more accurately, especially handwriting. To do that, MedicFood sends the photo or text to Google's Gemini through Firebase. MedicFood does not keep a copy on a server.\n\nYou can change this any time in Settings. Or MedicFood can read it on this device without sending anything.")
        }
    }
}
