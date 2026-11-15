import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/data/local/hive_place_codec.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/admin/admin_approval_screen.dart';

/// Regression coverage for the Admin Approval gate: the default admin PIN,
/// the admin session state machine, pending-proposal type routing, and the
/// defensive proposal/Hive decoding that fixes "Incomplete proposal".
void main() {
  group('placeFromHiveValue', () {
    test('decodes a Place.toMap() payload', () {
      final Place place = Place(
        id: 'st-1',
        name: 'Station',
        notes: '',
        latitude: 1,
        longitude: 2,
        timestamp: DateTime.utc(2026),
        displayName: 'Ali',
        phoneNumber: '555',
      );
      final Place? decoded = placeFromHiveValue(place.toMap());
      expect(decoded, isNotNull);
      expect(decoded!.id, 'st-1');
      expect(decoded.displayName, 'Ali');
      expect(decoded.phoneNumber, '555');
    });

    test('accepts an existing Place instance', () {
      final Place place = Place(
        id: 'st-2',
        name: 'S',
        notes: '',
        latitude: 0,
        longitude: 0,
        timestamp: DateTime.utc(2026),
      );
      expect(placeFromHiveValue(place), same(place));
    });

    test('returns null for null, garbage, and id-less payloads', () {
      expect(placeFromHiveValue(null), isNull);
      expect(placeFromHiveValue('nope'), isNull);
      expect(placeFromHiveValue(<String, dynamic>{'name': 'x'}), isNull);
    });
  });

  group('resolveProposalFields', () {
    test('reads contact update from proposedData', () {
      final ProposalFields f = resolveProposalFields(<String, dynamic>{
        'stationId': 'ST_1',
        'type': 'contact_update',
        'proposedData': <String, dynamic>{
          'managerName': 'Mona',
          'managerPhone': '0100',
          'managerRole': 'supervisor',
        },
      });
      expect(f.type, 'update_manager');
      expect(f.managerName, 'Mona');
      expect(f.managerPhone, '0100');
      expect(f.managerRole, 'supervisor');
      expect(f.isEmpty, isFalse);
    });

    test('reads new station from root fields', () {
      final ProposalFields f = resolveProposalFields(<String, dynamic>{
        'type': 'new_station',
        'name': 'New Depot',
        'latitude': 30.0,
        'longitude': 31.0,
        'city': 'Cairo',
      });
      expect(f.type, 'new_station');
      expect(f.stationName, 'New Depot');
      expect(f.city, 'Cairo');
      expect(f.latitude, 30.0);
      expect(f.longitude, 31.0);
      expect(f.isEmpty, isFalse);
    });

    test('accepts legacy data alias and phone spellings', () {
      final ProposalFields f = resolveProposalFields(<String, dynamic>{
        'data': <String, dynamic>{
          'displayName': 'Omar',
          'phone': '0777',
        },
        'stationName': 'Depot',
      });
      expect(f.stationName, 'Depot');
      expect(f.managerName, 'Omar');
      expect(f.managerPhone, '0777');
    });

    test('missing/unknown type degrades, never crashes; empty is flagged', () {
      expect(resolveProposalFields(null).type, 'update_manager');
      expect(
        resolveProposalFields(<String, dynamic>{'type': 'legacy'}).type,
        'update_manager',
      );
      expect(resolveProposalFields(<String, dynamic>{}).isEmpty, isTrue);
    });

    test('resolves standardized contact_update payload (no Incomplete proposal)', () {
      final ProposalFields f = resolveProposalFields(<String, dynamic>{
        'stationId': 'ST_42',
        'stationName': 'Alpha Depot',
        'type': 'contact_update',
        'managerName': 'Nadia',
        'managerPhone': '+20100111222',
        'managerRole': 'manager',
        'proposedData': <String, dynamic>{
          'stationId': 'ST_42',
          'stationName': 'Alpha Depot',
          'managerName': 'Nadia',
          'managerPhone': '+20100111222',
          'managerRole': 'manager',
          'displayName': 'Nadia',
          'phoneNumber': '+20100111222',
        },
        'status': 'pending',
      });
      expect(f.type, 'update_manager');
      expect(f.stationName, 'Alpha Depot');
      expect(f.managerName, 'Nadia');
      expect(f.managerPhone, '+20100111222');
      expect(f.managerRole, 'manager');
      expect(f.isEmpty, isFalse);
      // A manager payload means the approval card must not render
      // "Incomplete proposal" for this compliant proposal.
      expect(f.managerName.isNotEmpty || f.managerPhone.isNotEmpty, isTrue);
    });

    test('resolves standardized manager_removal payload', () {
      final ProposalFields f = resolveProposalFields(<String, dynamic>{
        'stationId': 'ST_7',
        'stationName': 'Beta Station',
        'type': 'manager_removal',
        'managerName': 'Old Manager',
        'managerPhone': '0555',
        'managerRole': 'manager',
        'proposedData': <String, dynamic>{
          'stationId': 'ST_7',
          'stationName': 'Beta Station',
          'managerName': 'Old Manager',
          'managerPhone': '0555',
          'managerRole': 'manager',
          'displayName': 'Old Manager',
          'phoneNumber': '0555',
        },
        'status': 'pending',
      });
      expect(f.type, 'manager_removal');
      expect(f.stationName, 'Beta Station');
      expect(f.managerName, 'Old Manager');
      expect(f.managerPhone, '0555');
      expect(f.isEmpty, isFalse);
      expect(f.managerName.isNotEmpty || f.managerPhone.isNotEmpty, isTrue);
    });
  });

  group('Admin PIN gate', () {
    test('accepts the default admin PIN', () {
      expect(verifyAdminPin('1991'), isTrue);
    });

    test('rejects an incorrect PIN', () {
      expect(verifyAdminPin('1992'), isFalse);
      expect(verifyAdminPin('0000'), isFalse);
    });

    test('rejects an empty or short PIN', () {
      expect(verifyAdminPin(''), isFalse);
      expect(verifyAdminPin('12'), isFalse);
    });
  });

  group('Admin session', () {
    test('starts locked and can be unlocked then locked again', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(adminSession), isFalse);
      container.read(adminSession.notifier).setSession(true);
      expect(container.read(adminSession), isTrue);
      container.read(adminSession.notifier).setSession(false);
      expect(container.read(adminSession), isFalse);
    });
  });

  group('Proposal type normalization', () {
    test('keeps new_station proposals distinct', () {
      expect(normalizeProposalType('new_station'), 'new_station');
    });

    test('keeps manager_removal proposals distinct', () {
      expect(normalizeProposalType('manager_removal'), 'manager_removal');
    });

    test('maps a plain manager update to update_manager', () {
      expect(normalizeProposalType('update_manager'), 'update_manager');
    });

    test('degrades unknown or missing types to update_manager', () {
      expect(normalizeProposalType('something_new'), 'update_manager');
      expect(normalizeProposalType(null), 'update_manager');
      expect(normalizeProposalType(''), 'update_manager');
    });
  });
}
