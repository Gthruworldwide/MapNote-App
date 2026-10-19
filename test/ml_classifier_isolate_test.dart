import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/core/sensors/gravity_alignment_calculator.dart';
import 'package:routenote/src/features/motion_analytics/data/heuristic_motion_model.dart';
import 'package:routenote/src/features/motion_analytics/data/inline_motion_inference_runner.dart';
import 'package:routenote/src/features/motion_analytics/data/isolate_motion_inference_runner.dart';
import 'package:routenote/src/features/motion_analytics/data/ml_classifier_isolate.dart';
import 'package:routenote/src/features/motion_analytics/data/motion_event_mapper.dart';
import 'package:routenote/src/features/motion_analytics/domain/entities/motion_event.dart';
import 'package:routenote/src/features/motion_analytics/domain/entities/motion_window.dart';
import 'package:routenote/src/features/motion_analytics/domain/services/motion_model.dart';
import 'package:routenote/src/features/motion_analytics/domain/services/motion_inference_runner.dart';
import 'package:routenote/src/services/motion_profiler.dart';
import 'package:routenote/src/services/motion_sensor_hub.dart';

/// A model that records the windows it was asked about and returns whatever the
/// test told it to, so buffering can be asserted without depending on the
/// shipped classifier's thresholds.
class _RecordingModel extends MotionModel {
  _RecordingModel({this.predictions = const <MotionPrediction>[]});

  final List<MotionPrediction> predictions;
  final List<MotionWindow> windows = <MotionWindow>[];

  @override
  String get id => 'recording';

  @override
  List<MotionEventKind> get labels => MotionEventKind.values;

  @override
  List<MotionPrediction> infer(MotionWindow window) {
    windows.add(window);
    return predictions;
  }
}

/// A model that always throws, standing in for a broken/absent model.
class _ExplodingModel extends MotionModel {
  @override
  String get id => 'exploding';

  @override
  List<MotionEventKind> get labels => MotionEventKind.values;

  @override
  List<MotionPrediction> infer(MotionWindow window) =>
      throw StateError('no model loaded');
}

/// A runner that never answers, standing in for a wedged worker.
class _HangingRunner implements MotionInferenceRunner {
  bool disposed = false;

  @override
  Future<List<MotionPrediction>> infer(MotionWindow window) =>
      Completer<List<MotionPrediction>>().future;

  @override
  Future<void> dispose() async => disposed = true;
}

/// Feeds [count] identical vehicle-frame samples, letting each inference
/// microtask run between hops.
Future<void> _drive(
  MLClassifierIsolate classifier,
  VehicleAcceleration sample, {
  required int count,
  DateTime? start,
}) async {
  for (int index = 0; index < count; index++) {
    classifier.feed(
      sample,
      at: (start ?? DateTime.utc(2026, 1, 1)).add(
        Duration(milliseconds: index * 20),
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }
}

MLClassifierIsolate _classifierWith(MotionModel model, {int hopSamples = 16}) =>
    MLClassifierIsolate(
      runner: InlineMotionInferenceRunner(model),
      hopSamples: hopSamples,
      eventCooldown: const Duration(seconds: 2),
    );

const VehicleAcceleration _braking = VehicleAcceleration(
  lateral: 0,
  vertical: 0,
  longitudinal: -5,
);

void main() {
  group('window buffering', () {
    test('does not classify until a full window is buffered', () async {
      final _RecordingModel model = _RecordingModel();
      final MLClassifierIsolate classifier = _classifierWith(model);

      await _drive(classifier, _braking, count: MotionWindow.sampleCount - 1);

      expect(model.windows, isEmpty);
      expect(classifier.bufferedSamples, MotionWindow.sampleCount - 1);

      classifier.feed(_braking, at: DateTime.utc(2026, 1, 1));
      await Future<void>.delayed(Duration.zero);

      expect(model.windows.length, 1);
      expect(model.windows.single.samples.length, MotionWindow.sampleCount);
      expect(model.windows.single.isFull, isTrue);
    });

    test('slides by one sample and infers once per hop', () async {
      final _RecordingModel model = _RecordingModel();
      final MLClassifierIsolate classifier = _classifierWith(model);

      await _drive(classifier, _braking, count: MotionWindow.sampleCount + 32);

      // 160 samples: full at 128, then a fresh inference every 16 → 3 total
      // (128, 144, 160).
      expect(model.windows.length, 3);
      expect(classifier.inferenceCount, 3);
      // The window never exceeds its documented length.
      for (final MotionWindow window in model.windows) {
        expect(window.samples.length, MotionWindow.sampleCount);
      }
      expect(classifier.bufferedSamples, MotionWindow.sampleCount);
    });

    test('keeps the newest samples, in capture order', () async {
      final _RecordingModel model = _RecordingModel();
      final MLClassifierIsolate classifier = _classifierWith(model);

      for (int index = 0; index < MotionWindow.sampleCount; index++) {
        classifier.feed(
          VehicleAcceleration(
            lateral: 0,
            vertical: 0,
            longitudinal: index.toDouble(),
          ),
          at: DateTime.utc(2026, 1, 1).add(Duration(milliseconds: index * 20)),
        );
        await Future<void>.delayed(Duration.zero);
      }

      final MotionWindow window = model.windows.single;
      expect(window.longitudinal.first, 0);
      expect(window.longitudinal.last, (MotionWindow.sampleCount - 1).toDouble());
      expect(window.span.inMilliseconds, (MotionWindow.sampleCount - 1) * 20);
    });

    test('a slow inference never queues up more work', () async {
      final _HangingRunner runner = _HangingRunner();
      final MLClassifierIsolate classifier = MLClassifierIsolate(
        runner: runner,
        hopSamples: 4,
      );

      await _drive(classifier, _braking, count: MotionWindow.sampleCount + 40);

      expect(classifier.inferenceInFlight, isTrue);
      expect(classifier.inferenceCount, 0);
      await classifier.dispose();
      expect(runner.disposed, isTrue);
    });

    test('clear() empties the window and the event log', () async {
      final MLClassifierIsolate classifier = _classifierWith(
        _RecordingModel(
          predictions: const <MotionPrediction>[
            MotionPrediction(
              kind: MotionEventKind.hardBrake,
              confidence: 0.9,
              peakMps2: -5,
            ),
          ],
        ),
      );
      await _drive(classifier, _braking, count: MotionWindow.sampleCount);
      expect(classifier.events, isNotEmpty);

      classifier.clear();

      expect(classifier.bufferedSamples, 0);
      expect(classifier.events, isEmpty);
    });
  });

  group('event publishing', () {
    test('captures every maneuver the model reports', () async {
      final MLClassifierIsolate classifier = _classifierWith(
        _RecordingModel(
          predictions: const <MotionPrediction>[
            MotionPrediction(
              kind: MotionEventKind.hardBrake,
              confidence: 0.8,
              peakMps2: -5,
            ),
          ],
        ),
      );
      final List<MotionEvent> seen = <MotionEvent>[];
      final StreamSubscription<MotionEvent> subscription =
          classifier.onEvent.listen(seen.add);

      await _drive(classifier, _braking, count: MotionWindow.sampleCount);
      await Future<void>.delayed(Duration.zero);

      expect(classifier.events.length, 1);
      expect(classifier.events.single.kind, MotionEventKind.hardBrake);
      expect(classifier.events.single.peakMps2, -5);
      expect(classifier.events.single.startedAt, isNotNull);
      expect(seen.length, 1);
      await subscription.cancel();
    });

    test('de-duplicates one maneuver across overlapping windows', () async {
      final MLClassifierIsolate classifier = _classifierWith(
        _RecordingModel(
          predictions: const <MotionPrediction>[
            MotionPrediction(
              kind: MotionEventKind.speedBump,
              confidence: 0.7,
              peakMps2: 6,
            ),
          ],
        ),
        hopSamples: 16,
      );

      // 128 + 4 hops = 5 windows, all inside the same 2 s cooldown.
      await _drive(classifier, _braking, count: MotionWindow.sampleCount + 64);

      expect(classifier.inferenceCount, 5);
      expect(classifier.events.length, 1);
    });

    test('reports the same maneuver again after the cooldown', () async {
      final MLClassifierIsolate classifier = _classifierWith(
        _RecordingModel(
          predictions: const <MotionPrediction>[
            MotionPrediction(
              kind: MotionEventKind.pothole,
              confidence: 0.7,
              peakMps2: -6,
            ),
          ],
        ),
        hopSamples: 16,
      );

      // First burst: one event in the 128-sample round (the 3 follow-up hops
      // are inside the 2 s cooldown). Second burst, 5 s later: two more, since
      // the 5th window's samples run another 1.3 s past the boundary.
      await _drive(classifier, _braking, count: MotionWindow.sampleCount);
      await _drive(
        classifier,
        _braking,
        count: 128,
        start: DateTime.utc(2026, 1, 1).add(const Duration(seconds: 5)),
      );

      expect(classifier.events.length, 3);
    });

    test('reports smooth driving once, not once per window', () async {
      final MLClassifierIsolate classifier = _classifierWith(
        _RecordingModel(
          predictions: const <MotionPrediction>[
            MotionPrediction(
              kind: MotionEventKind.smoothDrive,
              confidence: 0.9,
              peakMps2: 0,
            ),
          ],
        ),
      );

      await _drive(classifier, _braking, count: MotionWindow.sampleCount + 128);

      expect(classifier.events.length, 1);
      expect(classifier.events.single.kind, MotionEventKind.smoothDrive);
    });

    test('a throwing model yields no events and never crashes the pipeline',
        () async {
      final MLClassifierIsolate classifier = _classifierWith(_ExplodingModel());

      await _drive(classifier, _braking, count: MotionWindow.sampleCount + 16);

      expect(classifier.events, isEmpty);
      expect(classifier.inferenceCount, 2);
    });
  });

  group('accelerometer and gravity alignment', () {
    test('drops samples until the device is calibrated', () async {
      final GravlessStreamSlate slate = GravlessStreamSlate();
      final MLClassifierIsolate classifier = MLClassifierIsolate(
        runner: InlineMotionInferenceRunner(_RecordingModel()),
        accelerometer: slate.controller.stream,
        hopSamples: 16,
      );
      await classifier.start();

      // Phone on its end: gravity parallel to the nominal forward axis, so no
      // frame can be built.
      for (int index = 0; index < 30; index++) {
        slate.add(
          AccelerometerSample(
            0,
            9.81,
            0,
            DateTime.utc(2026, 1, 1).add(Duration(milliseconds: index * 20)),
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);

      expect(classifier.isCalibrated, isFalse);
      expect(classifier.uncalibratedSamples, 30);
      expect(classifier.bufferedSamples, 0);
      await classifier.dispose();
    });

    test('buffers gravity-free vehicle samples once calibrated', () async {
      final GravlessStreamSlate slate = GravlessStreamSlate();
      final _RecordingModel model = _RecordingModel();
      final MLClassifierIsolate classifier = MLClassifierIsolate(
        runner: InlineMotionInferenceRunner(model),
        accelerometer: slate.controller.stream,
      );
      await classifier.start();

      // Flat portrait cradle, parked, then a real brake. Alignment needs a
      // still moment to seed from: seeding it *during* a maneuver would bake
      // the maneuver into the reference frame.
      for (int index = 0; index < 30; index++) {
        slate.add(
          AccelerometerSample(
            0,
            0,
            9.81,
            DateTime.utc(2026, 1, 1).add(Duration(milliseconds: index * 20)),
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(classifier.isCalibrated, isTrue);

      for (int index = 30; index < 30 + MotionWindow.sampleCount; index++) {
        slate.add(
          AccelerometerSample(
            0,
            -4.0,
            9.81,
            DateTime.utc(2026, 1, 1).add(Duration(milliseconds: index * 20)),
          ),
        );
        // Feed over "real time" one sample per microtask, the way the hub's
        // broadcast stream delivers hardware samples.
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);

      expect(model.windows, isNotEmpty);
      // Every buffered sample is gravity-free on the vertical axis and the
      // brake is present at its full magnitude, so the shipped model classifies
      // it as a hard brake from the calibrated frame.
      final MotionWindow window = model.windows.first;
      expect(window.isFull, isTrue);
      final double worstVertical = window.vertical
          .map((double value) => value.abs())
          .reduce((double a, double b) => a > b ? a : b);
      expect(
        worstVertical,
        lessThan(0.01),
        reason: 'vertical channel leaked $worstVertical m/s²',
      );
      expect(
        window.longitudinal.any((double value) => value < -3.5),
        isTrue,
      );
      expect(
        buildHeuristicMotionModel().infer(window).first.kind,
        MotionEventKind.hardBrake,
      );
      await classifier.dispose();
    });

    test('start and stop are idempotent and release the feed', () async {
      final GravlessStreamSlate slate = GravlessStreamSlate();
      final MLClassifierIsolate classifier = MLClassifierIsolate(
        runner: InlineMotionInferenceRunner(_RecordingModel()),
        accelerometer: slate.controller.stream,
      );

      await classifier.start();
      await classifier.start();
      expect(classifier.isRunning, isTrue);
      expect(slate.controller.hasListener, isTrue);

      await classifier.stop();
      expect(classifier.isRunning, isFalse);
      expect(slate.controller.hasListener, isFalse);
      expect(slate.controller.isClosed, isFalse);
      await classifier.dispose();
    });

    test('without a feed, start() is a no-op', () async {
      final MLClassifierIsolate classifier = _classifierWith(_RecordingModel());

      await classifier.start();
      expect(classifier.isRunning, isFalse);
      await classifier.dispose();
    });
  });

  group('driving-event mapping', () {
    test('maps classified kinds onto the analyzer taxonomy', () {
      final DateTime at = DateTime.utc(2026, 1, 1);
      expect(
        toDrivingEvent(
          MotionEvent(
            kind: MotionEventKind.hardBrake,
            confidence: 0.9,
            peakMps2: -5,
            startedAt: at,
          ),
        )?.type,
        DrivingEventType.harshBraking,
      );
      expect(
        toDrivingEvent(
          MotionEvent(
            kind: MotionEventKind.hardAccel,
            confidence: 0.9,
            peakMps2: 5,
            startedAt: at,
          ),
        )?.type,
        DrivingEventType.harshAcceleration,
      );
      expect(
        toDrivingEvent(
          MotionEvent(
            kind: MotionEventKind.sharpTurn,
            confidence: 0.9,
            peakMps2: -4,
            startedAt: at,
          ),
        )?.type,
        DrivingEventType.sharpTurn,
      );
      expect(
        toDrivingEvent(
          MotionEvent(
            kind: MotionEventKind.speedBump,
            confidence: 0.9,
            peakMps2: 6,
            startedAt: at,
          ),
        )?.type,
        DrivingEventType.speedBump,
      );
      expect(
        toDrivingEvent(
          MotionEvent(
            kind: MotionEventKind.pothole,
            confidence: 0.9,
            peakMps2: -6,
            startedAt: at,
          ),
        )?.type,
        DrivingEventType.pothole,
      );
    });

    test('smooth driving is a state, so it maps to no event', () {
      expect(
        toDrivingEvent(
          MotionEvent(
            kind: MotionEventKind.smoothDrive,
            confidence: 0.9,
            peakMps2: 0,
            startedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
        isNull,
      );
    });

    test('carries the peak and the timestamp across', () {
      final DateTime at = DateTime.utc(2026, 1, 1, 12);
      final DrivingEvent? event = toDrivingEvent(
        MotionEvent(
          kind: MotionEventKind.pothole,
          confidence: 0.9,
          peakMps2: -7.5,
          startedAt: at,
        ),
      );

      expect(event?.peakMps2, -7.5);
      expect(event?.startedAt, at);
      expect(event?.duration, Duration.zero);
    });
  });

  group('real background isolate', () {
    test('classifies a window on a dedicated isolate', () async {
      final IsolateMotionInferenceRunner runner = IsolateMotionInferenceRunner(
        buildModel: buildHeuristicMotionModel,
      );
      addTearDown(runner.dispose);

      final List<MotionPrediction> predictions = await runner.infer(
        _brakingWindow(),
      );

      expect(runner.isRunning, isTrue);
      expect(predictions, isNotEmpty);
      expect(predictions.first.kind, MotionEventKind.hardBrake);
      expect(predictions.first.peakMps2, closeTo(-5, 1e-9));
    });

    test('keeps the worker alive across many windows', () async {
      final IsolateMotionInferenceRunner runner = IsolateMotionInferenceRunner(
        buildModel: buildHeuristicMotionModel,
      );
      addTearDown(runner.dispose);

      for (int index = 0; index < 5; index++) {
        await runner.infer(_brakingWindow());
      }

      expect(runner.pendingRequests, 0);
      expect(runner.isRunning, isTrue);
    });

    test('survives a model that throws on the far side', () async {
      final IsolateMotionInferenceRunner runner = IsolateMotionInferenceRunner(
        buildModel: _ExplodingModel.new,
      );
      addTearDown(runner.dispose);

      final List<MotionPrediction> predictions = await runner.infer(
        _brakingWindow(),
      );
      final List<MotionPrediction> after = await runner.infer(_brakingWindow());

      expect(predictions, isEmpty);
      expect(after, isEmpty);
      expect(runner.isRunning, isTrue);
    });

    test('a disposed runner reports nothing instead of throwing', () async {
      final IsolateMotionInferenceRunner runner = IsolateMotionInferenceRunner(
        buildModel: buildHeuristicMotionModel,
      );
      await runner.dispose();

      expect(await runner.infer(_brakingWindow()), isEmpty);
      expect(runner.isRunning, isFalse);
    });

    test('drives the whole pipeline end to end in an isolate', () async {
      final MLClassifierIsolate classifier = MLClassifierIsolate.standard();
      addTearDown(classifier.dispose);

      await _drive(classifier, _braking, count: MotionWindow.sampleCount + 16);

      expect(classifier.events, isNotEmpty);
      expect(classifier.events.first.kind, MotionEventKind.hardBrake);
    });
  });
}

MotionWindow _brakingWindow() => MotionWindow(
  <MotionWindowSample>[
    for (int index = 0; index < MotionWindow.sampleCount; index++)
      MotionWindowSample(
        lateral: 0,
        vertical: 0,
        longitudinal: -5,
        at: DateTime.utc(2026, 1, 1).add(Duration(milliseconds: index * 20)),
      ),
  ],
);

/// A hand-rolled accelerometer feed: a broadcast controller plus a way to push
/// samples, so the classifier's live-listener path can be driven without
/// `MotionSensorHub`'s platform channel.
class GravlessStreamSlate {
  final StreamController<AccelerometerSample> controller =
      StreamController<AccelerometerSample>.broadcast();

  void add(AccelerometerSample sample) => controller.add(sample);
}
