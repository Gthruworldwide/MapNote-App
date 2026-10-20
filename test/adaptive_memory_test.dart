import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/core/memory/adaptive_profile.dart';
import 'package:routenote/src/core/memory/adaptive_profile_key_store.dart';
import 'package:routenote/src/core/memory/adaptive_profile_repository.dart';
import 'package:routenote/src/core/memory/self_diagnostic_monitor.dart';

void main() {
  group('AdaptiveProfile defaults', () {
    test('defaults are the documented physical thresholds', () {
      expect(AdaptiveProfile.defaults.vibrationBaselineMps2, 0);
      expect(AdaptiveProfile.defaults.brakeThresholdMps2, 4.0);
      expect(AdaptiveProfile.defaults.accelThresholdMps2, 3.5);
      expect(AdaptiveProfile.defaults.bumpThresholdMps2, 3.0);
      expect(AdaptiveProfile.defaults.isTrustworthy, isFalse);
    });

    test('carries no user content — only numbers', () {
      final Map<String, Object?> map = AdaptiveProfile.defaults.toMap();
      for (final Object? value in map.values) {
        expect(value is num, isTrue, reason: 'only numeric values are stored');
      }
    });
  });

  group('learning', () {
    test('the first observation seeds the baseline exactly', () {
      final AdaptiveProfile learned =
          AdaptiveProfile.defaults.learn(vibrationRms: 0.5);

      expect(learned.vibrationBaselineMps2, 0.5);
      expect(learned.vibrationSamples, 1);
      expect(learned.drivesObserved, 1);
    });

    test('later observations adapt slowly', () {
      AdaptiveProfile profile = AdaptiveProfile.defaults.learn(vibrationRms: 0.4);
      profile = profile.learn(vibrationRms: 0.8);

      // 0.4 + (0.8 - 0.4) * 0.25 = 0.5
      expect(profile.vibrationBaselineMps2, closeTo(0.5, 1e-9));
      expect(profile.vibrationSamples, 2);
    });

    test('learn is pure — the receiver is unchanged', () {
      final AdaptiveProfile original = AdaptiveProfile.defaults.learn(
        vibrationRms: 0.3,
      );
      original.learn(vibrationRms: 9);

      expect(original.vibrationBaselineMps2, 0.3);
      expect(original.vibrationSamples, 1);
    });

    test('the noise floor only decreases', () {
      AdaptiveProfile profile =
          AdaptiveProfile.defaults.learn(noiseFloor: 0.2);
      profile = profile.learn(noiseFloor: 0.1);
      profile = profile.learn(noiseFloor: 0.5);

      expect(profile.noiseFloorMps2, 0.1);
      expect(profile.noiseSamples, 3);
    });

    test('a noisy mounting raises thresholds above the physical floor', () {
      AdaptiveProfile profile = AdaptiveProfile.defaults;
      // A rough mounting: characteristic residual well inside vehicle range but
      // much louder than the quiet-mount baseline the defaults assume.
      for (int i = 0; i < 20; i++) {
        profile = profile.learn(vibrationRms: 3.0);
      }

      expect(profile.vibrationBaselineMps2, greaterThan(2.0));
      expect(profile.brakeThresholdMps2, greaterThan(4.0));
      expect(profile.accelThresholdMps2, greaterThan(3.5));
      expect(profile.bumpThresholdMps2, greaterThan(3.0));
    });

    test('a quiet mounting leaves the thresholds at their starting values', () {
      AdaptiveProfile profile = AdaptiveProfile.defaults;
      for (int i = 0; i < 20; i++) {
        profile = profile.learn(vibrationRms: 0.3);
      }

      // The baseline is far below the floors, so nothing is loosened — the
      // thresholds neither rise nor fall below where they started.
      expect(profile.brakeThresholdMps2, AdaptiveProfile.defaults.brakeThresholdMps2);
      expect(profile.accelThresholdMps2, AdaptiveProfile.defaults.accelThresholdMps2);
      expect(profile.bumpThresholdMps2, AdaptiveProfile.defaults.bumpThresholdMps2);
    });

    test('thresholds never drop below the physical minima', () {
      AdaptiveProfile profile = AdaptiveProfile.defaults;
      for (int i = 0; i < 10; i++) {
        profile = profile.learn(vibrationRms: 0.001);
      }

      expect(profile.brakeThresholdMps2,
          greaterThanOrEqualTo(AdaptiveProfile.minBrakeMps2));
      expect(profile.accelThresholdMps2,
          greaterThanOrEqualTo(AdaptiveProfile.minAccelMps2));
      expect(profile.bumpThresholdMps2,
          greaterThanOrEqualTo(AdaptiveProfile.minBumpMps2));
    });

    test('becomes trustworthy after enough drives', () {
      AdaptiveProfile profile = AdaptiveProfile.defaults;
      for (int i = 0; i < AdaptiveProfile.minDrivesForTrust; i++) {
        expect(profile.isTrustworthy, isFalse);
        profile = profile.learn(vibrationRms: 0.4);
      }
      expect(profile.isTrustworthy, isTrue);
    });

    test('non-finite and negative observations are ignored', () {
      final AdaptiveProfile profile = AdaptiveProfile.defaults
          .learn(vibrationRms: double.nan)
          .learn(vibrationRms: -1)
          .learn(vibrationRms: double.infinity);

      expect(profile.vibrationSamples, 0);
      expect(profile.vibrationBaselineMps2, 0);
    });
  });

  group('serialization', () {
    test('round-trips every field', () {
      AdaptiveProfile profile = AdaptiveProfile.defaults
          .learn(vibrationRms: 0.6, noiseFloor: 0.12)
          .learn(vibrationRms: 0.7);

      final AdaptiveProfile restored =
          AdaptiveProfile.fromMap(Map<String, dynamic>.from(profile.toMap()));

      expect(restored.vibrationBaselineMps2, profile.vibrationBaselineMps2);
      expect(restored.vibrationSamples, profile.vibrationSamples);
      expect(restored.noiseFloorMps2, profile.noiseFloorMps2);
      expect(restored.brakeThresholdMps2, profile.brakeThresholdMps2);
      expect(restored.drivesObserved, profile.drivesObserved);
      expect(restored.revision, profile.revision);
    });

    test('a malformed record degrades field-by-field to the defaults', () {
      final AdaptiveProfile restored = AdaptiveProfile.fromMap(
        <String, dynamic>{
          'vibrationBaselineMps2': 'not a number',
          'drivesObserved': 4,
        },
      );

      expect(restored.vibrationBaselineMps2,
          AdaptiveProfile.defaults.vibrationBaselineMps2);
      expect(restored.drivesObserved, 4);
      expect(restored.brakeThresholdMps2,
          AdaptiveProfile.defaults.brakeThresholdMps2);
    });

    test('an empty record yields the defaults', () {
      final AdaptiveProfile restored = AdaptiveProfile.fromMap(<String, dynamic>{});
      expect(restored.brakeThresholdMps2,
          AdaptiveProfile.defaults.brakeThresholdMps2);
      expect(restored.drivesObserved, 0);
    });
  });

  group('AdaptiveProfileKeyStore', () {
    test('generates and reuses a 32-byte key', () async {
      final Map<String, String> values = <String, String>{};
      final AdaptiveProfileKeyStore store = AdaptiveProfileKeyStore(
        read: (String key) async => values[key],
        write: (String key, String value) async => values[key] = value,
      );

      final first = await store.loadOrCreateKey();
      final second = await store.loadOrCreateKey();

      expect(first.length, AdaptiveProfileKeyStore.keyLength);
      expect(second, first);
    });

    test('replaces a corrupt stored key instead of failing', () async {
      final Map<String, String> values = <String, String>{
        'mapnote.adaptive.aesKey': 'not-a-valid-key',
      };
      final AdaptiveProfileKeyStore store = AdaptiveProfileKeyStore(
        read: (String key) async => values[key],
        write: (String key, String value) async => values[key] = value,
      );

      final key = await store.loadOrCreateKey();
      expect(key.length, AdaptiveProfileKeyStore.keyLength);
    });
  });

  group('AdaptiveProfileRepository (no Hive available)', () {
    test('load falls back to the defaults when the box cannot open', () async {
      final AdaptiveProfileRepository repository = AdaptiveProfileRepository(
        keyStore: AdaptiveProfileKeyStore(
          read: (_) async => null,
          write: (_, _) async {},
        ),
        boxName: 'this_box_will_fail_to_open_without_hive_init',
      );

      final AdaptiveProfile profile = await repository.load();

      expect(profile.brakeThresholdMps2,
          AdaptiveProfile.defaults.brakeThresholdMps2);
      expect(repository.isLoaded, isTrue);
    });

    test('save reports failure without throwing and keeps the value in memory',
        () async {
      final AdaptiveProfileRepository repository = AdaptiveProfileRepository(
        keyStore: AdaptiveProfileKeyStore(
          read: (_) async => null,
          write: (_, _) async {},
        ),
        boxName: 'this_box_will_fail_to_open_without_hive_init',
      );

      final AdaptiveProfile learned =
          AdaptiveProfile.defaults.learn(vibrationRms: 0.5);
      final bool saved = await repository.save(learned);

      expect(saved, isFalse);
      // The current run still uses the learned numbers.
      expect(repository.profile.vibrationBaselineMps2, 0.5);
    });

    test('clear reverts to the defaults in memory', () async {
      final AdaptiveProfileRepository repository = AdaptiveProfileRepository(
        keyStore: AdaptiveProfileKeyStore(
          read: (_) async => null,
          write: (_, _) async {},
        ),
        boxName: 'this_box_will_fail_to_open_without_hive_init',
      );
      await repository.save(AdaptiveProfile.defaults.learn(vibrationRms: 0.5));

      await repository.clear();

      expect(repository.profile.vibrationBaselineMps2, 0);
    });
  });

  group('SelfDiagnosticMonitor', () {
    late DateTime now;
    late int memoryBytes;

    SelfDiagnosticMonitor build({
      double jank = 32,
      Duration memoryInterval = const Duration(seconds: 30),
    }) =>
        SelfDiagnosticMonitor(
          readMemoryBytes: () => memoryBytes,
          jankThresholdMillis: jank,
          memorySampleInterval: memoryInterval,
          clock: () => now,
        );

    setUp(() {
      now = DateTime.utc(2026, 1, 1);
      memoryBytes = 64 * 1024 * 1024;
    });

    test('a smooth frame is not janky', () {
      final monitor = build();

      monitor.recordFrame(buildMillis: 8, rasterMillis: 4);

      expect(monitor.frameCount, 1);
      expect(monitor.jankyFrameCount, 0);
      expect(monitor.hasJank, isFalse);
    });

    test('a frame over the threshold is janky', () {
      final monitor = build();

      monitor.recordFrame(buildMillis: 25, rasterMillis: 20);

      expect(monitor.jankyFrameCount, 1);
      expect(monitor.hasJank, isTrue);
    });

    test('build and raster are summed before the threshold', () {
      final monitor = build();

      // Each half is under 32 ms, but together they are not.
      monitor.recordFrame(buildMillis: 18, rasterMillis: 18);

      expect(monitor.jankyFrameCount, 1);
    });

    test('worst frame times are tracked', () {
      final monitor = build();

      monitor.recordFrame(buildMillis: 5, rasterMillis: 3);
      monitor.recordFrame(buildMillis: 20, rasterMillis: 9);
      monitor.recordFrame(buildMillis: 8, rasterMillis: 15);

      final DiagnosticSnapshot snapshot = monitor.snapshot();
      expect(snapshot.worstBuildMillis, 20);
      expect(snapshot.worstRasterMillis, 15);
      expect(snapshot.frames, 3);
    });

    test('jank ratio is a fraction of frames', () {
      final monitor = build();

      monitor.recordFrame(buildMillis: 40, rasterMillis: 0);
      monitor.recordFrame(buildMillis: 1, rasterMillis: 1);
      monitor.recordFrame(buildMillis: 1, rasterMillis: 1);
      monitor.recordFrame(buildMillis: 1, rasterMillis: 1);

      expect(monitor.snapshot().jankRatio, closeTo(0.25, 1e-9));
    });

    test('memory is sampled at most once per interval', () {
      final monitor = build(memoryInterval: const Duration(seconds: 30));

      expect(monitor.sampleMemory(), 64 * 1024 * 1024);
      // Immediately again: too soon, so nothing is read.
      memoryBytes = 128 * 1024 * 1024;
      expect(monitor.sampleMemory(), isNull);

      now = now.add(const Duration(seconds: 31));
      expect(monitor.sampleMemory(), 128 * 1024 * 1024);
    });

    test('a throwing memory reader is swallowed', () {
      final monitor = SelfDiagnosticMonitor(
        readMemoryBytes: () => throw StateError('no process info here'),
        clock: () => now,
      );

      expect(monitor.sampleMemory(), isNull);
      expect(monitor.snapshot().memoryBytes, 0);
    });

    test('background and foreground time are accumulated separately', () {
      final monitor = build();

      monitor.onLifecycle(backgrounded: false);
      now = now.add(const Duration(seconds: 10));
      monitor.onLifecycle(backgrounded: true);
      now = now.add(const Duration(seconds: 5));
      monitor.onLifecycle(backgrounded: false);

      final DiagnosticSnapshot snapshot = monitor.snapshot();
      expect(snapshot.foregroundFor, const Duration(seconds: 10));
      expect(snapshot.backgroundFor, const Duration(seconds: 5));
    });

    test('drain returns the window and resets the counters', () {
      final monitor = build();

      monitor.recordFrame(buildMillis: 40, rasterMillis: 0);
      final DiagnosticSnapshot drained = monitor.drain();

      expect(drained.frames, 1);
      expect(drained.jankyFrames, 1);
      expect(monitor.frameCount, 0);
      expect(monitor.jankyFrameCount, 0);
    });

    test('reset clears timing and memory counters', () {
      final monitor = build();
      monitor.recordFrame(buildMillis: 40, rasterMillis: 0);
      monitor.sampleMemory();

      monitor.reset();

      expect(monitor.frameCount, 0);
      expect(monitor.snapshot().memoryBytes, 0);
    });

    test('toData contains only numbers and coarse values', () {
      final monitor = build();
      monitor.recordFrame(buildMillis: 40, rasterMillis: 10);
      monitor.sampleMemory();

      final Map<String, Object?> data = monitor.snapshot().toData();

      expect(data['frames'], 1);
      expect(data['janky'], 1);
      expect(data['memoryMiB'], isA<double>());
      expect(data.keys, contains('backgroundS'));
    });

    test('empty snapshot is all zeroes', () {
      const DiagnosticSnapshot empty = DiagnosticSnapshot.empty;
      expect(empty.frames, 0);
      expect(empty.jankRatio, 0);
      expect(empty.memoryMiB, 0);
    });
  });
}
