import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:routenote/src/core/offline/offline_map_provider.dart';
import 'package:routenote/l10n/generated/app_localizations.dart';

/// Dialog for selecting map region and zoom levels for offline download.
///
/// Allows users to:
/// - Define a geographic region by minimum/maximum latitude and longitude
/// - Select zoom levels for tile download
class RegionSelectionDialog extends ConsumerWidget {
  const RegionSelectionDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    final minLatController = TextEditingController();
    final maxLatController = TextEditingController();
    final minLngController = TextEditingController();
    final maxLngController = TextEditingController();
    final minZoomController = TextEditingController(text: '5');
    final maxZoomController = TextEditingController(text: '12');

    return AlertDialog(
      title: Text(l10n.offlineMapRegionSelection),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildTextFieldRow(
              context: context,
              labels: [l10n.minLatitude, l10n.maxLatitude],
              controllers: [minLatController, maxLatController],
              hint: l10n.latitudeHint,
              validator: (value) {
                if (value == null || value.isEmpty) return 'required';
                final double? lat = double.tryParse(value);
                if (lat == null || lat < -90 || lat > 90) return 'invalid latitude';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildTextFieldRow(
              context: context,
              labels: [l10n.minLongitude, l10n.maxLongitude],
              controllers: [minLngController, maxLngController],
              hint: l10n.longitudeHint,
              validator: (value) {
                if (value == null || value.isEmpty) return 'required';
                final double? lng = double.tryParse(value);
                if (lng == null || lng < -180 || lng > 180) return 'invalid longitude';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildTextFieldRow(
              context: context,
              labels: [l10n.minZoom, l10n.maxZoom],
              controllers: [minZoomController, maxZoomController],
              hint: l10n.zoomHint,
              validator: (value) {
                if (value == null || value.isEmpty) return 'required';
                final int? zoom = int.tryParse(value);
                if (zoom == null || zoom < 0 || zoom > 20) return 'zoom 0-20';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final minLat = double.tryParse(minLatController.text);
            final maxLat = double.tryParse(maxLatController.text);
            final minLng = double.tryParse(minLngController.text);
            final maxLng = double.tryParse(maxLngController.text);
            final minZoom = int.tryParse(minZoomController.text);
            final maxZoom = int.tryParse(maxZoomController.text);

            if (minLat != null &&
                maxLat != null &&
                minLng != null &&
                maxLng != null &&
                minZoom != null &&
                maxZoom != null &&
                minLat < maxLat &&
                minLng < maxLng &&
                minZoom >= 0 &&
                maxZoom <= 20 &&
                minZoom <= maxZoom) {
              ref
                  .read(offlineMapProvider.notifier)
                  .startDownload(
                    minLat: minLat,
                    maxLat: maxLat,
                    minLng: minLng,
                    maxLng: maxLng,
                    minZoom: minZoom,
                    maxZoom: maxZoom,
                  );
              Navigator.of(context).pop();
            }
          },
          child: Text(l10n.startDownload),
        ),
      ],
    );
  }

  Widget _buildTextFieldRow({
    required BuildContext context,
    required List<String> labels,
    required List<TextEditingController> controllers,
    required String hint,
    required String? Function(String?) validator,
  }) {
    return Row(
      children: List.generate(2, (index) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextFormField(
              controller: controllers[index],
              decoration: InputDecoration(
                hintText: hint,
                labelText: labels[index],
                border: const OutlineInputBorder(),
              ),
              validator: validator,
            ),
          ),
        );
      }),
    );
  }
}