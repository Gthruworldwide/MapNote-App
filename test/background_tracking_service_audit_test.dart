import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:routenote/src/services/location_service.dart';

/// Objective 2 of the background-polling work: the foreground service must be
/// as quiet as the platform allows, and **nothing** in the app may hold a CPU
/// wakelock while the trackers are idle.
///
/// The native side is not reachable from a Dart unit test, so the invariants
/// are pinned against the sources themselves: a regression in the Kotlin
/// service or the manifest fails the suite instead of silently costing the
/// user battery on an OEM that is strict about it (Honor/MagicOS).
void main() {
  group('background tracking service hygiene', () {
    late final String kotlin;
    late final String manifest;

    setUpAll(() {
      kotlin = File(
        'android/app/src/main/kotlin/com/routenote/routenote/LocationTrackingService.kt',
      ).readAsStringSync();
      manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    });

    test('the notification channel is IMPORTANCE_LOW and fully silent', () {
      // IMPORTANCE_LOW = no sound, no heads-up; the channel additionally
      // switches off the badge, the vibration and the lights.
      expect(kotlin, contains('NotificationManager.IMPORTANCE_LOW'));
      expect(kotlin, contains('setShowBadge(false)'));
      expect(kotlin, contains('enableVibration(false)'));
      expect(kotlin, contains('enableLights(false)'));
      expect(kotlin, contains('setSound(null, null)'));
    });

    test('the ongoing notification is low priority and never alerts', () {
      expect(kotlin, contains('NotificationCompat.PRIORITY_LOW'));
      expect(kotlin, contains('.setSilent(true)'));
      expect(kotlin, contains('.setOnlyAlertOnce(true)'));
      expect(kotlin, contains('.setLocalOnly(true)'));
      expect(kotlin, contains('NotificationCompat.VISIBILITY_PRIVATE'));
      expect(kotlin, contains('NotificationCompat.CATEGORY_SERVICE'));
      expect(kotlin, contains('NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE'));
      expect(kotlin, contains('ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION'));
    });

    test('no CPU wakelock is ever taken', () {
      // A held wakelock keeps the CPU running between fixes, which is exactly
      // the drain this work removes. There is none: no permission, no import,
      // no acquisition.
      expect(manifest, isNot(contains('android.permission.WAKE_LOCK')));
      expect(kotlin, isNot(contains('WakeLock')));
      expect(kotlin, isNot(contains('PowerManager')));
      expect(kotlin, isNot(contains('WAKE_LOCK')));
    });

    test('the manifest declares the location foreground service', () {
      expect(manifest, contains('.LocationTrackingService'));
      expect(manifest, contains('android:foregroundServiceType="location"'));
      expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
      expect(
        manifest,
        contains('android.permission.FOREGROUND_SERVICE_LOCATION'),
      );
      expect(manifest, contains('android.permission.ACCESS_BACKGROUND_LOCATION'));
    });

    test('the plugin never enables its own wakelock or Wi-Fi lock', () {
      // geolocator used to offer `enableWakeLock` / `enableWifiLock` on
      // `AndroidSettings`: they hold the radio and the CPU awake between
      // fixes. The current plugin version no longer exposes them, and the
      // app must not reintroduce them through another route either.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final String locationService = File(
        'lib/src/services/location_service.dart',
      ).readAsStringSync();
      expect(locationService, isNot(contains('enableWakeLock:')));
      expect(locationService, isNot(contains('enableWifiLock:')));

      final AndroidSettings settings = LocationService.trackingSettingsFor(
        accuracy: LocationAccuracy.medium,
      ) as AndroidSettings;
      expect(settings.forceLocationManager, isFalse);
      expect(settings.intervalDuration, const Duration(seconds: 5));

      final AndroidSettings background =
          LocationService.backgroundTrackingLocationSettings
              as AndroidSettings;
      expect(background.forceLocationManager, isFalse);
      expect(background.intervalDuration, const Duration(seconds: 15));
    });
  });
}
