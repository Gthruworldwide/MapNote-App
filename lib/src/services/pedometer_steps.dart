/// Bridges the `pedometer` plugin's hardware step counter into the absolute
/// step counts `StepMeter` turns into per-fix increments.
///
/// The plugin owns the sensor: Android's `TYPE_STEP_COUNTER` is read on its own
/// `step_count` event channel (iOS uses `CMPedometer`), so MapNote never
/// registers a second step-counter listener of its own. One OS registration,
/// one source of truth — the same "one client per sensor" rule the location
/// side follows with `LocationHub` (AGENT_SKILLS.md §6).
///
/// Nothing here touches the network, identity or location: a single integer per
/// hardware reading, exactly what the sensor reports.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pedometer/pedometer.dart';

import 'step_meter.dart';

/// Whether the `pedometer` plugin can work on this platform at all.
///
/// `false` on desktop, web and in the unit-test VM, where the plugin has no
/// implementation and listening would raise `MissingPluginException`. Callers
/// read it as "no pedometer on this device", never as an error.
bool get isPedometerSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// The plugin's step feed, mapped to the absolute step count since boot.
///
/// Exposed separately from [hardwareStepCount] so tests can drive it through a
/// mocked `step_count` event channel without pretending to be a phone.
Stream<int> pedometerStepCounts() =>
    Pedometer.stepCountStream.map((StepCount event) => event.steps);

/// Factory for [StepMeter]'s `stepCounts` source: a fresh stream of absolute
/// step counts (steps since boot) from the hardware pedometer.
///
/// A factory rather than a stream because the plugin registers the OS sensor
/// when the stream is listened to and releases it on cancel: re-opening the feed
/// (see [StepMeter.refresh], used once `ACTIVITY_RECOGNITION` is granted) has to
/// ask for a **new** stream.
///
/// Silent rather than throwing when the platform has no pedometer: an empty
/// stream is exactly the "no sensor" answer [StepMeter] documents, so the
/// classifier falls back to GPS-speed bands instead of tracking failing.
Stream<int> hardwareStepCount() {
  if (!isPedometerSupported) return const Stream<int>.empty();
  return pedometerStepCounts();
}
