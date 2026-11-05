import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routenote/src/data/local/hive_place_codec.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/firebase_station_service.dart';
import 'package:routenote/src/services/app_logger.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';

// Admin PIN code default: 1991
const String _adminPinCode = '1991';

// Admin session notifier
class AdminSessionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setSession(bool value) => state = value;
}

final adminSession = NotifierProvider<AdminSessionNotifier, bool>(
  AdminSessionNotifier.new,
);

// PIN value notifier
class AdminPinNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setPin(String value) => state = value;
}

final adminPin = NotifierProvider<AdminPinNotifier, String>(
  AdminPinNotifier.new,
);

// Pending updates stream - memoized outside widget to prevent infinite rebuilds
final pendingUpdatesStreamProvider = StreamProvider.autoDispose<QuerySnapshot>((ref) {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  return db
      .collection('pending_updates')
      .where('status', isEqualTo: 'pending')
      .snapshots();
});

// Verify PIN
bool verifyAdminPin(String enteredPin) => enteredPin == _adminPinCode;

/// Normalises a raw `pending_updates` `type` into the admin screen's internal
/// proposal kind.
///
/// Unknown or legacy values degrade to the generic `update_manager` kind, and a
/// missing type degrades to the same generic kind — never to a crash.
String normalizeProposalType(String? updateType) {
  if (updateType == 'new_station') return 'new_station';
  if (updateType == 'manager_removal') return 'manager_removal';
  return 'update_manager';
}

/// All of a `pending_updates` document that the admin card needs, resolved
/// defensively from the two shapes the app writes (`proposedData` for contact
/// updates, root fields for new-station proposals) and the legacy `data` alias.
@immutable
class ProposalFields {
  const ProposalFields({
    required this.stationName,
    required this.managerName,
    required this.managerPhone,
    required this.managerRole,
    required this.type,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  final String stationName;
  final String managerName;
  final String managerPhone;
  final String managerRole;
  final String type;
  final String city;
  final double? latitude;
  final double? longitude;

  /// True when the document carries no usable identifying information at all.
  bool get isEmpty =>
      stationName.isEmpty &&
      managerName.isEmpty &&
      managerPhone.isEmpty &&
      type != 'new_station';
}

String _str(Object? value) => value?.toString().trim() ?? '';

/// Picks the first non-empty trimmed string from [candidates].
String _firstNonEmpty(Iterable<Object?> candidates) {
  for (final Object? candidate in candidates) {
    final String text = _str(candidate);
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// Extracts a latitude/longitude pair, or `(null, null)` when unusable.
(double?, double?) _coords(Map<String, dynamic> root, Map<String, dynamic> nested) {
  final double? lat = (root['latitude'] as num?)?.toDouble() ??
      (nested['latitude'] as num?)?.toDouble();
  final double? lon = (root['longitude'] as num?)?.toDouble() ??
      (nested['longitude'] as num?)?.toDouble();
  return (lat, lon);
}

/// Resolves the renderable fields of a `pending_updates` [raw] document.
///
/// Station identity favours root-level names (a new-station proposal names the
/// station at the root), manager/contact details favour the nested
/// `proposedData` (a contact update nests the proposed contact there), and both
/// accept the legacy `data` alias plus a wide set of field spellings. Unknown or
/// legacy type values degrade through [normalizeProposalType]; a missing type
/// becomes the generic `update_manager` kind, never a crash.
ProposalFields resolveProposalFields(Map<String, dynamic>? raw) {
  final Map<String, dynamic> root = raw ?? const <String, dynamic>{};
  final Map<String, dynamic> nested = root['proposedData'] is Map<String, dynamic>
      ? Map<String, dynamic>.from(root['proposedData'] as Map<String, dynamic>)
      : root['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(root['data'] as Map<String, dynamic>)
          : const <String, dynamic>{};

  final String type = normalizeProposalType(
    _firstNonEmpty(<Object?>[root['type'], nested['type']]).isEmpty
        ? null
        : _firstNonEmpty(<Object?>[root['type'], nested['type']]),
  );
  final (double? lat, double? lon) = _coords(root, nested);

  return ProposalFields(
    stationName: _firstNonEmpty(<Object?>[
      root['stationName'],
      root['name'],
      nested['stationName'],
      nested['name'],
    ]),
    managerName: _firstNonEmpty(<Object?>[
      nested['managerName'],
      nested['displayName'],
      nested['name'],
      root['managerName'],
      root['displayName'],
      root['name'],
    ]),
    managerPhone: _firstNonEmpty(<Object?>[
      nested['managerPhone'],
      nested['phoneNumber'],
      nested['phone'],
      root['managerPhone'],
      root['phoneNumber'],
      root['phone'],
    ]),
    managerRole: _firstNonEmpty(<Object?>[
      nested['managerRole'],
      root['managerRole'],
    ]),
    type: type,
    city: _firstNonEmpty(<Object?>[root['city'], nested['city']]),
    latitude: lat,
    longitude: lon,
  );
}

/// Localized label for a manager role key stored in a proposal.
String managerRoleLabel(AppLocalizations l10n, String role) {
  switch (role) {
    case 'supervisor':
      return l10n.roleSupervisor;
    case 'support':
      return l10n.roleSupport;
    case 'staff':
      return l10n.roleStaff;
    case 'manager':
    default:
      return role.isEmpty ? l10n.roleManager : l10n.roleManager;
  }
}

// ---------------------------------------------------------------------------
// Admin Approval Screen
// ---------------------------------------------------------------------------
/// Screen allowing admin to review and approve/reject station update proposals
/// from the `pending_updates` Firestore collection. Access is protected by an
/// Admin PIN.
class AdminApprovalScreen extends ConsumerWidget {
  const AdminApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // AppLocalizations available via the app root.
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Check admin session — if not unlocked, show PIN entry.
    final isAdmin = ref.watch(adminSession);
    if (!isAdmin) {
      return _buildPinEntry(context, ref, localizations, theme);
    }

    // Admin unlocked — show pending proposals.
    final updates = ref.watch(pendingUpdatesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.adminApprovalTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: localizations.logout,
            onPressed: () {
              ref.read(adminSession.notifier).setSession(false);
            },
          ),
        ],
      ),
      body: updates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${localizations.errorGeneric}: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(pendingUpdatesStreamProvider),
                child: Text(localizations.retry),
              ),
            ],
          ),
        ),
        data: (snapshot) {
          final docs = snapshot.docs.toList();
          // Sort in-memory by timestamp descending. Every field access is
          // null-safe so a legacy / incomplete Firestore document can never
          // crash the whole screen during sorting.
          docs.sort((a, b) {
            final aData =
                (a.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
            final bData =
                (b.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
            final aTimestamp = aData['timestamp'] as Timestamp?;
            final bTimestamp = bData['timestamp'] as Timestamp?;
            if (aTimestamp == null && bTimestamp == null) return 0;
            if (aTimestamp == null) return 1;
            if (bTimestamp == null) return -1;
            return bTimestamp.compareTo(aTimestamp);
          });
          if (docs.isEmpty) {
            return Center(
              child: Text(localizations.noPendingUpdates),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (BuildContext context, int index) {
              return _buildProposalCard(context, ref, docs[index]);
            },
          );
        },
      ),
    );
  }

  /// Builds a single proposal card. Fields are resolved defensively and the
  /// body is wrapped in a try/catch, so one malformed or legacy Firestore
  /// document can never crash the whole admin screen (element-level isolation).
  Card _buildProposalCard(
    BuildContext context,
    WidgetRef ref,
    DocumentSnapshot doc,
  ) {
    final AppLocalizations localizations = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String docId = doc.id;

    try {
      final Map<String, dynamic> raw =
          (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final ProposalFields fields = resolveProposalFields(raw);
      if (fields.isEmpty) {
        return _buildFallbackProposalCard(
          context,
          localizations,
          docId,
          localizations.incompleteProposal,
        );
      }

      final String stationId = _str(raw['stationId']);
      final String submittedBy = _str(raw['submittedBy']);
      final Timestamp? timestamp = raw['timestamp'] as Timestamp?;

      // Decode the local station record: the box stores `Place.toMap()` maps, so
      // reading it as a `Place` threw `NoSuchMethodError` and every real proposal
      // silently degraded to the fallback card.
      final Place? station = stationId.isNotEmpty
          ? placeFromHiveValue(
              ref.read(hiveDatabaseProvider).stationBox.get(stationId),
            )
          : null;
      final String currentManagerName =
          station?.displayName ?? localizations.unknownManager;
      final String currentManagerPhone =
          station?.phoneNumber ?? localizations.unknownPhone;

      final String titleStation = fields.stationName.isNotEmpty
          ? fields.stationName
          : localizations.unknownStation;
      final String managerName = fields.managerName.isNotEmpty
          ? fields.managerName
          : localizations.unknownManager;
      final String managerPhone = fields.managerPhone.isNotEmpty
          ? fields.managerPhone
          : localizations.unknownPhone;
      final String role = managerRoleLabel(localizations, fields.managerRole);

      final Map<String, dynamic> proposedData = <String, dynamic>{
        'managerName': fields.managerName,
        'managerPhone': fields.managerPhone,
        'managerRole': fields.managerRole,
      };
      final Map<String, dynamic> newStationData = <String, dynamic>{
        'name': fields.stationName,
        'latitude': fields.latitude,
        'longitude': fields.longitude,
        'city': fields.city,
      };

      final String submittedAt = timestamp != null
          ? '${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}'
          : '';

      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                fields.type == 'new_station'
                    ? localizations.newStationTitle(titleStation)
                    : titleStation,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _infoRow(
                Icons.person_outline,
                localizations.currentManager(currentManagerName),
                theme,
              ),
              const SizedBox(height: 4),
              _infoRow(
                Icons.phone_outlined,
                localizations.currentManagerPhone(currentManagerPhone),
                theme,
              ),
              if (fields.type == 'new_station') ...<Widget>[
                const Divider(height: 24),
                _infoRow(
                  Icons.location_on_outlined,
                  localizations.proposalLocation(
                    fields.latitude?.toString() ?? '-',
                    fields.longitude?.toString() ?? '-',
                  ),
                  theme,
                ),
                const SizedBox(height: 4),
                _infoRow(
                  Icons.location_city_outlined,
                  localizations.proposalCity(
                    fields.city.isNotEmpty ? fields.city : '-',
                  ),
                  theme,
                ),
              ] else ...<Widget>[
                const Divider(height: 24),
                _infoRow(
                  Icons.edit_outlined,
                  localizations.proposedManager(managerName),
                  theme,
                ),
                const SizedBox(height: 4),
                _infoRow(
                  Icons.phone_outlined,
                  localizations.proposedManagerPhone(managerPhone),
                  theme,
                ),
                const SizedBox(height: 4),
                _infoRow(
                  Icons.badge_outlined,
                  localizations.proposalRole(role),
                  theme,
                ),
              ],
              const Divider(height: 24),
              _infoRow(
                Icons.access_time_outlined,
                localizations.submittedBy(submittedBy),
                theme,
              ),
              const SizedBox(height: 4),
              _infoRow(
                Icons.schedule_outlined,
                localizations.submittedAt(submittedAt),
                theme,
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (fields.type == 'manager_removal') {
                          _handleRemoveManager(
                            context,
                            ref,
                            docId,
                            stationId.isEmpty ? null : stationId,
                            proposedData,
                          );
                        } else {
                          _handleApprove(
                            context,
                            ref,
                            docId,
                            stationId.isEmpty ? null : stationId,
                            proposedData,
                            fields.type,
                            newStationData,
                          );
                        }
                      },
                      icon: const Icon(Icons.check_circle),
                      label: Text(localizations.approve),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleReject(context, ref, docId),
                      icon: const Icon(Icons.cancel),
                      label: Text(localizations.reject),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      // Safe fallback: a bad document must not take the whole screen down.
      AppLogger.log(
        category: 'ADMIN',
        message: 'Failed to render proposal $docId: $e',
      );
      return _buildFallbackProposalCard(
        context,
        localizations,
        docId,
        localizations.incompleteProposal,
      );
    }
  }

  Widget _infoRow(IconData icon, String text, ThemeData theme) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Expanded(
          child: Text(text, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }

  /// Safe fallback card for proposals whose documents are incomplete or
  /// corrupted. Rendered in place of the broken card without failing the list.
  Card _buildFallbackProposalCard(
    BuildContext context,
    AppLocalizations localizations,
    String docId,
    String error,
  ) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        title: Text(
          localizations.incompleteProposal,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          localizations.proposalIdLabel(docId),
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          color: theme.colorScheme.error,
          onPressed: () => _dismissProposal(context, docId, localizations),
        ),
      ),
    );
  }

  /// Deletes an incomplete/corrupted pending proposal document so the admin
  /// can clean it up directly from the fallback card.
  Future<void> _dismissProposal(
    BuildContext context,
    String docId,
    AppLocalizations localizations,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('pending_updates')
          .doc(docId)
          .delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.proposalDismissed)),
        );
      }
    } catch (e) {
      AppLogger.log(
        category: 'ADMIN',
        message: 'Failed to dismiss proposal: $e',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.dismissFailed)),
        );
      }
    }
  }

  /// PIN entry screen with simple PIN verification.
  Widget _buildPinEntry(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations localizations,
    ThemeData theme,
  ) {
    final controller = TextEditingController();

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security_outlined, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              Text(
                localizations.adminPinRequired,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: localizations.pin,
                  border: OutlineInputBorder(),
                  hintText: localizations.adminPinHint,
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (controller.text.length == 4) {
                    if (verifyAdminPin(controller.text)) {
                      ref.read(adminSession.notifier).setSession(true);
                    } else {
                      _showPinError(context, localizations);
                    }
                  }
                },
                child: Text(localizations.unlock),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  controller.clear();
                },
                child: Text(localizations.resetPin),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show PIN error dialog.
  void _showPinError(BuildContext context, AppLocalizations localizations) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.incorrectPin),
        content: Text(localizations.incorrectPinAttempt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(localizations.ok),
          ),
        ],
      ),
    );
  }

  /// Handle manager removal approval - called from widget build.
  Future<void> _handleRemoveManager(
    BuildContext context,
    WidgetRef ref,
    String docId,
    String? stationId,
    Map<String, dynamic>? proposedData,
  ) async {
    final AppLocalizations localizations = AppLocalizations.of(context);
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      final hiveDb = ref.read(hiveDatabaseProvider);
      final stationService = FirebaseStationService(hiveDatabase: hiveDb);

      if (stationId == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.missingStation)),
        );
        return;
      }

      // Mark proposal status to 'approved' in pending_updates.
      await db.collection('pending_updates').doc(docId).update({
        'status': 'approved',
      });

      // Remove the manager from the local Hive station box + Firestore master.
      await stationService.removeManagerFromMaster(
        stationId: stationId,
        managerName: proposedData?['managerName']?.toString() ?? '',
        managerPhone: proposedData?['managerPhone']?.toString() ?? '',
      );

      // Invalidate placesProvider to refresh UI
      ref.invalidate(placesProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.proposalApproved)),
      );
    } catch (e) {
      AppLogger.log(
        category: 'ADMIN',
        message: 'Failed to remove manager: $e',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.approveFailed),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Handle approve proposal - called from widget build.
  Future<void> _handleApprove(
    BuildContext context,
    WidgetRef ref,
    String docId,
    String? stationId,
    Map<String, dynamic>? proposedData,
    String type,
    Map<String, dynamic> data,
  ) async {
    final AppLocalizations localizations = AppLocalizations.of(context);
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      final hiveDb = ref.read(hiveDatabaseProvider);
      final stationService = FirebaseStationService(hiveDatabase: hiveDb);

      if (type == 'manager_removal') {
        await _handleRemoveManager(context, ref, docId, stationId, proposedData);
        return;
      }

      if (type == 'new_station') {
        // Handle new station approval
        final name = data['name']?.toString() ?? '';
        final latitude = (data['latitude'] as num?)?.toDouble() ?? 0;
        final longitude = (data['longitude'] as num?)?.toDouble() ?? 0;
        final city = data['city']?.toString() ?? '';
        final submittedBy = data['submittedBy']?.toString() ?? 'unknown';

        if (name.isEmpty) {
          // Incomplete proposal — never write garbage to master stations.
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.incompleteNewStation)),
          );
          return;
        }

        await stationService.approveNewStation(
          docId: docId,
          name: name,
          latitude: latitude,
          longitude: longitude,
          city: city,
          submittedBy: submittedBy,
        );

        // Invalidate placesProvider to refresh UI
        ref.invalidate(placesProvider);

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.newStationApproved)),
        );
      } else {
        // Handle update manager approval
        if (stationId == null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.missingStation)),
          );
          return;
        }

        // Update proposal status to 'approved' in pending_updates.
        await db.collection('pending_updates').doc(docId).update({
          'status': 'approved',
        });

        // Apply update to master_stations and Hive.
        await stationService.applyMasterStationUpdate(
          stationId: stationId,
          updateData: proposedData ?? <String, dynamic>{},
        );

        // Invalidate placesProvider to refresh UI
        ref.invalidate(placesProvider);

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.proposalApproved)),
        );
      }
    } catch (e) {
      AppLogger.log(
        category: 'ADMIN',
        message: 'Failed to approve proposal: $e',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.approveFailed),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Handle reject proposal - called from widget build.
  Future<void> _handleReject(
    BuildContext context,
    WidgetRef ref,
    String docId,
  ) async {
    final AppLocalizations localizations = AppLocalizations.of(context);
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;

      // Update proposal status to 'rejected' in pending_updates.
      await db.collection('pending_updates').doc(docId).update({
        'status': 'rejected',
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.proposalRejected)),
      );
    } catch (e) {
      AppLogger.log(
        category: 'ADMIN',
        message: 'Failed to reject proposal: $e',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.rejectFailed),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}
