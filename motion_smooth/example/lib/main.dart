import 'package:flutter/material.dart';
import 'package:motion_smooth/motion_smooth.dart';

void main() => runApp(const SmoothDemoApp());

/// Minimal demo app showing how to use motion_smooth.
class SmoothDemoApp extends StatelessWidget {
  const SmoothDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'motion_smooth Demo',
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: const SmoothDemoHome(),
    );
  }
}

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
  late List<DrivingEvent> _events;

  @override
  void initState() {
    super.initState();
    // Example raw GPS points (a simple drive route with some jitter)
    _rawPoints = const <RoutePoint>[
      RoutePoint(latitude: 30.0, longitude: 31.0, at: DateTime.now()),
      RoutePoint(latitude: 30.0005, longitude: 31.001, at: DateTime.now()),
      RoutePoint(latitude: 30.001, longitude: 31.002, at: DateTime.now()),
      RoutePoint(latitude: 30.0015, longitude: 31.003, at: DateTime.now()),
      RoutePoint(latitude: 30.0012, longitude: 31.004, at: DateTime.now()),
    ];
    _smoothedPoints = _smoother.smooth(_rawPoints);
    // Feed some speed data to the analyzer
    _analyzer.observeTransport(VehicleMode.vehicle);
    _analyzer.observeSpeed(0, at: DateTime.now());
    _analyzer.observeSpeed(5,
        at: DateTime.now().add(const Duration(seconds: 1)));
    _analyzer.observeSpeed(15,
        at: DateTime.now().add(const Duration(seconds: 2)));
    _analyzer.observeSpeed(15,
        at: DateTime.now().add(const Duration(seconds: 3)));
    _events = _analyzer.events;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('motion_smooth Demo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Raw GPS Points:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ..._rawPoints
                .map((point) => Text(
                    '${point.latitude}, ${point.longitude} at ${point.at}'))
                .toList(),
            const SizedBox(height: 24),
            const Text('Smoothed GPS Points:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ..._smoothedPoints
                .map((point) => Text(
                    '${point.latitude}, ${point.longitude} at ${point.at}'))
                .toList(),
            const SizedBox(height: 24),
            const Text('Detected Driving Events:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ..._events
                .map((event) => Text(
                    '${event.type}: ${event.peakMps2} m/s², started ${event.startedAt}, duration ${event.duration.inSeconds}s'))
                .toList(),
            const SizedBox(height: 24),
            const Text('Number of smoothed points: ${_smoothedPoints.length}'),
            const Text('Number of driving events: ${_events.length}'),
          ],
        ),
      ),
    );
  }
}
