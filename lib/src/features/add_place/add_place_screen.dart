import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/haptics.dart';
import '../../core/utils/plus_code.dart';
import '../../data/models/place.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../../services/app_logger.dart';
import '../../services/location_parser.dart';
import '../../services/location_service.dart';

/// How the user is providing the coordinates for a place.
enum LocationEntryMode {
  /// Read the device's current GPS position.
  gps,

  /// Type or paste latitude/longitude by hand.
  manual,
}

/// Captures the current GPS position — or a manually entered / pasted one — and
/// lets the user name it.
///
/// When [place] is provided the screen edits that existing location instead of
/// capturing a new one. When [initialLatitude]/[initialLongitude] are provided
/// (for example from a shared map link) the screen opens in manual mode with
/// those coordinates pre-filled. [initialMode] forces a starting mode (used by
/// the home "Add location" menu).
class AddPlaceScreen extends ConsumerStatefulWidget {
  const AddPlaceScreen({
    super.key,
    this.place,
    this.initialLatitude,
    this.initialLongitude,
    this.initialName,
    this.initialMode,
  });

  final Place? place;
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialName;
  final LocationEntryMode? initialMode;

  @override
  ConsumerState<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends ConsumerState<AddPlaceScreen> {
  static const Uuid _uuid = Uuid();
  static const LocationParser _parser = LocationParser();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final TextEditingController _plusCodeController;

  LocationEntryMode _mode = LocationEntryMode.gps;
  LocationResult? _location;
  bool _capturing = false;
  bool _pasting = false;
  bool _saving = false;

  bool get _isEditing => widget.place != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.place?.name ?? widget.initialName ?? '',
    );
    _notesController = TextEditingController(text: widget.place?.notes ?? '');
    _latitudeController = TextEditingController();
    _longitudeController = TextEditingController();
    _plusCodeController = TextEditingController();

    final Place? place = widget.place;
    final bool hasInitial =
        widget.initialLatitude != null && widget.initialLongitude != null;

    if (place != null) {
      // Editing: start from the stored coordinates, but let the user change
      // them without depending on a fresh GPS fix.
      _mode = LocationEntryMode.manual;
      _latitudeController.text = place.latitude.toString();
      _longitudeController.text = place.longitude.toString();
    } else if (hasInitial) {
      // Opened from a shared/pasted location.
      _mode = LocationEntryMode.manual;
      _latitudeController.text = widget.initialLatitude!.toString();
      _longitudeController.text = widget.initialLongitude!.toString();
    } else if (widget.initialMode == LocationEntryMode.manual) {
      // Opened straight into manual entry (e.g. from the Add location menu).
      _mode = LocationEntryMode.manual;
    } else {
      _mode = LocationEntryMode.gps;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _captureLocation();
      });
    }

    // Seed the Plus Code preview from any coordinates that are already known
    // (an edit, a shared location, or the GPS fix that follows shortly).
    _refreshPlusCode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _plusCodeController.dispose();
    super.dispose();
  }

  Future<void> _captureLocation() async {
    setState(() => _capturing = true);
    final LocationService service = ref.read(locationServiceProvider);
    final LocationResult result = await service.determinePosition();
    if (!mounted) return;
    setState(() {
      _location = result;
      _capturing = false;
    });
  }

  void _setMode(LocationEntryMode mode) {
    if (mode == _mode) return;
    if (mode == LocationEntryMode.manual) {
      // Seed the manual fields from the last GPS fix so nothing is lost.
      if (_latitudeController.text.trim().isEmpty &&
          _location is LocationSuccess) {
        final LocationSuccess success = _location! as LocationSuccess;
        _latitudeController.text = success.latitude.toString();
        _longitudeController.text = success.longitude.toString();
      }
      setState(() => _mode = mode);
      _refreshPlusCode();
      return;
    }

    setState(() => _mode = mode);
    if (_location is! LocationSuccess) _captureLocation();
  }

  /// Recomputes the Plus Code whenever the manual latitude/longitude change.
  ///
  /// The field is a live preview, refreshed from the coordinates that are the
  /// source of truth; it is never saved itself.
  void _refreshPlusCode() {
    final double? latitude = double.tryParse(_latitudeController.text.trim());
    final double? longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude != null &&
        longitude != null &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180) {
      final String next = PlusCode.encode(latitude, longitude);
      if (_plusCodeController.text != next) {
        _plusCodeController.text = next;
      }
    } else if (_plusCodeController.text.isNotEmpty) {
      _plusCodeController.text = '';
    }
  }

  /// Decodes a Plus Code typed or pasted into the manual field and fills the
  /// latitude/longitude fields with its centre point.
  ///
  /// Programmatic `controller.text =` writes do not re-trigger the text fields'
  /// `onChanged`, so this cannot loop back into the Plus Code field.
  void _applyPlusCode(String value) {
    final PlusCodePoint? decoded = PlusCode.decode(value);
    if (decoded == null) return;
    // Five decimals is the precision the app already shows for coordinates and
    // is far finer than the ~13.5 m cell a ten-digit code describes, so this
    // only strips the binary-floating-point noise (e.g. 47.365562499999996).
    _latitudeController.text = decoded.latitude.toStringAsFixed(5);
    _longitudeController.text = decoded.longitude.toStringAsFixed(5);
  }

  /// Reads the clipboard and fills in any coordinates (and name) it finds.
  Future<void> _pasteFromClipboard() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() => _pasting = true);
    String text = '';
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text?.trim() ?? '';
    } finally {
      if (mounted) setState(() => _pasting = false);
    }

    ParsedLocation? parsed;
    if (text.isNotEmpty) {
      parsed = _parser.parse(text);
      if (parsed == null && _parser.looksLikeShortMapLink(text)) {
        if (mounted) setState(() => _pasting = true);
        parsed = await _parser.resolveShortLink(text);
        if (mounted) setState(() => _pasting = false);
      }
    }

    if (!mounted) return;
    if (parsed == null) {
      AppLogger.log(
        category: 'LOCATION_PARSER',
        message: 'Failed to parse pasted location',
        error: '"$text" did not match the maps/regex patterns',
        level: LogLevel.warning,
      );
      ref
          .read(appHealthLoggerProvider)
          .logParseFailure(
            source: 'add_place',
            shortLink: text.isNotEmpty && _parser.looksLikeShortMapLink(text),
          );
      messenger.showSnackBar(SnackBar(content: Text(l10n.clipboardNoLocation)));
      return;
    }

    final ParsedLocation location = parsed;
    setState(() {
      _mode = LocationEntryMode.manual;
      _latitudeController.text = location.latitude.toString();
      _longitudeController.text = location.longitude.toString();
      final String? name = location.name ?? _parser.guessName(text);
      if (name != null && name.isNotEmpty) _nameController.text = name;
    });
    messenger.showSnackBar(SnackBar(content: Text(l10n.clipboardPasted)));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    Haptics.light();

    final double? latitude;
    final double? longitude;
    if (_mode == LocationEntryMode.gps) {
      final LocationResult? location = _location;
      if (location is! LocationSuccess) return;
      latitude = location.latitude;
      longitude = location.longitude;
    } else {
      latitude = double.tryParse(_latitudeController.text.trim());
      longitude = double.tryParse(_longitudeController.text.trim());
      if (latitude == null || longitude == null) return;
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    final Place? original = widget.place;
    final Place place = original == null
        ? Place(
            id: _uuid.v4(),
            name: _nameController.text.trim(),
            notes: _notesController.text.trim(),
            latitude: latitude,
            longitude: longitude,
            timestamp: DateTime.now().toUtc(),
          )
        : original.copyWith(
            name: _nameController.text.trim(),
            notes: _notesController.text.trim(),
            latitude: latitude,
            longitude: longitude,
          );

    setState(() => _saving = true);
    await ref.read(placesProvider.notifier).save(place);

    messenger.showSnackBar(SnackBar(content: Text(l10n.placeSaved)));
    if (mounted) navigator.pop();
  }

  String? _validateLatitude(String? value) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return l10n.coordinateRequired;
    final double? parsed = double.tryParse(text);
    if (parsed == null) return l10n.coordinateInvalid;
    if (parsed < -90 || parsed > 90) return l10n.latitudeRange;
    return null;
  }

  String? _validateLongitude(String? value) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return l10n.coordinateRequired;
    final double? parsed = double.tryParse(text);
    if (parsed == null) return l10n.coordinateInvalid;
    if (parsed < -180 || parsed > 180) return l10n.longitudeRange;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.editPlaceTitle : l10n.addPlaceTitle),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _buildModeSelector(l10n),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (_pasting || _saving) ? null : _pasteFromClipboard,
              icon: _pasting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.content_paste_go),
              label: Text(l10n.pasteFromClipboard),
            ),
            const SizedBox(height: 16),
            if (_mode == LocationEntryMode.gps)
              _buildLocationCard(l10n)
            else
              _buildManualCoordinates(l10n),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.fieldName,
                hintText: l10n.fieldNameHint,
                prefixIcon: const Icon(Icons.label_outline),
              ),
              validator: (String? value) =>
                  (value == null || value.trim().isEmpty)
                  ? l10n.nameRequired
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.fieldNotes,
                hintText: l10n.fieldNotesHint,
                prefixIcon: const Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _canSave ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSave {
    if (_saving || _pasting) return false;
    if (_mode == LocationEntryMode.gps) {
      return !_capturing && _location is LocationSuccess;
    }
    return true;
  }

  Widget _buildModeSelector(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      children: <Widget>[
        ChoiceChip(
          label: Text(l10n.locationModeCurrentGps),
          selected: _mode == LocationEntryMode.gps,
          onSelected: (_) => _setMode(LocationEntryMode.gps),
        ),
        ChoiceChip(
          label: Text(l10n.locationModeManual),
          selected: _mode == LocationEntryMode.manual,
          onSelected: (_) => _setMode(LocationEntryMode.manual),
        ),
      ],
    );
  }

  Widget _buildManualCoordinates(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.customCoordinates,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _latitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.latitude,
                hintText: '30.044400',
                prefixIcon: const Icon(Icons.pin_drop_outlined),
              ),
              validator: (String? value) => _validateLatitude(value),
              onChanged: (_) => _refreshPlusCode(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _longitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.longitude,
                hintText: '31.235700',
                prefixIcon: const Icon(Icons.pin_drop_outlined),
              ),
              validator: (String? value) => _validateLongitude(value),
              onChanged: (_) => _refreshPlusCode(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plusCodeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.plusCode,
                hintText: l10n.plusCodeHint,
                prefixIcon: const Icon(Icons.grid_on),
              ),
              onChanged: _applyPlusCode,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);

    if (_capturing) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(l10n.fetchingLocation)),
            ],
          ),
        ),
      );
    }

    switch (_location) {
      case null:
        return const SizedBox.shrink();
      case LocationSuccess(:final latitude, :final longitude, :final accuracy):
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.currentLocation,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                _CoordRow(
                  icon: Icons.pin_drop_outlined,
                  label: l10n.latitude,
                  value: latitude.toStringAsFixed(6),
                ),
                const SizedBox(height: 4),
                _CoordRow(
                  icon: Icons.pin_drop_outlined,
                  label: l10n.longitude,
                  value: longitude.toStringAsFixed(6),
                ),
                const SizedBox(height: 4),
                _CoordRow(
                  icon: Icons.grid_on,
                  label: l10n.plusCode,
                  value: PlusCode.encode(latitude, longitude),
                ),
                if (accuracy != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '±${accuracy.toStringAsFixed(0)} m',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        );
      case LocationServiceDisabled():
        return _LocationMessageCard(
          icon: Icons.location_disabled_outlined,
          title: l10n.locationServicesDisabled,
          message: null,
          actionLabel: l10n.openAppSettings,
          onAction: () =>
              ref.read(locationServiceProvider).openLocationSettings(),
        );
      case LocationPermissionDenied(:final permanentlyDenied):
        return _LocationMessageCard(
          icon: Icons.location_off_outlined,
          title: l10n.locationPermissionTitle,
          message: l10n.locationPermissionMessage,
          actionLabel: permanentlyDenied ? l10n.openAppSettings : l10n.retry,
          onAction: permanentlyDenied
              ? () => ref.read(locationServiceProvider).openAppSettings()
              : _captureLocation,
        );
      case LocationFailure():
        return _LocationMessageCard(
          icon: Icons.error_outline,
          title: l10n.locationUnavailable,
          message: null,
          actionLabel: l10n.retry,
          onAction: _captureLocation,
        );
    }
  }
}

class _CoordRow extends StatelessWidget {
  const _CoordRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LocationMessageCard extends StatelessWidget {
  const _LocationMessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: theme.colorScheme.error),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.open_in_new),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
