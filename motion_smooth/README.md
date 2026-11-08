# motion_smooth

[![Pub Version](https://img.shields.io/pub/v/motion_smooth.svg)](https://pub.dev/packages/motion_smooth)
[![XERJ Corpus Hub contributor](https://hub.xerj.org/contributors/Gthruworldwide/badge.svg)](https://hub.xerj.org/contributors/Gthruworldwide)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A high-performance Flutter package for smoothing GPS polylines and analyzing driver motion behavior.

## Features

- **Polyline Smoothing**: Advanced Kalman-filter based smoothing that removes GPS jitter while preserving true path geometry
- **Motion Behavior Analysis**: Detects harsh acceleration, hard braking, and other driving maneuvers from GPS speed and accelerometer data
- **Offline-First**: All processing runs locally — no network required
- **Pure Dart**: No platform channels, no method calls, fully testable in isolation
- **WGS-84 Geometry**: Uses equirectangular projection for local tangent plane calculations

## Getting Started

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  motion_smooth: ^0.0.1
```

### Polyline Smoothing

```dart
import 'package:motion_smooth/motion_smooth.dart';

// Raw GPS points (lat/lng with optional timestamps)
final rawPoints = <RoutePoint>[
  RoutePoint(latitude: 30.0, longitude: 31.0, at: DateTime.now()),
  RoutePoint(latitude: 30.0005, longitude: 31.001, at: DateTime.now()),
  // ... more points
];

// Smooth the polyline — removes jitter, preserves corners
final smoothed = PolylineSmoother().smooth(rawPoints);

// Access the smoothed points
for (final point in smoothed) {
  print('${point.latitude}, ${point.longitude}');
}
```

### Motion Behavior Analysis

```dart
import 'package:motion_smooth/motion_smooth.dart';

// Analyze driving behavior from GPS speed and accelerometer data
final analyzer = MotionBehaviorAnalyzer();

// Feed GPS speed readings (m/s)
analyzer.observeTransport(VehicleMode.vehicle);
analyzer.observeSpeed(0, at: DateTime.now());
analyzer.observeSpeed(5, at: DateTime.now().add(const Duration(seconds: 1)));
analyzer.observeSpeed(15, at: DateTime.now().add(const Duration(seconds: 2)));

// Detect events
final events = analyzer.events;

// Listen for events as they're detected
analyzer.onEvent.listen((event) {
  print('Detected: ${event.type}, peak: ${event.peakMps2} m/s²');
});

// Feed accelerometer data
analyzer.feed(x: 0, y: 0, z: 9.81);

// Check current state
print('Is vehicle context: ${analyzer.isVehicleContext}');
print('Last variance RMS: ${analyzer.lastVarianceRms}');
print('Instant acceleration: ${analyzer.instantAccelerationMps2}');
```

### Custom Configuration

```dart
// Tuned for urban delivery driving — more responsive thresholds
final analyzer = MotionBehaviorAnalyzer(
  harshAccelerationThresholdMps2: 3.0,
  harshBrakingThresholdMps2: 3.5,
  minEventDuration: const Duration(seconds: 0.5),
  movingVarianceRms: 0.20,
);
```

## API Reference

### Classes

- **[RoutePoint](https://pub.dev/documentation/motion_smooth/latest/motion_smooth/RoutePoint-class.html)** — A single GPS fix with latitude, longitude, and optional timestamp
- **[PolylineSmoother](https://pub.dev/documentation/motion_smooth/latest/motion_smooth/PolylineSmoother-class.html)** — Smooths GPS polylines using a per-axis Kalman filter
- **[DrivingEvent](https://pub.dev/documentation/motion_smooth/latest/motion_smooth/DrivingEvent-class.html)** — A detected driving maneuver with type, peak acceleration, start time, and duration
- **[MotionBehaviorAnalyzer](https://pub.dev/documentation/motion_smooth/latest/motion_smooth/MotionBehaviorAnalyzer-class.html)** — Analyzes driving behavior from speed and accelerometer data
- **[DrivingEventType](https://pub.dev/documentation/motion_smooth/latest/motion_smooth/DrivingEventType-enum.html)** — Types of driving events: `harshAcceleration`, `harshBraking`, `sharpTurn`, `speedBump`, `pothole`
- **[VehicleMode](https://pub.dev/documentation/motion_smooth/latest/motion_smooth/VehicleMode-enum.html)** — Transport modes: `vehicle`, `walking`, `train`, `unknown`

### Enums

- **[DrivingEventType](https://pub.dev/documentation/motion_smooth/latest/motion_smooth/DrivingEventType-enum.html)**
  - `harshAcceleration`
  - `harshBraking`
  - `sharpTurn`
  - `speedBump`
  - `pothole`

- **[VehicleMode](https://pub.dev/documentation/motion_smooth/latest/motion_smooth/VehicleMode-enum.html)**
  - `vehicle`
  - `walking`
  - `train`
  - `unknown`

### Constants

- **[PolylineSmoother.earthRadiusKm](https://pub.dev/documentation/motion_smooth/latest/motion_smooth/PolylineSmoother/earthRadiusKm-constant.html)**: `6371.0088` — Mean Earth radius in kilometers

## Example

See the [`example/`](example/) directory for a complete working demo that demonstrates:
- Passing raw GPS points through `PolylineSmoother`
- Feeding speed and accelerometer data into `MotionBehaviorAnalyzer`
- Accessing smoothed points and detected events

## Additional Information

- **Platforms**: Android, iOS, Web, Desktop
- **SDK**: `>=3.0.0 <4.0.0`, `flutter: >=3.10.0`
- **Dependencies**: `latlong2` (for coordinate utilities), none beyond Flutter

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Changelog

### v0.0.1 — Initial Release

- `PolylineSmoother` with Kalman-filter based GPS jitter removal
- `MotionBehaviorAnalyzer` with harsh acceleration/braking detection
- Comprehensive unit tests for both modules
- Example project demonstrating core usage