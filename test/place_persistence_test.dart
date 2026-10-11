import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/place_local_data_source.dart';
import 'package:routenote/src/data/models/place.dart';

/// Verifies lock/unlock durability against real Hive storage on disk.
///
/// Unlike the widget tests (which use an in-memory fake), these tests open a
/// real Hive box in a temp directory, write through the actual
/// [PlaceLocalDataSource] (including its `flush()`), close the box and reopen
/// it to simulate an app restart, so a regression in the `isLocked`
/// persistence path cannot slip through.
void main() {
  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_hive_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('places');
    settingsBox = await Hive.openBox<dynamic>('settings');
  });

  tearDown(() async {
    await placesBox.close();
    await settingsBox.close();
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  PlaceLocalDataSource source() => PlaceLocalDataSource(
        HiveDatabase(placesBox: placesBox, settingsBox: settingsBox),
      );

  test('Place.toMap/fromMap round-trips the isLocked flag', () {
    // These boxes do not use generated Hive TypeAdapters: a Place travels as a
    // Map, so serialisation is toMap()/fromMap(). This pins the field both
    // ways so a "default fallback" can never silently unlock a stored place.
    for (final bool locked in <bool>[true, false]) {
      final Place place = _place(isLocked: locked);
      final Place back = Place.fromMap(place.toMap());
      expect(back.isLocked, locked,
          reason: 'isLocked=$locked must survive toMap()/fromMap()');
      expect(back, equals(place));
    }
  });

  test('fromMap defaults isLocked to false when the key is missing or null',
      () {
    // Places saved before the lock feature existed have no 'isLocked' key. It
    // must parse as false (never fall back to true and lock the location).
    final Map<String, dynamic> base = _place().toMap()..remove('isLocked');
    expect(Place.fromMap(base).isLocked, isFalse);

    // An explicitly-null value behaves identically.
    expect(
      Place.fromMap(<String, dynamic>{...base, 'isLocked': null}).isLocked,
      isFalse,
    );

    // Legacy string/number forms never coerce a "no" into "locked".
    expect(
      Place.fromMap(<String, dynamic>{...base, 'isLocked': 'no'}).isLocked,
      isFalse,
    );
    expect(
      Place.fromMap(<String, dynamic>{...base, 'isLocked': 0}).isLocked,
      isFalse,
    );
  });

  test('a locked place stays locked after put (flush) and a box reopen', () async {
    await source().put(_place(isLocked: true));

    // The raw map written into the box carries the locked flag.
    final Map<String, dynamic> raw =
        Map<String, dynamic>.from(placesBox.get('place-1') as Map);
    expect(raw['isLocked'], isTrue);

    // Simulate an app restart: close the box and reopen it from disk.
    await placesBox.close();
    placesBox = await Hive.openBox<dynamic>('places');

    final Place? stored = await source().getById('place-1');
    expect(stored, isNotNull);
    expect(stored!.isLocked, isTrue,
        reason:
            'startup must respect the persisted isLocked instead of falling '
            'back to the unlocked default');

    final List<Place> all = await source().getAll();
    expect(all.single.isLocked, isTrue);
  });

  test('unlocking persists isLocked=false durably (Hive round trip)', () async {
    await source().put(_place(isLocked: true));

    // Exactly what an unlock handler does: read latest -> copyWith(false) ->
    // save. The save's flush() must make the change durable.
    final Place? current = await source().getById('place-1');
    final Place unlocked = current!.copyWith(isLocked: false);
    await source().put(unlocked);

    await placesBox.close();
    placesBox = await Hive.openBox<dynamic>('places');

    final Place? stored = await source().getById('place-1');
    expect(stored, isNotNull);
    expect(stored!.isLocked, isFalse,
        reason: 'an unlock must survive a restart, not revert to locked');

    // The raw map read back from disk after the restart carries false too, so
    // no other read path (startup, backup, sync) can flip it back to locked.
    final Map<String, dynamic> rawAfterRestart =
        Map<String, dynamic>.from(placesBox.get('place-1') as Map);
    expect(rawAfterRestart['isLocked'], isFalse);
  });
}

Place _place({bool isLocked = false}) => Place(
      id: 'place-1',
      name: 'Cairo Tower',
      notes: '',
      latitude: 30.0444,
      longitude: 31.2357,
      timestamp: DateTime.utc(2026, 10, 9, 12),
      isLocked: isLocked,
    );