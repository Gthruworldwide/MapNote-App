import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motion_smooth/motion_smooth.dart';
import 'package:routenote/l10n/generated/app_localizations.dart';

import '../../domain/anti_gravity_models.dart';
import '../providers/anti_gravity_providers.dart';
import '../widgets/anti_gravity_visualizer.dart';

/// Full interactive telemetry dashboard and anti-gravity simulation visualizer.
class AntiGravityDashboardScreen extends ConsumerWidget {
  const AntiGravityDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simState = ref.watch(antiGravitySimulationProvider);
    final simNotifier = ref.read(antiGravitySimulationProvider.notifier);
    final config = ref.watch(antiGravityConfigProvider);
    final configNotifier = ref.read(antiGravityConfigProvider.notifier);
    final loc = AppLocalizations.of(context);

    final telemetry = simState.currentTelemetry;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Deep Obsidian
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.antiGravityTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
                color: Colors.white,
              ),
            ),
            Text(
              loc.antiGravitySubtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF10B981),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              simState.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: const Color(0xFF10B981),
              size: 28,
            ),
            tooltip: simState.isPlaying ? 'Pause' : 'Play',
            onPressed: simNotifier.togglePlay,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Reset',
            onPressed: simNotifier.reset,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Scenario Selector & Speed Bar
            _buildScenarioBar(context, simState, simNotifier),
            const SizedBox(height: 12),

            // 2. Trajectory Visualizer Canvas (Height: 260px)
            SizedBox(
              height: 260,
              child: AntiGravityVisualizer(
                rawPoints: simState.rawHistory,
                smoothedPoints: simState.smoothedHistory,
                antiGravityPoints: simState.antiGravityHistory,
                currentTelemetry: telemetry,
              ),
            ),
            const SizedBox(height: 12),

            // 3. Maneuver Alert Banner
            _buildManeuverBanner(context, telemetry),
            const SizedBox(height: 12),

            // 4. Primary Telemetry Metrics Grid
            _buildMetricsGrid(context, telemetry, config, simState),
            const SizedBox(height: 16),

            // 5. Physics Formula Card: $F_{net} = m \cdot (a_{motion} - g_{anti})$
            _buildFormulaCard(context, telemetry, config),
            const SizedBox(height: 16),

            // 6. Interactive Anti-Gravity Controls
            _buildControlPanel(context, config, configNotifier),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildScenarioBar(
    BuildContext context,
    AntiGravitySimulationState state,
    AntiGravitySimulationController notifier,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.route, color: Color(0xFF38BDF8), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AntiGravityScenario>(
                value: state.scenario,
                dropdownColor: const Color(0xFF1E293B),
                isDense: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                items: AntiGravityScenario.values.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(s.title),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) notifier.setScenario(val);
                },
              ),
            ),
          ),
          const VerticalDivider(color: Colors.white24, width: 20),
          // Playback speed chips
          ...[1.0, 2.0, 5.0].map((speed) {
            final isSelected = (state.playbackSpeed - speed).abs() < 0.1;
            return GestureDetector(
              onTap: () => notifier.setPlaybackSpeed(speed),
              child: Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF10B981)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${speed.toInt()}x',
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildManeuverBanner(
    BuildContext context,
    AntiGravityState? telemetry,
  ) {
    final maneuvers = telemetry?.activeManeuvers ?? [];
    final loc = AppLocalizations.of(context);

    if (maneuvers.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF064E3B).withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 16),
            SizedBox(width: 8),
            Text(
              'Dynamic Equilibrium — Trajectory Nominal',
              style: TextStyle(
                color: Color(0xFF34D399),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF7F1D1D).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: maneuvers.map((m) {
                String label;
                switch (m) {
                  case DrivingEventType.harshBraking:
                    label = loc.maneuverHarshBraking;
                    break;
                  case DrivingEventType.harshAcceleration:
                    label = loc.maneuverHarshAccel;
                    break;
                  case DrivingEventType.sharpTurn:
                  case DrivingEventType.harshCornering:
                    label = loc.maneuverSharpTurn;
                    break;
                  default:
                    label = m.name.toUpperCase();
                }
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(
    BuildContext context,
    AntiGravityState? telemetry,
    AntiGravityConfig config,
    AntiGravitySimulationState simState,
  ) {
    final loc = AppLocalizations.of(context);
    final speedKmh = telemetry?.speedKmh ?? 0.0;
    final netForceKn = telemetry?.netForceKn ?? 0.0;
    final apparentWeightKg = telemetry?.apparentWeightKg ?? config.massKg;
    final gForce = telemetry?.gForce ?? 1.0;

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: [
        // 1. Speed Metric
        _buildMetricCard(
          title: loc.telemetrySpeed,
          value: speedKmh.toStringAsFixed(1),
          unit: 'km/h',
          subtext: '${(telemetry?.velocityMps ?? 0).toStringAsFixed(1)} m/s',
          accentColor: const Color(0xFF38BDF8),
          icon: Icons.speed,
        ),

        // 2. Net Force ($F_{net}$)
        _buildMetricCard(
          title: loc.netForce,
          value: netForceKn.toStringAsFixed(2),
          unit: 'kN',
          subtext: '${(telemetry?.netForce.length ?? 0).toStringAsFixed(0)} N',
          accentColor: const Color(0xFF10B981),
          icon: Icons.compress,
        ),

        // 3. Apparent Weight
        _buildMetricCard(
          title: loc.apparentWeight,
          value: apparentWeightKg.toStringAsFixed(0),
          unit: 'kg',
          subtext: '${((apparentWeightKg / config.massKg) * 100).toStringAsFixed(0)}% base mass',
          accentColor: const Color(0xFFA78BFA),
          icon: Icons.fitness_center,
        ),

        // 4. Apparent G-Force
        _buildMetricCard(
          title: loc.telemetryGForce,
          value: gForce.toStringAsFixed(2),
          unit: 'G',
          subtext: 'Peak: ${simState.peakGForce.toStringAsFixed(2)} G',
          accentColor: gForce > 1.4 ? const Color(0xFFF59E0B) : const Color(0xFF34D399),
          icon: Icons.explore,
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String unit,
    required String subtext,
    required Color accentColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(icon, size: 16, color: accentColor.withValues(alpha: 0.8)),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Text(
            subtext,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulaCard(
    BuildContext context,
    AntiGravityState? telemetry,
    AntiGravityConfig config,
  ) {
    final aMag = telemetry?.accelerationVector.length ?? 0.0;
    final gAntiMag = telemetry?.antiGravityVector.length ?? 0.0;
    final fNetMag = telemetry?.netForce.length ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.functions, size: 16, color: Color(0xFF10B981)),
              SizedBox(width: 6),
              Text(
                'KINEMATIC TRANSFORM EQUATION',
                style: TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'F_net = m · (a_motion - g_anti)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '${fNetMag.toStringAsFixed(1)} N = ${config.massKg.toStringAsFixed(0)} kg · (${aMag.toStringAsFixed(2)} - ${gAntiMag.toStringAsFixed(2)}) m/s²',
              style: const TextStyle(
                color: Color(0xFF38BDF8),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(
    BuildContext context,
    AntiGravityConfig config,
    AntiGravityConfigController notifier,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ANTI-GRAVITY SIMULATION CONTROLS',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),

          // Simulation Mode Selector Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AntiGravityMode.values.map((mode) {
              final isSelected = config.mode == mode;
              return ChoiceChip(
                label: Text(mode.displayName),
                selected: isSelected,
                selectedColor: const Color(0xFF10B981),
                backgroundColor: const Color(0xFF0F172A),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (selected) {
                  if (selected) notifier.setMode(mode);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Mass Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Vehicle Mass (m):',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${config.massKg.toStringAsFixed(0)} kg',
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          Slider(
            value: config.massKg,
            min: 500.0,
            max: 5000.0,
            divisions: 45,
            activeColor: const Color(0xFF10B981),
            inactiveColor: Colors.white12,
            onChanged: notifier.setMass,
          ),

          // Smoothing Alpha Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'motion_smooth Alpha (α):',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                config.smoothingAlpha.toStringAsFixed(2),
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          Slider(
            value: config.smoothingAlpha,
            min: 0.05,
            max: 1.0,
            divisions: 19,
            activeColor: const Color(0xFF38BDF8),
            inactiveColor: Colors.white12,
            onChanged: notifier.setSmoothingAlpha,
          ),
        ],
      ),
    );
  }
}
