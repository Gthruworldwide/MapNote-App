import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/place.dart';
import '../../data/remote/auth_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../../services/app_logger.dart';
import '../../services/location_parser.dart';
import '../../services/lock_gate.dart';
import '../../services/navigation_service.dart';
import '../add_place/add_place_screen.dart';
import '../place_detail/place_detail_screen.dart';
import '../settings/settings_screen.dart';
import 'widgets/auto_motion_card.dart';
import 'widgets/location_status_chip.dart';
import 'widgets/place_actions_sheet.dart';
import 'widgets/place_card.dart';
import 'widgets/qr_code_dialog.dart';
import 'widgets/smart_insights_card.dart';

/// The main screen: search, list, add-location menu, sync + settings actions.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const LocationParser _parser = LocationParser();

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Guards the one-time "sync on open" check for a cached session.
  bool _checkedInitialSession = false;

  @override
  void initState() {
    super.initState();
    // Measure time-to-first-frame for the primary screen.
    final Stopwatch stopwatch = Stopwatch()..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appHealthLoggerProvider).logUiLatency('home', stopwatch.elapsed);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAddPlace({
    double? latitude,
    double? longitude,
    String? name,
    LocationEntryMode? mode,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddPlaceScreen(
          initialLatitude: latitude,
          initialLongitude: longitude,
          initialName: name,
          initialMode: mode,
        ),
      ),
    );
  }

  /// Opens the "Add location" bottom sheet with the three capture options.
  Future<void> _showAddLocationOptions() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      // Defaults to half-screen; allow full height so the options never
      // overflow on small screens / large text scales.
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Text(
                  l10n.addLocation,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.my_location),
                title: Text(l10n.addCurrentLocation),
                subtitle: Text(l10n.addCurrentLocationSubtitle),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openAddPlace(mode: LocationEntryMode.gps);
                },
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: Text(l10n.aiSmartPaste),
                subtitle: Text(l10n.aiSmartPasteSubtitle),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handleSmartPaste();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: Text(l10n.enterCoordinates),
                subtitle: Text(l10n.enterCoordinatesSubtitle),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openAddPlace(mode: LocationEntryMode.manual);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Reads the clipboard, parses a map link / raw coordinates and pre-fills the
  /// Add Location form.
  Future<void> _handleSmartPaste() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    String text = '';
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text?.trim() ?? '';
    } catch (_) {
      text = '';
    }

    ParsedLocation? parsed;
    if (text.isNotEmpty) {
      parsed = _parser.parse(text);
      if (parsed == null && _parser.looksLikeShortMapLink(text)) {
        parsed = await _parser.resolveShortLink(text);
      }
    }

    if (!mounted) return;
    if (parsed == null) {
      AppLogger.log(
        category: 'LOCATION_PARSER',
        message: 'Failed to parse clipboard location',
        error: '"$text" did not match the maps/regex patterns',
        level: LogLevel.warning,
      );
      ref
          .read(appHealthLoggerProvider)
          .logParseFailure(
            source: 'clipboard',
            shortLink: text.isNotEmpty && _parser.looksLikeShortMapLink(text),
          );
      messenger.showSnackBar(SnackBar(content: Text(l10n.clipboardNoLocation)));
      return;
    }

    _openAddPlace(
      latitude: parsed.latitude,
      longitude: parsed.longitude,
      name: parsed.name ?? _parser.guessName(text),
    );
  }

  void _openPlace(BuildContext context, Place place) async {
    if (place.isLocked) {
      final bool allowed = await ensureUnlocked(
        ref,
        l10n: AppLocalizations.of(context),
        reason: AppLocalizations.of(context).unlockToContinue,
        messenger: ScaffoldMessenger.of(context),
        allowWhenUnavailable: true,
      );
      if (!allowed || !context.mounted) return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaceDetailScreen(placeId: place.id),
      ),
    );
  }

  Future<void> _navigateToPlace(Place place) async {
    if (place.isLocked) {
      final bool allowed = await ensureUnlocked(
        ref,
        l10n: AppLocalizations.of(context),
        reason: AppLocalizations.of(context).unlockToNavigate,
        messenger: ScaffoldMessenger.of(context),
        allowWhenUnavailable: true,
      );
      if (!allowed) return;
    }
    final NavigationService nav = ref.read(navigationServiceProvider);
    final bool launched = await nav.navigate(place.latitude, place.longitude);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).locationUnavailable),
        ),
      );
    }
  }

  /// Opens the long-press context menu, then shows a QR dialog if requested.
  ///
  /// A locked place encodes its raw coordinates into the QR code, so sharing
  /// one requires identity verification first (same gate as navigate/edit).
  /// Unlocked places are shared directly, without any prompt.
  Future<void> _showPlaceActions(Place place) async {
    final PlaceActionResult? result = await showPlaceActionsSheet(
      context,
      place,
    );
    if (result != PlaceActionResult.shareQr || !mounted) return;

    if (place.isLocked) {
      final bool allowed = await ensureUnlocked(
        ref,
        l10n: AppLocalizations.of(context),
        reason: AppLocalizations.of(context).unlockToShareQr,
        messenger: ScaffoldMessenger.of(context),
        allowWhenUnavailable: true,
      );
      if (!allowed || !mounted) return;
    }

    await showPlaceQrDialog(context, place);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // When a Google session is restored or a new one is signed in, back up the
    // local database automatically ("sync on open").
    ref.listen<AsyncValue<AuthUser?>>(authProvider, (prev, next) {
      if (next.isLoading) return;
      final AuthUser? user = next.value;
      if (user != null && prev?.value == null) {
        _scheduleSyncOnOpen();
      }
    });

    // A cached session is already signed in on the very first frame, so the
    // listener above never sees the null -> user transition. Kick off the
    // "sync on open" once for that case.
    if (!_checkedInitialSession) {
      _checkedInitialSession = true;
      if (ref.read(authProvider).value != null) {
        _scheduleSyncOnOpen();
      }
    }

    final AsyncValue<List<Place>> placesAsync = ref.watch(placesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.placesTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.addLocation,
            onPressed: _showAddLocationOptions,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: l10n.settingsTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (String value) {
                setState(() => _query = value.trim().toLowerCase());
              },
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),
          const LocationStatusChip(),
          // Keep the card on screen while AutoMotion is enabled, or while the
          // day already has recorded motion, so paused users can still see
          // today's totals from the Paused badge.
          if (ref.watch(autoMotionEnabledProvider) ||
              ref.watch(autoMotionControllerProvider).totalKm > 0)
            const AutoMotionCard(),
          if (ref.watch(smartInsightsEnabledProvider))
            const SmartInsightsCard(),
          Expanded(child: _buildBody(placesAsync, l10n)),
        ],
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<List<Place>> placesAsync,
    AppLocalizations l10n,
  ) {
    return placesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => _MessageView(
        icon: Icons.error_outline,
        title: l10n.errorGeneric,
        message: '$error',
      ),
      data: (List<Place> allPlaces) {
        // Hidden places live only in the Settings → Hidden Vault.
        final List<Place> places = allPlaces
            .where((Place place) => !place.isHidden)
            .toList();

        if (places.isEmpty && _query.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: _MessageView(
              icon: Icons.place_outlined,
              title: l10n.emptyPlacesTitle,
              message: l10n.emptyPlacesMessage,
            ),
          );
        }

        final List<Place> filtered = _query.isEmpty
            ? places
            : places
                  .where(
                    (Place p) =>
                        p.name.toLowerCase().contains(_query) ||
                        p.notes.toLowerCase().contains(_query) ||
                        p.plusCode.toLowerCase().contains(_query),
                  )
                  .toList();

        // Pinned places first, then newest → oldest.
        filtered.sort((Place a, Place b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.timestamp.compareTo(a.timestamp);
        });

        if (filtered.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: _MessageView(
              icon: Icons.search_off,
              title: l10n.noSearchResults,
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            itemCount: filtered.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final Place place = filtered[index];
              return PlaceCard(
                place: place,
                onTap: () => _openPlace(context, place),
                onNavigate: () => _navigateToPlace(place),
                onLongPress: () => _showPlaceActions(place),
              );
            },
          ),
        );
      },
    );
  }

  /// Backs up local data once a session is available, deferred out of build so
  /// no provider state is modified while the widget tree is building.
  void _scheduleSyncOnOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(syncControllerProvider.notifier).syncNow();
    });
  }

  /// Pull-to-refresh performs a sync, then the places list is reloaded.
  Future<void> _refresh() =>
      ref.read(syncControllerProvider.notifier).syncNow();
}

/// Centered icon + text state, scrollable so it works inside a
/// [RefreshIndicator].
class _MessageView extends StatelessWidget {
  const _MessageView({required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 56, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (message != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
