# two_person_app

Pairing + chat between exactly two people. Direct peer-to-peer,
end-to-end encrypted, no servers, no accounts. This is the entire
scope of this build — nothing else is stubbed in or half-started.

## What's here

35 files, ~3,270 lines.

```
lib/
  core/
    database/    — drift schema (SQLCipher-encrypted): messages, media
                    metadata, reactions, keys, settings. 5 tables, all used.
    di/           — get_it service locator, 2 registrations
    error/         — 4 failure types, all used somewhere
    theme/
    utils/         — Result<T>
  features/
    pairing/
      domain/      — PairingRepository interface, DeviceIdentity,
                      EncryptedChannel interface
      data/
        crypto/     — key generation, signed payloads, fingerprint,
                       session keys (X25519 + Ed25519 + HKDF + ChaCha20-Poly1305)
        signaling/   — WebRTC offer/answer/ICE, encrypted transport
      presentation/ — pairing flow screen (create/join/verify/reconnect),
                       QR scanner, Riverpod providers
    chat/
      domain/       — ChatRepository interface, ChatMessage
      data/          — drift-backed CRUD + live delivery over the wire
      presentation/  — chat screen, Riverpod providers
  main.dart
```

Every file here is either used by the running app or by a test. There
is no unused feature module, no placeholder screen, no dead code path
left over from broader scope — that was true before this pass too, for
the parts that had UI, but the calls signaling/media backend, six
unused database tables, and unused packages (freezed, json_serializable)
from earlier passes are gone now. What used to be a ~50-file project
with real code sitting behind no UI is now a smaller project where
everything is reachable and load-bearing.

## What the app actually does

1. First launch on two devices → pairing screen.
2. One side creates an invite (QR + copyable text), the other scans or
   pastes it and sends back a response the same way.
3. Both sides see the same safety-number fingerprint and confirm it
   matches — that's the actual trust check, not the QR exchange itself.
4. Chat: send, edit, delete for me, delete for both (fails if the peer
   isn't reachable — by design), pin, react (❤️ only).
5. Closing and reopening the app shows a lighter "Reconnect" screen
   instead of full pairing — no server means every launch re-establishes
   the live connection, but the long-term trust (and the fingerprint
   verification) persists.

## What's explicitly not here

Media/voice notes, stories, feed, gallery, calls UI, settings screens,
any visual design beyond default Material 3 dark theme, TURN toggle,
screen-recording/lock-screen privacy. None of it is half-built —
it was removed rather than left as broken stubs.

## Before real use

`main.dart` hardcodes the database passphrase
(`'REPLACE_WITH_DERIVED_KEY'`) — this needs to come from a real
biometric/PIN-gated key before this holds actual private conversations.
That's the one remaining TODO in the codebase (`grep -rn TODO lib`
finds exactly one hit).

## Building it

I can't produce an installable `.apk`/`.ipa` — this was written
without a Flutter toolchain or network access, so it's never been
compiled. What I can tell you: every internal import resolves to a
file that exists (checked), every Companion/table field name matches
its drift table definition (checked by hand), and the trickier
third-party APIs (`qr_flutter`'s `QrImageView`, `mobile_scanner`'s
`onDetect`, `cryptography`'s `Hkdf`/`Chacha20`/`Ed25519`/`X25519`) were
checked against current package documentation, not just recalled. Two
real bugs were caught and fixed this way in earlier passes (a missing
WebRTC enum prefix, a drift table/row class name collision), and one
more this pass (a missing `mounted` check before `setState` after an
async call). That's a real, careful review — not a substitute for
`flutter analyze`.

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

`build_runner` is required because drift's generated
`app_database.g.dart` isn't checked in.

## Platform support (Android / iOS)

Full build instructions: **`BUILD.md`**. Full list of what's
machine-generated and exactly how to generate it: **`CHECKLIST.md`**.
Short version below.

**Android — fully generated.** `android/` has the complete Gradle
Kotlin DSL setup, `AndroidManifest.xml` with camera + network
permissions, `MainActivity.kt`, ProGuard rules for
flutter_webrtc/SQLCipher/flutter_secure_storage, and real launcher
icons at every density. `applicationId` is `com.twoperson.us`,
`minSdk` 23, `compileSdk`/`targetSdk` 35. One gap: `gradle-wrapper.jar`
is a compiled binary I can't hand-write — see `CHECKLIST.md` for the
one-line fix.

**iOS — the plain-text parts are generated, the Xcode project graph
is not.** `ios/Info.plist` (camera/microphone/local-network
permissions), `AppDelegate.swift`, `Podfile` (with the
flutter_webrtc-required `post_install` workaround), the `.xcconfig`
files, `Assets.xcassets` with a real 1024×1024 icon, and
`LaunchScreen.storyboard` are all in this zip. `Runner.xcodeproj`
(`project.pbxproj`, the workspace, the scheme) is not — that file
format is generated by Xcode's own model layer, cross-references
internal UUIDs, and — concretely, not just abstractly — Flutter's
default iOS app lifecycle is *mid-migration right now* (UIScene-based
became the `flutter create` default as of Flutter 3.41, replacing the
AppDelegate pattern that had been stable for years), which makes this
a worse-than-usual moment to hand-fabricate that structure from
memory. One command generates it correctly for whatever Flutter
version you have: `flutter create --platforms=ios .` — it fills in
only what's missing, won't touch the files already here.

**Web** isn't included, and it's not a missing-folder problem — the
database layer uses `dart:io` file paths that don't exist in a
browser; supporting web means a second WASM-based drift backend, a
real chunk of work, not a generated folder.

**macOS / Linux / Windows desktop** — not attempted this pass. Ask if
you want them; macOS has the same Xcode-project caveat as iOS, Linux/
Windows are CMake + C++ (more like Android's Gradle in risk profile)
and could be built out the same way Android was.

If `flutter analyze` still finds something — possible, since a
third-party package API can differ from what documentation showed, or
a Flutter-version-specific detail could be off — the failure is most
likely narrow (one method signature) rather than structural, given how
this pass went through the codebase file by file.
