import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wraps `permission_handler` for contacts access so the rest of the app never
/// touches the plugin channel directly. All failures degrade gracefully.
class ContactsService {
  const ContactsService();

  /// Whether the platform supports contacts permission.
  static bool get _isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Check if contacts permission is currently granted.
  static Future<bool> isGranted() async {
    if (!_isSupported) return false;
    try {
      final status = await Permission.contacts.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Check if contacts permission is permanently denied (settings open required).
  static Future<bool> isPermanentlyDenied() async {
    if (!_isSupported) return false;
    try {
      final status = await Permission.contacts.status;
      return status.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  /// Request contacts permission from the user.
  /// Returns `true` if the user grants the permission, `false` otherwise.
  /// This must be called on a user gesture (e.g. tapping "Link Contact").
  static Future<bool> request() async {
    if (!_isSupported) return false;
    try {
      final status = await Permission.contacts.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Open the app settings page so the user can grant contacts permission
  /// manually if it was permanently denied.
  static Future<void> openSettings() async {
    if (!_isSupported) return;
    try {
      await openAppSettings();
    } catch (_) {}
  }
}