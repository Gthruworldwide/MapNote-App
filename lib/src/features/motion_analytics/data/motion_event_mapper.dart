import '../../../services/motion_profiler.dart';
import '../domain/entities/motion_event.dart';

/// Bridges one classified [MotionEvent] into the profiler's maneuver log.
///
/// This is the single place where the motion-analytics taxonomy meets the
/// driving-event taxonomy, so neither side has to know about the other:
/// `MotionBehaviorAnalyzer` stays a dependency-free service and [MotionEvent]
/// stays a pure entity.
///
/// Returns `null` for [MotionEventKind.smoothDrive]: smooth driving is a
/// *state*, not a maneuver, so it has no place in a log of things that
/// happened.
///
/// The classified kinds carry [Duration.zero], because the classifier reports
/// the instant a window crossed its threshold rather than how long the driver
/// held it — that hold is what the speed-timeline path measures.
DrivingEvent? toDrivingEvent(MotionEvent event) => switch (event.kind) {
  MotionEventKind.hardBrake => DrivingEvent(
    type: DrivingEventType.harshBraking,
    peakMps2: event.peakMps2,
    startedAt: event.startedAt,
    duration: Duration.zero,
  ),
  MotionEventKind.hardAccel => DrivingEvent(
    type: DrivingEventType.harshAcceleration,
    peakMps2: event.peakMps2,
    startedAt: event.startedAt,
    duration: Duration.zero,
  ),
  MotionEventKind.sharpTurn => DrivingEvent(
    type: DrivingEventType.sharpTurn,
    peakMps2: event.peakMps2,
    startedAt: event.startedAt,
    duration: Duration.zero,
  ),
  MotionEventKind.speedBump => DrivingEvent(
    type: DrivingEventType.speedBump,
    peakMps2: event.peakMps2,
    startedAt: event.startedAt,
    duration: Duration.zero,
  ),
  MotionEventKind.pothole => DrivingEvent(
    type: DrivingEventType.pothole,
    peakMps2: event.peakMps2,
    startedAt: event.startedAt,
    duration: Duration.zero,
  ),
  MotionEventKind.smoothDrive => null,
};
