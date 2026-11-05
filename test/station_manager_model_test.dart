import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/data/models/station_manager.dart';

/// The seeded catalogue carries each station's manager(s). These tests pin the
/// storage shape both ways, because the managers travel as a plain map inside
/// the same Hive record as the rest of the place: a missing key must never throw
/// and a stale record must never lose the data.
void main() {
  Place place({List<StationManager> managers = const <StationManager>[]}) =>
      Place(
        id: 'stn_29',
        name: 'محطة طاقة الغردقة',
        notes: '',
        latitude: 27.0833039,
        longitude: 33.8323399,
        timestamp: DateTime.utc(2026, 10, 20),
        managers: managers,
      );

  group('StationManager', () {
    test('round-trips name and phone', () {
      const StationManager manager =
          StationManager(name: 'احمد ايمن', phone: '+201001234567');
      final StationManager back = StationManager.fromMap(manager.toMap());

      expect(back, manager);
      expect(back.name, 'احمد ايمن');
      expect(back.phone, '+201001234567');
      expect(back.hasPhone, isTrue);
    });

    test('a blank or null phone degrades to null, never to an empty string', () {
      for (final Object? raw in <Object?>[null, '', '   ']) {
        final StationManager manager = StationManager.fromMap(
          <String, dynamic>{'name': 'يحي إبراهيم', 'phone': raw},
        );
        expect(manager.phone, isNull, reason: 'raw=$raw');
        expect(manager.hasPhone, isFalse);
      }
    });

    test('names are trimmed', () {
      final StationManager manager = StationManager.fromMap(
        <String, dynamic>{'name': '  شادي ناصف  '},
      );
      expect(manager.name, 'شادي ناصف');
    });
  });

  group('Place.managers', () {
    test('survives toMap/fromMap with several managers', () {
      final Place source = place(
        managers: const <StationManager>[
          StationManager(name: 'احمد حمدي'),
          StationManager(name: 'احمد عز', phone: '01001234567'),
        ],
      );

      final Place back = Place.fromMap(source.toMap());

      expect(back.managers, hasLength(2));
      expect(back.managers.first.name, 'احمد حمدي');
      expect(back.managers.last.phone, '01001234567');
      expect(back, equals(source));
    });

    test('a place stored before managers existed still parses', () {
      final Map<String, dynamic> legacy = place().toMap()
        ..remove('managers');

      final Place back = Place.fromMap(legacy);

      expect(back.managers, isEmpty);
      expect(back.managerName, isNull);
    });

    test('a corrupted managers value degrades to empty instead of throwing', () {
      for (final Object? raw in <Object?>[
        'not-a-list',
        42,
        <Object?>[1, 'x', null],
      ]) {
        final Map<String, dynamic> map = place().toMap()
          ..['managers'] = raw;
        expect(Place.fromMap(map).managers, isEmpty, reason: 'raw=$raw');
      }
    });

    test('nameless entries are dropped, real ones kept in order', () {
      final Map<String, dynamic> map = place().toMap()
        ..['managers'] = <Object?>[
          <String, dynamic>{'name': '', 'phone': '0100'},
          <String, dynamic>{'name': 'علي فؤاد'},
          <String, dynamic>{'phone': '0111'},
        ];

      final Place back = Place.fromMap(map);

      expect(back.managers, hasLength(1));
      expect(back.managerName, 'علي فؤاد');
    });

    test('managerName exposes the primary (first) manager', () {
      final Place source = place(
        managers: const <StationManager>[
          StationManager(name: 'خالد عبد الناصر'),
          StationManager(name: 'احمد شعبان'),
        ],
      );
      expect(source.managerName, 'خالد عبد الناصر');
    });

    test('toMap omits the key for a place without managers', () {
      expect(place().toMap().containsKey('managers'), isFalse);
    });

    test('two places with equal managers compare equal and hash alike', () {
      const List<StationManager> managers = <StationManager>[
        StationManager(name: 'شادي ناصف', phone: '0100'),
      ];
      final Place a = place(managers: managers);
      final Place b = place(managers: managers);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith keeps managers unless they are replaced', () {
      final Place source = place(
        managers: const <StationManager>[StationManager(name: 'احمد ايمن')],
      );

      expect(source.copyWith(isPinned: true).managers, source.managers);
      expect(source.copyWith(managers: const <StationManager>[]).managers,
          isEmpty);
    });

    test('exports keep the managers in the backup JSON', () {
      final Place source = place(
        managers: const <StationManager>[StationManager(name: 'احمد عمران')],
      );

      final List<dynamic> exported = source.toJson()['managers'] as List<dynamic>;
      expect(exported, hasLength(1));
      expect(Place.fromJson(source.toJson()).managerName, 'احمد عمران');
    });
  });

  group('StationManager.isDuplicate', () {
    test('is true for the same trimmed name and phone', () {
      const StationManager candidate = StationManager(
        name: 'احمد ايمن',
        phone: '01001234567',
      );
      const StationManager existing = StationManager(
        name: '  احمد ايمن ',
        phone: ' 01001234567 ',
      );

      expect(StationManager.isDuplicate(candidate, existing), isTrue);
    });

    test('is false when the phone differs', () {
      const StationManager candidate = StationManager(
        name: 'احمد ايمن',
        phone: '01001234568',
      );
      const StationManager existing = StationManager(
        name: 'احمد ايمن',
        phone: '01001234567',
      );

      expect(StationManager.isDuplicate(candidate, existing), isFalse);
    });

    test('is false when the name differs', () {
      const StationManager candidate = StationManager(
        name: 'يحي إبراهيم',
        phone: '01001234567',
      );
      const StationManager existing = StationManager(
        name: 'احمد ايمن',
        phone: '01001234567',
      );

      expect(StationManager.isDuplicate(candidate, existing), isFalse);
    });

    test('is true when both phone values are blank', () {
      const StationManager candidate = StationManager(name: 'احمد ايمن');
      const StationManager existing = StationManager(name: 'احمد ايمن');

      expect(StationManager.isDuplicate(candidate, existing), isTrue);
    });
  });

  group('StationManager.withoutDuplicates', () {
    test('keeps a single manager untouched', () {
      const StationManager manager =
          StationManager(name: 'احمد ايمن', phone: '01001234567');

      final List<StationManager> result =
          StationManager.withoutDuplicates(<StationManager>[manager]);

      expect(result, hasLength(1));
      expect(result.first, manager);
    });

    test('appends a manager when the (name, phone) pair is unique', () {
      const StationManager existing = StationManager(
        name: 'احمد ايمن',
        phone: '01001234567',
      );
      const StationManager fresh = StationManager(
        name: 'يحي إبراهيم',
        phone: '01009876543',
      );

      final List<StationManager> result = StationManager.withoutDuplicates(
        <StationManager>[existing, fresh],
      );

      expect(result, hasLength(2));
    });

    test('skips an exact duplicate instead of appending', () {
      const StationManager existing = StationManager(
        name: 'احمد ايمن',
        phone: '01001234567',
      );

      final List<StationManager> result = StationManager.withoutDuplicates(
        <StationManager>[existing, existing],
      );

      expect(result, hasLength(1));
    });

    test('skips a duplicate that differs only in surrounding whitespace', () {
      const StationManager existing = StationManager(
        name: 'احمد ايمن',
        phone: '01001234567',
      );
      const StationManager candidate = StationManager(
        name: '  احمد ايمن ',
        phone: ' 01001234567 ',
      );

      final List<StationManager> result = StationManager.withoutDuplicates(
        <StationManager>[existing, candidate],
      );

      expect(result, hasLength(1));
    });

    test('removes later duplicates while keeping first-occurrence order', () {
      const List<StationManager> managers = <StationManager>[
        StationManager(name: 'احمد حمدي'),
        StationManager(name: 'احمد عز', phone: '01001234567'),
        StationManager(name: 'احمد حمدي'),
        StationManager(name: 'علي فؤاد', phone: '01005556666'),
      ];

      final List<StationManager> result = StationManager.withoutDuplicates(managers);

      expect(result, hasLength(3));
      expect(
        result.map((StationManager m) => m.name).toList(),
        <String>['احمد حمدي', 'احمد عز', 'علي فؤاد'],
      );
    });

    test('does not mutate the input list', () {
      final List<StationManager> managers = <StationManager>[
        StationManager(name: 'احمد ايمن', phone: '01001234567'),
        StationManager(name: 'احمد ايمن', phone: '01001234567'),
      ];

      final List<StationManager> result = StationManager.withoutDuplicates(managers);

      expect(managers, hasLength(2));
      expect(result, hasLength(1));
    });
  });
}
