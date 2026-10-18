import 'package:fake_async/fake_async.dart'; // ignore: depend_on_referenced_packages
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:routenote/src/services/adaptive_sampling_manager.dart';
import 'package:routenote/src/services/transport_classifier.dart';

/// A scripted [BatteryStatusSource]: reads are counted, the answer is
/// whatever the test queued next.
class _FakeBatterySource implements BatteryStatusSource {
  _FakeBatterySource([this.next = BatteryStatus.unknown]);

  /// What the next [read] will return.
  BatteryStatus next;

  /// How many times the sampler asked.
  int reads = 0;

  @override
  Future<BatteryStatus> read() async {
    reads += 1;
    return next;
  }
}

void main() {
  // The platform battery source talks over a MethodChannel.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BatteryStatus.isLow', () {
    test('is low only when unplugged and below 20 percent', () {
      expect(
        const BatteryStatus(level: 0.1, charging: false).isLow,
        isTrue,
      );
      // Charging cancels the power concern entirely.
      expect(
        const BatteryStatus(level: 0.1, charging: true).isLow,
        isFalse,
      );
      expect(
        const BatteryStatus(level: 0.5, charging: false).isLow,
        isFalse,
      );
      // An unknown level is treated as healthy — tracking is never throttled
      // on a guess.
      expect(BatteryStatus.unknown.isLow, isFalse);
      expect(BatteryStatus.unknown.level, isNull);
    });
  });

  group('computeProfile', () {
    test('maps every transport mode to its documented tier', () {
      const BatteryStatus healthy = BatteryStatus(level: 0.9, charging: false);

      final SamplingProfile vehicle = computeProfile(
        mode: TransportMode.vehicle,
        battery: healthy,
      );
      expect(vehicle.interval, SamplingProfile.vehicleInterval);
      expect(vehicle.interval, const Duration(seconds: 1));
      expect(vehicle.accuracy, LocationAccuracy.high);

      final SamplingProfile train = computeProfile(
        mode: TransportMode.train,
        battery: healthy,
      );
      expect(train.interval, SamplingProfile.trainInterval);
      expect(train.interval, const Duration(seconds: 1));
      expect(train.accuracy, LocationAccuracy.high);

      final SamplingProfile walking = computeProfile(
        mode: TransportMode.walking,
        battery: healthy,
      );
      expect(walking.interval, SamplingProfile.walkingInterval);
      expect(walking.interval, const Duration(seconds: 15));
      expect(walking.accuracy, LocationAccuracy.high);

      final SamplingProfile stationary = computeProfile(
        mode: TransportMode.stationary,
        battery: healthy,
      );
      expect(stationary.interval, SamplingProfile.stationaryInterval);
      expect(stationary.interval, const Duration(seconds: 60));
      expect(stationary.accuracy, LocationAccuracy.lowest);
    });

    test('doubles the interval and drops accuracy one notch on a low battery',
        () {
      const BatteryStatus low = BatteryStatus(level: 0.1, charging: false);

      final SamplingProfile vehicle = computeProfile(
        mode: TransportMode.vehicle,
        battery: low,
      );
      expect(vehicle.interval, const Duration(seconds: 2));
      expect(vehicle.accuracy, LocationAccuracy.medium);

      final SamplingProfile walking = computeProfile(
        mode: TransportMode.walking,
        battery: low,
      );
      expect(walking.interval, const Duration(seconds: 30));
      expect(walking.accuracy, LocationAccuracy.medium);

      // The stationary tier is already the lowest accuracy — there is no
      // lower notch to fall to, only the interval doubles.
      final SamplingProfile stationary = computeProfile(
        mode: TransportMode.stationary,
        battery: low,
      );
      expect(stationary.interval, const Duration(seconds: 120));
      expect(stationary.accuracy, LocationAccuracy.lowest);
    });

    test('halves the interval while charging with a one-second floor', () {
      const BatteryStatus charging = BatteryStatus(level: 0.5, charging: true);

      final SamplingProfile walking = computeProfile(
        mode: TransportMode.walking,
        battery: charging,
      );
      expect(walking.interval, const Duration(seconds: 7, milliseconds: 500));
      expect(walking.accuracy, LocationAccuracy.high);

      // 1 s / 2 would be 500 ms, but the floor keeps the fastest tier at 1 s.
      final SamplingProfile vehicle = computeProfile(
        mode: TransportMode.vehicle,
        battery: charging,
      );
      expect(vehicle.interval, SamplingProfile.vehicleInterval);
      expect(vehicle.accuracy, LocationAccuracy.high);

      final SamplingProfile train = computeProfile(
        mode: TransportMode.train,
        battery: charging,
      );
      expect(train.interval, SamplingProfile.trainInterval);
      expect(train.accuracy, LocationAccuracy.high);

      final SamplingProfile stationary = computeProfile(
        mode: TransportMode.stationary,
        battery: charging,
      );
      expect(stationary.interval, const Duration(seconds: 30));
      expect(stationary.accuracy, LocationAccuracy.lowest);
    });

    test('treats an unknown battery exactly like a healthy one', () {
      const BatteryStatus healthy = BatteryStatus(level: 0.9, charging: false);

      for (final TransportMode mode in TransportMode.values) {
        final SamplingProfile withUnknown = computeProfile(
          mode: mode,
          battery: BatteryStatus.unknown,
        );
        final SamplingProfile withHealthy = computeProfile(
          mode: mode,
          battery: healthy,
        );
        expect(withUnknown.interval, withHealthy.interval, reason: '$mode');
        expect(withUnknown.accuracy, withHealthy.accuracy, reason: '$mode');
        expect(withUnknown.battery, BatteryStatus.unknown);
      }
      // …and the conservative default profile is the stationary one.
      expect(SamplingProfile.defaults.mode, TransportMode.stationary);
      expect(SamplingProfile.defaults.interval, const Duration(seconds: 60));
      expect(SamplingProfile.defaults.accuracy, LocationAccuracy.lowest);
      expect(SamplingProfile.defaults.battery, BatteryStatus.unknown);
    });
  });

  group('PlatformBatteryStatusSource', () {
    const MethodChannel channel = PlatformBatteryStatusSource.defaultChannel;
    final List<String> calls = <String>[];

    void mockReply(Object? Function(MethodCall call) reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call.method);
        return reply(call);
      });
    }

    setUp(calls.clear);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reads the platform level as a healthy zero-to-one value', () async {
      mockReply((MethodCall call) => 0.75);

      final BatteryStatus status =
          await const PlatformBatteryStatusSource().read();

      expect(calls, <String>['getBatteryLevel']);
      expect(status.level, 0.75);
      expect(status.charging, isFalse);
      expect(status.isLow, isFalse);
    });

    test('treats a negative level as unknown, not as empty', () async {
      mockReply((MethodCall call) => -1);

      final BatteryStatus status =
          await const PlatformBatteryStatusSource().read();

      expect(status, BatteryStatus.unknown);
      expect(status.isLow, isFalse);
    });

    test('treats a non-numeric platform reply as unknown', () async {
      mockReply((MethodCall call) => 'not a number');

      final BatteryStatus status =
          await const PlatformBatteryStatusSource().read();

      expect(status, BatteryStatus.unknown);
    });

    test('treats a throwing platform channel as unknown', () async {
      mockReply((MethodCall call) {
        throw PlatformException(code: 'battery_unreadable');
      });

      final BatteryStatus status =
          await const PlatformBatteryStatusSource().read();

      expect(status, BatteryStatus.unknown);
    });

    test('falls back to unknown when the platform has no handler at all',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      final BatteryStatus status =
          await const PlatformBatteryStatusSource().read();

      expect(status, BatteryStatus.unknown);
      expect(status.charging, isFalse);
    });

    test('clamps a level above one to exactly one', () async {
      mockReply((MethodCall call) => 1.6);

      final BatteryStatus status =
          await const PlatformBatteryStatusSource().read();

      expect(status.level, 1.0);
      expect(status.isLow, isFalse);
    });
  });

  // Privacy: the adaptive sampler's entire state is a transport enum, a
  // Duration, an accuracy tier and a coarse battery snapshot — no location,
  // no identity, nothing that could place the user or their saved places.
  group('AdaptiveSamplingNotifier', () {
    ProviderContainer buildContainer(_FakeBatterySource source) {
      final ProviderContainer container = ProviderContainer(
        overrides: [batteryStatusProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('starts from the conservative stationary defaults', () {
      final ProviderContainer container =
          buildContainer(_FakeBatterySource());

      expect(container.read(adaptiveSamplingProvider), SamplingProfile.defaults);

      final AdaptiveSamplingNotifier notifier =
          container.read(adaptiveSamplingProvider.notifier);
      expect(notifier.mode, TransportMode.stationary);
      expect(notifier.battery, BatteryStatus.unknown);
    });

    test('ignores a repeated transport mode without churning state', () async {
      final ProviderContainer container =
          buildContainer(_FakeBatterySource());
      final AdaptiveSamplingNotifier notifier =
          container.read(adaptiveSamplingProvider.notifier);

      notifier.observeTransport(TransportMode.vehicle);
      final SamplingProfile afterFirst = container
          .read(adaptiveSamplingProvider);
      expect(afterFirst.mode, TransportMode.vehicle);
      expect(afterFirst.interval, const Duration(seconds: 1));
      expect(afterFirst.accuracy, LocationAccuracy.high);

      int notifications = 0;
      final ProviderSubscription<SamplingProfile> subscription =
          container.listen(
        adaptiveSamplingProvider,
        (SamplingProfile? previous, SamplingProfile next) {
          notifications += 1;
        },
      );

      // The same verdict again: no new state object, no notification.
      notifier.observeTransport(TransportMode.vehicle);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
      expect(
        identical(container.read(adaptiveSamplingProvider), afterFirst),
        isTrue,
      );

      // Sanity check: a real change does notify, so the zero above is
      // meaningful rather than a listener that never fires.
      notifier.observeTransport(TransportMode.stationary);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      expect(
        container.read(adaptiveSamplingProvider),
        SamplingProfile.defaults,
      );

      subscription.close();
    });

    test('recomputes when the battery turns low while walking', () async {
      final _FakeBatterySource source = _FakeBatterySource();
      final ProviderContainer container = buildContainer(source);
      final AdaptiveSamplingNotifier notifier =
          container.read(adaptiveSamplingProvider.notifier);

      notifier.observeTransport(TransportMode.walking);
      expect(container.read(adaptiveSamplingProvider).interval,
          const Duration(seconds: 15));

      source.next = const BatteryStatus(level: 0.1, charging: false);
      await notifier.refreshBattery();

      final SamplingProfile updated = container.read(adaptiveSamplingProvider);
      expect(notifier.mode, TransportMode.walking);
      expect(notifier.battery.level, 0.1);
      expect(notifier.battery.isLow, isTrue);
      expect(updated.mode, TransportMode.walking);
      expect(updated.interval, const Duration(seconds: 30));
      expect(updated.accuracy, LocationAccuracy.medium);
      expect(updated.battery.isLow, isTrue);
    });

    test('keeps state identical when the battery reading repeats', () async {
      final _FakeBatterySource source = _FakeBatterySource();
      final ProviderContainer container = buildContainer(source);
      final AdaptiveSamplingNotifier notifier =
          container.read(adaptiveSamplingProvider.notifier);

      notifier.observeTransport(TransportMode.walking);
      source.next = const BatteryStatus(level: 0.4, charging: false);
      await notifier.refreshBattery();
      final SamplingProfile afterFirstRead =
          container.read(adaptiveSamplingProvider);
      expect(afterFirstRead.battery.level, 0.4);

      int notifications = 0;
      final ProviderSubscription<SamplingProfile> subscription =
          container.listen(
        adaptiveSamplingProvider,
        (SamplingProfile? previous, SamplingProfile next) {
          notifications += 1;
        },
      );

      // The source returns the same value: no recompute, no churn.
      await notifier.refreshBattery();
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 0);
      expect(
        identical(container.read(adaptiveSamplingProvider), afterFirstRead),
        isTrue,
      );
      expect(source.reads, 2);

      subscription.close();
    });

    test('polls the battery until stopPolling and survives disposal', () {
      fakeAsync((FakeAsync async) {
        final _FakeBatterySource source = _FakeBatterySource(
          const BatteryStatus(level: 0.7, charging: false),
        );
        final ProviderContainer container = ProviderContainer(
          overrides: [batteryStatusProvider.overrideWithValue(source)],
        );
        // Force the notifier into existence so every timer below is created
        // inside this fake zone.
        container.read(adaptiveSamplingProvider);
        final AdaptiveSamplingNotifier notifier =
            container.read(adaptiveSamplingProvider.notifier);

        // startPolling refreshes immediately, then arms one periodic timer.
        notifier.startPolling();
        async.flushMicrotasks();
        expect(source.reads, 1);
        expect(notifier.battery.level, 0.7);

        // Idempotent: a second start must not double the timer.
        notifier.startPolling();
        async.flushMicrotasks();
        expect(source.reads, 1);

        async.elapse(AdaptiveSamplingNotifier.batteryPollEvery);
        async.flushMicrotasks();
        expect(source.reads, 2);

        // stopPolling halts the periodic reads…
        notifier.stopPolling();
        async.elapse(AdaptiveSamplingNotifier.batteryPollEvery * 4);
        async.flushMicrotasks();
        expect(source.reads, 2);

        // …and disposal neither throws nor leaves a timer running behind it.
        container.dispose();
        async.elapse(AdaptiveSamplingNotifier.batteryPollEvery * 4);
        async.flushMicrotasks();
        expect(source.reads, 2);
      });
    });
  });
}
