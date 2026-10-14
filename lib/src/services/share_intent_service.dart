import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Bridges the platform "share" sheet into MapNote.
///
/// Other apps (Google Maps, WhatsApp, browsers, ...) can share plain text or
/// links with MapNote; those arrive here as raw strings for
/// `LocationParser` to interpret.
class ShareIntentService {
  const ShareIntentService();

  static bool get _isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Text/links shared while the app is already running.
  Stream<String> textStream() {
    if (!_isSupported) return const Stream<String>.empty();
    return ReceiveSharingIntent.instance
        .getMediaStream()
        .expand((List<SharedMediaFile> files) => files.map(_textOf))
        .where((String text) => text.isNotEmpty);
  }

  /// Text/links that launched the app from a cold start.
  Future<List<String>> initialText() async {
    if (!_isSupported) return const <String>[];
    try {
      final List<SharedMediaFile> files = await ReceiveSharingIntent.instance
          .getInitialMedia();
      final List<String> texts = files
          .map(_textOf)
          .where((String text) => text.isNotEmpty)
          .toList(growable: false);
      ReceiveSharingIntent.instance.reset();
      return texts;
    } catch (_) {
      return const <String>[];
    }
  }

  /// Plain-text shares carry their payload in [SharedMediaFile.path]; some
  /// platforms additionally populate [SharedMediaFile.message].
  String _textOf(SharedMediaFile file) {
    final String text = file.path.isNotEmpty
        ? file.path
        : (file.message ?? '');
    return text.trim();
  }
}
