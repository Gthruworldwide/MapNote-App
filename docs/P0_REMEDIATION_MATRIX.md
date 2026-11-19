# P0 Remediation Matrix

Source: `docs/P0_FINAL_SECURITY_AUDIT.md` (30 `needs_validation` records; 1 rejected record excluded). Severity is a remediation triage value assigned here; the audit deliberately assigned no severity to unverified leads.

| ID | Finding | Severity | Code Fix Possible? | Environment Required? | Action | Status |
|---|---|---|---|---|---|---|
| 1 | `adaptive-lifecycle/setpowermode-reopens-paused-location-stream` | High | Yes | Device/lifecycle test optional | Guard `setPowerMode` with paused state and add regression test | FIXED AND TESTED |
| 2 | `android-foreground-tracking/manifest-service-name-mismatch-disables-foreground-service` | High | Yes | Android build to observe service promotion | Align manifest service class with Kotlin service and audit test | ENVIRONMENT VERIFICATION REQUIRED |
| 3 | `ci-opencode-comment-trigger-missing-author-association-gate` | High | Yes | GitHub repository settings | Restrict comment trigger to trusted author association and least-privilege token | ENVIRONMENT VERIFICATION REQUIRED |
| 4 | `ci-release-secrets/dart-define-key-embedded-in-distributed-apk` | High | Yes | Release pipeline/build inspection | Remove compile-time secret injection and document server-side boundary | ENVIRONMENT VERIFICATION REQUIRED |
| 5 | `cloud-geocoding-disclosure/cloud-ai-toggle-default-on-enables-third-party-coordinate-upload` | High | Yes | None | Split cloud AI and geocoding consent; default both off | FIXED AND TESTED |
| 6 | `cloud-key-handling.app-config.geoapify-doc-comment-hex-literal` | Medium | Yes | None | Replace key-shaped documentation literal with safe placeholder | FIXED AND TESTED |
| 7 | `device-context-privacy/detector-reset-never-invoked-stale-verdict-crosses-sessions` | Medium | Yes | None | Call reset on session boundaries and add regression test | FIXED AND TESTED |
| 8 | `device-context-privacy/detector-stop-leaves-motion-hub-consumer-registered` | High | Yes | Device sensor observation optional | Release hub consumer in stop/dispose and add leak test | FIXED AND TESTED |
| 9 | `diagnostic-telemetry/analytics-logEvent-forwards-arbitrary-parameter-map` | Medium | Yes | None | Allowlist/sanitize analytics parameters and add boundary test | FIXED AND TESTED |
| 10 | `diagnostic-telemetry/global-error-handlers-forward-unredacted-exception-to-crashlytics` | High | Yes | None | Redact/truncate exception text before Crashlytics and test | FIXED AND TESTED |
| 11 | `firestore-root-allow-defeats-shared-station-ownership` | High | Yes | Firebase Emulator for runtime rules proof | Replace root-wide allow with scoped owner/admin rules and emulator tests | ENVIRONMENT VERIFICATION REQUIRED |
| 12 | `firestore-rules-deployment-authority-unresolved` | High | Partly | Firebase project access | Add deployment config/test suite; owner must confirm live ruleset | ENVIRONMENT VERIFICATION REQUIRED |
| 13 | `gemini-tool-parseLocationLink-model-url-arbitrary-network-get` | High | Yes | None | Reuse hardened short-link resolver from Gemini tool and test | FIXED AND TESTED |
| 14 | `git-history-secrets/hardcoded-admin-pin-in-work-edition-source-history` | High | Partly | Repository owner credential rotation | Move Work Edition admin auth to claims; rotate exposed PIN | ENVIRONMENT VERIFICATION REQUIRED |
| 15 | `health-log-persists-unsanitized-exception-text` | Medium | Yes | None | Reuse AppLogger redaction/truncation in AppHealthLogger and test | FIXED AND TESTED |
| 16 | `home-search-filter-oracle-over-locked-place-hidden-fields` | High | Yes | None | Exclude locked places from search/index and add oracle regression test | FIXED AND TESTED |
| 17 | `locked-place-masked-name-revealed-via-automotion-suggestions` | High | Yes | None | Exclude locked places from suggestions/navigation and add widget test | FIXED AND TESTED |
| 18 | `mobile-share-parsing.resolveShortLink.first-url-no-host-allowlist` | High | Yes | None | Bind fetch target to supported host and restrict redirects | FIXED AND TESTED |
| 19 | `os-launcher-shortcuts/locked-pinned-place-name-exported-to-dynamic-shortcut` | High | Yes | Platform launcher observation optional | Exclude locked places from dynamic shortcuts and add test | FIXED AND TESTED |
| 20 | `sync-restore-toctou-clears-locally-added-place` | High | Yes | None | Re-check empty precondition immediately before atomic replace and test race | FIXED AND TESTED |
| 21 | `sync-restore-unbounded-backup-buffering-and-cardinality` | High | Yes | None | Bound download bytes/cardinality/field lengths before decode and test | FIXED AND TESTED |
| 22 | `sync-restore-untrusted-last-synced-trust-evidence` | High | Yes | None | Never persist backup-supplied `last_synced`; stamp only on local success | FIXED AND TESTED |
| 23 | `vault-pin-lockout/permanent-lockout-hours-vs-minutes` | High | Yes | None | Correct permanent lockout to 15 minutes and fix test clock | FIXED AND TESTED |
| 24 | `vault-pin-lockout/pin-replacement-without-step-up-auth` | High | Yes | None | Require step-up auth for PIN replacement/removal | FIXED AND TESTED |
| 25 | `vault-pin-lockout/progressive-delay-dropped-by-clearlockout-flag` | High | Yes | None | Persist progressive deadline and add timing tests | FIXED AND TESTED |
| 26 | `vault-session-lifecycle/lock-race-unlock-reopens-box` | High | Yes | None | Add epoch guard so lock invalidates in-flight unlock | FIXED AND TESTED |
| 27 | `verification-gate/geocoding-api-drift-stale-tests` | Medium | Yes | None | Update tests to current GeocodingService API | FIXED AND TESTED |
| 28 | `verification-gate/runtime-test-result-unverified` | Medium | Partly | Clean local toolchain | Run analyzer/tests locally and record real results | ENVIRONMENT VERIFICATION REQUIRED |
| 29 | `work-edition/admin-approval/hardcoded-pin-and-email-bypass-admin-claim` | High | Partly | Firebase custom claims configuration | Replace PIN/email bypass with server-enforced claim | ENVIRONMENT VERIFICATION REQUIRED |
| 30 | `work-edition-release-edition-identity-unbound` | High | Yes | Release pipeline digest binding | Add deterministic edition build flag/capabilities and bind artifacts | REQUIRES MANUAL REVIEW |
