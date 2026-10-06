## What changed

<!-- One or two sentences. What does this PR do? -->

## Why

<!-- Link an issue if there is one. -->

## How I verified it

<!-- Delete what does not apply. Be honest — "did not run" is a valid answer
     and much better than a checked box that is not true. -->

- [ ] `flutter analyze` is clean
- [ ] `flutter test` passes
- [ ] Ran on the iOS Simulator
- [ ] Ran on a physical device
- [ ] Did not run the app (explain below)

<!-- If this touches reminders, say which you checked: scheduling, firing,
     snooze, notification actions, or the 64-notification top-up on resume. -->

## Checklist

- [ ] New screens live in `lib/features/<name>/` with `view/` and `viewmodel/`
- [ ] No `BuildContext`, `Navigator` or `material.dart` inside a ViewModel
- [ ] Used `package:` imports, not relative ones
- [ ] Used `safeNotifyListeners()`, not `notifyListeners()`
- [ ] No secrets committed (`.env`, `GoogleService-Info.plist`)
