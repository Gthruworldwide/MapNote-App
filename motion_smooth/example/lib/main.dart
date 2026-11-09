import 'package:flutter/material.dart';
import 'package:motion_smooth/motion_smooth.dart';

void main() => runApp(const SmoothDemoApp());

/// Minimal demo app for motion_smooth v0.0.3.
/// Demonstrates GPS polyline smoothing and motion behavior analysis.
class SmoothDemoApp extends StatelessWidget {
  const SmoothDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'motion_smooth Demo',
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.light(
          primary: Color(0xFF1B6C4A),
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: Color(0xFF66BB6A),
          onPrimary: Colors.black,
          surface: Color(0xFF1E1E1E),
          onSurface: Colors.white,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const SmoothDemoHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Home screen demonstrating motion_smooth features.
class SmoothDemoHome extends StatefulWidget {
  const SmoothDemoHome({super.key});

  @override
  State<SmoothDemoHome> createState() => _SmoothDemoHomeState();
}

class _SmoothDemoHomeState extends State<SmoothDemoHome> {
  final PolylineSmoother _smoother = PolylineSmoother();
  final MotionBehaviorAnalyzer _analyzer = MotionBehaviorAnalyzer();

  late List<RoutePoint> _rawPoints;
  late List<RoutePoint> _smoothedPoints;
  VehicleMode _currentMode = VehicleMode.vehicle;

  @override
  void initState() {
    super.initState();
    _initializeDemoData();
  }

  void _initializeDemoData() {
    // Raw GPS points representing a driving route with some jitter
    _rawPoints = const <RoutePoint>[
      RoutePoint(latitude: 30.0, longitude: 31.0),
      RoutePoint(latitude: 30.0008, longitude: 31.001),
      RoutePoint(latitude: 30.0015, longitude: 31.002),
      RoutePoint(latitude: 30.002, longitude: 31.003),
      RoutePoint(latitude: 30.0025, longitude: 31.004),
    ];

    // Smooth the raw points using PolylineSmoother static method
    _smoothedPoints = PolylineSmoother.smooth(_rawPoints);

    // Initialize the motion behavior analyzer with vehicle mode
    _analyzer.observeTransport(_currentMode);

    // Feed sample speed data to demonstrate event detection
    // observeSpeed requires: 2 positional args (speed, at) + named parameter
    _analyzer.observeSpeed(0, DateTime.now());
    _analyzer.observeSpeed(5, DateTime.now().add(const Duration(seconds: 1)));
    _analyzer.observeSpeed(15, DateTime.now().add(const Duration(seconds: 2)));
    _analyzer.observeSpeed(15, DateTime.now().add(const Duration(seconds: 3)));
    _analyzer.observeSpeed(15, DateTime.now().add(const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('motion_smooth Demo'),
        actions: [
          // Mode selector - simplified
          IconButton(
            icon: Icon(
              _currentMode == VehicleMode.vehicle
                  ? Icons.drive_eta
                  : Icons.person,
            ),
            tooltip: _currentMode == VehicleMode.vehicle
                ? 'Pedestrian mode'
                : 'Vehicle mode',
            onPressed: () {
              setState(() {
                _currentMode = _currentMode == VehicleMode.vehicle
                    ? VehicleMode.pedestrian
                    : VehicleMode.vehicle;
                _analyzer.observeTransport(_currentMode);
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- GPS Smoothing Section ---
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GPS Polyline Smoothing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'PolylineSmoother uses exponential moving average filtering to remove '
                      'GPS jitter while preserving true path geometry including corners and turns. '
                      'Pure Dart implementation with no platform channels or method calls.',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 12),
                    // Raw points
                    const Text(
                      'Raw GPS Points:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._rawPoints
                        .map(
                          (point) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              '${point.latitude.toStringAsFixed(4)}, '
                              '${point.longitude.toStringAsFixed(4)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    const SizedBox(height: 12),
                    // Smoothed points
                    const Text(
                      'Smoothed GPS Points:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._smoothedPoints
                        .map(
                          (point) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              '${point.latitude.toStringAsFixed(4)}, '
                              '${point.longitude.toStringAsFixed(4)}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.blue),
                            ),
                          ),
                        )
                        .toList(),
                    const SizedBox(height: 8),
                    // Summary stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Raw: ',
                          style: TextStyle(fontSize: 12),
                        ),
                        Text(
                          '${_rawPoints.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Text(
                          ' | Smoothed: ',
                          style: TextStyle(fontSize: 12),
                        ),
                        Text(
                          '${_smoothedPoints.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // --- Motion Behavior Section ---
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Motion Behavior Analysis',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'MotionBehaviorAnalyzer detects driving maneuvers using GPS speed data:',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    // Event type chips using DrivingEventType
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: DrivingEventType.values
                          .map(
                            (type) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _eventColor(type).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: BorderSide(
                                  color: _eventColor(type).withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                _eventLabel(type),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    // Speed and mode info
                    Row(
                      children: [
                        const Icon(
                          Icons.speed,
                          size: 20,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Speed: --- m/s',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Mode chip
                    ChoiceChip(
                      label: const Text('Vehicle'),
                      selected: _currentMode == VehicleMode.vehicle,
                      onSelected: (bool selected) {
                        setState(() {
                          _currentMode = selected
                              ? VehicleMode.vehicle
                              : VehicleMode.pedestrian;
                          _analyzer.observeTransport(_currentMode);
                        });
                      },
                      avatar: const Icon(
                        Icons.drive_eta,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // --- Features Summary ---
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'motion_smooth v0.0.3 - Features Demonstrated:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _featureRow(
                      icon: Icons.map,
                      label: 'Polyline Smoothing',
                      desc:
                          'EMA filter removes GPS jitter, preserves corners and turns',
                    ),
                    const SizedBox(height: 4),
                    _featureRow(
                      icon: Icons.dangerous,
                      label: 'Maneuver Detection',
                      desc:
                          'Harsh acceleration, braking, sharp turns, speed bumps, potholes, harsh cornering',
                    ),
                    const SizedBox(height: 4),
                    _featureRow(
                      icon: Icons.compass_calibration,
                      label: 'Heading Interp.',
                      desc:
                          'Circular smoothing prevents 180° flips at low speeds',
                    ),
                    const SizedBox(height: 4),
                    _featureRow(
                      icon: Icons.transfer_within_a_station,
                      label: 'Mode Adaptation',
                      desc:
                          'Vehicle vs pedestrian threshold adjustment via _mode field',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow({
    required IconData icon,
    required String label,
    required String desc,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 12,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Text(
          desc,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Color _eventColor(DrivingEventType type) {
    switch (type) {
      case DrivingEventType.harshAcceleration:
        return Colors.orange;
      case DrivingEventType.harshBraking:
        return Colors.red;
      case DrivingEventType.sharpTurn:
        return Colors.blue;
      case DrivingEventType.speedBump:
        return Colors.amber;
      case DrivingEventType.pothole:
        return Colors.brown;
      case DrivingEventType.harshCornering:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _eventLabel(DrivingEventType type) {
    switch (type) {
      case DrivingEventType.harshAcceleration:
        return 'Harsh Accel';
      case DrivingEventType.harshBraking:
        return 'Hard Brk';
      case DrivingEventType.sharpTurn:
        return 'Sharp Tn';
      case DrivingEventType.speedBump:
        return 'Speed Bump';
      case DrivingEventType.pothole:
        return 'Pothole';
      case DrivingEventType.harshCornering:
        return 'Harsh Crn';
      default:
        return 'Unknown';
    }
  }
}
