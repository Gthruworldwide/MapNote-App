import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/core/config/preferred_nav_app.dart';
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
}
