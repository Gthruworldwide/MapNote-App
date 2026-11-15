import 'package:flutter/material.dart';
import 'package:routenote/l10n/generated/app_localizations.dart';

import '../../data/models/station_model.dart';

/// A bottom sheet that allows support staff to find the nearest active
/// alternative stations for a given station and travel direction.
///
/// In a full implementation, the [allStations] list would be provided
/// via a Riverpod provider or passed as a constructor argument.
/// The [currentStationId] is the station that is broken/inactive.
/// [onStationSelected] is called when a station is selected from the results.
class StationLookupBottomSheet extends StatelessWidget {
  const StationLookupBottomSheet({
    required this.currentStationId,
    required this.onStationSelected,
    required this.allStations,
    super.key,
  });

  /// The ID of the currently broken/inactive station to find alternatives for.
  final String currentStationId;

  /// Called when a station is selected from the results.
  final void Function(Station station) onStationSelected;

  /// Optional pre-loaded list of all stations (from Hive/Drive).
  final List<Station> allStations;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Placeholder implementation - in a full app, this would show
    // a proper bottom sheet with search, filters, and result cards.
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.map, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                l10n.supportDispatchAssistant,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.selectStationForAlternatives,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // Dismiss the bottom sheet.
                  Navigator.of(context).pop();
                },
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
