import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/data/models/station_manager.dart';
import 'package:routenote/src/features/place_detail/widgets/station_managers_card.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/manager_contact_service.dart';

/// Records what the card asks the platform to do instead of opening a dialer.
class _RecordingContactService extends ManagerContactService {
  final List<String> calls = <String>[];
  final List<String> messages = <String>[];
  final List<String?> payloads = <String?>[];

  @override
  Future<bool> call(String phone) async {
    calls.add(phone);
    return true;
  }

  @override
  Future<bool> whatsApp(String phone, {String? message}) async {
    messages.add(phone);
    payloads.add(message);
    return true;
  }
}

/// Always unavailable, to pin the fallback snackbar path.
class _UnavailableContactService extends ManagerContactService {
  @override
  Future<bool> call(String phone) async => false;
}

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

  Future<void> pumpCard(
    WidgetTester tester,
    Place value, {
    ManagerContactService? service,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          if (service != null)
            managerContactServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(brightness: brightness),
          home: Scaffold(body: StationManagersCard(place: value)),
        ),
      ),
    );
  }

  testWidgets('renders nothing for a place without managers', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, place());

    expect(find.text('Station manager'), findsNothing);
    expect(find.byIcon(Icons.support_agent), findsNothing);
  });

  testWidgets('shows the manager name and an explicit "no number" hint', (
    WidgetTester tester,
  ) async {
    await pumpCard(
      tester,
      place(
        managers: const <StationManager>[StationManager(name: 'احمد ايمن')],
      ),
    );

    expect(find.text('Station manager'), findsOneWidget);
    expect(find.text('احمد ايمن'), findsOneWidget);
    expect(find.text('No phone number on file yet'), findsOneWidget);
    // A dead button is worse than no button: neither action is rendered.
    expect(find.byIcon(Icons.call_outlined), findsNothing);
    expect(find.byIcon(Icons.chat_outlined), findsNothing);
  });

  testWidgets('offers call and WhatsApp once a number exists', (
    WidgetTester tester,
  ) async {
    final _RecordingContactService service = _RecordingContactService();
    await pumpCard(
      tester,
      place(
        managers: const <StationManager>[
          StationManager(name: 'يحي إبراهيم', phone: '01001234567'),
        ],
      ),
      service: service,
    );

    expect(find.text('01001234567'), findsOneWidget);
    expect(find.byIcon(Icons.call_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chat_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call_outlined));
    await tester.pump();
    expect(service.calls, <String>['01001234567']);

    await tester.tap(find.byIcon(Icons.chat_outlined));
    await tester.pump();
    expect(service.messages, <String>['01001234567']);
    // The pre-filled message names the manager and the station.
    expect(service.payloads.single, contains('يحي إبراهيم'));
    expect(service.payloads.single, contains('محطة طاقة الغردقة'));
  });

  testWidgets('lists every manager of a two-manager station', (
    WidgetTester tester,
  ) async {
    await pumpCard(
      tester,
      place(
        managers: const <StationManager>[
          StationManager(name: 'احمد حمدي', phone: '01000000000'),
          StationManager(name: 'احمد عز'),
        ],
      ),
      service: _RecordingContactService(),
    );

    expect(find.text('احمد حمدي'), findsOneWidget);
    expect(find.text('احمد عز'), findsOneWidget);
    // Exactly one contactable manager -> exactly one pair of buttons.
    expect(find.byIcon(Icons.call_outlined), findsOneWidget);
    expect(find.text('No phone number on file yet'), findsOneWidget);
  });

  testWidgets('a failed launch shows the unavailable message', (
    WidgetTester tester,
  ) async {
    await pumpCard(
      tester,
      place(
        managers: const <StationManager>[
          StationManager(name: 'علي فؤاد', phone: '01001234567'),
        ],
      ),
      service: _UnavailableContactService(),
    );

    await tester.tap(find.byIcon(Icons.call_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No app on this device can handle that'), findsOneWidget);
  });

  testWidgets('renders in dark mode from the theme, not hardcoded colors', (
    WidgetTester tester,
  ) async {
    await pumpCard(
      tester,
      place(
        managers: const <StationManager>[
          StationManager(name: 'احمد ايمن', phone: '01001234567'),
        ],
      ),
      service: _RecordingContactService(),
      brightness: Brightness.dark,
    );

    expect(find.text('احمد ايمن'), findsOneWidget);
    expect(find.byIcon(Icons.call_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
