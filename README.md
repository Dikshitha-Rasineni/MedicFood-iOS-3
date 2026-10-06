# MedicFood — iOS

A medication reminder and adherence app. **Swift 6 · SwiftUI · MVVM · iOS 17+.**

Get your prescription into the app → get reminded at the right times → record
whether you took it → let a caretaker check in on you.

---

## Run it

```bash
git clone https://github.com/Sanjaaaay/MedicFood-iOS.git
cd MedicFood-iOS
open MedicFood.xcodeproj
```

Press ⌘R. That is the whole setup — no CocoaPods, no `.env`, no API keys, no
`GoogleService-Info.plist`. The app runs on sample data.

Needs Xcode 16 or newer. To sign in, use any email address and any password of
six characters or more.

---

## Layout

```
MedicFood.xcodeproj
MedicFood/
├── MedicFoodApp.swift  App entry point
├── App/            App lifecycle (AppDelegate)
├── Config/         Constants and feature switches
├── Screens/        Feature-based screens using MVVM + Models structure
│   ├── Splash/              Splash View/ViewModel/Models
│   ├── Dashboard/           Today's Doses Dashboard
│   ├── FeatureTour/         First-run app feature tour
│   ├── SignIn/              Authentication and Sign In / Sign Up
│   ├── MedicineDetail/      Medicine list and detail screens
│   ├── AddMedicine/         Add or edit medicine details
│   ├── PrescriptionScanner/ Scan prescriptions using shorthand/AI
│   ├── MedicineSearch/      Drug interactions search and lookup
│   ├── DrugFoodInteraction/ Drug-food interaction search and detail
│   ├── Adherence/           Adherence tracking charts and streaks
│   ├── Caretaker/           Caretaker linking and dashboard view
│   └── Profile/             User profile, settings, help, and privacy
├── Networking/     APIConfiguration, APIEndpoint, HTTPRequestManager, APIService
├── Services/       Auth, medicines, adherence, notifications, drug info, caretakers
├── Utils/          Session, theme, prescription and duration parsers
├── Extensions/     Shared Swift extensions
├── Resources/      Assets.xcassets
└── Info.plist
MedicFoodTests/     48 unit tests
```

The folders are synchronised with the file system, so adding a file in Finder
adds it to the project. You never edit the `.xcodeproj` by hand and it never
causes a merge conflict.

---

## Screens Architecture

The app uses a modular, feature-based directory structure inside `Screens/` to encapsulate all components of a single screen or functional user flow.

Inside each screen directory (e.g., `Screens/Splash/` or `Screens/Dashboard/`), the structure is laid out as follows:

- **`Views/`**: Houses all SwiftUI views and subviews specific to that screen (e.g., `SplashView.swift`, `DashboardView.swift`, `DoseRow.swift`).
- **`ViewModels/`**: Houses the screen's state and business logic using a MainActor-isolated `@Observable` class. As per project rules, view models never import SwiftUI to maintain a clean layer separation and make testing straightforward.
- **`Models/`**: Houses feature-specific data models and custom configurations (e.g., `SplashModels.swift`, `DashboardModels.swift`) that are encapsulated and not reused globally.

By keeping these files co-located, adding, updating, or deleting a feature is extremely simple and does not impact other areas of the codebase.

---

## Data Models Architecture

We divide our data models into two distinct categories based on their usage scope:

### 1. Screen-Specific Models (Feature-level)
Located under `Screens/<ScreenName>/Models/` (e.g., `Screens/Splash/Models/SplashModels.swift` and `Screens/Dashboard/Models/DashboardModels.swift`).
- **Purpose**: Houses data structures and models that are exclusively used by a single screen or feature. This keeps the feature self-contained and avoids cluttering the global scope with configurations or structures that other screens do not need.

### 2. App-wide / Global Models (Shared-level)
Located globally under the core models or networking directories.
- **Scope**: App-wide / Global
- **Purpose**: Houses core, shared data structures and models that represent backend resources or common network wrappers. These models are reused across multiple screens and manager services.
- **Key Files & Examples**:
EXAMPLES:
  - `ResponseModel.swift`: A generic wrapper class (`ResponseModel<T>`) used to decode the standard envelope of all server responses.
  - `LoginModels.swift`: Models like `UserData` and `HeaderData` which are stored and referred to globally for session state management.
  - `RegionModels.swift`: Models representing region configurations (`RegionData`, `ServerData`) used at startup to configure base URLs.

---

## The one rule: a ViewModel never imports SwiftUI

A `ViewModel` holds state and runs logic. A `View` decides what that looks like
and where to navigate. The ViewModel hands a result back and the view acts on
it:

```swift
// SignInViewModel — no SwiftUI import anywhere in this file
func submit() async -> UserProfile? { … }

// SignInView decides what to do with it
if let profile = await model.submit() {
    session.signIn(profile)
}
```

This is checkable in review: if `import SwiftUI` appears in `ViewModels/`, the
rule has been broken. It is also why `MedicFoodTests` can drive the whole
dashboard with no UI and no simulator.

---

## Services are protocols

Every service is a protocol with a mock implementation, wired together in one
place — `Services/ServiceContainer.swift`:

```swift
protocol MedicineServicing: AnyObject {
    func medicines() async throws -> [Medicine]
    …
}

MockMedicineService       ← used now, runs offline
FirestoreMedicineService  ← drop in later, nothing else changes
```

To move to a real backend, write the live implementation and change one line in
`ServiceContainer.mock()`. No view and no ViewModel changes.

Network details are in **[NETWORKING_ARCHITECTURE.md](NETWORKING_ARCHITECTURE.md)**.

---

## Screens

| Screen | Folder |
|---|---|
| First-run tour | `Screens/FeatureTour/` |
| Sign in / sign up | `Screens/SignIn/` |
| Today's doses | `Screens/Dashboard/` |
| Medicine list and detail | `Screens/MedicineDetail/` |
| Add or edit a medicine | `Screens/AddMedicine/` |
| Add a prescription | `Screens/PrescriptionScanner/` |
| Drug lookup and food interactions | `Screens/MedicineSearch/` |
| Adherence and streaks | `Screens/Adherence/` |
| Caretaker linking | `Screens/Caretaker/` |
| Profile, settings, help, privacy | `Screens/Profile/`, `Screens/Settings/`, … |

---

## Two things worth knowing

**Prescription shorthand.** `Utils/PrescriptionParser.swift` reads what doctors
actually write: `1-0-1` notation (morning-afternoon-night), and `OD` / `BD` /
`TID` / `QID`. Type it into the add-medicine form and the times fill themselves
in. Behaviour is pinned by tests, because getting it wrong means someone takes
a tablet at the wrong time.

**iOS only allows 64 pending notifications.** A 30-day prescription is far more
than that, and iOS silently drops the excess — the app would look fine and stop
reminding people. `Services/NotificationService.swift` keeps a ledger of every
dose and registers only the soonest 55, topping the window up whenever the app
opens. If you add a code path that schedules doses, call `topUpWindow()` after
it.

---

## Tests

```bash
xcodebuild test -project MedicFood.xcodeproj -scheme MedicFood \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

48 tests, covering the prescription parser, the duration parser, the medicine
model and the dashboard ViewModel. CI runs these on every push and pull
request.

---

## Not built yet

- Firebase Auth and Firestore — the protocols are ready, see `ServiceContainer.live()`
- Photo scanning of prescriptions. Typing the prescription works today; the AI
  path is behind `AppConfig.Features.aiPrescriptionScanning` and belongs behind
  a server endpoint, never with an API key shipped inside the app
- App icon artwork

---

## History

This repo was a Flutter port of the Android app
[`sv6095/MedicFood`](https://github.com/sv6095/MedicFood). It was rewritten in
native SwiftUI in August 2026. The Flutter sources are not in the working tree
any more; they remain in this repository's git history and in the upstream
Android repo.
