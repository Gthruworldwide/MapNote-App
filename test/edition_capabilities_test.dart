import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/core/config/app_config.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/settings_repository.dart';
import 'package:routenote/src/providers/app_providers.dart';

void main() {
  group('build-bound edition identity', () {
    test('the default build is work with every AutoMotion capability off', () {
      final EditionCapabilities capabilities = EditionCapabilities.fromBuild();

      expect(capabilities.edition, AppEdition.work);
      expect(capabilities.isAutomotion, isFalse);
      expect(capabilities.automotionEnabled, isFalse);
      expect(capabilities.backgroundLocationEnabled, isFalse);
      expect(capabilities.activityRecognitionEnabled, isFalse);
      expect(capabilities.motionSensorsEnabled, isFalse);
      expect(capabilities.automotiveForegroundServiceEnabled, isFalse);
      expect(capabilities.automotionUiEnabled, isFalse);
      expect(capabilities.allowAdminUi, isTrue);
      expect(capabilities.allowFirebaseStationAdmin, isFalse);
    });

    test('unknown edition strings fail closed to work', () {
      for (final String raw in <String>[
        '',
        'WORK_EDITION',
        'admin',
        'personal',
        'work ',
      ]) {
        expect(AppConfig.parseEdition(raw), AppEdition.work, reason: raw);
      }
      expect(AppConfig.parseEdition('work'), AppEdition.work);
      expect(AppConfig.parseEdition('WORK'), AppEdition.work);
      expect(AppConfig.parseEdition('automotion'), AppEdition.automotion);
      // Parsing is case-insensitive and trims surrounding whitespace, so a
      // padded automotion value is a *valid* automotion identity, not unknown.
      expect(AppConfig.parseEdition('AUTOMOTION '), AppEdition.automotion);
      expect(AppConfig.parseEdition(' AutoMotion'), AppEdition.automotion);
    });

    test('an automotion build grants every vehicle capability', () {
      const EditionCapabilities automotion =
          EditionCapabilities(AppEdition.automotion);

      expect(automotion.isAutomotion, isTrue);
      expect(automotion.automotionEnabled, isTrue);
      expect(automotion.backgroundLocationEnabled, isTrue);
      expect(automotion.activityRecognitionEnabled, isTrue);
      expect(automotion.motionSensorsEnabled, isTrue);
      expect(automotion.automotiveForegroundServiceEnabled, isTrue);
      expect(automotion.automotionUiEnabled, isTrue);
      expect(automotion.allowAdminUi, isFalse);
      expect(automotion.allowFirebaseStationAdmin, isFalse);
    });

    test('the provider exposes the build flag, not a runtime override', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(editionCapabilitiesProvider).edition,
        AppConfig.appEdition,
      );
    });
  });

  group('AutoMotion capability gate', () {
    late Directory tempDir;
    late Box<dynamic> placesBox;
    late Box<dynamic> settingsBox;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('edition_capabilities_');
      Hive.init(tempDir.path);
      placesBox = await Hive.openBox<dynamic>('edition_places');
      settingsBox = await Hive.openBox<dynamic>('edition_settings');
    });

    tearDown(() async {
      await placesBox.close();
      await settingsBox.close();
      await tempDir.delete(recursive: true);
    });

    ProviderContainer containerFor(AppEdition edition) => ProviderContainer(
          overrides: <Override>[
            editionCapabilitiesProvider
                .overrideWithValue(EditionCapabilities(edition)),
            hiveDatabaseProvider.overrideWithValue(
              HiveDatabase(placesBox: placesBox, settingsBox: settingsBox),
            ),
          ],
        );

    test('work forces tracking toggles off even when persisted on', () async {
      final SettingsRepository settings = SettingsRepository(settingsBox);
      await settings.setAutoMotionEnabled(true);
      await settings.setGpsTrackingEnabled(true);

      final ProviderContainer container = containerFor(AppEdition.work);
      addTearDown(container.dispose);

      expect(container.read(automotionAvailableProvider), isFalse);
      expect(container.read(autoMotionEnabledProvider), isFalse);
      expect(container.read(gpsTrackingEnabledProvider), isFalse);

      // The controllers return inert snapshots before touching any tracker,
      // sensor or foreground service on the work path.
      final AutoMotionState motion = container.read(autoMotionControllerProvider);
      final GpsTrackingState gps = container.read(gpsTrackingControllerProvider);
      expect(motion.active, isFalse);
      expect(motion.totalKm, 0);
      expect(motion.enabled, isFalse);
      expect(gps.active, isFalse);
      expect(gps.totalKm, 0);
      expect(gps.enabled, isFalse);
    });

    test('work refuses to enable tracking through the notifier', () async {
      final ProviderContainer container = containerFor(AppEdition.work);
      addTearDown(container.dispose);

      await container.read(autoMotionEnabledProvider.notifier).setEnabled(true);
      await container.read(gpsTrackingEnabledProvider.notifier).setEnabled(true);
      await container.read(autoMotionControllerProvider.notifier).start();
      await container.read(gpsTrackingControllerProvider.notifier).start();

      // The effective, gated state stays off. The notifiers are a no-op on the
      // work path, so nothing is persisted either — assert the box stayed
      // empty rather than the raw getter default (which is `true` for
      // AutoMotion and therefore not evidence of a write).
      expect(container.read(autoMotionEnabledProvider), isFalse);
      expect(container.read(gpsTrackingEnabledProvider), isFalse);
      expect(settingsBox.isEmpty, isTrue);
    });

    test('automotion honours the persisted tracking preferences', () async {
      final SettingsRepository settings = SettingsRepository(settingsBox);
      await settings.setAutoMotionEnabled(true);
      await settings.setGpsTrackingEnabled(false);

      final ProviderContainer container = containerFor(AppEdition.automotion);
      addTearDown(container.dispose);

      expect(container.read(automotionAvailableProvider), isTrue);
      expect(container.read(autoMotionEnabledProvider), isTrue);
      expect(container.read(gpsTrackingEnabledProvider), isFalse);

      await container.read(gpsTrackingEnabledProvider.notifier).setEnabled(true);
      expect(container.read(gpsTrackingEnabledProvider), isTrue);
      expect(SettingsRepository(settingsBox).isGpsTrackingEnabled, isTrue);
    });
  });
}
