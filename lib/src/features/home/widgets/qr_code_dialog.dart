import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/utils/haptics.dart';
import '../../../data/models/place.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Shows a QR code dialog encoding the place's map link, so another device can
/// scan it and open the location.
Future<void> showPlaceQrDialog(BuildContext context, Place place) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => _PlaceQrDialog(place: place),
  );
}

class _PlaceQrDialog extends StatelessWidget {
  const _PlaceQrDialog({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.qrCodeTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              place.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            // A white plate keeps the code scannable in dark mode.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                ),
              ),
              child: QrImageView(
                data: place.mapsLink,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              place.formattedCoordinates,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.qrCodeHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton.icon(
          onPressed: () async {
            final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
              context,
            );
            Haptics.light();
            await Clipboard.setData(ClipboardData(text: place.mapsLink));
            messenger.showSnackBar(SnackBar(content: Text(l10n.linkCopied)));
          },
          icon: const Icon(Icons.copy),
          label: Text(l10n.copyLink),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
