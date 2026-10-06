import Foundation

/// App-wide constants and feature switches.
///
/// Anything that is a *decision about the app* rather than a piece of logic
/// lives here, so those decisions are in one readable file instead of being
/// scattered as magic numbers.
enum AppConfig {

    static let appName = "MedicFood"
    static let bundleIdentifier = "com.srmist.medicfood"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// Which service stack the app runs on. **This is the switch.**
    ///
    /// `mock` runs entirely on device with sample data and no secrets, so the
    /// app works from a fresh clone and demos reliably with no network and no
    /// account. That is why it is the default.
    ///
    /// `live` talks to Firebase project `medicfood-84cbf` — the same backend
    /// the Android app uses, so data written on either appears on both. It
    /// needs `GoogleService-Info.plist` in `MedicFood/`, which is gitignored:
    /// a fresh clone does not have it, so leaving this on `mock` is also what
    /// keeps the app running for a teammate who has not been sent the file.
    enum Backend { case mock, live }
    static let backend: Backend = .mock

    enum Reminders {
        /// iOS drops pending local notifications past 64. We stay under it and
        /// keep headroom for snoozes created at runtime.
        static let iosPendingLimit = 64
        static let windowSize = 55

        /// How many days ahead the dashboard registers reminders for.
        static let lookAheadDays = 14

        static let snoozeMinutes = 15
    }

    /// Gemini, reached through Firebase AI Logic — see `GeminiMedicineAI`.
    enum AI {
        /// A fast, inexpensive model is the right one for reading text off a
        /// page. Change it here; nothing else names a model.
        static let modelName = "gemini-2.5-flash"
    }

    enum Features {
        /// Read prescriptions and medicine packs with Gemini, and turn dictation
        /// into medicines. When off — or when Firebase is not configured — the
        /// app uses its on-device reader and never mentions AI.
        ///
        /// Needs Firebase AI Logic enabled for the project.
        static let geminiAI = true

        /// ⚠️ Gates nothing — no code reads this.
        ///
        /// It described the Flutter app's Gemini path, where the prescription
        /// *image* was sent to `gemini-1.5-pro` for structured extraction. This
        /// app does not do that: scanning runs on Apple's Vision framework
        /// on-device, needs no key, and is not switched off by this flag.
        ///
        /// If a Gemini step is ever added it must live behind a server
        /// endpoint — an API key shipped in an iOS binary is readable by
        /// anyone who downloads the app.
        static let aiPrescriptionScanning = false

        static let caretakerLinking = true
        static let drugSearch = true
    }

    enum Support {
        static let email = "support@medicfood.app"
        static let privacyPolicy = URL(string: "https://medicfood.app/privacy")!
        static let termsOfUse = URL(string: "https://medicfood.app/terms")!
    }
}
