import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/core/config/preferred_nav_app.dart';
import 'package:routenote/src/core/security/session_guard.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/settings_repository.dart';
import 'package:routenote/src/providers/app_providers.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late HiveDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_prefs_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('prefs_test');
    database = HiveDatabase(placesBox: box, settingsBox: box);
  });

  tearDown(() async {
    await box.close();
    await tempDir.delete(recursive: true);
  });

  test('SettingsRepository persists the preferred navigation app', () async {
    final SettingsRepository repo = SettingsRepository(box);

    // Defaults to system.
    expect(repo.preferredNavApp, PreferredNavApp.system);

    await repo.setPreferredNavApp(PreferredNavApp.waze);
    expect(repo.preferredNavApp, PreferredNavApp.waze);
    expect(box.get('preferred_nav_app'), 'waze');

    await repo.setPreferredNavApp(PreferredNavApp.googleMaps);
    expect(repo.preferredNavApp, PreferredNavApp.googleMaps);

    // Unknown stored values degrade to system without throwing.
    await box.put('preferred_nav_app', 'not-an-app');
    expect(repo.preferredNavApp, PreferredNavApp.system);
  });

  test('SettingsRepository defaults smart insights to enabled', () async {
    final SettingsRepository repo = SettingsRepository(box);
    expect(repo.areSmartInsightsEnabled, isTrue);

    await repo.setSmartInsightsEnabled(false);
    expect(repo.areSmartInsightsEnabled, isFalse);
    expect(box.get('smart_insights_enabled'), isFalse);
  });

  test('preferredNavAppProvider controller persists and notifies', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [hiveDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    expect(container.read(preferredNavAppProvider), PreferredNavApp.system);
    await container
        .read(preferredNavAppProvider.notifier)
        .setPreferredApp(PreferredNavApp.googleMaps);

    expect(container.read(preferredNavAppProvider), PreferredNavApp.googleMaps);
    expect(box.get('preferred_nav_app'), 'googleMaps');
  });

  test(
    'smartInsightsEnabledProvider controller persists and notifies',
    () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [hiveDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);

      expect(container.read(smartInsightsEnabledProvider), isTrue);
      await container
          .read(smartInsightsEnabledProvider.notifier)
          .setEnabled(false);

      expect(container.read(smartInsightsEnabledProvider), isFalse);
      expect(box.get('smart_insights_enabled'), isFalse);
    },
  );

  group('vault session settings', () {
    test('session timeout defaults to the guard default', () {
      final SettingsRepository repo = SettingsRepository(box);

      expect(
        repo.sessionTimeoutMinutes,
        SessionGuard.defaultInactivityTimeout.inMinutes,
      );
    });

    test('session timeout round-trips and is persisted', () async {
      final SettingsRepository repo = SettingsRepository(box);

      await repo.setSessionTimeoutMinutes(30);
      expect(repo.sessionTimeoutMinutes, 30);
      expect(box.get('session_timeout_minutes'), 30);
    });

    test('an out-of-set or corrupt value degrades to the default', () async {
      final SettingsRepository repo = SettingsRepository(box);

      // A hand-edited box must never yield an instantly-locking vault.
      await box.put('session_timeout_minutes', 0);
      expect(
        repo.sessionTimeoutMinutes,
        SessionGuard.defaultInactivityTimeout.inMinutes,
      );

      await box.put('session_timeout_minutes', 'not-a-number');
      expect(
        repo.sessionTimeoutMinutes,
        SessionGuard.defaultInactivityTimeout.inMinutes,
      );
    });

    test('rejects a value outside the selectable set', () {
      final SettingsRepository repo = SettingsRepository(box);

      expect(() => repo.setSessionTimeoutMinutes(7), throwsArgumentError);
    });

    test('lock-on-device-lock defaults to on and round-trips', () async {
      final SettingsRepository repo = SettingsRepository(box);

      expect(repo.isLockOnDeviceLockEnabled, isTrue);

      await repo.setLockOnDeviceLockEnabled(false);
      expect(repo.isLockOnDeviceLockEnabled, isFalse);
      expect(box.get('lock_on_device_lock'), isFalse);
    });

    test('sessionTimeoutProvider controller persists and updates the guard',
        () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [hiveDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(sessionTimeoutProvider),
        SessionGuard.defaultInactivityTimeout.inMinutes,
      );
      await container
          .read(sessionTimeoutProvider.notifier)
          .setMinutes(5);

      expect(container.read(sessionTimeoutProvider), 5);
      expect(box.get('session_timeout_minutes'), 5);
      // The live guard picks the new window up immediately.
      expect(
        container.read(sessionGuardProvider).inactivityTimeout,
        const Duration(minutes: 5),
      );
    });

    test('lockOnDeviceLockProvider controller updates the live guard',
        () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [hiveDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);

      expect(container.read(lockOnDeviceLockProvider), isTrue);
      await container
          .read(lockOnDeviceLockProvider.notifier)
          .setEnabled(false);

      expect(container.read(lockOnDeviceLockProvider), isFalse);
      expect(container.read(sessionGuardProvider).lockOnDeviceLock, isFalse);
    });

    test('the guard honours the persisted settings from the first build',
        () async {
      final SettingsRepository repo = SettingsRepository(box);
      await repo.setSessionTimeoutMinutes(60);
      await repo.setLockOnDeviceLockEnabled(false);

      final ProviderContainer container = ProviderContainer(
        overrides: [hiveDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);

      final SessionGuard guard = container.read(sessionGuardProvider);
      expect(guard.inactivityTimeout, const Duration(minutes: 60));
      expect(guard.lockOnDeviceLock, isFalse);
    });
  });
}
