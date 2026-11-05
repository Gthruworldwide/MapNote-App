import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:routenote/src/core/offline/offline_map_provider.dart';
import 'package:routenote/src/core/offline/region_selection_dialog.dart';

/// Screen for managing offline maps.
///
/// Provides an interface to:
/// - Start new offline map downloads
/// - View download progress
/// - List available offline maps
/// - Clear stored maps to free storage
class OfflineMapManagerScreen extends ConsumerWidget {
  const OfflineMapManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offlineMapProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Offline Maps')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Download controls card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Pre-load saved places maps',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: state.status == DownloadStatus.idle
                                ? () => _showRegionDialog(context, ref)
                                : null,
                            icon: const Icon(Icons.flag),
                            label: const Text('Select Region'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: state.status == DownloadStatus.idle
                                ? () => ref
                                    .read(offlineMapProvider.notifier)
                                    .cancelDownload()
                                : null,
                            icon: const Icon(Icons.stop),
                            label: state.status == DownloadStatus.downloading
                                ? const Text('Cancel')
                                : const Text('Resume'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (state.status != DownloadStatus.idle)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: LinearProgressIndicator(
                                value: state.progress,
                                minHeight: 8,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              state.progress >= 1.0
                                  ? 'Offline maps downloaded'
                                  : '${state.progress.toInt()}%',
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Downloaded maps preview
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Downloaded Maps',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No maps downloaded yet',
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

  /// Show the region selection dialog
  static void _showRegionDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => const RegionSelectionDialog(),
    );
  }
}

/// Extension for formatting progress percentage
extension IntPercentExtension on int {
  String toIntPercent() => '${toInt()}%';
}