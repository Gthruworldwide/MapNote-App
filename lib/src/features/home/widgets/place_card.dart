import 'package:flutter/material.dart';

import '../../../data/models/place.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// A single saved location shown in the home list.
///
/// When [Place.isLocked] is true the title, notes and coordinates are replaced
/// by blurred placeholder bars so the raw text never leaks onto the screen.
class PlaceCard extends StatelessWidget {
  const PlaceCard({
    super.key,
    required this.place,
    required this.onTap,
    required this.onNavigate,
    this.onLongPress,
  });

  final Place place;
  final VoidCallback onTap;
  final VoidCallback onNavigate;

  /// Opens the context menu (bottom sheet) with privacy + quick actions.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String? notes = place.notes.trim().isEmpty ? null : place.notes;
    final bool masked = place.isLocked;

    // A dedicated GestureDetector owns the long-press gesture (with its own
    // slop/hysteresis) so micro-drifts and ListView scroll gestures cannot
    // accidentally trigger onTap or fire the context menu twice.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      onLongPressStart: (_) {},
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.20),
                  ),
                ),
                child: Icon(
                  Icons.place_outlined,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (place.isPinned) ...<Widget>[
                          Icon(
                            Icons.push_pin,
                            size: 16,
                            color: theme.colorScheme.primary,
                            semanticLabel: l10n.pinnedLabel,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (place.isLocked) ...<Widget>[
                          Icon(
                            Icons.lock,
                            size: 16,
                            color: theme.colorScheme.primary,
                            semanticLabel: l10n.lockedLabel,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: masked
                              ? const _LockMask(height: 20, widthFactor: 0.55)
                              : Text(
                                  place.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium,
                                ),
                        ),
                      ],
                    ),
                    if (notes != null)
                      masked
                          ? const _LockMask(
                              height: 14,
                              widthFactor: 0.92,
                              top: 3,
                            )
                          : Text(
                              notes,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                    if (masked)
                      const _LockMask(height: 14, widthFactor: 0.5, top: 3)
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            place.formattedCoordinates,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            place.plusCode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.navigate,
                onPressed: onNavigate,
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.10,
                  ),
                  foregroundColor: theme.colorScheme.primary,
                ),
                icon: const Icon(Icons.directions, size: 20),
              ),
            ],
          ),
        ),
      ),
    ),   // Card close
    );   // GestureDetector close
  }
}

/// A blurred-looking placeholder bar used to hide sensitive text while a place
/// is locked, instead of painting the real title / notes / coordinates.
class _LockMask extends StatelessWidget {
  const _LockMask({
    required this.height,
    required this.widthFactor,
    this.top = 0,
  });

  final double height;
  final double widthFactor;

  /// Extra spacing above the bar so masked lines still feel line-height'd.
  final double top;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: colors.onSurface.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(height / 3),
          ),
        ),
      ),
    );
  }
}
