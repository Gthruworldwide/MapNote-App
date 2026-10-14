import 'package:flutter/services.dart';

import '../core/utils/plus_code.dart';

/// Spots Open Location Codes ("Plus Codes") in the system clipboard so the app
/// can offer a one-tap import when it returns to the foreground.
///
/// The pattern is deliberately broad — it matches both full codes
/// (`8FVC9G8F+6W`) and short, locality-relative ones (`9G8F+6W`) — and every
/// candidate is then validated against [PlusCode] so plain text that merely
/// looks code-shaped is ignored.
class SmartClipboardService {
  const SmartClipboardService();

  /// A raw Plus Code as it appears in copied text: two to eight characters
  /// before the `+`, then two or three after it.
  static final RegExp plusCodePattern = RegExp(
    r'[23456789CFGHJMPQRVWX]{2,8}\+[23456789CFGHJMPQRVWX]{2,3}',
    caseSensitive: false,
  );

  /// The first valid Plus Code in [text], normalised to upper case, or `null`.
  String? extractPlusCode(String? text) {
    if (text == null || text.isEmpty) return null;
    for (final RegExpMatch match in plusCodePattern.allMatches(text)) {
      final String code = match.group(0)!.toUpperCase();
      if (PlusCode.isPlusCode(code) || PlusCode.isShortPlusCode(code)) {
        return code;
      }
    }
    return null;
  }

  /// Reads the clipboard and returns the first Plus Code it contains, or `null`
  /// when the clipboard is empty, unreadable or holds no code.
  ///
  /// Clipboard access can be unavailable (desktop, tests) or denied (some
  /// Android background states); any failure simply stands the feature down.
  Future<String?> readPlusCode() async {
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      return extractPlusCode(data?.text);
    } catch (_) {
      return null;
    }
  }
}
