import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/generated/app_localizations.dart';
import 'src/core/navigation/app_navigator.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/utils/haptics.dart';
import 'src/data/models/place.dart';
import 'src/features/add_place/add_place_screen.dart';
import 'src/features/home/home_screen.dart';
import 'src/features/splash/brand_splash.dart';
import 'src/providers/app_providers.dart';
import 'src/services/app_health_logger.dart';
import 'src/services/app_logger.dart';
import 'src/services/dynamic_icon_service.dart';
import 'src/services/home_shortcut_service.dart';
import 'src/services/location_parser.dart';
import 'src/services/lock_gate.dart';
import 'src/services/share_intent_service.dart';

/// Root widget of MapNote.
///
/// Watches the app lifecycle and triggers a silent, throttled Drive sync
/// whenever the app returns to the foreground (sync on resume). It also
/// listens for text/links shared into MapNote from other apps, and offers to
/// import a Plus Code it finds on the clipboard.
class MapNoteApp extends ConsumerStatefulWidget {
  const MapNoteApp({super.key});

  @override
  ConsumerState<MapNoteApp> createState() => _MapNoteAppState();
}

class _MapNoteAppState extends ConsumerState<MapNoteApp>
    with WidgetsBindingObserver {
  static const LocationParser _parser = LocationParser();

  StreamSubscription<String>? _shareSubscription;
  StreamSubscription<String>? _shortcutSubscription;

  /// The last Plus Code the clipboard import was offered for, so a code the
  /// user ignored is not offered again on every resume.
  String? _lastOfferedPlusCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(appHealthLoggerProvider).log(HealthEventType.appLaunch);
    _listenForSharedLocations();
    _listenForShortcuts();
    _listenForThemeIconChanges();
    // A Plus Code can already be on the clipboard at cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _shortcutSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final AppHealthLogger health = ref.read(appHealthLoggerProvider);
    if (state == AppLifecycleState.resumed) {
      health.log(HealthEventType.appResume);
      // Sync on resume is always silent: the user never sees a dialog, and a
      // signed-out device simply skips (SyncOutcome.skippedNotSignedIn).
      ref.read(syncControllerProvider.notifier).syncSilently();
      // The user may have toggled GPS or granted permission in the system
      // settings while the app was backgrounded.
      ref.read(locationStatusProvider.notifier).refresh();
      // Retry the native tracking foreground service now that MapNote is
      // visible: Android refuses foreground-service starts from the background,
      // so an earlier attempt may have been dropped.
      resyncTrackingForegroundService(ref);
      // They may also have copied a Plus Code from Maps or a chat app.
      _checkClipboard();
    } else if (state == AppLifecycleState.paused) {
      health.log(HealthEventType.appPause);
    }
  }

  @override
  void didChangePlatformBrightness() {
    // Fires when the OS flips dark mode; only matters while ThemeMode.system is
    // active, but recomputing in every mode is harmless (apply() no-ops when the
    // active icon already matches).
    _syncLauncherIcon();
  }

  /// Keeps the launcher icon variant in step with the effective theme: manual
  /// light/dark/system changes from Settings (listenManual) plus OS dark-mode
  /// flips while in system mode (didChangePlatformBrightness).
  void _listenForThemeIconChanges() {
    ref.listenManual<ThemeMode>(
      themeModeProvider,
      (ThemeMode? previous, ThemeMode next) => _syncLauncherIcon(),
    );
    // Sync once after the first frame so the icon matches on cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLauncherIcon());
  }

  Future<void> _syncLauncherIcon() async {
    final ThemeMode mode = ref.read(themeModeProvider);
    final Brightness brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    await ref
        .read(dynamicIconServiceProvider)
        .apply(DynamicIconService.isDark(mode, brightness));
  }

  // --- Clipboard Plus Code import ---------------------------------------------

  /// Looks for a raw Plus Code on the clipboard and offers a one-tap import.
  ///
  /// Best-effort: reading the clipboard can fail (no permission, an empty
  /// clipboard, or a platform without the channel), and none of that is worth
  /// interrupting the user for.
  Future<void> _checkClipboard() async {
    if (!mounted) return;
    String? text;
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    } catch (_) {
      return;
    }
    if (!mounted) return;

    final String? code = ref
        .read(smartClipboardServiceProvider)
        .extractPlusCode(text);
    if (code == null || code == _lastOfferedPlusCode) return;
    _lastOfferedPlusCode = code;

    final BuildContext? context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    Haptics.light();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.plusCodeDetected),
        action: SnackBarAction(
          label: l10n.plusCodeImport,
          onPressed: () => _importPlusCode(code),
        ),
      ),
    );
  }

  void _importPlusCode(String code) {
    final NavigatorState? navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AddPlaceScreen(initialPlusCode: code, initialMode: LocationEntryMode.manual),
      ),
    );
  }

  // --- Share target -----------------------------------------------------------

  /// Handles text/links shared into MapNote from other apps (share target).
  void _listenForSharedLocations() {
    final ShareIntentService service = ref.read(shareIntentServiceProvider);
    _shareSubscription = service.textStream().listen(_handleSharedText);
    // A cold-start share is delivered before the first frame is rendered.
    service.initialText().then((List<String> texts) {
      for (final String text in texts) {
        _handleSharedText(text);
      }
    });
  }

  Future<void> _handleSharedText(String raw) async {
    ParsedLocation? parsed = _parser.parse(raw);
    if (parsed == null && _parser.looksLikeShortMapLink(raw)) {
      parsed = await _parser.resolveShortLink(raw);
    }
    if (!mounted) return;

    // A raw Plus Code shared from Maps has no lat/lng, but can be decoded
    // offline — hand it straight to the Add Place screen.
    if (parsed == null) {
      final String? code = ref
          .read(smartClipboardServiceProvider)
          .extractPlusCode(raw);
      if (code != null) {
        final NavigatorState? navigator = appNavigatorKey.currentState;
        if (navigator == null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _handleSharedText(raw),
          );
          return;
        }
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => AddPlaceScreen(initialPlusCode: code),
          ),
        );
        return;
      }
    }

    if (parsed == null) {
      AppLogger.log(
        category: 'LOCATION_PARSER',
        message: 'Failed to parse shared map text',
        error: '"$raw" did not match the maps/regex patterns',
        level: LogLevel.warning,
      );
      ref
          .read(appHealthLoggerProvider)
          .logParseFailure(
            source: 'share',
            shortLink: _parser.looksLikeShortMapLink(raw),
          );
      _showShareMessage();
      return;
    }

    final ParsedLocation location = parsed;
    _openSharedLocation(
      ParsedLocation(
        latitude: location.latitude,
        longitude: location.longitude,
        name: location.name ?? _parser.guessName(raw),
      ),
    );
  }

  void _openSharedLocation(ParsedLocation location) {
    if (!mounted) return;
    final NavigatorState? navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      // The navigator is not mounted yet (very early cold start); try again on
      // the next frame.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openSharedLocation(location),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AddPlaceScreen(
          initialLatitude: location.latitude,
          initialLongitude: location.longitude,
          initialName: location.name,
        ),
      ),
    );
  }

  void _showShareMessage() {
    final BuildContext? context = appNavigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).shareNoLocation)),
    );
  }

  /// Handles home-screen / dynamic shortcuts that launch the app for a place.
  void _listenForShortcuts() {
    final HomeShortcutService service = ref.read(homeShortcutServiceProvider);
    service.initialize();
    _shortcutSubscription = service.placeTaps().listen(_openShortcut);
    service.initialPlaceId().then((String? id) {
      if (id != null && id.isNotEmpty) _openShortcut(id);
    });

    // Keep the platform's dynamic shortcuts aligned with pinned places.
    ref.listenManual<AsyncValue<List<Place>>>(
      placesProvider,
      (AsyncValue<List<Place>>? previous, AsyncValue<List<Place>> next) {
        final List<Place>? places = next.value;
        if (places != null) service.syncDynamicShortcuts(places);
      },
      fireImmediately: true,
    );
  }

  /// Navigates straight to a place (1-tap shortcut), verifying identity first
  /// when the place is locked.
  Future<void> _openShortcut(String id) async {
    Place? place;
    final List<Place>? places = ref.read(placesProvider).value;
    if (places != null) {
      for (final Place candidate in places) {
        if (candidate.id == id) {
          place = candidate;
          break;
        }
      }
    }
    place ??= await ref.read(placeRepositoryProvider).getById(id);
    if (place == null || !mounted) return;

    if (place.isLocked) {
      final BuildContext? rootContext = appNavigatorKey.currentContext;
      if (rootContext != null && rootContext.mounted) {
        final AppLocalizations l10n = AppLocalizations.of(rootContext);
        final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
          rootContext,
        );
        if (messenger != null) {
          final bool allowed = await ensureUnlocked(
            ref,
            l10n: l10n,
            reason: l10n.unlockToNavigate,
            messenger: messenger,
            allowWhenUnavailable: true,
          );
          if (!allowed) return;
        }
      } else {
        return;
      }
    }

    Haptics.light();
    final bool launched = await ref
        .read(navigationServiceProvider)
        .navigate(place.latitude, place.longitude);
    if (!launched && mounted) {
      final BuildContext? rootContext2 = appNavigatorKey.currentContext;
      if (rootContext2 != null && rootContext2.mounted) {
        ScaffoldMessenger.maybeOf(rootContext2)?.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(rootContext2).locationUnavailable),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Locale? locale = ref.watch(localeControllerProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // Branded cold-start splash: an overlay above the navigator, so the home
      // route (and early share-intent / shortcut navigation) is live underneath.
      builder: (BuildContext context, Widget? child) =>
          BrandSplash(child: child ?? const SizedBox.shrink()),
      home: const HomeScreen(),
    );
  }
}
