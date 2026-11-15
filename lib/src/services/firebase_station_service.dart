import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/place.dart';
import '../data/models/station_manager.dart';
import '../data/local/hive_database.dart';
import '../data/local/hive_place_codec.dart';
import 'package:hive_ce/hive.dart';

/// Service for handling station update proposals via Firebase Cloud Firestore.
///
/// Supports two-way sync between local Hive database and the master stations
/// collection, and manages pending user-submitted update proposals.
class FirebaseStationService {
  /// The Firestore instance used for all operations.
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// The Hive database instance for local station storage.
  final HiveDatabase hiveDatabase;

  /// Creates a [FirebaseStationService] with required dependencies.
  FirebaseStationService({required this.hiveDatabase});

  /// Submits a new station proposal for admin approval.
///
/// Creates a document in the [pending_updates] collection with type 'new_station'.
/// The status is set to 'pending' awaiting admin approval.
///
/// - [name] the station name
/// - [latitude] the station latitude
/// - [longitude] the station longitude
/// - [city] the city name (optional)
/// - [submittedBy] the name/ID of the staff member submitting the proposal
Future<void> submitNewStationProposal({
  required String name,
  required double latitude,
  required double longitude,
  required String city,
  required String submittedBy,
}) async {
  final pendingUpdate = <String, dynamic>{
    'type': 'new_station',
    'status': 'pending',
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'city': city,
    'submittedBy': submittedBy,
    'timestamp': FieldValue.serverTimestamp(),
  };

  await _db.collection('pending_updates').add(pendingUpdate);
}
  ///
  /// Creates a document in the [pending_updates] collection with the original
  /// and proposed manager data. The status is set to 'pending' awaiting admin
  /// approval.
  ///
  /// - [originalPlace] the pre-edit place (typically a default station)
  /// - [newManagerName] the proposed new manager name
  /// - [newManagerPhone] the proposed new manager phone number
  /// - [employeeName] the name/ID of the staff member submitting the update
  Future<void> submitStationUpdate({
    required Place originalPlace,
    required String newManagerName,
    required String newManagerPhone,
    required String employeeName,
    String? managerRole,
  }) async {
    final String role = managerRole ?? 'manager';
    final String stationId = originalPlace.id;
    final String stationName = originalPlace.name;
    final pendingUpdate = <String, dynamic>{
      'stationId': stationId,
      'stationName': stationName,
      'type': 'contact_update',
      'managerName': newManagerName,
      'managerPhone': newManagerPhone,
      'managerRole': role,
      'proposedData': {
        'stationId': stationId,
        'stationName': stationName,
        'managerName': newManagerName,
        'managerPhone': newManagerPhone,
        'managerRole': role,
        'displayName': newManagerName,
        'phoneNumber': newManagerPhone,
      },
      'originalData': {
        'managerName': originalPlace.displayName,
        'managerPhone': originalPlace.phoneNumber,
      },
      'submittedBy': employeeName,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    };

    await _db.collection('pending_updates').add(pendingUpdate);
  }

  /// Fetches approved master station updates from Firestore and applies them
  /// to the local Hive station box.
  ///
  /// Listens to the [master_stations] collection for documents with
  /// [status] == 'approved'. For each approved document, the method identifies
  /// the matching station in the local Hive [stationBox] and updates the
  /// managerName and managerPhone fields.
  ///
  /// This method should be called periodically (e.g., on app startup or via
  /// the background sync scheduler) to pull in approved updates from the
  /// cloud.
  Stream<QuerySnapshot> fetchMasterStationUpdates(
    WidgetRef ref,
  ) {
    final stationBox = hiveDatabase.stationBox;

    return _db
        .collection('master_stations')
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .map((snapshot) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final stationId = doc.id;
        _applyMasterStationUpdateFromFirestore(stationBox, stationId, data);
      }
      return snapshot;
    });
  }

  /// Applies a single approved master station update to the local Hive database.
  ///
  /// Finds the station in [stationBox] by [stationId] and updates the
  /// [managerName] and [managerPhone] fields with the values from the
  /// [updateData] map.
  ///
  /// Returns `true` if the update was applied successfully, `false` if the
  /// station was not found in the local database.
  Future<void> applyMasterStationUpdate({
    required String stationId,
    required Map<String, dynamic> updateData,
  }) async {
    final Box<dynamic> stationBox = hiveDatabase.stationBox;
    // The box stores `Place.toMap()` payloads, so the raw value must be decoded
    // before any field is read. Reading it as a `Place` threw
    // `NoSuchMethodError` on the first real record and every approval silently
    // degraded to an "Incomplete proposal" card.
    final Place? station = placeFromHiveValue(stationBox.get(stationId));

    if (station == null) {
      return;
    }

    // Append the proposed contact while preserving all existing managers,
    // skipping duplicates by (name, phone).
    final String? managerName = _stringOrNull(updateData['managerName']);
    final String? managerPhone = _stringOrNull(updateData['managerPhone']);
    final StationManager newManager = StationManager(
      name: managerName ?? station.displayName ?? '',
      phone: managerPhone ?? station.phoneNumber,
    );
    final List<StationManager> updatedManagers =
        List<StationManager>.from(station.managers);
    final bool alreadyManaged = updatedManagers.any(
      (StationManager m) => StationManager.isDuplicate(newManager, m),
    );
    if (newManager.name.isNotEmpty && !alreadyManaged) {
      updatedManagers.add(newManager);
    }

    final Place updatedPlace = station.copyWith(
      displayName: station.displayName ?? managerName,
      phoneNumber: station.phoneNumber ?? managerPhone,
      managers: updatedManagers,
    );

    // Write back to Hive stationBox
    stationBox.put(updatedPlace.id, updatedPlace.toMap());

    // Also update placesBox if the station exists there
    final placesBox = hiveDatabase.placesBox;
    final placesStation = placesBox.get(stationId);
    if (placesStation != null) {
      placesBox.put(stationId, updatedPlace.toMap());
    }

    // Persist the approved manager list to the Firestore master stations.
    await _db.collection('master_stations').doc(stationId).set({
      'stationId': stationId,
      'managerName': updateData['managerName'],
      'managerPhone': updateData['managerPhone'],
      'managerRole': updateData['managerRole'],
      'status': 'approved',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Removes a manager from the local station list and the Firestore master.
  ///
  /// Used when an admin approves a `manager_removal` proposal: the manager
  /// identified by [managerName] / [managerPhone] is dropped from the station's
  /// manager list, local Hive is updated, and the master stations document is
  /// re-written with the resulting primary contact.
  Future<void> removeManagerFromMaster({
    required String stationId,
    required String managerName,
    required String managerPhone,
  }) async {
    final Box<dynamic> stationBox = hiveDatabase.stationBox;
    final Place? station = placeFromHiveValue(stationBox.get(stationId));
    if (station == null) {
      return;
    }

    final List<StationManager> remaining =
        List<StationManager>.from(station.managers)
          ..removeWhere(
            (StationManager m) => StationManager.isDuplicate(
              m,
              StationManager(name: managerName, phone: managerPhone),
            ),
          );

    final Place updatedPlace = remaining.isNotEmpty
        ? station.copyWith(
            displayName: remaining.first.name,
            phoneNumber: remaining.first.phone,
            managers: remaining,
          )
        : station.copyWith(displayName: '', phoneNumber: '', managers: remaining);

    stationBox.put(stationId, updatedPlace.toMap());

    final placesBox = hiveDatabase.placesBox;
    final placesStation = placesBox.get(stationId);
    if (placesStation != null) {
      placesBox.put(stationId, updatedPlace.toMap());
    }

    await _db.collection('master_stations').doc(stationId).set({
      'stationId': stationId,
      'managerName': updatedPlace.displayName,
      'managerPhone': updatedPlace.phoneNumber,
      'status': 'approved',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Approves a new station proposal:
/// - Auto-assigns the next station ID (e.g., ST_426)
/// - Writes to Firestore master_stations/{stationId} with isDefault: true and isCustom: false
/// - Updates proposal status to 'approved'
/// - Syncs instantly to local Hive box
Future<String> approveNewStation({
  required String docId,
  required String name,
  required double latitude,
  required double longitude,
  required String city,
  required String submittedBy,
}) async {
  // Get the next station ID by counting existing master_stations
  final masterStationsSnapshot = await _db.collection('master_stations').get();
  final nextId = 'ST_${masterStationsSnapshot.docs.length + 1}';

  // Create the new station document in master_stations
  final newStationData = <String, dynamic>{
    'id': nextId,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'city': city,
    'isDefault': true,
    'isCustom': false,
    'status': 'approved',
    'timestamp': FieldValue.serverTimestamp(),
  };

  await _db.collection('master_stations').doc(nextId).set(newStationData);

  // Update proposal status to 'approved'
  await _db.collection('pending_updates').doc(docId).update({
    'status': 'approved',
    'stationId': nextId,
  });

  // Sync to local Hive box
  final place = Place(
    id: nextId,
    name: name,
    notes: '',
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.now().toUtc(),
    isDefault: true,
    isCustom: false,
  );
  hiveDatabase.stationBox.put(nextId, place.toMap());
  hiveDatabase.placesBox.put(nextId, place.toMap());

  return nextId;
}

/// Internal helper to apply a master station update from Firestore snapshot data.
  void _applyMasterStationUpdateFromFirestore(
    Box<dynamic> stationBox,
    String stationId,
    Map<String, dynamic> data,
  ) {
    // stationBox values are `Place.toMap()` payloads, not `Place` instances.
    final Place? station = placeFromHiveValue(stationBox.get(stationId));
    if (station == null) {
      return;
    }

    // Append the proposed contact while preserving all existing managers.
    final String? managerName = _stringOrNull(data['managerName']);
    final String? managerPhone = _stringOrNull(data['managerPhone']);
    final StationManager newManager = StationManager(
      name: managerName ?? station.displayName ?? '',
      phone: managerPhone ?? station.phoneNumber,
    );
    final List<StationManager> updatedManagers =
        List<StationManager>.from(station.managers);
    if (newManager.name.isNotEmpty &&
        !updatedManagers.any(
          (StationManager m) => StationManager.isDuplicate(newManager, m),
        )) {
      updatedManagers.add(newManager);
    }

    final Place updatedPlace = station.copyWith(
      displayName: station.displayName ?? managerName,
      phoneNumber: station.phoneNumber ?? managerPhone,
      managers: updatedManagers,
    );

    // Write back to Hive stationBox
    stationBox.put(updatedPlace.id, updatedPlace.toMap());

    // Also update placesBox if the station exists there
    final Box<dynamic> placesBox = hiveDatabase.placesBox;
    final Place? placesStation = placeFromHiveValue(placesBox.get(stationId));
    if (placesStation != null) {
      placesBox.put(stationId, updatedPlace.toMap());
    }
  }

  /// Returns a trimmed, non-empty string, or `null` for absent/blank values.
  static String? _stringOrNull(Object? value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}