import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quick_actions/quick_actions.dart';

import '../data/models/place.dart';

/// Places eligible for an OS launcher shortcut. Locked places are excluded:
/// the launcher label would disclose masked content before any unlock prompt.
List<Place> shortcutEligiblePlaces(List<Place> places) => places
    .where((Place p) => p.isPinned && !p.isHidden && !p.isLocked)
    .take(4)
    .toList(growable: false);

/// Bridges native home-screen shortcuts and `quick_actions` dynamic shortcuts
/// into a single stream of place ids.
///
/// * Android "pin to home screen" is handled by a small method channel in
///   `MainActivity` (`ShortcutManager.requestPinShortcut`).
/// * `quick_actions` maintains the app's long-press dynamic shortcuts.
class HomeShortcutService {
  HomeShortcutService();

  static const MethodChannel _channel = MethodChannel(
    'com.routenote.routenote/shortcuts',
  );
  static const String _placeTypePrefix = 'place_';

  final QuickActions _quickActions = QuickActions();
  final StreamController<String> _tapController =
      StreamController<String>.broadcast();

  bool _initialized = false;

  static bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Place ids tapped from a home-screen or dynamic shortcut.
  Stream<String> placeTaps() => _tapController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!_isMobile) return;

    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onShortcutTap') {
        final Object? id = call.arguments;
        if (id is String && id.isNotEmpty) _tapController.add(id);
      }
      return null;
    });

    try {
      await _quickActions.initialize((String type) {
        if (type.startsWith(_placeTypePrefix)) {
          _tapController.add(type.substring(_placeTypePrefix.length));
        }
      });
    } catch (_) {
      // quick_actions is unavailable (e.g. unsupported host).
    }
  }

  /// Place id that launched the app from a pinned shortcut, if any.
  Future<String?> initialPlaceId() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>('getInitialPlaceId');
    } catch (_) {
      return null;
    }
  }

  /// Asks Android to pin a home-screen shortcut for [place]. Returns `false`
  /// when the device does not support pinned shortcuts.
  Future<bool> pinToHomeScreen(Place place) async {
    if (place.isLocked) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'requestPin',
        <String, dynamic>{'id': place.id, 'label': place.name},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Keeps the platform's dynamic shortcuts in sync with pinned places.
  Future<void> syncDynamicShortcuts(List<Place> places) async {
    if (!_isMobile) return;
    try {
      final List<Place> pinned = shortcutEligiblePlaces(places);
      if (pinned.isEmpty) {
        await _quickActions.clearShortcutItems();
        return;
      }
      await _quickActions.setShortcutItems(
        pinned
            .map(
              (Place p) => ShortcutItem(
                type: '$_placeTypePrefix${p.id}',
                localizedTitle: p.name,
              ),
            )
            .toList(growable: false),
      );
    } catch (_) {
      // Best-effort: dynamic shortcuts are a convenience only.
    }
  }

  void dispose() {
    _tapController.close();
  }
}
