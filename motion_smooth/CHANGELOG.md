# Changelog

## [0.0.1] - 2026-11-08

### Added
- Initial release of `motion_smooth`
- `PolylineSmoother` with Kalman-filter based GPS jitter removal
- `MotionBehaviorAnalyzer` with harsh acceleration/braking detection
- `RoutePoint` class for GPS vertex representation
- `DrivingEvent` and `DrivingEventType` enums
- Comprehensive unit tests for both modules
- Example project demonstrating core usage
- Full API documentation with generics and configuration options

## [0.0.2] - 2026-11-08

### Added
- `Harsh Cornering Detection` to `MotionBehaviorAnalyzer` — detects sudden direction changes based on angular rate and lateral acceleration
- `Heading/Bearing Interpolation` in `PolylineSmoother` — circular angle smoothing to prevent 180° flips at low speeds
- Expanded unit test suite for directional and angular behavior

### Changed
- Updated `MotionBehaviorAnalyzer` with new cornering sensitivity parameters
- Updated `PolylineSmoother` with bearing calculation and smoothing utilities