import '../domain/entities/motion_window.dart';
import '../domain/services/motion_model.dart';
import '../domain/services/motion_inference_runner.dart';

/// Runs the model on the caller's isolate.
///
/// Used by unit tests (which need deterministic, isolate-free scheduling) and
/// as the fallback when a real worker cannot be spawned. The production path is
/// `IsolateMotionInferenceRunner`.
class InlineMotionInferenceRunner implements MotionInferenceRunner {
  InlineMotionInferenceRunner(this.model);

  /// The model to run.
  final MotionModel model;

  @override
  Future<List<MotionPrediction>> infer(MotionWindow window) async =>
      model.infer(window);

  @override
  Future<void> dispose() async {}
}
