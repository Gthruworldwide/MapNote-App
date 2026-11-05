/// Utility for normalizing Arabic text for fuzzy search.
/// Handles common Arabic character variations:
/// - أ, إ, آ -> ا
/// - ة -> ه
/// - ى -> ي
/// - Removes diacritics (tashkeel)
/// - Strips extra spaces
class ArabicNormalizer {
  /// Normalizes Arabic text for fuzzy search matching.
  static String normalize(String text) {
    if (text.isEmpty) return '';

    // Remove diacritics (tashkeel)
    String normalized = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');

    // Normalize Arabic characters
    normalized = normalized
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');

    // Normalize whitespace
    normalized = normalized.trim().replaceAll(RegExp(r'\s+'), ' ');

    return normalized.toLowerCase();
  }

  /// Checks if [text] contains [query] after normalization.
  static bool contains(String text, String query) {
    return normalize(text).contains(normalize(query));
  }

  /// Checks if [text] starts with [query] after normalization.
  static bool startsWith(String text, String query) {
    return normalize(text).startsWith(normalize(query));
  }
}