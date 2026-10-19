import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/features/saved_places/domain/repositories/vault_repository.dart';
import 'package:routenote/src/features/saved_places/domain/services/vault_authenticator.dart';
import 'package:routenote/src/features/saved_places/presentation/providers/saved_places_providers.dart';
import 'package:routenote/src/features/saved_places/presentation/saved_places_vault_screen.dart';

/// In-memory vault port: no Hive, no AES, no timers — so the screen's
/// verification → unlock → list → re-lock lifecycle runs in a widget test.
class _FakeVault implements VaultRepository {
  _FakeVault(this._places);

  final List<Place> _places;
  bool unlocked = false;

  @override
  bool get isUnlocked => unlocked;

  @override
  Future<void> unlock() async => unlocked = true;

  @override
  Future<void> lock() async => unlocked = false;

  @override
  Future<List<Place>> getAll() async {
    if (!unlocked) throw StateError('locked');
    return List<Place>.of(_places);
  }

  @override
  Future<Place?> getById(String id) async {
    if (!unlocked) throw StateError('locked');
    for (final Place place in _places) {
      if (place.id == id) return place;
    }
    return null;
  }

  @override
  Future<void> save(Place place) async => _places.add(place);

  @override
  Future<void> delete(String id) async =>
      _places.removeWhere((Place place) => place.id == id);
}

class _FakeAuthenticator implements VaultAuthenticator {
  _FakeAuthenticator({this.verification = VaultVerification.verified});

  VaultVerification verification;
  int verifyCalls = 0;

  @override
  Future<VaultVerification> verify({required String reason}) async {
    verifyCalls++;
    return verification;
  }
}

void main() {
  late AppLocalizations l10n;
  late AppLocalizations l10nAr;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    l10nAr = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  Place place() => Place(
    id: 'vault-1',
    name: 'Vaulted Spot',
    notes: 'encrypted notes',
    latitude: 30.0444,
    longitude: 31.2357,
    timestamp: DateTime.utc(2026, 10, 19, 9),
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required _FakeVault vault,
    required _FakeAuthenticator authenticator,
    ThemeData? theme,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          vaultRepositoryProvider.overrideWithValue(vault),
          vaultAuthenticatorProvider.overrideWithValue(authenticator),
        ],
        child: MaterialApp(
          theme: theme,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SavedPlacesVaultScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('prompts for verification, then lists the vaulted places', (
    WidgetTester tester,
  ) async {
    final _FakeVault vault = _FakeVault(<Place>[place()]);
    final _FakeAuthenticator authenticator = _FakeAuthenticator();

    await pumpScreen(tester, vault: vault, authenticator: authenticator);

    expect(authenticator.verifyCalls, 1);
    expect(vault.unlocked, isTrue);
    expect(find.text('Vaulted Spot'), findsOneWidget);
  });

  testWidgets('stays locked when verification fails', (
    WidgetTester tester,
  ) async {
    final _FakeVault vault = _FakeVault(<Place>[place()]);
    final _FakeAuthenticator authenticator = _FakeAuthenticator(
      verification: VaultVerification.failed,
    );

    await pumpScreen(tester, vault: vault, authenticator: authenticator);

    expect(authenticator.verifyCalls, 1);
    expect(vault.unlocked, isFalse);
    expect(find.text('Vaulted Spot'), findsNothing);
    expect(find.text(l10n.savedPlacesVaultLocked), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text(l10n.authenticationFailed), findsOneWidget);
  });

  testWidgets('opens with the no-security warning when the device cannot verify', (
    WidgetTester tester,
  ) async {
    final _FakeVault vault = _FakeVault(<Place>[place()]);
    final _FakeAuthenticator authenticator = _FakeAuthenticator(
      verification: VaultVerification.unavailable,
    );

    await pumpScreen(tester, vault: vault, authenticator: authenticator);

    // MapNote's one documented escape hatch (AGENT_SKILLS §2.4): the vault
    // opens, but the user is told why the check was skipped.
    expect(vault.unlocked, isTrue);
    expect(find.text(l10n.noDeviceSecurityWarning), findsOneWidget);
    expect(find.text('Vaulted Spot'), findsOneWidget);
  });

  testWidgets('shows the locked placeholder for an empty unlocked vault', (
    WidgetTester tester,
  ) async {
    final _FakeVault vault = _FakeVault(<Place>[]);
    final _FakeAuthenticator authenticator = _FakeAuthenticator();

    await pumpScreen(tester, vault: vault, authenticator: authenticator);

    expect(vault.unlocked, isTrue);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text(l10n.savedPlacesVaultEmpty), findsOneWidget);
    expect(find.text(l10n.savedPlacesVaultLocked), findsNothing);
  });

  testWidgets('re-locks the vault when the screen goes away', (
    WidgetTester tester,
  ) async {
    final _FakeVault vault = _FakeVault(<Place>[place()]);
    final _FakeAuthenticator authenticator = _FakeAuthenticator();

    await pumpScreen(tester, vault: vault, authenticator: authenticator);
    expect(vault.unlocked, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(vault.unlocked, isFalse);
  });

  testWidgets('renders in dark mode', (WidgetTester tester) async {
    final _FakeVault vault = _FakeVault(<Place>[place()]);

    await pumpScreen(
      tester,
      vault: vault,
      authenticator: _FakeAuthenticator(),
      theme: ThemeData.dark(),
    );

    expect(find.text('Vaulted Spot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders mirrored for Arabic', (WidgetTester tester) async {
    final _FakeVault vault = _FakeVault(<Place>[place()]);

    await pumpScreen(
      tester,
      vault: vault,
      authenticator: _FakeAuthenticator(),
      locale: const Locale('ar'),
    );

    expect(
      Directionality.of(tester.element(find.byType(Scaffold))),
      TextDirection.rtl,
    );
    expect(find.text(l10nAr.savedPlacesVault), findsOneWidget);
    expect(find.text('Vaulted Spot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
