# CHECKLIST — machine-generated files

Everything in this list is intentionally **not** in the zip. Each one
is either a compiled binary, a content-addressed lockfile computed by
resolving against a live package index, a machine-specific path
reference, or (for iOS specifically) part of a project format that's
actively mid-migration upstream — reasons are given per item, not just
asserted.

## Android

| File | Why it can't be hand-written | Command to generate it |
|---|---|---|
| `android/gradle/wrapper/gradle-wrapper.jar` | Compiled Java bytecode (a class-file bootstrapper), not source text. | From `android/`: `gradle wrapper --gradle-version 8.10.2` (needs a system Gradle install), or open the project in Android Studio once — it regenerates this automatically. |
| `android/local.properties` | Machine-specific: contains the absolute path to *your* Flutter SDK install. | Auto-created the first time you run `flutter pub get` or `flutter build` in the project — nothing to run manually. |
| `android/.gradle/`, `android/app/build/` | Build cache and compiled output, not source. | Created automatically by any `./gradlew` or `flutter build` invocation. |
| A real release signing key + `android/key.properties` | This is *your* keystore, generated once and kept private — I cannot generate a secret for you, and a placeholder here would just be a security footgun if it accidentally shipped. | `keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`, then point `key.properties` at it. Until then, `android/app/build.gradle.kts` signs release builds with the debug key so `flutter build apk --release` still succeeds — **do not distribute that build.** |

## iOS

| File | Why it can't be hand-written | Command to generate it |
|---|---|---|
| `ios/Runner.xcodeproj/project.pbxproj` | This is the project's full object graph — targets, build phases, file references — cross-linked by generated UUIDs, normally written by Xcode's own model layer. It's technically text, but internal-consistency requirements are strict enough that a mistake won't show up as a readable error, just a project Xcode refuses to open. On top of that, Flutter's default iOS template lifecycle is **actively mid-migration right now** (UIScene-based lifecycle became the `flutter create` default as of Flutter 3.41, replacing the AppDelegate pattern that had been stable for years) — meaning even the "standard" structure this file should have is less settled than usual at the time this was written. | `flutter create --platforms=ios .` from the project root — regenerates this correctly for whatever Flutter version you have installed, without touching `lib/`, `android/`, or `pubspec.yaml`. |
| `ios/Runner.xcodeproj/project.xcworkspace/` | Depends on `project.pbxproj` existing and being valid — generated alongside it. | Same command as above. |
| `ios/Runner.xcworkspace/` | The top-level workspace CocoaPods extends with `Pods.xcodeproj` — depends on the `.xcodeproj` above existing first. | Created by `flutter create`, then updated by `pod install` (see below). |
| `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` | References the target by the UUID `project.pbxproj` assigns it — has to be generated alongside that file, not independently. | Same `flutter create` command; Xcode also regenerates a default scheme automatically if one is missing. |
| `ios/Flutter/Generated.xcconfig` | Contains the absolute path to your Flutter SDK and other machine-specific build settings (`FLUTTER_ROOT`, `FLUTTER_APPLICATION_PATH`). Regenerated on every build — never meant to be committed. | Auto-created by `flutter pub get` / `flutter build ios`. |
| `ios/Flutter/Flutter.podspec`, `Flutter.framework`, `App.framework`, `ios/Flutter/ephemeral/` | Copied in from the Flutter SDK itself / compiled build output, not project source. | Auto-created by `flutter build ios` / `flutter run`. |
| `ios/Pods/`, `ios/Podfile.lock` | `Podfile.lock` records exact resolved versions and checksums computed by CocoaPods resolving `ios/Podfile` against the live CocoaPods trunk spec repo at install time — this requires network access to that repo, so it's inherently something only `pod install` can produce correctly. | From `ios/`: `pod install` (Flutter's tooling also runs this automatically as part of `flutter build ios` / `flutter run`). |
| A provisioning profile / signing certificate | Tied to your Apple Developer account. Not something any tool generates unattended — Xcode walks you through it interactively. | Xcode → Runner target → Signing & Capabilities → select your team. Required even for a Simulator build in some Xcode versions; definitely required for a physical device. |

## What IS in this zip for iOS

`Info.plist`, `AppDelegate.swift`, `Podfile`, the three `.xcconfig`
include files, `Assets.xcassets` (including a real 1024×1024 app icon),
and `LaunchScreen.storyboard` — all plain, stable text formats safe to
hand-write, all real content rather than placeholders. Run
`flutter create --platforms=ios .` first to generate the Xcode project
files above, and it will slot in around these without overwriting them
— `flutter create` only fills in files that are missing.

## Quick reference — commands to run, in order

```bash
# 1. Android — regenerate the Gradle wrapper jar
cd android && gradle wrapper --gradle-version 8.10.2 && cd ..

# 2. iOS — generate the Xcode project files
flutter create --platforms=ios .

# 3. Both — fetch Dart packages (also creates local.properties,
#    Generated.xcconfig)
flutter pub get

# 4. Drift's generated database code
dart run build_runner build --delete-conflicting-outputs

# 5. iOS only — resolve and install CocoaPods
cd ios && pod install && cd ..

# 6. Build
flutter build apk --release
flutter build ios --release   # or open ios/Runner.xcworkspace in Xcode
```
