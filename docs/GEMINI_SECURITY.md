# Gemini API Key Security Architecture

## Current Implementation

The Gemini API key is managed as follows:

- **Source**: Read from environment only via `--dart-define=GEMINI_API_KEY=...`
- **Never committed**: The `GEMINI_API_KEY` environment variable is gitignored and
  not stored in any release artifact
- **Transport**: Key is sent in the `x-goog-api-key` HTTP header, **never** in the
  URL query string
- **Pool**: Comma/whitespace-separated key pool enables rotation without new builds
- **Rotation**: `KeyRotationService` tracks key health and cooldowns; exhausted keys
  are skipped automatically
- **Default**: When `GEMINI_API_KEY` is empty, `isGeminiConfigured = false` and the
  app runs fully offline-first with the local rule-based engine
- **Scope**: Only anonymous aggregate metrics are sent (counts and structural
  summaries — never place names, notes, coordinates)

## Security Limitations — Explicit Disclosure

### 1. Client-Side Secret
A Gemini API key embedded in a mobile binary **cannot be considered a true
server-side secret**. The key is:
- Visible in the compiled APK/IPA (readable via `strings` or `dumpjava`)
- Subject to exposure if the device is compromised
- Not rotatable at runtime without a new build (though the key pool mitigates this)

**Mitigation**: The key pool (`--dart-define=GEMINI_API_KEY=key1,key2,key3`)
allows rotating keys without a new build. Keys are never logged or persisted.

### 2. No Server Proxy
All Gemini requests go directly from the mobile app to Google's servers.
There is no server-side proxy to validate requests or enforce per-user limits.

**Mitigation**:
- Quotas are enforced by Google Cloud, not by the app
- The app respects HTTP 429 (quota exceeded) responses and rotates keys
- No privileged operations are performed through Gemini (see below)

### 3. AI Cannot Authorize Dangerous Actions
The Gemini client is explicitly designed **never** to be an authorization layer.

**Hard constraints**:
- `fetchInsights()` returns `List<AgentInsight>` only — never controls app state
- Agent tools (`AgentTool`) execute **locally** on the device; the model never
  executes arbitrary code
- The system prompt explicitly instructs the model: "Never invent data or
  mention that you are an AI. If you need current sync state or a pasted link
  parsed, call the provided functions instead of guessing."
- Insights are limited to `maxAgentInsights = 3` and are purely observational
- The model responds with JSON arrays of tips, never with commands to delete,
  unlock, or modify data

### 4. Abuse Protection
- **Rate limiting**: Relies on Google's API quota system (429 responses trigger
  key rotation and backoff)
- **Key cooldown**: Failed keys enter a 10-minute cooldown (configurable) before
  being re-attempted
- **Maximum round trips**: `agentToolRounds = 4` limits conversation length
- **Maximum insights**: `maxAgentInsights = 3` limits output per request
- **Timeout**: `agentRequestTimeout = 12s` prevents hanging requests

### 5. Privileged Operations — Explicitly Forbidden
The Gemini system must never be allowed to:
- ✅ **Delete user data** — not possible; `fetchInsights` only returns insights
- ✅ **Approve admin requests** — no admin workflow runs through Gemini
- ✅ **Unlock the Vault** — Vault authentication uses biometrics/device PIN,
  not AI
- ✅ **Change security settings** — settings changes require explicit user gestures
- ✅ **Expose private data** — only anonymous metrics are sent; no place names,
  notes, or coordinates leave the device
- ✅ **Modify authentication** — auth changes use Firebase Auth flow, not Gemini
- ✅ **Change account roles** — role changes require Firestore Rules + Admin claims
- ✅ **Execute privileged operations** — all privileged ops are Firestore Rules–enforced

## Recommended Production Hardening

While the current architecture is reasonably secure for an offline-first app, the
following additional measures are recommended for production:

### A. Server-Side Cloud Function (Preferred)
```text
Mobile App
    ↓
Cloud Function (backend, trusted environment)
    ↓
Gemini API (server-side, key kept secret)
    ↓
Response only (no write access to user data)
```

This moves the Gemini key to a server environment where it can be a true secret.

### B. If Keeping Client-Side Access (Current Approach)
- ✅ Keep key in `x-goog-api-key` header (already done)
- ✅ Use key pool with rotation (already done)
- ✅ Never send user-identifying data with requests (already done — only anonymous metrics)
- ✅ Implement request monitoring/alerting for quota errors
- ✅ Set up Google Cloud API restrictions to limit which APIs the key can access
- ✅ Regular key rotation schedule (e.g., every 90 days)
- ✅ Monitor Google Cloud Console for unusual API usage patterns
- ✅ Addrate limiting at the Google Cloud console level

### C. Environment Separation
- **Debug/Dev**: `--dart-define=GEMINI_API_KEY=debug-key-...`
- **Release**: `--dart-define=GEMINI_API_KEY=release-key-...` (different key)
- **CI**: `GEMINI_API_KEY` from GitHub Actions secret (never in YAML)
- The same binary can use different keys based on the build environment.

## Test Regression Checks

Ensure the following tests pass:

1. **No key in URL**: `gemini_client_test.dart` asserts the key appears in the
   `x-goog-api-key` header and **not** in the request URL
2. **Transport errors stay opaque**: Transport failures surface as
   `AgentException('Cloud suggestions unavailable' | '... timed out')` — no
   raw stack traces or key exposure
3. **Offline-first default**: When `isConfigured == false`, `fetchInsights`
   returns empty list `[]` and no network call is made
4. **Key rotation works**: `KeyRotationService` marks failures and advances
   cursor correctly; no single key exhaustion takes offline
5. **No privileged operations**: Unit tests verify that Gemini insights never
   contain commands to delete, unlock, or modify protected data