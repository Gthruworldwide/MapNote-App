import 'package:flutter/material.dart';
import 'package:motion_smooth/motion_smooth.dart';

/// Main entry point for the Work Edition.
///
/// This variant is configured for enterprise/work environments with
/// separate package ID, distinct name, and branding.
class WorkApp extends StatelessWidget {
  const WorkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MapNote Work',
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.light(
          primary: Color(0xFF1976D2),
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: Color(0xFF1565C0),
          onPrimary: Colors.white,
          surface: Color(0xFF1E1E1E),
          onSurface: Colors.white,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const WorkHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Home screen for Work Edition.
class WorkHome extends StatefulWidget {
  const WorkHome({super.key});

  @override
  State<WorkHome> createState() => _WorkHomeState();
}

class _WorkHomeState extends State<WorkHome> {
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
      RoutePoint(latitude: 40.0, longitude: -74.0),
      RoutePoint(latitude: 40.0005, longitude: -74.001),
      RoutePoint(latitude: 40.001, longitude: -74.002),
      RoutePoint(latitude: 40.0015, longitude: -74.003),
      RoutePoint(latitude: 40.002, longitude: -74.004),
    ];
    _smoothedPoints = PolylineSmoother.smooth(_rawPoints);
    _analyzer.observeTransport(_currentMode);
    _analyzer.observeSpeed(0, DateTime.now());
    _analyzer.observeSpeed(10, DateTime.now().add(const Duration(seconds: 1)));
    _analyzer.observeSpeed(25, DateTime.now().add(const Duration(seconds: 2)));
    _analyzer.observeSpeed(25, DateTime.now().add(const Duration(seconds: 3)));
    _analyzer.observeSpeed(25, DateTime.now().add(const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MapNote Work'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield, color: Colors.blueGrey),
            tooltip: 'Privacy',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Work Edition: Enterprise data governance active'),
                  backgroundColor: Colors.blueGrey,
                  behavior: SnackBarBehavior.floating,
                ),
              );
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
                    Text('motion_smooth v0.0.3 - Work Edition',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Fleet management optimized, data governance active',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                    SizedBox(height: 4),
                    Text('Audit logging and compliance features',
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
