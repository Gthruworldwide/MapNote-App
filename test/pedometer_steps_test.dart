import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/pedometer_steps.dart';
import 'package:routenote/src/services/step_meter.dart';

/// The `pedometer` plugin end of the step pipeline: `pedometerStepCounts` must
/// turn the plugin's `StepCount` events into the raw absolute counts
/// `StepMeter` subtracts, by listening to the plugin's own `step_count` event
/// channel. `StepMeter`'s arithmetic is covered in `step_meter_test.dart`; this
/// file pins the wiring between the two.
void main() {
  // The plugin subscribes to an EventChannel when its stream is listened to.
  TestWidgetsFlutterBinding.ensureInitialized();

  // `package:pedometer` hard-codes this channel name (Pedometer._stepCountChannel).
  const EventChannel channel = EventChannel('step_count');

  MockStreamHandlerEventSink? events;
  int listens = 0;
  int cancels = 0;

  setUp(() {
    events = null;
    listens = 0;
    cancels = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink sink) {
          listens += 1;
          events = sink;
        },
        onCancel: (Object? arguments) {
          cancels += 1;
        },
      ),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(channel, null);
    events = null;
  });

  test('maps the plugin DTO to the raw absolute step count', () async {
    final List<int> counts = <int>[];
    final StreamSubscription<int> subscription =
        pedometerStepCounts().listen(counts.add);
    await pumpEventQueue();
    expect(listens, 1);

    events!.success(17);
    events!.success(42);
    await pumpEventQueue();

    expect(counts, <int>[17, 42]);

    await subscription.cancel();
    await pumpEventQueue();
    expect(cancels, 1);
  });

  test('feeds StepMeter real increments from the plugin channel', () async {
    final StepMeter meter = StepMeter(stepCounts: pedometerStepCounts);
    await meter.start();
    await pumpEventQueue();
    expect(listens, 1);

    // TYPE_STEP_COUNTER reports the count since boot: the first reading is the
    // baseline, so nothing is attributed to this trip yet.
    events!.success(4210);
    await pumpEventQueue();
    expect(meter.hasSensor, isTrue);
    expect(meter.drain(), 0);

    events!.success(4235);
    await pumpEventQueue();
    expect(meter.drain(), 25);
    expect(meter.totalSteps, 25);

    await meter.stop();
    await pumpEventQueue();
    // Stopping unsubscribes, which is what releases the OS sensor in the
    // plugin's `onCancel`.
    expect(cancels, 1);

    await meter.dispose();
  });

  test('the plugin re-opens on refresh, so the sensor attaches after a grant',
      () async {
    final StepMeter meter = StepMeter(stepCounts: pedometerStepCounts);
    await meter.start();
    await pumpEventQueue();
    expect(listens, 1);

    // Nothing was delivered while the permission was still denied. The grant
    // re-subscribes, and the plugin registers the sensor again (`onListen`).
    await meter.refresh();
    await pumpEventQueue();
    expect(listens, 2);
    expect(cancels, 1);

    events!.success(1200);
    await pumpEventQueue();
    expect(meter.hasSensor, isTrue);
    expect(meter.drain(), 0);

    await meter.dispose();
  });

  test('an unavailable pedometer is a platform error, not a crash', () async {
    final StepMeter meter = StepMeter(stepCounts: pedometerStepCounts);
    await meter.start();
    await pumpEventQueue();

    // The plugin's `onListen` errors with code "1" when the device has no
    // step counter.
    events!.error(
      code: '1',
      message: 'StepCount not available',
      details: 'StepCount is not available on this device',
    );
    await pumpEventQueue();

    expect(meter.hasSensor, isFalse);
    expect(meter.drain(), isNull);

    await meter.dispose();
  });

  test('non-mobile hosts report no pedometer and never touch the channel',
      () async {
    // The unit-test VM (and desktop/web) has no plugin implementation: the
    // production source must answer with an empty stream instead of raising
    // MissingPluginException at the first fix.
    expect(isPedometerSupported, isFalse);
    expect(await hardwareStepCount().toList(), isEmpty);
    expect(listens, 0);
  });
}
