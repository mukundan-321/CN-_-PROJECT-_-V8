# AUDIT — production readiness review

Every `lib/` and `test/` file was re-read in full, plus the Android
and iOS platform files. This is what was found and fixed. Nothing
below was fixed by running a compiler — I don't have one — everything
here was found and verified by tracing the code by hand.

## Fixed

### Security
- **SQL injection risk in `PRAGMA key`** (`app_database.dart`) — the
  DB passphrase was interpolated into raw SQL unescaped. A passphrase
  containing a `'` would have broken the statement. Now escapes
  embedded quotes.
- **SQLCipher verification was fake** (`app_database.dart`) — the code
  ran `PRAGMA cipher_version;` and claimed to "fail loudly" if
  SQLCipher wasn't active, but discarded the result instead of
  checking it. Now actually inspects the result and throws if empty.
- **Authorization gap: peer could edit/delete the *other* person's
  messages** (`chat_repository_impl.dart`) — incoming `'edit'` and
  `'delete_for_both'` frames were applied to any message ID the peer
  sent, with no check that the peer actually authored that message.
  Now scoped to `senderDeviceId == peer`.
- **Invite replay had no time bound** (`pairing_repository_impl.dart`)
  — an old or intercepted invite could be redeemed indefinitely. Now
  rejected if older than 10 minutes. (Low actual impact — session keys
  are always freshly generated regardless — but cheap to close.)

### Correctness
- **Race condition in identity generation** (`identity_key_service.dart`)
  — concurrent calls to `getOrCreateIdentity()` could each see no
  stored key, each generate a *different* keypair, and race to
  persist, leaving the losing caller with in-memory keys that no
  longer matched storage. Now memoized so concurrent callers share one
  result. Added a regression test.
- **Peer's real device ID was computed and discarded**
  (`pairing_repository_impl.dart`) — `peerIdentity.deviceId` returned
  a meaningless locally-generated row UUID instead of the peer's
  actual transmitted device ID. Fixed to persist and return the real one.
- **Type-inference risk in `Result.when()`** (`pairing_flow_screen.dart`)
  — mixed an `async` callback (`Future<void>`-returning) with a
  synchronous one in the same generic `when<R>()` call, which is
  fragile at best. Restructured to keep async work outside `when()`.
- **SQL `LIKE` wildcard injection in search** (`chat_repository_impl.dart`)
  — a search query containing literal `%`/`_` was treated as a SQL
  wildcard, silently producing wrong results. Now filtered in Dart.
- **Stale ICE candidates on retry** (`webrtc_connection_manager.dart`)
  — candidates from a previous, abandoned connection attempt were
  never cleared, so a retry would ship a mix of old and new candidates
  and leak the old `RTCPeerConnection`. Now reset before every attempt.
- **Latent FK-enforcement trap** (`messages_table.dart`) — `replyToMessageId`
  and `mediaMetadataId` declared SQL foreign keys that are currently
  unenforced (no `PRAGMA foreign_keys = ON` anywhere), but would start
  rejecting legitimately out-of-order P2P message delivery the moment
  anyone "correctly" enabled that pragma later. Removed — this is
  meant to be an application-level concern in a system with no
  guaranteed delivery order.

### Lifecycle / async safety
- **Missing `mounted` checks after `await`** in `chat_screen.dart`
  (`_send()`) and `pairing_flow_screen.dart` (`_startCreateFlow()`) —
  could touch a disposed controller/context.
- **Auto-scroll fired on every rebuild, not just new messages**
  (`chat_screen.dart`) — any unrelated rebuild (e.g. the connection
  indicator changing) yanked a manually-scrolled-up user back to the
  bottom. Now only fires when the message count actually increases.
- **`FutureBuilder` re-querying on every rebuild** (`main.dart`) —
  `isPaired` was fetched fresh inside `build()`; any unrelated rebuild
  reset the widget to its loading state. Now cached in `State`.
- **Transport leak on pairing retry** (`pairing_repository_impl.dart`)
  — a new `EncryptedTransport` replaced the old one without disposing
  it, leaking a stream subscription and session cipher per retry.
- **Possible duplicate navigation** (`pairing_flow_screen.dart`) — two
  independent triggers could both call `_goToChat()` close together
  and stack a duplicate route push. Added a guard.
- **No startup error handling** (`main.dart`) — a DI/database/secure-storage
  init failure would have surfaced as an unhandled framework crash.
  Now caught and shown as a real (if minimal) error screen.

### Lint / `flutter analyze` compliance
- **`unawaited_futures` violations** (`chat_screen.dart`) — pin, react,
  delete-for-me, and edit actions called repository methods without
  awaiting or consuming the result, which the project's own
  `analysis_options.yaml` (`unawaited_futures: true`) explicitly flags.
  Also meant failures on those actions were silently swallowed — no
  error ever reached the user. Fixed by awaiting + surfacing failures
  via snackbar, consistent with how "delete for both" already worked.

### Build configuration
- **Dead multidex config** (`android/app/build.gradle.kts`) —
  `multiDexEnabled = true` plus the `androidx.multidex` dependency are
  only meaningful for `minSdk < 21`; this project's `minSdk` is 23,
  where multidex is native. Harmless, but unnecessary. Removed.

### Performance
- **No index on `sentAt`/search path** (`messages_table.dart`) — every
  message load (`ORDER BY sentAt`) and search was a full table scan.
  Added an index. (Low real-world impact at this app's scale, but free.)

## Reviewed and found correct (no change needed)
- `session_crypto_service.dart` — ECDH, HKDF domain separation, AEAD,
  nonce construction, and the strict monotonic replay counter (correct
  *because* the data channel is configured `ordered: true`, guaranteeing
  in-order delivery) are all sound.
- `fingerprint.dart` — order-independent, sufficient entropy in the
  truncated digit string for a human-verification safety number.
- `pairing_payload.dart` — signature verification correctly rejects
  tampered payloads; the async-return-flattening in `verifySignature()`
  is valid Dart, not a bug (initially suspected one, checked, is fine).
- iOS `Podfile`'s `ONLY_ACTIVE_ARCH = YES` — only affects
  device-targeted builds, not Archive builds (which always target
  "Generic iOS Device" and ignore this setting), so it doesn't risk
  producing an App-Store-incomplete build the way it might first appear to.

## Not fixed — flagged as known gaps, not silently left broken

- **`AppDatabase`/`WebRtcConnectionManager`/`ChatRepositoryImpl` have
  `close()`/`dispose()` methods that are never called anywhere.** For
  `get_it` lazy singletons meant to live the app's full lifetime, this
  is largely intentional (the OS reclaims resources on process death),
  but there's no explicit "unpair"/"quit" path that would exercise
  cleanup. Not fixed — would need a real app-lifecycle/settings feature
  to hang cleanup off of, which is out of scope for an audit pass.
- **Reactions have no deduplication**, locally or on receipt — a
  double-tap or a retried delivery could produce duplicate reaction
  rows. Low severity (cosmetic at worst), not fixed.
- **The debug-key-signs-release-build situation** in
  `android/app/build.gradle.kts` — necessary for `flutter build apk
  --release` to succeed out of the box (documented in `CHECKLIST.md`
  and `BUILD.md`), but is not something to distribute. This is a
  known, intentional, documented placeholder, not an oversight.
- **App Store / Google Play policy considerations** — flagged, not
  "fixed" since there's no code-level fix: this app collects no data
  and has no backend, which simplifies most privacy-policy
  requirements, but both stores still require a **privacy policy URL**
  and an **account-deletion/data-deletion path** disclosure at
  submission time (Google Play's Data Safety form, Apple's App Privacy
  labels) even for a zero-collection app — that's a store-listing
  requirement, not something `lib/` can satisfy. Neither store's
  policy is violated by anything in this codebase itself.

## What this audit could not do

No compiler, no `flutter analyze`, no `flutter test` run — everything
above was found by tracing execution paths and cross-referencing
against package documentation by hand. That's a real, careful review,
but it is categorically not the same guarantee an actual build gives
you. Run `flutter analyze` and `flutter test` yourself as the real
verification step; see `BUILD.md`.
