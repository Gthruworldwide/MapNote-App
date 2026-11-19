// Shared redaction for every diagnostic sink that can leave the app process.
//
// `AppLogger` writes to the bounded on-device file, while Crashlytics and the
// local Hive health log are separate sinks. They must all apply the same
// credential rules: a secret accidentally included in an exception message
// cannot be allowed to survive because one sink forgot a regex.
//
// This is *defense in depth*, not permission to log user content. Callers
// still pass coarse diagnostics only; the redactor is the last gate.

/// Default cap for a single remote diagnostic value.
const int diagnosticMaxChars = 500;

/// Credential/path redaction without length clipping.
///
/// Used by [AppLogger] where the caller already clips individual fields and
/// needs the whole multi-line entry preserved.
String redactCredentials(String value) {
  String result = value;
  for (final RegExp pattern in _sensitivePatterns) {
    result = result.replaceAll(pattern, '[redacted]');
  }
  return result;
}

/// Redacts and bounds one value before it reaches Crashlytics or the health log.
String redactForDiagnostics(
  String value, {
  int maxLength = diagnosticMaxChars,
}) {
  final String redacted = redactCredentials(value);
  if (redacted.length <= maxLength) return redacted;
  if (maxLength <= 3) return redacted.substring(0, maxLength);
  return '${redacted.substring(0, maxLength - 3)}...';
}

final List<RegExp> _sensitivePatterns = <RegExp>[
  // Google API keys (AIza...).
  RegExp(r'AIza[0-9A-Za-z\-_]{20,}'),
  // Other provider-style keys.
  RegExp(r'sk-[0-9A-Za-z\-_]{16,}'),
  // Bearer tokens.
  RegExp(r'[Bb]earer\s+[A-Za-z0-9\-._~+/]+={0,2}'),
  // `x-goog-api-key:` / `api_key=` / `authorization=` / `token=` values.
  RegExp(
    r'(?:x-goog-api-key|api[_-]?key|authorization|token)\s*[:=]\s*\S+',
    caseSensitive: false,
  ),
  // Emails.
  RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'),
  // Long base64-ish / hex tokens (32+ chars).
  RegExp(r'[A-Za-z0-9+/]{32,}={0,2}'),
  // Absolute file paths, including Dart's `file://` URIs and Windows drives.
  // Stack frames are useful as coarse frames, but a user's home directory is
  // identifying information and has no place in a remote report.
  RegExp(r'file:///[^\s]+', caseSensitive: false),
  RegExp(r'[A-Za-z]:[\\/][^\s]+'),
  RegExp(r'/[A-Za-z0-9_.\-~/\\]{8,}'),
];
