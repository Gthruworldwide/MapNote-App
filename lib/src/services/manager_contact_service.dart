import 'package:url_launcher/url_launcher.dart';

/// Opens the phone dialer and WhatsApp for a station manager.
///
/// Both entry points degrade to `false` instead of throwing, so a device without
/// a dialer/WhatsApp simply shows an "unavailable" snackbar rather than crashing
/// on a tap. Numbers are normalised first: the manager sheet is maintained by
/// hand in Egypt, so `0100 123 4567`, `+20 100 123 4567` and `00201001234567`
/// all have to reach the same contact.
class ManagerContactService {
  const ManagerContactService();

  /// Dials [phone] through the system dialer.
  Future<bool> call(String phone) async {
    final String? dialable = normalizePhone(phone);
    if (dialable == null) return false;
    return _launch(Uri(scheme: 'tel', path: dialable));
  }

  /// Opens the WhatsApp chat for [phone], optionally pre-filled with [message].
  ///
  /// Falls back to `https://wa.me/<number>` when the app scheme is not handled
  /// (WhatsApp not installed / desktop), so the message is never lost.
  Future<bool> whatsApp(String phone, {String? message}) async {
    final String? number = normalizeWhatsAppNumber(phone);
    if (number == null) return false;

    final String query =
        'phone=$number${message == null || message.isEmpty ? '' : '&text=${Uri.encodeComponent(message)}'}';
    if (await _launch(Uri.parse('whatsapp://send?$query'))) return true;
    return _launch(Uri.parse('https://wa.me/$number'), external: true);
  }

  /// Digits only, keeping a leading `+`; null when nothing dialable remains.
  ///
  /// Arabic-Indic digits (`٠١٢٣٤٥٦٧٨٩`) are folded to ASCII because a number
  /// pasted from an Arabic spreadsheet can arrive in that form.
  static String? normalizePhone(String? raw) {
    final String digits = _asciiDigits(raw);
    if (digits.isEmpty) return null;
    final String bare = digits.replaceAll('+', '');
    if (bare.length < 7) return null;
    return digits.startsWith('+') ? '+$bare' : bare;
  }

  /// WhatsApp's international form: `wa.me` rejects a national trunk `0`, and
  /// Egyptian numbers are stored locally as `01x…`, so they become `201x…`.
  static String? normalizeWhatsAppNumber(String? raw) {
    final String? normalized = normalizePhone(raw);
    if (normalized == null) return null;
    String number = normalized.replaceAll('+', '');
    if (number.startsWith('00')) number = number.substring(2);
    if (number.startsWith('0')) {
      number = '20${number.substring(1)}';
    } else if (number.length == 10 && number.startsWith('1')) {
      // A number stored without the trunk zero (`100 123 4567`).
      number = '20$number';
    }
    return number;
  }

  /// Strips every separator and folds Arabic-Indic digits; keeps a leading `+`.
  static String _asciiDigits(String? raw) {
    if (raw == null) return '';
    final StringBuffer buffer = StringBuffer();
    for (final int rune in raw.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        // Arabic-Indic ٠-٩
        buffer.writeCharCode(0x30 + (rune - 0x0660));
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        // Extended Arabic-Indic ۰-۹
        buffer.writeCharCode(0x30 + (rune - 0x06F0));
      } else if (rune >= 0x30 && rune <= 0x39) {
        buffer.writeCharCode(rune);
      } else if (rune == 0x2B) {
        // '+'
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  Future<bool> _launch(Uri uri, {bool external = false}) async {
    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(
        uri,
        mode: external
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      );
    } catch (_) {
      return false;
    }
  }
}
