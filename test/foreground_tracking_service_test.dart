import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/foreground_tracking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    ForegroundTrackingService.channelName,
  );
  final List<String> calls = <String>[];

  setMockHandler({required bool answer}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call.method);
      return answer;
    });
  }

  setUp(() {
    calls.clear();
    setMockHandler(answer: true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('requests permissions, starts once, stops once', () async {
    final ForegroundTrackingService service = ForegroundTrackingService();

    // Nothing runs while neither tracker is enabled.
    await service.sync(needed: false);
    expect(calls, isEmpty);
    expect(service.isRunning, isFalse);

    await service.sync(needed: true);
    expect(calls, <String>[
      'requestNotificationPermission',
      'requestBackgroundLocationPermission',
      'startForeground',
    ]);
    expect(service.isRunning, isTrue);

    // Idempotent: a second "needed" must not restart or re-prompt.
    await service.sync(needed: true);
    expect(calls.where((String method) => method == 'startForeground'),
        hasLength(1));

    await service.sync(needed: false);
    expect(calls.last, 'stopForeground');
    expect(service.isRunning, isFalse);

    // Already stopped: no further channel traffic.
    final int before = calls.length;
    await service.sync(needed: false);
    expect(calls, hasLength(before));
  });

  test('a refused platform start leaves the service not running', () async {
    final ForegroundTrackingService service = ForegroundTrackingService();

    setMockHandler(answer: false);
    await service.sync(needed: true);
    expect(calls, contains('startForeground'));
    expect(service.isRunning, isFalse);

    // The next sync retries (e.g. after the user returns to the foreground).
    setMockHandler(answer: true);
    await service.sync(needed: true);
    expect(service.isRunning, isTrue);
  });

  test('a missing platform channel is a silent no-op', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    final ForegroundTrackingService service = ForegroundTrackingService();
    await service.sync(needed: true);
    expect(service.isRunning, isFalse);

    await service.requestPermissions();
    expect(service.isRunning, isFalse);
  });

  test('a native side that never replies times out into a safe no-op',
      () async {
    // Permission calls answer immediately; only startForeground hangs on
    // forever — a destroyed activity that never processes the message.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call.method);
      if (call.method == 'startForeground') {
        return Completer<Object?>().future; // never completes
      }
      return true;
    });

    final ForegroundTrackingService service = ForegroundTrackingService(
      invokeTimeout: const Duration(milliseconds: 50),
    );

    final Stopwatch elapsed = Stopwatch()..start();
    await service.sync(needed: true);
    elapsed.stop();

    expect(calls, <String>[
      'requestNotificationPermission',
      'requestBackgroundLocationPermission',
      'startForeground',
    ]);
    expect(
      service.isRunning,
      isFalse,
      reason: 'the stuck start reports failure instead of wedging on',
    );
    expect(
      elapsed.elapsed,
      lessThan(const Duration(seconds: 10)),
      reason: 'invokeTimeout bounds the wait, not the (dead) platform side',
    );

    // And the service is not wedged: with the native side answering again,
    // the very next sync starts normally.
    setMockHandler(answer: true);
    await service.sync(needed: true);
    expect(service.isRunning, isTrue);
  });
}
