import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/core/config/app_config.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/data/models/station_manager.dart';
import 'package:routenote/src/services/database_seeder.dart';

/// The bundled catalogue is merged into the **places** box on cold start, so a
/// regression here would either duplicate 394 stations next to the user's own
/// places or erase their edits. These tests run against real Hive boxes in a
/// temp directory (same approach as `place_persistence_test.dart`) and use an
/// injected asset loader instead of `rootBundle`.
void main() {
  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;

  final String catalogue = jsonEncode(<Object>[
    _station(
      id: 'stn_29',
      name: 'محطة طاقة الغردقة',
      latitude: 27.0833039,
      longitude: 33.8323399,
      managers: <Object>[
        <String, Object?>{'name': 'احمد ايمن', 'phone': null},
        <String, Object?>{'name': 'يحي إبراهيم', 'phone': '01001234567'},
      ],
    ),
    _station(
      id: 'stn_70',
      name: 'محطة موبيل المرور - الغردقة الجديدة',
      latitude: 27.1234,
      longitude: 33.9,
    ),
  ]);

  Future<int> seed({String? json}) => DatabaseSeeder.maybeSeed(
        placesBox: placesBox,
        settingsBox: settingsBox,
        loadAsset: (String _) async => json ?? catalogue,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_seed_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('places_seed_test');
    settingsBox = await Hive.openBox<dynamic>('settings_seed_test');
  });

  tearDown(() async {
    await placesBox.close();
    await settingsBox.close();
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('seeds the catalogue into an empty places box', () async {
    final int inserted = await seed();

    expect(inserted, 2);
    expect(placesBox.length, 2);

    final Place station = Place.fromMap(
      Map<String, dynamic>.from(placesBox.get('stn_29') as Map),
    );
    expect(station.name, 'محطة طاقة الغردقة');
    expect(station.isDefault, isTrue);
    expect(station.isCustom, isFalse);
    expect(station.managers.map((StationManager m) => m.name),
        <String>['احمد ايمن', 'يحي إبراهيم']);
    expect(settingsBox.get(AppConfig.stationsSeedVersionKey),
        AppConfig.stationsSeedVersion);
  });

  test('a second launch inserts nothing', () async {
    await seed();
    final int inserted = await seed();

    expect(inserted, 0);
    expect(placesBox.length, 2);
  });

  test('a station the user deleted does not come back', () async {
    await seed();
    await placesBox.delete('stn_29');

    final int inserted = await seed();

    expect(inserted, 0);
    expect(placesBox.containsKey('stn_29'), isFalse);
  });

  test('a place the user edited is never overwritten', () async {
    final Place edited = Place(
      id: 'stn_29',
      name: 'محطة طاقة الغردقة',
      notes: 'ملاحظة المستخدم',
      latitude: 27.0833039,
      longitude: 33.8323399,
      timestamp: DateTime.utc(2026, 1, 1),
      isPinned: true,
      isCustom: true,
    );
    await placesBox.put(edited.id, edited.toMap());
    await settingsBox.delete(AppConfig.stationsSeedVersionKey);

    final int inserted = await seed();

    expect(inserted, 1); // only stn_70 is new
    final Place stored = Place.fromMap(
      Map<String, dynamic>.from(placesBox.get('stn_29') as Map),
    );
    expect(stored.notes, 'ملاحظة المستخدم');
    expect(stored.isPinned, isTrue);
    expect(stored.isCustom, isTrue);
  });

  test('a station the user saved manually is not duplicated', () async {
    await placesBox.put(
      'user-uuid-1',
      Place(
        id: 'user-uuid-1',
        name: 'محطة طاقة الغردقة',
        notes: '',
        latitude: 27.0833039,
        longitude: 33.8323399,
        timestamp: DateTime.utc(2026, 1, 1),
      ).toMap(),
    );

    final int inserted = await seed();

    expect(inserted, 1); // same name + coordinates already present
    expect(placesBox.containsKey('stn_29'), isFalse);
  });

  test('catalogue entries without coordinates are skipped', () async {
    final String broken = jsonEncode(<Object>[
      _station(id: 'stn_bad', name: 'بلا إحداثيات'),
    ]);

    final int inserted = await seed(json: broken);

    expect(inserted, 0);
    expect(placesBox.isEmpty, isTrue);
  });

  test('a malformed catalogue never throws', () async {
    expect(await seed(json: 'not json'), 0);
    expect(await seed(json: '{"a": 1}'), 0);
    expect(placesBox.isEmpty, isTrue);
  });

  test('bumping the version tops up newly added stations only', () async {
    await seed(); // version 1
    await settingsBox.put(AppConfig.stationsSeedVersionKey, 0); // pretend stale

    final String updated = jsonEncode(<Object>[
      ...jsonDecode(catalogue) as List<dynamic>,
      _station(id: 'stn_999', name: 'محطة جديدة', latitude: 30.1, longitude: 31.2),
    ]);
    final int inserted = await seed(json: updated);

    expect(inserted, 1);
    expect(placesBox.containsKey('stn_999'), isTrue);
    expect(placesBox.length, 3);
  });

  test('seeded managers keep their phone when the catalogue provides one',
      () async {
    await seed();
    final Place station = Place.fromMap(
      Map<String, dynamic>.from(placesBox.get('stn_29') as Map),
    );

    expect(station.managers.last.hasPhone, isTrue);
    expect(station.managers.last.phone, '01001234567');
  });
}

Map<String, Object?> _station({
  required String id,
  required String name,
  double latitude = 0,
  double longitude = 0,
  List<Object> managers = const <Object>[],
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'notes': '',
    'category': 'gas_station',
    'latitude': latitude,
    'longitude': longitude,
    'managers': managers,
    'timestamp': '2026-10-20T00:00:00.000Z',
    'isDefault': true,
    'isCustom': false,
  };
}
