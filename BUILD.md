# BUILD — Android & iOS

Read `CHECKLIST.md` first if you want to know *why* each generated
step below is necessary — this file is just the steps themselves.

## Prerequisites

- Flutter SDK (stable channel) on your PATH — `flutter doctor` should
  show no blocking issues for the platform(s) you're building.
- **Android:** Android Studio or the standalone Android SDK/command-line
  tools, plus a JDK (17, matching this project's Gradle config).
- **iOS:** a Mac with Xcode installed (Xcode itself, not just Command
  Line Tools — you'll need it for signing regardless), and CocoaPods
  (`sudo gem install cocoapods` if you don't have it).

## Android

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
cd android
gradle wrapper --gradle-version 8.10.2
cd ..
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

That APK is signed with the debug key (see `CHECKLIST.md` for why) —
installable on a device for testing, but not something to distribute.
For a real release build, generate a keystore, create
`android/key.properties` pointing to it, and update the
`signingConfig` in `android/app/build.gradle.kts` to use it instead of
`signingConfigs.getByName("debug")`.

To run directly on a connected device or emulator instead of just
building:
```bash
flutter run -d <device-id>
```

## iOS

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter create --platforms=ios .
cd ios
pod install
cd ..
open ios/Runner.xcworkspace
```

Then in Xcode: select the `Runner` target → **Signing & Capabilities**
→ choose your team (needed even for Simulator builds on some Xcode
versions, required for a physical device). Select a run destination
and press ▶, or from the command line:

```bash
flutter build ios --release
```

This produces an unsigned `.app`/build artifact suitable for archiving
— actually shipping to TestFlight/App Store requires archiving and
exporting through Xcode's Organizer (Product → Archive), which needs
your Apple Developer account wired up as above.

## Running the test suite

```bash
flutter test
```

Covers the crypto module (key generation, fingerprint, session keys,
signed payloads), the chat wire protocol (a real two-simulated-device
test, not mocks), and the pairing repository's offline/online paths.
It does not cover UI widgets — there are no widget tests in this build.

## If something fails

I don't have a Flutter/Android/Xcode toolchain in the environment this
was written in, so none of the above has actually been run end to end.
If a build fails:
- **Android:** most likely a Gradle/AGP/Kotlin version mismatch if
  your installed Flutter SDK expects different pinned versions than
  the ones in `android/settings.gradle.kts` (AGP 8.7.2, Kotlin 2.1.0) —
  bump them to whatever `flutter create` would generate for your SDK
  version and retry.
- **iOS:** most likely a CocoaPods dependency resolution issue (network
  access to the CocoaPods spec repo is required for `pod install`), or
  a signing configuration issue — both are normal first-build friction
  for any Flutter iOS project, not specific to this one.
- Either way, the actual Dart application code (`lib/`, `test/`) is the
  part that was reviewed most carefully and is least likely to be the
  source of a build failure — see `README.md` for what was checked there.
