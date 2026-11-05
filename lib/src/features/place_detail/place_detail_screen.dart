import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date_formats.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/place.dart';
import '../../data/models/station_manager.dart';
import '../admin/admin_approval_screen.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../../services/lock_gate.dart';
import '../add_place/add_place_screen.dart';
import '../saved_places/domain/usecases/unlock_vault.dart';
import '../saved_places/presentation/providers/saved_places_providers.dart';
import '../../features/home/widgets/nearby_stations_card.dart';
import 'widgets/modern_contact_dialog.dart';
import 'widgets/route_preview_card.dart';

/// Shows a saved location with navigation, copy, edit and delete actions.
class PlaceDetailScreen extends ConsumerWidget {
  const PlaceDetailScreen({super.key, required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<Place>? places = ref.watch(placesProvider).value;

    // Resolve through a helper so `place` stays `final`:
    // Dart preserves a final's non-null promotion inside the edit callback below,
    // which a reassigned local would lose.
    final Place? place = _placeById(places);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.placeDetailsTitle),
        actions: [
          // Edit/Propose Update icon.
          if (place != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.editPlaceTitle,
              onPressed: () => _submitStationUpdate(context, ref, l10n, place),
            ),
        ],
      ),
      body: place == null
          ? _MissingPlace(l10n: l10n)
          : _buildBody(context, ref, l10n, place),
    );
  }

  /// Finds the place matching [placeId] in the loaded list, or null while the
  /// list is still loading / the id no longer exists.
  Place? _placeById(List<Place>? places) {
    if (places == null) return null;
    for (final Place candidate in places) {
      if (candidate.id == placeId) return candidate;
    }
    return null;
  }

  /// Builds the body of the place detail screen.
  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // Interactive, offline route preview: current position → saved place,
        // with the estimated distance. The primary Navigate action sits
        // directly below it.
        RoutePreviewCard(place: place),
        const SizedBox(height: 20),
        NearbyStationsCard(currentPlace: place),
        const SizedBox(height: 20),
        _buildModernContactsSection(context, ref, l10n, place),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  place.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall,
                ),
                if (place.notes.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    place.notes,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  l10n.createdAt(
                    formatDateTime(
                      place.timestamp,
                      Localizations.localeOf(context).toString(),
                    ),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.pin_drop_outlined,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${l10n.latitude}: ${place.latitude.toStringAsFixed(6)} | ${l10n.longitude}: ${place.longitude.toStringAsFixed(6)} | ${l10n.plusCode}: ${place.plusCode}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.copyCoordinates,
                        onPressed: () => _copyCoordinates(context, l10n, place),
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: 0.10,
                          ),
                          foregroundColor: theme.colorScheme.primary,
                        ),
                        icon: const Icon(Icons.copy, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _navigate(context, ref, l10n, place),
          icon: const Icon(Icons.directions),
          label: _PillLabel(text: l10n.navigate),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openInGoogleMaps(context, ref, l10n, place),
                icon: const Icon(Icons.map_outlined),
                label: _PillLabel(text: l10n.openInGoogleMaps),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openInWaze(context, ref, l10n, place),
                icon: const Icon(Icons.near_me_outlined),
                label: _PillLabel(text: l10n.openInWaze),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _shareViaWhatsApp(context, ref, l10n, place),
          icon: const Icon(Icons.chat_outlined),
          label: const Text('مشاركة بيانات المحطة مع سائق عبر WhatsApp'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF25D366),
          ),
        ),
        const SizedBox(height: 32),
        if (ref.watch(biometricVaultEnabledProvider)) ...<Widget>[
          OutlinedButton.icon(
            onPressed: () => _moveToEncryptedVault(context, ref, l10n, place),
            icon: const Icon(Icons.enhanced_encryption_outlined),
            label: _PillLabel(text: l10n.moveToEncryptedVault),
          ),
          const SizedBox(height: 32),
        ],
        Center(
          child: TextButton.icon(
            onPressed: () => _confirmDelete(context, ref, l10n, place),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.delete),
          ),
        ),
      ],
    );
  }

  /// Displays the station's internal contacts (manager/supervisor/support).
  /// No device contacts permission required.
  Widget _buildModernContactsSection(BuildContext context, WidgetRef ref, AppLocalizations l10n, Place place) {
    final theme = Theme.of(context);
    final List<StationManager> managers = place.managers.isNotEmpty
        ? place.managers
        : (place.displayName != null && place.displayName!.isNotEmpty
            ? <StationManager>[
                StationManager(name: place.displayName!, phone: place.phoneNumber ?? ''),
              ]
            : <StationManager>[]);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.contacts_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'جهات الاتصال والمسؤولين',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => _showContactDialog(context, place),
                ),
              ],
            ),
            const Divider(),
            if (managers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () {
                      _showContactDialog(context, place).then(
                        (bool? updated) {
                          if (updated == true && context.mounted) {
                            ref.invalidate(placesProvider);
                          }
                        },
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('+ إضافة / اقتراح جهة اتصال'),
                  ),
                ),
              )
            else
              ...managers.asMap().entries.map((entry) {
                final int index = entry.key;
                final StationManager m = entry.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(m.phone ?? '', style: const TextStyle(fontSize: 13)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.phone_outlined),
                        onPressed: () {
                          _makePhoneCall(m.phone);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () {
                          _removeManager(context, ref, place, index);
                        },
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  /// Opens the modern contact dialog for the given place.
  Future<bool?> _showContactDialog(BuildContext context, Place place) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => ModernContactDialog(place: place),
    );
  }

  /// Starts a phone call for the given manager phone number.
  Future<void> _makePhoneCall(String? phone) async {
    final String cleaned = (phone ?? '').trim();
    if (cleaned.isEmpty) {
      return;
    }
    final Uri uri = Uri(scheme: 'tel', path: cleaned);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// Removes a manager from the station contact list. Admins apply the
  /// removal locally + to Firestore immediately; non-admins never touch local
  /// data and surface the admin approval gate instead.
  Future<void> _removeManager(BuildContext context, WidgetRef ref, Place place, int index) async {
    if (place.managers.length <= index) {
      return;
    }
    final StationManager removedManager = place.managers[index];
    final List<StationManager> remaining = List<StationManager>.from(place.managers)..removeAt(index);

    final Place updatedPlace = remaining.isNotEmpty
        ? place.copyWith(
            displayName: remaining.first.name,
            phoneNumber: remaining.first.phone,
            managers: remaining,
          )
        : place.copyWith(displayName: '', phoneNumber: '', managers: remaining);

    final ProviderContainer container = ProviderScope.containerOf(context);
    final bool isAdmin = container.read(adminSession);

    if (isAdmin) {
      final hiveDb = ref.read(hiveDatabaseProvider);
      final placeData = updatedPlace.toMap();
      await hiveDb.placesBox.put(place.id, placeData);
      await hiveDb.stationBox.put(place.id, placeData);
      await FirebaseFirestore.instance.collection('master_stations').doc(place.id).set({
        'stationId': place.id,
        'managerName': updatedPlace.displayName,
        'managerPhone': updatedPlace.phoneNumber,
        'status': 'approved',
        'timestamp': FieldValue.serverTimestamp(),
      });
      ref.invalidate(placesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المسؤول بنجاح')),
        );
      }
    } else {
      // Non-admin: route the removal through the admin approval gate without
      // touching local Hive.
      await FirebaseFirestore.instance.collection('pending_updates').add({
        'stationId': place.id,
        'stationName': place.name,
        'type': 'manager_removal',
        'managerName': removedManager.name,
        'managerPhone': removedManager.phone ?? '',
        'managerRole': 'manager',
        'proposedData': {
          'managerName': removedManager.name,
          'managerPhone': removedManager.phone ?? '',
          'managerRole': 'manager',
        },
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الاقتراح للأدمن للموافقة')),
        );
      }
    }
  }

  /// Moves the place into the AES-256 encrypted vault.
  Future<void> _moveToEncryptedVault(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    final VaultUnlockResult result = await ref
        .read(vaultPlacesProvider.notifier)
        .unlock(reason: l10n.unlockToMoveToEncryptedVault);
    if (!context.mounted) return;

    switch (result) {
      case VaultUnlockResult.denied:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.authenticationFailed)),
        );
        return;
      case VaultUnlockResult.pinRejected:
      case VaultUnlockResult.pinLockedOut:
        // The biometric path never produces these.
        return;
      case VaultUnlockResult.unlocked:
      case VaultUnlockResult.unlockedUnverified:
        break;
    }
    if (result == VaultUnlockResult.unlockedUnverified) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.noDeviceSecurityWarning)),
      );
    }

    await ref.read(vaultPlacesProvider.notifier).moveIn(place);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.moveToEncryptedVaultDone)),
    );
    // The place is no longer in the plain list, so leave its detail screen.
    navigator.pop();
  }

  /// Copies the place coordinates and plus code to the clipboard.
  Future<void> _copyCoordinates(
    BuildContext context,
    AppLocalizations l10n,
    Place place,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    Haptics.light();
    // Include the Plus Code so the pasted text works everywhere, even in apps
    // that only understand Open Location Codes.
    final String text =
        '${place.formattedCoordinates}\\n${l10n.plusCode}: ${place.plusCode}';
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(l10n.coordinatesCopied)));
  }

  /// Navigates to the place coordinates.
  Future<void> _navigate(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (place.isLocked) {
      final bool allowed = await ensureUnlocked(
        ref,
        l10n: l10n,
        reason: l10n.unlockToNavigate,
        messenger: messenger,
        allowWhenUnavailable: true,
      );
      if (!allowed) return;
    }
    Haptics.light();
    final bool launched = await ref
        .read(navigationServiceProvider)
        .navigate(place.latitude, place.longitude);
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationUnavailable)));
    }
  }

  /// Opens the place in Google Maps.
  Future<void> _openInGoogleMaps(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    if (place.isLocked) {
      final bool allowed = await ensureUnlocked(
        ref,
        l10n: l10n,
        reason: l10n.unlockToNavigate,
        messenger: ScaffoldMessenger.of(context),
        allowWhenUnavailable: true,
      );
      if (!allowed) return;
    }
    Haptics.light();
    await ref
        .read(navigationServiceProvider)
        .openInGoogleMaps(place.latitude, place.longitude);
  }

  /// Opens the place in Waze.
  Future<void> _openInWaze(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    if (place.isLocked) {
      final bool allowed = await ensureUnlocked(
        ref,
        l10n: l10n,
        reason: l10n.unlockToNavigate,
        messenger: ScaffoldMessenger.of(context),
        allowWhenUnavailable: true,
      );
      if (!allowed) return;
    }
    Haptics.light();
    await ref
        .read(navigationServiceProvider)
        .navigateWithWaze(place.latitude, place.longitude);
  }

  /// Shares station name, ID, and Google Maps location link via WhatsApp.
  /// Does NOT include manager names, phone numbers, or other personal details.
  Future<void> _shareViaWhatsApp(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    final String googleMapsLink =
        'https://www.google.com/maps/search/?api=1&query=${place.latitude},${place.longitude}';

    final String message = '''⛽ *بيانات محطة الوقود - Manex*
📍 *المحطة:* ${place.name} (${place.id})
🗺️ *رابط الموقع (Google Maps):*
$googleMapsLink''';

    final Uri whatsappUri = Uri.parse(
      'whatsapp://send?text=${Uri.encodeComponent(message)}',
    );

    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri);
    } else {
      // Fallback to web WhatsApp
      final Uri webUri = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent(message)}',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  /// Confirms place deletion.
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    Haptics.light();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.deletePlaceTitle),
        content: Text(l10n.deletePlaceMessage(place.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    await ref.read(placesProvider.notifier).delete(place.id);
    messenger.showSnackBar(SnackBar(content: Text(l10n.placeDeleted)));
    if (context.mounted) navigator.pop();
  }

  /// Submits a station update proposal to the admin channel.
  Future<void> _submitStationUpdate(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Place place,
  ) async {
    Haptics.light();

    // 1️⃣ Check that this is a default station (isCustom == false) and isDefault == true.
    // Custom user places should never show this button (kept 100% private).
    if (place.isCustom == true) {
      // Should not reach here, but guard anyway.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom places are private and cannot be submitted.')),
      );
      return;
    }

    if (place.isDefault != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only default stations can be submitted for update.')),
      );
      return;
    }

    // 2️⃣ Open the AddPlaceScreen pre-filled with the current place data,
    //     allowing the user to make/propose changes.
    //     In a full implementation, this would capture before/after state and
    //     call StationUpdateService.submitStationUpdate().
    //     For this demo, we navigate to the edit screen.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddPlaceScreen(place: place),
      ),
    );
  }
}

/// A simple data model for a device contact, used by the contact picker.
class ContactModel {
  /// The contact's unique identifier (raw contact ID).
  final String id;

  /// The contact's display name.
  final String name;

  /// The contact's primary phone number.
  final String phone;

  ContactModel({
    required this.id,
    required this.name,
    required this.phone,
  });
}

/// A widget that displays when no place is found.
class _MissingPlace extends StatelessWidget {
  const _MissingPlace({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => const Center(child: Text('Error'));
}

/// A pill-button label that shrinks to fit rather than clipping or overflowing
/// when the system accessibility font size is turned all the way up.
class _PillLabel extends StatelessWidget {
  const _PillLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(text, maxLines: 1),
    );
  }
}