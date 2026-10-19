import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/features/motion_analytics/data/heuristic_motion_model.dart';
import 'package:routenote/src/features/motion_analytics/domain/entities/motion_event.dart';
import 'package:routenote/src/features/motion_analytics/domain/entities/motion_window.dart';
import 'package:routenote/src/features/motion_analytics/domain/services/motion_model.dart';

/// Builds a window of [samples] samples where every sample is the same
/// constant vehicle-frame reading.
MotionWindow _steady({
  double lateral = 0,
  double vertical = 0,
  double longitudinal = 0,
  int samples = MotionWindow.sampleCount,
}) => MotionWindow(
  <MotionWindowSample>[
    for (int index = 0; index < samples; index++)
      MotionWindowSample(
        lateral: lateral,
        vertical: vertical,
        longitudinal: longitudinal,
        at: DateTime.utc(2026, 1, 1).add(
          Duration(milliseconds: index * 20),
        ),
      ),
  ],
);

/// Builds a window that is calm except for one short burst lasting
/// [burstSamples] samples, starting at [start] — the shape of a bump or a
/// pothole.
MotionWindow _burst({
  required double vertical,
  int burstSamples = 8,
  int start = 40,
  int samples = MotionWindow.sampleCount,
}) => MotionWindow(
  <MotionWindowSample>[
    for (int index = 0; index < samples; index++)
      MotionWindowSample(
        lateral: 0,
        vertical:
            index >= start && index < start + burstSamples ? vertical : 0,
        longitudinal: 0,
        at: DateTime.utc(2026, 1, 1).add(
          Duration(milliseconds: index * 20),
        ),
      ),
  ],
);

MotionEventKind? _kindOf(List<MotionPrediction> predictions) =>
    predictions.isEmpty ? null : predictions.first.kind;

void main() {
  const HeuristicMotionModel model = HeuristicMotionModel();

  test('exposes a stable id and the full label set', () {
    expect(model.id, 'heuristic-v1');
    expect(model.labels, MotionEventKind.values);
  });

  group('maneuver classification', () {
    test('sustained braking is a hard brake, signed negative', () {
      final List<MotionPrediction> predictions = model.infer(
        _steady(longitudinal: -4.0),
      );

      expect(_kindOf(predictions), MotionEventKind.hardBrake);
      expect(predictions.first.peakMps2, closeTo(-4.0, 1e-9));
      expect(predictions.first.confidence, greaterThan(0));
    });

    test('sustained acceleration is a hard launch, signed positive', () {
      final List<MotionPrediction> predictions = model.infer(
        _steady(longitudinal: 4.0),
      );

      expect(_kindOf(predictions), MotionEventKind.hardAccel);
      expect(predictions.first.peakMps2, closeTo(4.0, 1e-9));
    });

    test('sustained lateral force is a sharp turn, keeping its sign', () {
      final List<MotionPrediction> leftTurn = model.infer(
        _steady(lateral: 3.0),
      );
      expect(_kindOf(leftTurn), MotionEventKind.sharpTurn);
      expect(leftTurn.first.peakMps2, closeTo(3.0, 1e-9));

      final List<MotionPrediction> rightTurn = model.infer(
        _steady(lateral: -3.0),
      );
      expect(_kindOf(rightTurn), MotionEventKind.sharpTurn);
      expect(rightTurn.first.peakMps2, closeTo(-3.0, 1e-9));
    });

    test('a brief upward impulse is a speed bump', () {
      final List<MotionPrediction> predictions = model.infer(
        _burst(vertical: 6.0),
      );

      expect(_kindOf(predictions), MotionEventKind.speedBump);
      expect(predictions.first.peakMps2, closeTo(6.0, 1e-9));
    });

    test('a brief downward impulse is a pothole', () {
      final List<MotionPrediction> predictions = model.infer(
        _burst(vertical: -6.0),
      );

      expect(_kindOf(predictions), MotionEventKind.pothole);
      expect(predictions.first.peakMps2, closeTo(-6.0, 1e-9));
    });

    test('a calm window is a smooth drive', () {
      final List<MotionPrediction> predictions = model.infer(
        _steady(lateral: 0.2, vertical: 0.3, longitudinal: 0.1),
      );

      expect(_kindOf(predictions), MotionEventKind.smoothDrive);
      expect(predictions.first.peakMps2, 0);
      expect(predictions.first.confidence, greaterThan(0.5));
    });
  });

  group('rejecting false positives', () {
    test('a short longitudinal spike is not sustained braking', () {
      final MotionWindow window = MotionWindow(
        <MotionWindowSample>[
          for (int index = 0; index < MotionWindow.sampleCount; index++)
            MotionWindowSample(
              lateral: 0,
              vertical: 0,
              longitudinal: index == 60 ? -9.0 : 0.0,
              at: DateTime.utc(2026, 1, 1),
            ),
        ],
      );

      expect(_kindOf(model.infer(window)), MotionEventKind.smoothDrive);
    });

    test('a sustained vertical climb is not a bump (bumps are brief)', () {
      // A long ramp holds the vertical reading far past impulseMaxSamples.
      final List<MotionPrediction> predictions = model.infer(
        _burst(vertical: 6.0, burstSamples: 80),
      );

      expect(
        predictions.map((MotionPrediction p) => p.kind),
        isNot(contains(MotionEventKind.speedBump)),
      );
    });

    test('one window may report two maneuvers (braking into a corner)', () {
      final List<MotionPrediction> predictions = model.infer(
        _steady(lateral: 3.0, longitudinal: -4.0),
      );

      expect(
        predictions.map((MotionPrediction p) => p.kind),
        containsAll(<MotionEventKind>[
          MotionEventKind.hardBrake,
          MotionEventKind.sharpTurn,
        ]),
      );
      // Smooth drive never mixes with a maneuver: it means "nothing happened".
      expect(
        predictions.map((MotionPrediction p) => p.kind),
        isNot(contains(MotionEventKind.smoothDrive)),
      );
    });

    test('an empty window classifies as nothing at all', () {
      expect(model.infer(MotionWindow.empty), isEmpty);
    });
  });

  group('decodeMotionScores (the trained-model seam)', () {
    test('maps scores through the label order above the threshold', () {
      final MotionWindow window = _steady(vertical: 7.0);
      final List<MotionPrediction> predictions = decodeMotionScores(
        scores: <double>[0.1, 0.2, 0.3, 0.95, 0.05, 0.02],
        labels: MotionEventKind.values,
        window: window,
        minConfidence: 0.5,
      );

      expect(predictions.length, 1);
      expect(predictions.single.kind, MotionEventKind.speedBump);
      expect(predictions.single.confidence, closeTo(0.95, 1e-9));
      // The peak is measured from the window on the deciding axis.
      expect(predictions.single.peakMps2, closeTo(7.0, 1e-9));
    });

    test('returns strongest first and ignores low scores', () {
      final List<MotionPrediction> predictions = decodeMotionScores(
        scores: <double>[0.6, 0.9, 0.1, 0.1, 0.1, 0.1],
        labels: MotionEventKind.values,
        window: _steady(longitudinal: 3.0),
        minConfidence: 0.5,
      );

      expect(
        predictions.map((MotionPrediction p) => p.kind).toList(),
        <MotionEventKind>[
          MotionEventKind.hardAccel,
          MotionEventKind.hardBrake,
        ],
      );
      expect(predictions.first.confidence, 0.9);
    });

    test('tolerates a score vector that is shorter than the label set', () {
      final List<MotionPrediction> predictions = decodeMotionScores(
        scores: <double>[0.1, 0.8],
        labels: MotionEventKind.values,
        window: _steady(longitudinal: 5.0),
      );

      expect(predictions.single.kind, MotionEventKind.hardAccel);
    });

    test('ignores non-finite scores', () {
      final List<MotionPrediction> predictions = decodeMotionScores(
        scores: <double>[double.nan, double.infinity],
        labels: MotionEventKind.values,
        window: _steady(),
      );

      expect(predictions, isEmpty);
    });
  });

  group('decidingAxisPeak', () {
    test('reads the right axis and sign for every kind', () {
      final MotionWindow window = MotionWindow(
        <MotionWindowSample>[
          for (int index = 0; index < MotionWindow.sampleCount; index++)
            MotionWindowSample(
              lateral: index == 3 ? -2.5 : 0.5,
              vertical: index == 5 ? -8.0 : 0.5,
              longitudinal: index == 7 ? 6.0 : -1.0,
              at: DateTime.utc(2026, 1, 1),
            ),
        ],
      );

      expect(decidingAxisPeak(MotionEventKind.hardBrake, window), -1.0);
      expect(decidingAxisPeak(MotionEventKind.hardAccel, window), 6.0);
      // Largest *magnitude* on the lateral channel keeps the turn's sign, so
      // the -2.5 sample beats the +0.5 background.
      expect(decidingAxisPeak(MotionEventKind.sharpTurn, window), -2.5);
      expect(decidingAxisPeak(MotionEventKind.speedBump, window), 0.5);
      expect(decidingAxisPeak(MotionEventKind.pothole, window), -8.0);
      expect(decidingAxisPeak(MotionEventKind.smoothDrive, window), 0);
    });
  });

  group('model labels', () {
    test('match the published taxonomy', () {
      expect(
        MotionEventKind.values
            .map((MotionEventKind kind) => kind.modelLabel)
            .toList(),
        <String>[
          'Hard_Brake',
          'Hard_Accel',
          'Sharp_Turn',
          'Speed_Bump',
          'Pothole',
          'Smooth_Drive',
        ],
      );
    });

    test('round-trip through fromModelLabel', () {
      for (final MotionEventKind kind in MotionEventKind.values) {
        expect(MotionEventKind.fromModelLabel(kind.modelLabel), kind);
      }
      expect(MotionEventKind.fromModelLabel('Not_A_Class'), isNull);
    });
  });
}
