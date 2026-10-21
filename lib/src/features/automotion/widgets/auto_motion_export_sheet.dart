import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/auto_motion_data_source.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../../services/auto_motion_export_service.dart';

/// Bottom sheet offering CSV/JSON export of AutoMotion aggregates for a
/// selectable date range. All output is coordinate-free.
class AutoMotionExportBottomSheet extends ConsumerStatefulWidget {
  const AutoMotionExportBottomSheet({super.key});

  @override
  ConsumerState<AutoMotionExportBottomSheet> createState() =>
      _AutoMotionExportBottomSheetState();
}

class _AutoMotionExportBottomSheetState
    extends ConsumerState<AutoMotionExportBottomSheet> {
  DateTimeRange? _range;
  String? _lastOutput;

  Future<void> _pickRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _export(bool asJson) {
    final AutoMotionDataSource store = ref.read(autoMotionDataSourceProvider);
    final AutoMotionExportService service =
        AutoMotionExportService(store);
    final String out = asJson
        ? service.exportJson(from: _range?.start, to: _range?.end)
        : service.exportCsv(from: _range?.start, to: _range?.end);
    setState(() {
      _lastOutput = out;
    });
  }

  Future<void> _copy() async {
    if (_lastOutput == null) return;
    await Clipboard.setData(ClipboardData(text: _lastOutput!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).autoMotionExportCopied),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.autoMotionExport,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              l10n.zeroCoordinatesNotice,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range),
              label: Text(
                _range == null
                    ? l10n.autoMotionSelectRange
                    : l10n.autoMotionRangeLabel(
                        _format(_range!.start),
                        _format(_range!.end),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _export(false),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: Text(l10n.autoMotionExportCsv),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _export(true),
                    icon: const Icon(Icons.data_object),
                    label: Text(l10n.autoMotionExportJson),
                  ),
                ),
              ],
            ),
            if (_lastOutput != null) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: SingleChildScrollView(
                  child: SelectableText(
                    _lastOutput!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: Text(l10n.autoMotionExportCopy),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _format(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
