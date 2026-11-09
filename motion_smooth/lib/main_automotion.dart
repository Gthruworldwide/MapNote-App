import 'package:flutter/material.dart';
import 'package:motion_smooth/motion_smooth.dart';

/// Main entry point for the AutoMotion Edition.
///
/// This variant focuses on the core motion analysis and GPS smoothing features.
class AutoMotionApp extends StatelessWidget {
  const AutoMotionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MapNote AutoMotion',
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
      home: const AutoMotionHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Simple home screen for AutoMotion Edition.
class AutoMotionHome extends StatefulWidget {
  const AutoMotionHome({super.key});

  @override
  State<AutoMotionHome> createState() => _AutoMotionHomeState();
}

class _AutoMotionHomeState extends State<AutoMotionHome> {
  final MotionBehaviorAnalyzer _analyzer = MotionBehaviorAnalyzer();
  VehicleMode _currentMode = VehicleMode.vehicle;

  List<RoutePoint> _rawPoints = [];
  List<RoutePoint> _smoothedPoints = [];

  @override
  void initState() {
    super.initState();
    _initializeDemoData();
  }

  void _initializeDemoData() {
    _rawPoints = const <RoutePoint>[
      RoutePoint(latitude: 30.0, longitude: 31.0),
      RoutePoint(latitude: 30.0008, longitude: 31.001),
      RoutePoint(latitude: 30.0015, longitude: 31.002),
      RoutePoint(latitude: 30.002, longitude: 31.003),
      RoutePoint(latitude: 30.0025, longitude: 31.004),
    ];
    _smoothedPoints = PolylineSmoother.smooth(_rawPoints);
    _analyzer.observeTransport(_currentMode);
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
        title: const Text('MapNote AutoMotion'),
        actions: [
          IconButton(
            icon: Icon(
              _currentMode == VehicleMode.vehicle
                  ? Icons.drive_eta
                  : Icons.person,
            ),
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
            const Text(
              'Raw GPS Points:',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.green),
            ),
            const SizedBox(height: 4),
            ..._rawPoints
                .map(
                  (point) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                )
                .toList(),
            const SizedBox(height: 12),
            const Text(
              'Smoothed GPS Points:',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue),
            ),
            const SizedBox(height: 4),
            ..._smoothedPoints
                .map(
                  (point) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                )
                .toList(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Raw: ', style: TextStyle(fontSize: 12)),
                Text('${_rawPoints.length}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
                const Text(' | Smoothed: ', style: TextStyle(fontSize: 12)),
                Text('${_smoothedPoints.length}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const Spacer(),
            const Card(
              elevation: 1,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('motion_smooth v0.0.3 - AutoMotion Edition',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                        'EMA filter removes GPS jitter, preserves corners and turns',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                    SizedBox(height: 4),
                    Text('Harsh acceleration, braking, sharp turns detected',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
