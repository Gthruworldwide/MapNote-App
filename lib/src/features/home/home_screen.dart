import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/place.dart';
import '../../data/remote/auth_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/haptics.dart';
import '../../providers/app_providers.dart';
import '../../services/analytics_service.dart';
import '../../services/app_logger.dart';
import '../../services/location_parser.dart';
import '../../services/lock_gate.dart';
import '../../services/navigation_service.dart';
import '../../widgets/qibla_indicator.dart';
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

/// Dynamic Island expansion state toggles.
  bool _isCompassExpanded = false;

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
    Haptics.light();
    await showModalBottomSheet<void>(
      context: context,
      // Defaults to half-screen; allow full height so the options never
      // overflow on small screens / large text scales.
      isScrollControlled: true,
      showDragHandle: true,
      // Design-system motion: a 250ms ease-out slide-up, or instant when the
      // OS "Reduce Motion" setting is on.
      sheetAnimationStyle: AppMotion.sheetAnimationStyle(context),
      builder: (BuildContext sheetContext) => SheetEntrance(
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                  child: Text(
                    l10n.addLocation,
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
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
    Haptics.light();
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
    Haptics.light();
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
          // Single tap opens the full compass sheet; long press toggles the
          // Dynamic Island slot above the search bar.
          GestureDetector(
            onLongPress: () {
              // Only the expand counts as "opening" the compass, so collapsing
              // the island never logs an event.
              final bool opening = !_isCompassExpanded;
              setState(() {
                _isCompassExpanded = opening;
              });
              if (opening) _trackCompassOpened();
            },
            // The tooltip uses a manual trigger so it never competes for the
            // long press (a default long-press tooltip would swallow it and the
            // island would never expand). Hover on desktop/web still shows it,
            // and the icon keeps the accessible label either way.
            child: Tooltip(
              message: l10n.compassTitle,
              triggerMode: TooltipTriggerMode.manual,
              child: IconButton(
                onPressed: _openOfflineCompass,
                icon: Icon(
                  _isCompassExpanded ? Icons.explore : Icons.explore_outlined,
                  semanticLabel: l10n.compassTitle,
                  color: _isCompassExpanded
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ),
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
      body: _buildBody(placesAsync, l10n),
    );
  }

  /// The block above the saved-places list: compass slot, search, location
  /// status and the AutoMotion / Smart Insights cards.
  ///
  /// It scrolls **with** the list instead of sitting in a fixed header above
  /// it. AutoMotion is on by default, so this stack is tall enough to overflow
  /// a short viewport (an 800×600 window lost 24 px); a fixed header would then
  /// either clip the cards or starve the list of its remaining height.
  Widget _buildHeader(AppLocalizations l10n) {
    return Column(
      children: <Widget>[
        // Dynamic Island expansion slot: long-pressing the compass action in
        // the app bar toggles the live Qibla indicator above the search bar.
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _isCompassExpanded
              ? Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
                  child: QiblaIndicator(
                    locationHub: ref.read(locationHubProvider),
                  ),
                )
              : const SizedBox.shrink(),
        ),
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
      ],
    );
  }

  /// One scroll surface for the header and the saved places.
  ///
  /// A fixed header above an `Expanded` list cannot guarantee room for both:
  /// now that AutoMotion's card is always present the block is taller than a
  /// short viewport. Slivers let the cards scroll away instead of overflowing,
  /// and one [RefreshIndicator] still owns pull-to-refresh in every state.
  Widget _buildBody(
    AsyncValue<List<Place>> placesAsync,
    AppLocalizations l10n,
  ) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(child: _buildHeader(l10n)),
          ..._buildPlaceSlivers(placesAsync, l10n),
        ],
      ),
    );
  }

  /// The saved-places half of the scroll view: a status state or the list.
  List<Widget> _buildPlaceSlivers(
    AsyncValue<List<Place>> placesAsync,
    AppLocalizations l10n,
  ) {
    return placesAsync.when(
      loading: () => const <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (Object error, StackTrace stackTrace) => <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: _MessageContent(
            icon: Icons.error_outline,
            title: l10n.errorGeneric,
            message: '$error',
          ),
        ),
      ],
      data: (List<Place> allPlaces) {
        // Hidden places live only in the Settings → Hidden Vault.
        final List<Place> places = allPlaces
            .where((Place place) => !place.isHidden)
            .toList();

        if (places.isEmpty && _query.isEmpty) {
          return <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: _MessageContent(
                icon: Icons.place_outlined,
                title: l10n.emptyPlacesTitle,
                message: l10n.emptyPlacesMessage,
              ),
            ),
          ];
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
          return <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: _MessageContent(
                icon: Icons.search_off,
                title: l10n.noSearchResults,
              ),
            ),
          ];
        }

        return <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            sliver: SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                final Place place = filtered[index];
                // Staggered fade + rise so the list settles in instead of
                // snapping into place.
                return StaggeredReveal(
                  index: index,
                  child: PlaceCard(
                    place: place,
                    onTap: () => _openPlace(context, place),
                    onNavigate: () => _navigateToPlace(place),
                    onLongPress: () => _showPlaceActions(place),
                  ),
                );
              },
            ),
          ),
        ];
      },
    );
  }

  /// Backs up local data once a session is available, deferred out of build so
  /// no provider state is modified while the widget tree is building.
  ///
  /// Automatic, not user-initiated: this runs on every launch, so it must not
  /// re-establish the Google session — the platform call behind that is
  /// allowed to raise the Credential Manager chooser, which would steal the
  /// focus right back off the Home screen the user just opened.
  void _scheduleSyncOnOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(syncControllerProvider.notifier).syncNow();
    });
  }

  /// Pull-to-refresh performs a sync, then the places list is reloaded.
  ///
  /// User-initiated: the user asked for fresh data, so re-establishing the
  /// session here is expected.
  ///
  /// The Smart Insights card is derived from the **health log**, not from the
  /// places list, so `syncNow`'s `placesProvider` reload alone is not enough:
  /// when the download changes nothing the list still re-emits, but a stale
  /// "A sync didn't finish" banner would only be re-evaluated if the agent runs
  /// again. Re-running it here makes the recovery visible on the same pull that
  /// fixed it.
  Future<void> _refresh() async {
    await ref
        .read(syncControllerProvider.notifier)
        .syncNow(userInitiated: true);
    if (!mounted) return;
    unawaited(ref.read(agentProvider.notifier).refresh());
  }

  /// Records that the Qibla compass became visible to the user. Fired by both
  /// entry points (the Dynamic Island expansion and the full sheet).
  void _trackCompassOpened() {
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .logEvent(AnalyticsEvents.qiblaCompassOpened),
    );
  }

  /// Opens the offline compass: a full sheet with the live Qibla indicator,
  /// which fuses the magnetometer heading with the GPS position.
  Future<void> _openOfflineCompass() async {
    Haptics.light();
    _trackCompassOpened();
    // The Dynamic Island slot above the search bar renders its own
    // QiblaIndicator. Mounting this sheet on top would leave both alive at once
    // — two magnetometer streams and two GPS subscriptions — so collapse the
    // slot for the sheet's lifetime and restore it afterwards. That keeps
    // exactly one live sensor subscription at any time.
    final bool wasExpanded = _isCompassExpanded;
    if (wasExpanded) {
      setState(() => _isCompassExpanded = false);
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                AppLocalizations.of(sheetContext).compassTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              QiblaIndicator(locationHub: ref.read(locationHubProvider)),
            ],
          ),
        ),
      ),
    );
    if (!mounted || !wasExpanded) return;
    setState(() => _isCompassExpanded = true);
  }
}

/// Centered icon + text state used by the list's empty, no-results and error
/// slivers.
///
/// It paints only the content: the surrounding [CustomScrollView] already
/// provides the scrollable surface (and the pull-to-refresh gesture), so
/// nesting another scrollable here would swallow the drag.
class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.20),
                ),
              ),
              child: Icon(
                icon,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
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
    );
  }
}
