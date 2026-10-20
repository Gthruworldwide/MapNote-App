import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../domain/entities/motion_window.dart';
import '../domain/services/motion_model.dart';
import '../domain/services/motion_inference_runner.dart';

/// One inference job handed to the worker.
class MotionInferenceRequest {
  const MotionInferenceRequest(this.id, this.window);

  final int id;
  final MotionWindow window;
}

/// The worker's answer to one [MotionInferenceRequest].
class MotionInferenceResponse {
  const MotionInferenceResponse(this.id, this.predictions);

  final int id;
  final List<MotionPrediction> predictions;
}

/// The worker's opening message: where to send results, and how to build the
/// model. The model is *built* on the far side rather than sent, because a live
/// interpreter cannot cross an isolate boundary.
///
/// Public only because it is part of the isolate entry point's signature — the
/// runner is the only thing that should ever construct one.
class MotionInferenceIsolateStart {
  const MotionInferenceIsolateStart({
    required this.replies,
    required this.buildModel,
  });

  final SendPort replies;
  final MotionModelBuilder buildModel;
}

/// Entry point of the inference isolate.
///
/// Top-level and `vm:entry-point`-marked for two reasons: a spawned isolate can
/// only reach top-level entry points, and the release AOT compiler must not
/// tree-shake it (which would only surface as a failure in a release build).
///
/// The worker owns the model for its whole life and answers requests one at a
/// time over a single channel. A window the model refuses yields an empty
/// answer — the worker never dies from ordinary data.
@pragma('vm:entry-point')
void motionInferenceIsolateMain(MotionInferenceIsolateStart start) {
  final MotionModel model = start.buildModel();
  final ReceivePort requests = ReceivePort();
  start.replies.send(requests.sendPort);
  requests.listen((Object? message) {
    if (message is MotionInferenceRequest) {
      List<MotionPrediction> predictions;
      try {
        predictions = model.infer(message.window);
      } catch (_) {
        // A single bad window must not take down the worker and stall the
        // whole trip; it simply contributes no events.
        predictions = const <MotionPrediction>[];
      }
      start.replies.send(MotionInferenceResponse(message.id, predictions));
      return;
    }
    // Anything else is the shutdown signal: drop the port and let the isolate
    // end on its own.
    requests.close();
  });
}

/// Runs inference on a **dedicated background isolate**, spawned once and kept
/// alive for the whole trip.
///
/// One worker beats spawning per window: at a 0.32 s hop this replaces ~3
/// isolate spawns a second with a single long-lived one, and the model is built
/// exactly once. Requests are matched to answers by id, so an abandoned or
/// late answer can never be attributed to the wrong window.
///
/// Failure is contained by design: spawn failures, worker death, errors and
/// timeouts all surface as an empty prediction list (and the worker is respawned
/// on the next window), because losing motion analytics must never disturb the
/// drive itself. Costs one isolate and a deep copy of the 128-sample window per
/// inference — well inside the sensor pipeline's budget.
class IsolateMotionInferenceRunner implements MotionInferenceRunner {
  IsolateMotionInferenceRunner({
    required this.buildModel,
    this.timeout = const Duration(seconds: 2),
    this.debugName = 'motion-inference',
  }) {
    _replies.listen(_onReply);
  }

  /// How to rebuild the model inside the worker (see [MotionModelBuilder]).
  final MotionModelBuilder buildModel;

  /// How long a spawn or a single inference may take before it is abandoned.
  final Duration timeout;

  /// Name shown for the isolate in debuggers and crash reports.
  final String debugName;

  final ReceivePort _replies = ReceivePort();
  final Map<int, Completer<List<MotionPrediction>>> _pending =
      <int, Completer<List<MotionPrediction>>>{};

  Isolate? _isolate;
  SendPort? _toWorker;
  Future<SendPort?>? _starting;
  Completer<SendPort?>? _handshake;
  ReceivePort? _errors;
  ReceivePort? _exits;
  StreamSubscription<Object?>? _errorsSubscription;
  StreamSubscription<Object?>? _exitsSubscription;
  int _nextRequestId = 0;
  bool _disposed = false;

  /// Whether a worker isolate is currently alive.
  bool get isRunning => _isolate != null;

  /// Windows awaiting an answer.
  int get pendingRequests => _pending.length;

  @override
  Future<List<MotionPrediction>> infer(MotionWindow window) async {
    if (_disposed) return const <MotionPrediction>[];

    final SendPort? toWorker;
    try {
      toWorker = await _ensureWorker().timeout(timeout);
    } on TimeoutException {
      return const <MotionPrediction>[];
    }
    if (toWorker == null || _disposed) return const <MotionPrediction>[];

    final int id = _nextRequestId++;
    final Completer<List<MotionPrediction>> reply =
        Completer<List<MotionPrediction>>();
    _pending[id] = reply;
    toWorker.send(MotionInferenceRequest(id, window));
    try {
      return await reply.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      return const <MotionPrediction>[];
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _failPending();
    _dropWorker(graceful: true);
    final Completer<SendPort?>? handshake = _handshake;
    _handshake = null;
    if (handshake != null && !handshake.isCompleted) handshake.complete(null);
    _replies.close();
  }

  /// The worker, spawning it on first use. `null` means "no worker available"
  /// — never an error, so callers degrade to no events.
  Future<SendPort?> _ensureWorker() {
    final SendPort? live = _toWorker;
    if (live != null) return Future<SendPort?>.value(live);
    final Future<SendPort?>? starting = _starting;
    if (starting != null) return starting;

    final Completer<SendPort?> handshake = Completer<SendPort?>();
    _handshake = handshake;
    final Future<SendPort?> pending = handshake.future;
    _starting = pending;
    unawaited(_spawn());
    return pending;
  }

  Future<void> _spawn() async {
    final ReceivePort errors = ReceivePort();
    final ReceivePort exits = ReceivePort();
    _errors = errors;
    _exits = exits;
    try {
      final Isolate isolate = await Isolate.spawn(
        motionInferenceIsolateMain,
        MotionInferenceIsolateStart(
          replies: _replies.sendPort,
          buildModel: buildModel,
        ),
        onError: errors.sendPort,
        onExit: exits.sendPort,
        debugName: debugName,
      );
      if (_disposed) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
      _isolate = isolate;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MapNote: motion inference isolate failed to start ($error)');
      }
      _workerLost();
      return;
    }
    _errorsSubscription = errors.listen((Object? message) {
      if (kDebugMode) {
        debugPrint('MapNote: motion inference isolate error ($message)');
      }
      _workerLost();
    });
    _exitsSubscription = exits.listen((Object? _) => _workerLost());
  }

  void _onReply(Object? message) {
    if (message is SendPort) {
      _toWorker = message;
      final Completer<SendPort?>? handshake = _handshake;
      _handshake = null;
      if (handshake != null && !handshake.isCompleted) handshake.complete(message);
      return;
    }
    if (message is MotionInferenceResponse) {
      final Completer<List<MotionPrediction>>? reply = _pending.remove(message.id);
      if (reply != null && !reply.isCompleted) reply.complete(message.predictions);
    }
  }

  /// Cancels the error/exit listeners and closes their ports.
  ///
  /// Order matters: a `ReceivePort` must be closed *after* its subscription is
  /// cancelled, otherwise the listener would be torn down by the port close
  /// while still stored here — the reference would outlive the port.
  void _closeWorkerPorts() {
    final StreamSubscription<Object?>? errors = _errorsSubscription;
    _errorsSubscription = null;
    unawaited(errors?.cancel());
    final StreamSubscription<Object?>? exits = _exitsSubscription;
    _exitsSubscription = null;
    unawaited(exits?.cancel());
    _errors?.close();
    _errors = null;
    _exits?.close();
    _exits = null;
  }

  /// Handles a worker that died (or never started): pending windows get empty
  /// answers and the next `infer` spawns a fresh worker.
  void _workerLost() {
    _isolate = null;
    _toWorker = null;
    _starting = null;
    final Completer<SendPort?>? handshake = _handshake;
    _handshake = null;
    if (handshake != null && !handshake.isCompleted) handshake.complete(null);
    _failPending();
    _closeWorkerPorts();
  }

  /// Drops the worker. [graceful] asks the worker to close its own `ReceivePort`
  /// before the isolate is killed, so the far side is not torn down mid-listen;
  /// on dispose that is the only chance to release it.
  void _dropWorker({required bool graceful}) {
    final Isolate? isolate = _isolate;
    final SendPort? worker = _toWorker;
    _isolate = null;
    _toWorker = null;
    _starting = null;
    if (graceful && worker != null) {
      // The worker treats any non-request message as its shutdown signal and
      // closes its `ReceivePort` (see [motionInferenceIsolateMain]).
      try {
        worker.send(const Object());
      } catch (_) {
        // The worker may already be gone; killing below is the backstop.
      }
    }
    isolate?.kill(priority: Isolate.immediate);
    _closeWorkerPorts();
  }

  void _failPending() {
    final List<Completer<List<MotionPrediction>>> replies = _pending.values
        .toList(growable: false);
    _pending.clear();
    for (final Completer<List<MotionPrediction>> reply in replies) {
      if (!reply.isCompleted) reply.complete(const <MotionPrediction>[]);
    }
  }
}
