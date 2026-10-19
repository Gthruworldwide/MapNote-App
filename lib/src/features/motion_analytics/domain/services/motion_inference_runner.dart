import 'motion_model.dart';
import '../entities/motion_window.dart';

/// Runs a [MotionModel]'s inference away from the platform thread.
///
/// The contract is deliberately tiny so the pipeline can be exercised
/// deterministically in tests: `MLClassifierIsolate` buffers and de-duplicates
/// events, while *this* decides **where** the model actually runs — a real
/// background isolate in the app, straight on the caller's isolate in unit
/// tests (see `InlineMotionInferenceRunner`).
///
/// Implementations never throw. A window that cannot be classified — a dead
/// worker, a timeout, a refused model — yields an empty list, so a broken
/// inference path degrades to "no events" instead of taking the trip down.
abstract class MotionInferenceRunner {
  /// Classifies one window.
  Future<List<MotionPrediction>> infer(MotionWindow window);

  /// Releases the worker. Safe to call more than once.
  Future<void> dispose();
}
