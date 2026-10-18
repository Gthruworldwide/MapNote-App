import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/gap_recovery_service.dart';

void main() {
  group('GapRecoveryService.haversineKm', () {
    test('identical points are zero kilometres apart', () {
      expect(
        GapRecoveryService.haversineKm(30.0444, 31.2590, 30.0444, 31.2590),
        0.0,
      );
    });

    test('one degree of latitude is about 111.19 km', () {
      final double km = GapRecoveryService.haversineKm(0, 0, 1, 0);
      expect(km, closeTo(111.19, 0.5));
    });

    test('is symmetric: A→B measures the same as B→A', () {
      final double ab =
          GapRecoveryService.haversineKm(30.0444, 31.2590, 31.5761, 35.1131);
      final double ba =
          GapRecoveryService.haversineKm(31.5761, 35.1131, 30.0444, 31.2590);
      expect(ab, greaterThan(0));
      expect(ab, closeTo(ba, 1e-9));
    });
  });

  group('GapRecoveryService.initialBearingDegrees', () {
    test('travel due north reads ~0°', () {
      final double bearing =
          GapRecoveryService.initialBearingDegrees(30.0, 31.0, 31.0, 31.0);
      expect(bearing, closeTo(0, 0.1));
    });

    test('travel due east at a constant latitude reads ~90°', () {
      final double bearing =
          GapRecoveryService.initialBearingDegrees(30.0, 31.0, 30.0, 32.0);
      expect(bearing, closeTo(90, 0.5));
    });
  });

  group('GapRecoveryService.judge', () {
    const GapRecoveryService service = GapRecoveryService();

    test('a gap that is not positive recovers nothing and implies no speed', () {
      final GapVerdict zeroGap =
          service.judge(gap: Duration.zero, crossingKm: 30);
      expect(zeroGap.recoveredKm, 0);
      expect(zeroGap.impliedSpeedKmh, isNull);
      expect(zeroGap.recovered, isFalse);

      final GapVerdict negativeGap = service.judge(
        gap: const Duration(seconds: -5),
        crossingKm: 30,
      );
      expect(negativeGap.recoveredKm, 0);
      expect(negativeGap.impliedSpeedKmh, isNull);
      expect(negativeGap.recovered, isFalse);
    });

    test('a plausible 45-minute 30 km drive is bridged in full', () {
      final GapVerdict verdict = service.judge(
        gap: const Duration(minutes: 45),
        crossingKm: 30,
      );
      expect(verdict.crossingKm, 30);
      expect(verdict.impliedSpeedKmh, closeTo(40, 1e-9));
      expect(verdict.recoveredKm, 30);
      expect(verdict.recovered, isTrue);
    });

    test('a 600 km/h teleport across a one-minute gap is refused, not bridged',
        () {
      final GapVerdict verdict = service.judge(
        gap: const Duration(minutes: 1),
        crossingKm: 10,
      );
      expect(verdict.crossingKm, 10);
      expect(verdict.impliedSpeedKmh, closeTo(600, 0.01));
      expect(verdict.recoveredKm, 0);
      expect(verdict.recovered, isFalse);
    });

    test('exactly the 160 km/h ceiling is still recovered', () {
      final GapVerdict verdict = service.judge(
        gap: const Duration(hours: 1),
        crossingKm: 160,
      );
      expect(verdict.impliedSpeedKmh, closeTo(160, 1e-9));
      expect(verdict.recoveredKm, 160);
      expect(verdict.recovered, isTrue);
    });

    test('a negative crossing distance is clamped to zero', () {
      final GapVerdict verdict = service.judge(
        gap: const Duration(minutes: 1),
        crossingKm: -5,
      );
      expect(verdict.crossingKm, 0);
      expect(verdict.impliedSpeedKmh, 0);
      expect(verdict.recoveredKm, 0);
      expect(verdict.recovered, isFalse);
    });
  });

  group('GapRecoveryService.judgeFix', () {
    const GapRecoveryService service = GapRecoveryService();
    final DateTime t0 = DateTime(2026, 10, 18, 8);

    test('a plausible resumption recovers the measured crossing with a bearing',
        () {
      final GapVerdict verdict = service.judgeFix(
        lastFixAt: t0,
        lastLatitude: 30.0,
        lastLongitude: 31.0,
        resumedAt: t0.add(const Duration(minutes: 30)),
        resumedLatitude: 30.2, // ~22 km due north
        resumedLongitude: 31.0,
      );
      final double crossing =
          GapRecoveryService.haversineKm(30.0, 31.0, 30.2, 31.0);
      expect(crossing, closeTo(22.2, 0.5));
      expect(verdict.crossingKm, closeTo(crossing, 1e-9));
      expect(verdict.recoveredKm, closeTo(crossing, 1e-9));
      expect(verdict.impliedSpeedKmh, closeTo(crossing / 0.5, 1e-6));
      expect(verdict.crossingBearingDegrees, isNotNull);
      expect(verdict.crossingBearingDegrees, closeTo(0, 0.1));
      expect(verdict.recovered, isTrue);
    });

    test('an implausible resumption is refused but still carries a bearing', () {
      final GapVerdict verdict = service.judgeFix(
        lastFixAt: t0,
        lastLatitude: 30.0,
        lastLongitude: 31.0,
        resumedAt: t0.add(const Duration(seconds: 5)),
        resumedLatitude: 30.09, // ~10 km in five seconds
        resumedLongitude: 31.0,
      );
      expect(verdict.crossingKm, greaterThan(9));
      expect(verdict.impliedSpeedKmh, greaterThan(6000));
      expect(verdict.recoveredKm, 0);
      expect(verdict.recovered, isFalse);
      expect(verdict.crossingBearingDegrees, closeTo(0, 0.1));
    });

    test('recoveredKm agrees with judge() on the same gap and crossing', () {
      const Duration gap = Duration(minutes: 20);
      final double crossing =
          GapRecoveryService.haversineKm(30.0, 31.0, 30.3, 31.4);
      final GapVerdict fromDistance =
          service.judge(gap: gap, crossingKm: crossing);
      final GapVerdict fromFixes = service.judgeFix(
        lastFixAt: t0,
        lastLatitude: 30.0,
        lastLongitude: 31.0,
        resumedAt: t0.add(gap),
        resumedLatitude: 30.3,
        resumedLongitude: 31.4,
      );
      expect(fromFixes.crossingKm, fromDistance.crossingKm);
      expect(fromFixes.recoveredKm, fromDistance.recoveredKm);
      expect(fromFixes.impliedSpeedKmh, fromDistance.impliedSpeedKmh);
      expect(fromFixes.crossingBearingDegrees, isNotNull);
    });
  });

  group('GapVerdict.recovered', () {
    test('is true only when distance was actually appended', () {
      const GapVerdict bridged = GapVerdict(
        crossingKm: 12,
        impliedSpeedKmh: 48,
        recoveredKm: 12,
      );
      const GapVerdict refused = GapVerdict(
        crossingKm: 12,
        impliedSpeedKmh: 900,
        recoveredKm: 0,
      );
      const GapVerdict empty = GapVerdict(
        crossingKm: 0,
        impliedSpeedKmh: null,
        recoveredKm: 0,
      );
      expect(bridged.recovered, isTrue);
      expect(refused.recovered, isFalse);
      expect(empty.recovered, isFalse);
    });
  });
}
