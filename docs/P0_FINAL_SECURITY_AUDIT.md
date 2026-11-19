# P0 Final Security Audit

## A. Executive summary

This report records the final P0 security audit of MapNote on branch `security/p0-final-audit` at base commit `bf0b2174d0056fbde278ab15640bc3a9e080ae8a`, including the dirty worktree's uncommitted P0-related changes. The audit was source-first and read-only. No target code was executed because the required OS-enforced sandbox was unavailable. The run produced no confirmed findings, but it produced multiple high-impact source-grounded leads that remain unresolved. The final disposition is printed exactly once as the last line of this document.

**Confirmed vulnerabilities fixed by this audit:** none.

**No target source was modified by the audit.** Pre-existing dirty worktree changes were preserved; no commit, push, pull request, deployment, emulator run, device test, APK build or AAB build was performed.

## B. Scope and source reference

- Run: `run-1` / `MapNote-App`.
- Target: `D:\RouteNote App`.
- Branch: `security/p0-final-audit` from `bf0b2174d0056fbde278ab15640bc3a9e080ae8a`.
- Worktree: dirty (uncommitted P0-related changes included).
- Profile: `standard`; no strict budget.
- Prior runs: none.

Scope paths requested:

  - .github
  - android/app/build.gradle.kts
  - android/app/firestore.rules
  - android/app/google-services.json
  - android/app/master_stations.rules
  - lib/src/core/config/app_config.dart
  - lib/src/core/orchestrator/adaptive_engine_orchestrator.dart
  - lib/src/data/remote/google_auth_service.dart
  - lib/src/features/saved_places/data/repositories/keystore_vault_pin_verifier.dart
  - lib/src/providers/app_providers.dart
  - test

Coverage is recorded in the parent-owned external ledger and summarized below.

## C. Method and execution boundary

- Execution policy: `sandboxed-source-and-local-only`.
- Source ref: branch `security/p0-final-audit`, base commit `bf0b2174d0056fbde278ab15640bc3a9e080ae8a`, dirty worktree: true.
- Profile: `standard`; budget: not set.
- OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox: unavailable.
- Target process execution: not allowed.
- Reason: No OS-enforced sandbox satisfying the full required control set is available in this environment.
- Therefore no target build, test, emulator, device command, live deployment probe, or network request was executed in this run.

No live Firebase project, GitHub deployment, production identity, release artifact, secret value or network endpoint was contacted or inspected. Branch-qualified `work-edition/...` sources were read with read-only git metadata only.

## D. Coverage, verification gate and test status

- Coverage units: 30
- Unit statuses: candidate=23, covered=7
- Unique candidate fingerprints linked from ledger: 32
- Fingerprint reconciliation: one duplicate fingerprint (`verification-gate/vault-lockout-hours-vs-minutes`) was consolidated into `vault-pin-lockout/permanent-lockout-hours-vs-minutes`.
- Findings records: 31 (0 confirmed, 30 needs_validation, 1 rejected)
- Ledger checks with a promoted local artifact: 0
- Deferred units: 0; out-of-scope units: 0.
- Carried same-source confirmations: none; changed-source revalidations: none.
- Post-wave-6 critic A: stop=false; missing_units=clipboard-plus-code/system-clipboard-text-to-plus-code-and-location-state; reassign_ids=0
- Post-wave-6 critic B: stop=false; missing_units=clipboard-paste-location/clipboard-text-to-location-and-shortlink-sinks, automotion-export-egress/local-motion-aggregates-to-clipboard-export; reassign_ids=0
- Post-wave-7 critic: stop=true; missing_units=none; reassign_ids=0
- Final-clean critic: stop=true; missing_units=none; reassign_ids=0
- Run status: complete (all 30 retained records received an independent Phase 5 disposition and passed final schema validation).
- Phase 5 record verification: retained=30, verified=28, replacements=2, applied=2.

### Target verification gate

- `flutter analyze lib test`: NOT EXECUTED (OS-enforced sandbox unavailable).
- `flutter test`: NOT EXECUTED (OS-enforced sandbox unavailable).
- Firebase Emulator Suite rules tests: NOT EXECUTED (Docker daemon unavailable; WSL node unavailable; OS-enforced sandbox unavailable).
- APK/AAB builds: NOT EXECUTED (OS-enforced sandbox unavailable).
- Device/emulator tests: NOT EXECUTED (OS-enforced sandbox unavailable).
- Prior report claim of 997 passing tests and 5 failing tests: NOT VERIFIED in this run.

Previously reported failures that remain NOT VERIFIED:
- `test/add_place_screen_test.dart`
- `test/encrypted_vault_test.dart`
- `test/geocoding_service_test.dart`
- `test/milestone_name_resolver_test.dart`
- `test/route_history_screen_test.dart`

### Audit validators

- `C:/Users/nader/.agents/skills/security-audit/validate-findings.cjs`: PASS (structural and semantic validation of `findings.json`).
- `C:/Users/nader/.agents/skills/security-audit/validate-coverage-ledger.cjs`: PASS (structural and semantic validation of `coverage-ledger.json`).
- These validators prove schema and ledger consistency only; they do not execute target code.

## E. Confirmed findings

No independently demonstrated confirmed findings were retained in this run.

## F. Needs-validation leads

| Fingerprint | Title | Source-grounded hypothesis | Exact blocker |
| --- | --- | --- | --- |
| `adaptive-lifecycle/setpowermode-reopens-paused-location-stream` | Background/foreground transition reopens a paused OS location stream | The paused verdict produced by the adaptive FSM is stored only in the trackers' _streamPaused field and is enforced in start() and applySampling(), but the independent setPowerMode lifecycle path omits that field from its guards and unconditionally reopens _openFixes; the LocationHub, which holds the single OS handle, has no knowledge of the paused verdict and re-registers the consumer. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, and the verifier boundary forbids flutter test, builds, emulators and device commands, so no target-neutral local observed result exists to promote to confirmed. |
| `android-foreground-tracking/manifest-service-name-mismatch-disables-f...` | Manifest foreground service name does not match the started Kotlin Service class | The manifest <service> entry uses android:name=".ForegroundTrackingService" (AndroidManifest.xml:108) while the Kotlin file of the same name defines class LocationTrackingService : Service() (ForegroundTrackingService.kt:29) and MainActivity's start/stop intents target LocationTrackingService::class.java (MainActivity.kt:180,192). Android resolves services by class name, so the declared component does not exist and the component actually started is undeclared; the OS cannot promote it to a location-type foreground service. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, so the required isolation for a confirmed verdict cannot be established. |
| `ci-opencode-comment-trigger-missing-author-association-gate` | Unrestricted comment-triggered opencode workflow grants write scopes and a provider secret | Authorization for a write-capable, secret-bearing automation job is derived from comment body text alone; no author_association, collaborator/owner check, CODEOWNERS rule, or branch-protection control is visible on the trigger path, allowing any commenter accepted by the deployment to provision release-capable token scopes. | The required OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is unavailable in this run, and no already-promoted target-neutral local observed artifact exists; confirming would require executing target or GitHub Actions behavior, which is outside this verifier's boundary. |
| `ci-release-secrets/dart-define-key-embedded-in-distributed-apk` | Release workflows compile GEMINI_API_KEY into distributed APKs | The release pipelines inject GEMINI_API_KEY as a compile-time Dart environment value, so any configured secret value is embedded in the release binary that is uploaded and distributed rather than kept server-side or omitted from published artifacts. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, and no promoted local artifact exists; a source trace alone cannot establish a confirmed verdict under the audit contract. |
| `cloud-geocoding-disclosure/cloud-ai-toggle-default-on-enables-third-p...` | Default-on cloud flag enables third-party coordinate upload | SettingsRepository.isCloudAiEnabled defaults a missing cloud_ai_enabled value to true, and the same cloud-AI switch is reused as the consent gate for Geoapify reverse geocoding, so a fresh install is treated as opted in to third-party coordinate upload whenever a Geoapify key is present. | No OS-enforced target sandbox is available in this run with an empty environment, no external network, a read-only target, scratch-only writes and explicit resource limits, and the verifier contract forbids executing target code; no promoted local observed artifact exists. |
| `cloud-key-handling.app-config.geoapify-doc-comment-hex-literal` | Provider-shaped 32-hex literal in lib doc comment | A provider-shaped example credential was placed in a tracked source doc comment for the Geoapify configuration surface, creating a risk that a real key could be copied into source or shared build documentation even though the runtime configuration reads only from a build-time environment variable. | Source and bounded git metadata cannot establish whether the redacted 32-hex literal is a real, active Geoapify credential or only a synthetic documentation example. |
| `device-context-privacy/detector-reset-never-invoked-stale-verdict-cro...` | Vault session boundaries never reset DeviceLockDetector stale verdict | DeviceLockDetector.stop() (lib/src/core/security/device_lock_detector.dart:197-202) sets _running=false and cancels _subscription but does not clear _context, _hasGravity, _gx/_gy/_gz, _lastMovementAt or _samples. reset() (lines 189-194) is the sole clearing routine and is referenced only by tests. The session-end handler (lib/app.dart:175-188, call at line 178) invokes stop() without reset(), and the unlock path (lib/src/features/saved_places/presentation/providers/saved_places_providers.dart:151-158, call at line 156) invokes start() without reset(); deviceLockDetectorProvider is a process-wide singleton that is never invalidated, so the stale verdict survives into the next session. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run (architecture.md:8), so the source trace cannot be promoted to a confirmed local observed result (verifier-common.md:5). |
| `device-context-privacy/detector-stop-leaves-motion-hub-consumer-regis...` | DeviceLockDetector.stop() never releases its MotionSensorHub consumer | On the production path (no accelerationStream override), DeviceLockDetector.start() calls `await hub.start()`, incrementing MotionSensorHub._users and opening the native EventChannel on the first consumer. DeviceLockDetector.stop() cancels only its own _subscription and omits the balancing hub.stop(); reset() has no production caller. Therefore every vault unlock leaks one hub consumer, the count never returns to zero, and the platform accelerometer subscription is never cancelled even after the session ends and no tracking is active. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, and no promoted local artifact exists; the audit contract forbids a confirmed verdict from source-only reasoning. |
| `diagnostic-telemetry/analytics-logEvent-forwards-arbitrary-parameter-map` | AnalyticsService forwards an unconstrained caller-supplied parameter map to FirebaseAnalytics | AnalyticsService.logEvent exposes a generic Map<String, Object>? parameters pass-through to the FirebaseAnalytics remote sink with no allowlist, key filter, value-type constraint or size bound; the privacy promise is only a doc comment rather than a validated boundary, so any future or maintainer-supplied caller could place names, notes, coordinates, tokens or API-key-shaped values into forwarded event parameters without any code-level guard refusing or sanitizing them. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, so no target-neutral runtime observation can be produced or promoted: a recording FirebaseAnalytics fake would need to be executed on a call such as logEvent(name, parameters: {'place_name': ..., 'lat': ..., 'apiKey': ...}) to show the map reaching the remote sink unchanged, and Flutter/Dart test execution is forbidden by the run contract. |
| `diagnostic-telemetry/global-error-handlers-forward-unredacted-excepti...` | Global error handlers forward raw exception text and stacks to Firebase Crashlytics | The two global error handlers in lib/main.dart forward the unmodified FlutterErrorDetails / error object / StackTrace to the FirebaseCrashlytics sink with no content restriction; the only guard is the crashlyticsReady boolean, and the existing redaction helper (AppLogger._redact) is scoped to the local-file logging path only, so no redaction, allowlist or size bound is applied before data leaves the device via Crashlytics. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run; under the audit contract a confirmed verdict requires a complete, bounded local observed result, which cannot be produced from source inspection alone. |
| `firestore-root-allow-defeats-shared-station-ownership` | Root-wide authenticated allow defeats per-collection owner/admin controls | The two rulesets put a permissive authenticated allow at `/databases/{database}/documents` itself (android/app/firestore.rules:14-15 and android/app/master_stations.rules:19-20). Under Firestore's OR semantics any authenticated request satisfies that allow for all descendant documents; narrower owner/admin conditions and the terminal `allow write: if false` are only extra allows or non-overriding denies and cannot gate access, so authenticated non-owners can read/write protected station documents. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run and no promoted local artifact exists, so the audit contract forbids a confirmed verdict from this source-only trace. |
| `firestore-rules-deployment-authority-unresolved` | Authoritative/deployed Firestore ruleset not determinable from source | Firestore rule files were introduced as untracked local artifacts with no Firebase project binding (.firebaserc/firebase.json) or rules-deployment workflow tying either file to the deployed project. The two candidate rulesets diverge and share a root-wide authenticated allow, while no source-visible authority selects one; the effective access-control policy consequently cannot be determined from source alone. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, so no target execution or promoted local observed artifact can support a confirmed verdict; source-only reasoning is insufficient under the audit contract. |
| `gemini-tool-parseLocationLink-model-url-arbitrary-network-get` | Gemini tool converts model-controlled inputUrl into unrestricted network GET | Model-controlled tool arguments are executed without value validation: AgentService._parseLocationLink passes args['inputUrl'] verbatim into LocationParser.resolveShortLink, whose trigger uses _shortLink.hasMatch (match anywhere) while its request target uses _url.firstMatch (first URL anywhere), and whose GET/redirect loop never verifies that the resolved host is an allowed Google Maps short-link host. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run (architecture.md:8). The decisive behavior is a runtime outbound GET to a model-controlled host, which cannot be observed without executing target code or contacting a network endpoint; both are prohibited by the run contract (verifier-common.md:3,5). |
| `git-history-secrets/hardcoded-admin-pin-in-work-edition-source-history` | Hardcoded admin PIN committed in Work Edition source history | The Work Edition admin approval flow embeds its authorization secret as a compile-time string constant in version-controlled source instead of obtaining it from a runtime secret, secure configuration, or an authoritative Firebase custom claim, so the credential is permanently recorded in git history and exposed to any repository reader. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox and no promoted local artifact exist in this run; under the audit contract a proposed confirmed record cannot rest on a source/git-metadata trace alone, so it must be demoted to needs_validation. |
| `health-log-persists-unsanitized-exception-text` | Hive health log persists raw exception text without AppLogger redaction | Redaction is implemented only in AppLogger before its file write, while AppHealthLogger treats the message field as trusted diagnostic data and several callers pass e.toString(), error.toString() or AgentException.message into that field. | The required OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is unavailable in this run, so target code cannot be executed under the required containment. |
| `home-search-filter-oracle-over-locked-place-hidden-fields` | Home search is a filter oracle over masked locked-place fields | The Home list filter is computed over raw Place.name, Place.notes and derived Place.plusCode (home_screen.dart:466-475) for all non-hidden/non-vaulted places, including isLocked places (home_screen.dart:449-451, place.dart:52). The UI masking in PlaceCard (place_card.dart:90-137) and the shared ensureUnlocked gate (lock_gate.dart:57-71) are applied only on reveal/navigate/QR paths, never on the search predicate, so the filtered.isEmpty message and filtered.length expose a per-character membership oracle over fields that are supposed to stay hidden until authentication. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, so no complete, bounded local observed result could be produced; a source trace alone is not sufficient for a confirmed verdict under the audit contract. |
| `locked-place-masked-name-revealed-via-automotion-suggestions` | AutoMotion suggestions reveal and navigate to locked places without the unlock gate | The derived AutoMotion place-link path (saved_places_providers.dart placeLinkSuggestionsProvider -> PlaceLinkSuggester -> PlaceLinkSuggestion -> PlaceLinkSuggestionsCard) treats the saved-place list as a flat data source and omits both the isLocked exclusion/masking predicate and the shared lock_gate.ensureUnlocked gate that every other locked-content reveal surface applies, so a field masked on PlaceCard is rendered in cleartext and made navigable on a different surface of the same unlocked app session. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, so the bounded local observed result required by the audit contract for a confirmed verdict cannot be produced; per verifier-common.md line 5 the candidate must be demoted to needs_validation. |
| `mobile-share-parsing.resolveShortLink.first-url-no-host-allowlist` | Share-text gate validates presence but fetches first URL with no host allowlist | looksLikeShortMapLink at lib/src/services/location_parser.dart:160 validates only `_shortLink.hasMatch(raw.trim())`, the presence of a fixed Google short-link substring anywhere in the text, while resolveShortLink at lines 184-199 fetches `_url.firstMatch(raw.trim())`, the first http(s) URL in the entire text. No code binds the fetched URI to the matched short link or restricts its scheme or host, and `current.resolve(location)` at line 210 accepts redirect targets on any host for up to six hops. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, as recorded in architecture.md:8 and verifier-common.md:5; under the audit contract a proposed confirmed record cannot be promoted without a target-neutral local observed result. |
| `os-launcher-shortcuts/locked-pinned-place-name-exported-to-dynamic-sh...` | Dynamic shortcut sync exports a locked place name to the OS launcher | HomeShortcutService.syncDynamicShortcuts (lib/src/services/home_shortcut_service.dart:89-92,97,102) selects places only by isPinned && !isHidden and uses p.name verbatim for the platform shortcut label, while the fireImmediately placesProvider listener in lib/app.dart:448-455 hands it the full unfiltered list from PlacesNotifier.build (lib/src/providers/app_providers.dart:1034). Locking a place (lib/src/features/home/widgets/place_actions_sheet.dart:179-197) neither clears isPinned nor masks Place.name in the data, so the cleartext name reaches the OS launcher without the ensureUnlocked gate used on the in-app reveal/tap paths. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, and target execution is prohibited, so no bounded local observed result can be produced. |
| `sync-restore-toctou-clears-locally-added-place` | Automatic restore clears places saved during network await | The empty-store precondition for restore is evaluated before the asynchronous network work and never re-checked at the destructive step. SyncRepository.syncNow (lib/src/data/repositories/sync_repository.dart:49-51) snapshots the list and gates on local.isEmpty before awaiting _drive.backupExists(); restoreFromDrive then awaits _drive.downloadBackup() (line 70) before calling _places.replaceAll() (line 83). PlaceLocalDataSource.replaceAll (lib/src/data/local/place_local_data_source.dart:44-52) unconditionally calls clear() at line 49 followed by putAll() at line 50, with no merge of keys written concurrently. SyncController.syncNow (app_providers.dart:1317-1325) and PlacesNotifier.save (app_providers.dart:1036-1037) hold no shared lock, mutex, or generation token, so a place persisted after the emptiness check but before clear() is erased; the trailing placesProvider.reload() (app_providers.dart:1353) has no copy left to restore it. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, so no target-neutral local observed result for the interleaving could be produced; the claim rests on a source-only async-window trace. |
| `sync-restore-unbounded-backup-buffering-and-cardinality` | Drive restore fully buffers and writes backup payload with no size or cardinality bound | The Drive backup restore pipeline lacks any bound on downloaded byte count, decoded place cardinality, or individual field length: downloadBackup fully buffers the authenticated response into memory with no cap, jsonDecode and BackupData.fromJson construct unbounded objects from attacker-influenced JSON, and PlaceLocalDataSource.replaceAll writes the entire unbounded collection to Hive via a non-atomic clear/putAll/flush sequence. Because restore executes on fresh installs when local places are empty and a backup exists, an oversized or high-cardinality backup in the user's private Drive appDataFolder can drive device memory and storage exhaustion with no rejection point. | No OS-enforced sandbox is available in this run (Docker daemon unavailable; Windows Sandbox requires elevation), so the required empty-environment/no-network/read-only-target/scratch-only/resource-limited execution boundary cannot be established. |
| `sync-restore-untrusted-last-synced-trust-evidence` | Drive restore writes backup-controlled last_synced into session-trust key | SyncRepository.restoreFromDrive (lib/src/data/repositories/sync_repository.dart:84) writes the remote backup-supplied data.lastSynced, parsed without range or future bound by BackupData._parseDate (backup_data.dart:40-46), directly into the local last_synced session-trust key via SettingsRepository.setLastSynced (settings_repository.dart:17,57). AuthNotifier._sessionIsTrusted (app_providers.dart:1140-1147) reads that key as trust evidence and treats any timestamp yielding a negative age (a future time) as trusted, so AuthNotifier.build (app_providers.dart:1116-1124) returns the cached user and skips attemptLightweightAuthentication indefinitely. The documented invariant that last_synced is local proof of a successful round-trip and cannot come from remote backup content is therefore violated. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, so the required complete bounded local observed result cannot be produced. |
| `vault-pin-lockout/permanent-lockout-hours-vs-minutes` | Permanent vault lockout uses 15 hours vs documented/tested minutes | The dirty P0 rewrite replaced the committed five-minute lockout with a progressive scheme whose permanent branch uses Duration(hours: 15) both for progressiveDelay and for the persisted lockedUntil, while retaining a comment and gate report that document a 15-minute lockout and a unit test that advances the injected clock only six minutes. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, and the task forbids executing target code; therefore no bounded observed result exists for the asserted test failure or runtime lockout duration. |
| `vault-pin-lockout/pin-replacement-without-step-up-auth` | Vault PIN can be replaced/removed without current-PIN or biometric step-up | PIN management is implemented as an unauthenticated local preference: the settings UI and VaultPinVerifier mutation API allow replacing or deleting the PIN record without a current-PIN or biometric step-up, even though that record is later trusted as an alternative credential for the encrypted vault. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, and no complete target-neutral local observed result was promoted; under the audit contract a source trace alone cannot support confirmed. |
| `vault-pin-lockout/progressive-delay-dropped-by-clearlockout-flag` | Vault PIN progressive lockout deadline dropped by clearLockout flag | In KeystoreVaultPinVerifier.check, the wrong-PIN write calls record.copyWith(failedAttempts: ..., lockedUntil: permanentLock ? now.add(15h) : now.add(progressiveDelay), clearLockout: !permanentLock). Because clearLockout is true for attempts 1-4, VaultPinRecord.copyWith takes its 'null' branch and sets lockedUntil to null, so the progressiveDelay computed immediately above is never persisted. Since the only lockout check is 'lockedUntil != null && now.isBefore(lockedUntil)', the escalating backoff is dead code. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run, so the required bounded local observed result could not be produced; the run contract prohibits flutter test, builds, emulators, device commands and network access. |
| `vault-session-lifecycle/lock-race-unlock-reopens-box` | Vault lock can be defeated by unlock already awaiting keystore/Hive open | HiveVaultRepository.unlock/_openBox has no epoch or cancellation guard, publishes _dataSource before the awaited source.getAll(), and lock() only clears/closes the current snapshot; an in-flight open can re-establish encrypted-box access after the lock has run. VaultPlacesNotifier additionally begins a new session and refreshes state from the same late result without revalidating the lock. | The required OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is unavailable in this run. |
| `verification-gate/geocoding-api-drift-stale-tests` | Geocoding API drift and stale test expectations are source-visible, but the reported gate failures are not independently observed | GeocodingService was migrated to an opt-in GeoApify client and a different constructor/forward signature without updating dependent tests, and the PIN verifier's permanent lockout was changed to 15 hours without updating its timing test, leaving stale expectations that plausibly produce the five failures characterized in VERIFICATION_GATE_REPORT.md. | The required OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is unavailable in this run, so no promoted local observed result exists. |
| `verification-gate/runtime-test-result-unverified` | Verification-gate runtime results are unverified claims contradicted by current source | The verification report treats runtime analyzer/test counts as established while this verifier cannot execute the target and no bounded observed artifact exists. The source/test tree contains deterministic API and policy mismatches, so the reported 997/5 result, analyzer counts, exact diagnostics, and device timing cannot be promoted from documentation alone. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run. |
| `work-edition-release-edition-identity-unbound` | Work-edition release publishes unbound unvalidated build with no edition identity | The documented edition-separation contract was never implemented as a build-bound control: edition is inferred from a runtime provider default overridden by one alternate entry point, the admin capability ignores that provider entirely, and the release/distribution workflows neither inject an edition identity nor bind the distributed APK to the analyzed/tested artifact by digest. | The required OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is unavailable in this run, so no target-neutral observed result could be produced; all candidate evidence is source-only. |
| `work-edition/admin-approval/hardcoded-pin-and-email-bypass-admin-claim` | Work Edition admin approval authorized by hardcoded PIN/email instead of admin claim | Admin authority is modeled as knowledge of a shared compile-time PIN plus a hardcoded email comparison and a client-only notifier boolean, instead of a server-issued admin custom claim; privileged mutations are issued straight from the client, and the visible rulesets fail open at the root match before the narrower admin-claim rules. | No OS-enforced empty-environment/no-network/read-only-target/scratch-only/resource-limited sandbox is available in this run and no promoted local artifact exists, so a target-neutral observed result cannot be produced; source tracing alone is insufficient for a confirmed verdict. |

Detailed source traces, blockers and validation plans are preserved in the external `NEEDS-VALIDATION.md` artifact. No severity is assigned to these leads.

## G. Rejected candidates

### Malformed adaptive profile record bypasses physical threshold floors

- Fingerprint: `adaptive-memory/frommap-skips-threshold-physical-floor-clamp`
- Refutation: Rejected for missing meaningful impact and an impossible prerequisite. The reported defect is factually present in fromMap/load, but the linked unit is corrupt-local-profile-to-adaptive-classification, and source inspection shows that path is absent: adaptiveProfileRepositoryProvider has no consumer anywhere in lib/, no code calls load/save/learn on the repository, the shipped motion classifiers use hardcoded constant thresholds with no AdaptiveProfile injection, and the profile box is private AES-256 encrypted storage with no application path that writes a malformed finite threshold. The candidate's own hardening notes state the provider is dead and no live classification impact is present. No runtime fact or deployment state is needed to establish this; the refutation is complete from source. No target code was executed and no secret values were inspected.


## H. P0 control-area assessment

### Architecture and offline-first behavior

Source reviewed; no required network call was added by the audit. Cloud-geocoding default-on and edition-boundary issues remain needs_validation.

### Hive CE persistence and data integrity

Source reviewed; no schema change made. Restore TOCTOU and unbounded restore buffering remain needs_validation.

### Silent Google auth and sign-out

Source reviewed; no audit modification. Last-synced trust evidence and automatic restore paths remain needs_validation.

### Secrets and release hygiene

No secret values were inspected or reproduced. Hardcoded Work Edition PIN history, release key scoping, and CI key exposure remain needs_validation.

### Locked/hidden places

Source traces show masking gaps in Home search, AutoMotion suggestions and OS launcher shortcuts; all remain needs_validation.

### Location parsing and short links

Source traces show trigger/fetch mismatch and absent host allowlist in resolveShortLink; both remain needs_validation.

### Motion analytics, privacy and resource lifecycle

Source reviewed; paused-stream reopening and detector hub leak remain needs_validation.

### Adaptive engine and session security

Source reviewed; vault PIN lockout defects and lock-race/edition-boundary issues remain needs_validation.

### CI/Admin authority

Comment-triggered workflow, Firestore root-wide allows and Work Edition admin PIN/email path remain needs_validation.

### Hardening notes

- Clipboard ingress is best-effort: cold-start and resume reads require an explicit user tap before import, Plus Code decode is offline/checksum-validated, raw parse failures reach only the bounded redacted AppLogger, and health events remain aggregate.
- AutoMotion export serializes only coordinate-free per-day and aggregate scalars; it does not call DailyGpsSummary.toMap and does not emit last-fix coordinates, place identity, notes or driving-event fields.
- LocationParser range-checks every numeric coordinate through one validator, and url_launcher URIs are built only from numeric doubles rather than raw share text.
- Silent auth restore is persisted-session-gated, single-flight, and suppressed while `last_synced` is inside the session trust window; automatic syncs do not re-establish the session.
- Locked Home cards use PlaceCard masking and _openPlace calls ensureUnlocked; the source-grounded gaps are on derived surfaces, not the primary card.

### Positive source patterns

- Gemini remains opt-in, uses `x-goog-api-key` rather than a URL query parameter, and surfaces opaque transport errors.
- No second file logger was found; AppLogger is the sole bounded on-disk writer with redaction and truncation.
- Adaptive profile data is numeric-only in its own box with fail-safe defaults; diagnostics remain local health-log entries.
- Both daily trackers acquire location through the shared LocationHub; idleStandby is designed to pause the hub outright rather than merely stretch the interval.

## I. Blockers, safe-to-proceed decision and required next actions

- No OS-enforced sandbox is available, so no target-controlled test, build or device observation could be promoted as evidence.
- Docker daemon and WSL node are unavailable, so Firebase Emulator rules tests could not be run.
- No `firebase.json`/`.firebaserc` exists and both Firestore rules files are untracked; deployed rules authority is unresolved.
- Admin custom claims, OAuth provider/SHA configuration, GitHub branch/tag protection, service-account IAM, key restrictions, repository visibility, Actions artifact visibility, provider quota/restrictions and key liveness are external deployment facts.
- Five previously reported test failures remain unverified in this run.
- Work/AutoMotion edition separation exists mainly on the `work-edition` branch; the current worktree has no deterministic edition build flag or `EditionCapabilities`.
- Several high-impact source defects are source-grounded but cannot be promoted to confirmed without bounded local observation; they are not evidence of safety.

**Safe to proceed to P1: NO.** A P0 pass has not been established. Required next actions, in order:

1. Establish an OS-enforced sandbox satisfying empty environment, no external network, read-only target, scratch-only writes and explicit resource limits.
2. Run `flutter analyze lib test` and `flutter test`; resolve the five previously reported failing test files.
3. Run Firebase Emulator rules tests for both candidate Firestore rulesets and determine the deployed authoritative ruleset from the Firebase project without exposing credentials.
4. Add bounded regression tests for the unresolved high-impact source traces (locked-place disclosure, short-link host binding, location-stream pause lifecycle, restore TOCTOU/bounds, vault PIN lockout, sensor-hub lifecycle, Work Edition admin authority).
5. Re-run this audit workflow with promoted local artifacts; remediate any confirmed high/critical findings before P1.

## J. Files inspected, files modified and artifacts

Files inspected (union of ledger starting paths, reviewed paths, verifier evidence paths and requested scope paths):

  - .github
  - .github/workflows/android-release.yml
  - .github/workflows/firebase-distribution.yml
  - .github/workflows/opencode.yml
  - .gitignore
  - AGENT_SKILLS.md
  - README.md
  - VERIFICATION_GATE_REPORT.md
  - android/.gitignore
  - android/app/build.gradle.kts
  - android/app/firestore.rules
  - android/app/google-services.json
  - android/app/master_stations.rules
  - android/app/src/debug/AndroidManifest.xml
  - android/app/src/main/AndroidManifest.xml
  - android/app/src/main/kotlin/com/routenote/routenote/ForegroundTrackingService.kt
  - android/app/src/main/kotlin/com/routenote/routenote/MainActivity.kt
  - android/app/src/main/kotlin/com/routenote/routenote/MotionSensorChannel.kt
  - android/app/src/main/res/layout/notification_tracking_compact.xml
  - android/app/src/profile/AndroidManifest.xml
  - docs/ARCHITECTURE_AUDIT.md
  - docs/GEMINI_SECURITY.md
  - integration_test/app_test.dart
  - ios/ShareExtension/ShareViewController.swift
  - lib/app.dart
  - lib/l10n/app_ar.arb
  - lib/l10n/app_en.arb
  - lib/main.dart
  - lib/src/core/config/app_config.dart
  - lib/src/core/memory/adaptive_profile.dart
  - lib/src/core/memory/adaptive_profile_key_store.dart
  - lib/src/core/memory/adaptive_profile_repository.dart
  - lib/src/core/memory/self_diagnostic_monitor.dart
  - lib/src/core/motion/activity_state_manager.dart
  - lib/src/core/motion/motion_gate.dart
  - lib/src/core/orchestrator/adaptive_engine_orchestrator.dart
  - lib/src/core/security/device_lock_detector.dart
  - lib/src/core/security/secure_session_token_store.dart
  - lib/src/core/security/session_guard.dart
  - lib/src/core/utils/plus_code.dart
  - lib/src/data/local/auto_motion_data_source.dart
  - lib/src/data/local/hive_database.dart
  - lib/src/data/local/place_local_data_source.dart
  - lib/src/data/local/settings_repository.dart
  - lib/src/data/models/agent_insight.dart
  - lib/src/data/models/backup_data.dart
  - lib/src/data/models/daily_gps_summary.dart
  - lib/src/data/models/place.dart
  - lib/src/data/models/trip_segment.dart
  - lib/src/data/remote/auth_service.dart
  - lib/src/data/remote/drive_service.dart
  - lib/src/data/remote/google_auth_service.dart
  - lib/src/data/repositories/place_repository.dart
  - lib/src/data/repositories/sync_repository.dart
  - lib/src/features/add_place/add_place_screen.dart
  - lib/src/features/automotion/automotion_screen.dart
  - lib/src/features/automotion/widgets/auto_motion_export_sheet.dart
  - lib/src/features/automotion/widgets/driving_event_presentation.dart
  - lib/src/features/automotion/widgets/driving_events_card.dart
  - lib/src/features/automotion/widgets/motion_summary_sheet.dart
  - lib/src/features/automotion/widgets/motion_timeline_widget.dart
  - lib/src/features/automotion/widgets/route_map_view.dart
  - lib/src/features/automotion/widgets/route_map_viewer.dart
  - lib/src/features/automotion/widgets/route_timeline.dart
  - lib/src/features/automotion/widgets/trip_route_card.dart
  - lib/src/features/home/home_screen.dart
  - lib/src/features/home/widgets/auto_motion_card.dart
  - lib/src/features/home/widgets/place_actions_sheet.dart
  - lib/src/features/home/widgets/place_card.dart
  - lib/src/features/home/widgets/qr_code_dialog.dart
  - lib/src/features/home/widgets/smart_insights_card.dart
  - lib/src/features/motion_analytics/data/heuristic_motion_model.dart
  - lib/src/features/motion_analytics/data/isolate_motion_inference_runner.dart
  - lib/src/features/motion_analytics/data/ml_classifier_isolate.dart
  - lib/src/features/motion_analytics/data/motion_event_mapper.dart
  - lib/src/features/motion_analytics/domain/entities/motion_event.dart
  - lib/src/features/place_detail/place_detail_screen.dart
  - lib/src/features/saved_places/data/datasources/flutter_secure_secret_store.dart
  - lib/src/features/saved_places/data/datasources/secure_places_local_data_source.dart
  - lib/src/features/saved_places/data/datasources/vault_key_store.dart
  - lib/src/features/saved_places/data/datasources/vault_pin_store.dart
  - lib/src/features/saved_places/data/repositories/biometric_vault_authenticator.dart
  - lib/src/features/saved_places/data/repositories/hive_vault_repository.dart
  - lib/src/features/saved_places/data/repositories/keystore_vault_pin_verifier.dart
  - lib/src/features/saved_places/domain/entities/place_link_suggestion.dart
  - lib/src/features/saved_places/domain/services/place_link_suggester.dart
  - lib/src/features/saved_places/domain/services/vault_authenticator.dart
  - lib/src/features/saved_places/domain/services/vault_pin_hasher.dart
  - lib/src/features/saved_places/domain/services/vault_pin_verifier.dart
  - lib/src/features/saved_places/domain/usecases/unlock_vault.dart
  - lib/src/features/saved_places/presentation/providers/saved_places_providers.dart
  - lib/src/features/saved_places/presentation/saved_places_vault_screen.dart
  - lib/src/features/saved_places/presentation/widgets/place_link_suggestions_card.dart
  - lib/src/features/saved_places/presentation/widgets/vault_pin_dialog.dart
  - lib/src/features/saved_places/presentation/widgets/vault_privacy_dimmer.dart
  - lib/src/features/settings/account_settings_screen.dart
  - lib/src/features/settings/hidden_vault_screen.dart
  - lib/src/features/settings/preferences_settings_screen.dart
  - lib/src/features/settings/security_vault_settings_screen.dart
  - lib/src/features/settings/settings_screen.dart
  - lib/src/l10n/app_en.arb
  - lib/src/providers/app_providers.dart
  - lib/src/services/agent_service.dart
  - lib/src/services/analytics_service.dart
  - lib/src/services/app_health_logger.dart
  - lib/src/services/app_logger.dart
  - lib/src/services/app_observer_service.dart
  - lib/src/services/auto_motion_export_service.dart
  - lib/src/services/auto_motion_service.dart
  - lib/src/services/background_sync_scheduler.dart
  - lib/src/services/biometric_service.dart
  - lib/src/services/daily_track_engine.dart
  - lib/src/services/driving_event_locator.dart
  - lib/src/services/foreground_tracking_service.dart
  - lib/src/services/gemini_client.dart
  - lib/src/services/geoapify_client.dart
  - lib/src/services/geocoding_service.dart
  - lib/src/services/gps_tracker_service.dart
  - lib/src/services/home_shortcut_service.dart
  - lib/src/services/key_rotation_service.dart
  - lib/src/services/local_insight_engine.dart
  - lib/src/services/location_hub.dart
  - lib/src/services/location_parser.dart
  - lib/src/services/location_service.dart
  - lib/src/services/lock_gate.dart
  - lib/src/services/milestone_name_resolver.dart
  - lib/src/services/motion_classifier_service.dart
  - lib/src/services/motion_profiler.dart
  - lib/src/services/motion_score.dart
  - lib/src/services/motion_sensor_hub.dart
  - lib/src/services/motion_signal.dart
  - lib/src/services/navigation_service.dart
  - lib/src/services/pedometer_steps.dart
  - lib/src/services/polyline_smoother.dart
  - lib/src/services/route_milestones.dart
  - lib/src/services/sampling_target.dart
  - lib/src/services/share_intent_service.dart
  - lib/src/services/smart_clipboard_service.dart
  - lib/src/services/step_meter.dart
  - lib/src/widgets/qibla_indicator.dart
  - opencode.json
  - orig.dart
  - pubspec.yaml
  - test
  - test/adaptive_engine_orchestrator_test.dart
  - test/adaptive_memory_test.dart
  - test/add_place_screen_test.dart
  - test/analytics_service_test.dart
  - test/app_logger_test.dart
  - test/app_observer_service_test.dart
  - test/auth_session_test.dart
  - test/auto_motion_service_test.dart
  - test/automotion_dashboard_test.dart
  - test/automotion_export_ui_test.dart
  - test/background_tracking_service_audit_test.dart
  - test/device_lock_detector_test.dart
  - test/encrypted_vault_test.dart
  - test/engine_profile_application_test.dart
  - test/foreground_tracking_service_test.dart
  - test/gemini_client_test.dart
  - test/geocoding_service_test.dart
  - test/gps_tracker_test.dart
  - test/location_hub_test.dart
  - test/location_parser_test.dart
  - test/milestone_name_resolver_test.dart
  - test/ml_classifier_isolate_test.dart
  - test/motion_overlay_test.dart
  - test/motion_score_test.dart
  - test/motion_sensor_hub_test.dart
  - test/pedometer_steps_test.dart
  - test/place_card_test.dart
  - test/resource_leak_audit_test.dart
  - test/route_history_screen_test.dart
  - test/session_guard_test.dart
  - test/smart_clipboard_service_test.dart
  - test/step_meter_test.dart
  - test/unlock_flow_test.dart
  - test/vault_privacy_dimmer_test.dart
  - third_party/pedometer/android/src/main/kotlin/com/example/pedometer/SensorStreamHandler.kt
  - third_party/pedometer/lib/pedometer.dart
  - work-edition/.github/workflows/android-release.yml
  - work-edition/.github/workflows/build.yml
  - work-edition/.github/workflows/firebase-distribution.yml
  - work-edition/lib/main.dart
  - work-edition/lib/main_work.dart
  - work-edition/lib/src/features/admin/admin_approval_card.dart
  - work-edition/lib/src/features/admin/admin_approval_screen.dart
  - work-edition/lib/src/features/home/home_screen.dart
  - work-edition/lib/src/providers/app_providers.dart
  - work-edition/lib/src/services/firebase_station_service.dart
  - work-edition/pubspec.yaml
  - work-edition/test/admin_approval_test.dart

Files modified by the audit:

- `docs/P0_FINAL_SECURITY_AUDIT.md` — created/updated as the required final report.
- External run artifacts under `C:/Users/nader/AppData/Local/Temp/opencode/security-audit/MapNote-App/run-1` — created/updated outside the target repository.

No target source file, test, workflow, Hive schema, localization file or Android/iOS resource was modified by the audit.

Parent-owned external artifacts: `findings.json`, `coverage-ledger.json`, `REPORT.md`, `FINDINGS-DETAIL.md`, `NEEDS-VALIDATION.md`, `candidate-packets/`, `verifier-tasks/`, and `agents/`.

P0 SECURITY: NOT VERIFIED
