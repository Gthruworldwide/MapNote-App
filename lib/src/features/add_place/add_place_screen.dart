import 'dart:async';

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
import '../../services/geocoding_service.dart';
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
/// The form is laid out top-to-bottom the way a place is actually described:
///
/// 1. **Name** plus one-tap category tags (`#Work`, `#Home`, …).
/// 2. **Coordinates** — the "Smart Plus Code" field up front, an "AI Smart
///    Paste" button, and an expandable latitude/longitude pair for anyone who
///    would rather type the numbers.
/// 3. **Notes** and the save button.
///
/// A place can be saved with *only* a Plus Code, *only* a latitude/longitude
/// pair, or all three. Plus Codes are resolved entirely on-device (see
/// [PlusCode]), so nothing here needs a network round-trip.
///
/// When [place] is provided the screen edits that existing location instead of
/// capturing a new one. When [initialLatitude]/[initialLongitude] are provided
/// (for example from a shared map link) the screen opens in manual mode with
/// those coordinates pre-filled. [initialPlusCode] seeds the Smart Plus Code
/// field (used by the clipboard import). [initialMode] forces a starting mode
/// (used by the home "Add location" menu).
class AddPlaceScreen extends ConsumerStatefulWidget {
  const AddPlaceScreen({
    super.key,
    this.place,
    this.initialLatitude,
    this.initialLongitude,
    this.initialName,
    this.initialPlusCode,
    this.initialMode,
  });

  final Place? place;
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialName;
  final String? initialPlusCode;
  final LocationEntryMode? initialMode;

  @override
  ConsumerState<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends ConsumerState<AddPlaceScreen> {
  static const Uuid _uuid = Uuid();
  static const LocationParser _parser = LocationParser();

  /// How long the coordinate fields must sit still before a reverse-geocode is
  /// attempted, so typing `30.0444` fires one lookup rather than six.
  static const Duration _geocodeDebounce = Duration(milliseconds: 600);

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

  /// Whether the latitude/longitude pair is expanded. Defaults to open so the
  /// numbers are always visible for a manual coordinate, and can be folded
  /// away once a Plus Code has been entered.
  bool _coordinatesExpanded = true;

  /// The reverse-geocoded suggestion awaiting the user's decision.
  PlaceSuggestion? _suggestion;

  /// The rounded coordinate the current/attempted suggestion belongs to, so
  /// unchanged coordinates are never looked up twice.
  String? _suggestionKey;

  /// Set once the user accepts or dismisses a suggestion, so it is not offered
  /// again for the same place.
  bool _suggestionDismissed = false;

  Timer? _geocodeTimer;

  bool get _isEditing => widget.place != null;

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The last GPS fix as a Plus Code reference point, if there is one.
  PlusCodePoint? get _gpsReference {
    final LocationResult? location = _location;
    if (location is LocationSuccess) {
      return PlusCodePoint(
        latitude: location.latitude,
        longitude: location.longitude,
      );
    }
    return null;
  }

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
    final String? initialPlusCode = widget.initialPlusCode;

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
    } else if (initialPlusCode != null && initialPlusCode.trim().isNotEmpty) {
      // Imported from the clipboard: the code is the only thing we have, so
      // decode it offline straight away.
      _mode = LocationEntryMode.manual;
      _plusCodeController.text =
          PlusCode.extract(initialPlusCode) ??
          initialPlusCode.trim().toUpperCase();
      _applyPlusCode(_plusCodeController.text);
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
    _geocodeTimer?.cancel();
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
    if (result is LocationSuccess) {
      _refreshPlusCode();
      _scheduleGeocode(result.latitude, result.longitude);
    }
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

  /// Recomputes the Plus Code whenever the coordinates that are the source of
  /// truth change.
  ///
  /// The field is a live preview, never the source itself. It is *not* cleared
  /// when the coordinates are blank, because a Plus Code can be the only thing
  /// the user provided and must survive until save.
  void _refreshPlusCode() {
    final double? latitude;
    final double? longitude;
    if (_mode == LocationEntryMode.gps) {
      final PlusCodePoint? fix = _gpsReference;
      latitude = fix?.latitude;
      longitude = fix?.longitude;
    } else {
      latitude = double.tryParse(_latitudeController.text.trim());
      longitude = double.tryParse(_longitudeController.text.trim());
    }

    if (latitude != null &&
        longitude != null &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180) {
      final String next = PlusCode.encode(latitude, longitude);
      if (_plusCodeController.text != next) {
        _plusCodeController.text = next;
      }
    }
  }

  /// Handles the Smart Plus Code field: decodes what is typed or pasted into
  /// latitude/longitude and asks for a name suggestion.
  ///
  /// Programmatic `controller.text =` writes do not re-trigger the text fields'
  /// `onChanged`, so this cannot loop back into the Plus Code field.
  void _onPlusCodeChanged(String value) {
    _applyPlusCode(value);
    if (_latitudeController.text.isNotEmpty) {
      _scheduleGeocode(
        double.tryParse(_latitudeController.text.trim()) ?? 0,
        double.tryParse(_longitudeController.text.trim()) ?? 0,
      );
    }
  }

  /// Decodes [value] (full or short) into the coordinate fields.
  ///
  /// A short code uses the last GPS fix as its reference when one is available;
  /// otherwise the code is left in place for [save][_save] to resolve against
  /// the locality the user typed after a comma.
  void _applyPlusCode(String value) {
    final PlusCodePoint? decoded = PlusCode.decodeFlexible(
      value,
      reference: _gpsReference,
    );
    if (decoded == null) return;
    // Five decimals is the precision the app already shows for coordinates and
    // is far finer than the ~13.5 m cell a ten-digit code describes, so this
    // only strips the binary-floating-point noise (e.g. 47.365562499999996).
    _latitudeController.text = decoded.latitude.toStringAsFixed(5);
    _longitudeController.text = decoded.longitude.toStringAsFixed(5);
  }

  /// Reads the clipboard and fills in any coordinates, map link, name or raw
  /// Plus Code it finds.
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
    String? plusCode;
    if (text.isNotEmpty) {
      parsed = _parser.parse(text);
      if (parsed == null && _parser.looksLikeShortMapLink(text)) {
        if (mounted) setState(() => _pasting = true);
        parsed = await _parser.resolveShortLink(text);
        if (mounted) setState(() => _pasting = false);
      }
      plusCode ??= ref.read(smartClipboardServiceProvider).extractPlusCode(text);
    }

    if (!mounted) return;

    if (parsed == null && plusCode != null) {
      // A raw Plus Code: hand it to the Smart field, which decodes it offline.
      Haptics.light();
      setState(() {
        _mode = LocationEntryMode.manual;
        _plusCodeController.text = plusCode!;
      });
      _onPlusCodeChanged(plusCode);
      messenger.showSnackBar(SnackBar(content: Text(l10n.clipboardPasted)));
      return;
    }

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
    Haptics.light();
    setState(() {
      _mode = LocationEntryMode.manual;
      _coordinatesExpanded = true;
      _latitudeController.text = location.latitude.toString();
      _longitudeController.text = location.longitude.toString();
      final String? name = location.name ?? _parser.guessName(text);
      if (name != null && name.isNotEmpty) _nameController.text = name;
    });
    _scheduleGeocode(location.latitude, location.longitude);
    messenger.showSnackBar(SnackBar(content: Text(l10n.clipboardPasted)));
  }

  // --- Reverse-geocoded suggestion -------------------------------------------

  /// Schedules a best-effort reverse geocode for [latitude]/[longitude].
  void _scheduleGeocode(double latitude, double longitude) {
    if (_suggestionDismissed) return;
    if (_nameController.text.trim().isNotEmpty) return;

    final String key =
        '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
    if (key == _suggestionKey) return;
    _suggestionKey = key;

    _geocodeTimer?.cancel();
    _geocodeTimer = Timer(_geocodeDebounce, () {
      _geocodeTimer = null;
      unawaited(_geocode(latitude, longitude, key));
    });
  }

  Future<void> _geocode(double latitude, double longitude, String key) async {
    if (!mounted || key != _suggestionKey) return;
    final PlaceSuggestion? suggestion = await ref
        .read(geocodingServiceProvider)
        .reverse(latitude: latitude, longitude: longitude);
    if (!mounted || key != _suggestionKey) return;
    if (suggestion == null || suggestion.isEmpty) return;
    if (_nameController.text.trim().isNotEmpty) return;
    setState(() => _suggestion = suggestion);
  }

  void _autoFillFromSuggestion() {
    final PlaceSuggestion? suggestion = _suggestion;
    if (suggestion == null) return;
    Haptics.light();
    setState(() {
      final String? title = suggestion.title;
      if (title != null) _nameController.text = title;
      final String? detail = suggestion.detail;
      if (detail != null && _notesController.text.trim().isEmpty) {
        _notesController.text = detail;
      }
      _suggestion = null;
      _suggestionDismissed = true;
    });
  }

  void _dismissSuggestion() {
    setState(() {
      _suggestion = null;
      _suggestionDismissed = true;
    });
  }

  void _onNameChanged(String value) {
    if (_suggestion == null) return;
    setState(() => _suggestion = null);
  }

  // --- Category tags ---------------------------------------------------------

  static const List<String> _categories = <String>[
    'categoryWork',
    'categoryHome',
    'categorySchool',
    'categoryPersonal',
  ];

  String _categoryLabel(AppLocalizations l10n, String key) => switch (key) {
    'categoryWork' => l10n.categoryWork,
    'categoryHome' => l10n.categoryHome,
    'categorySchool' => l10n.categorySchool,
    _ => l10n.categoryPersonal,
  };

  bool _hasCategory(String tag) =>
      RegExp('(^|\\s)${RegExp.escape(tag)}(?=\\s|\$)').hasMatch(
        _notesController.text,
      );

  void _toggleCategory(String tag) {
    Haptics.light();
    setState(() {
      final String current = _notesController.text;
      if (_hasCategory(tag)) {
        _notesController.text = current
            .replaceAll(RegExp('\\s*${RegExp.escape(tag)}'), '')
            .trim();
      } else {
        _notesController.text = current.trim().isEmpty
            ? tag
            : '${current.trim()} $tag';
      }
    });
  }

  // --- Saving -----------------------------------------------------------------

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    Haptics.light();

    final PlusCodePoint? resolved = await _resolveCoordinates();
    if (!mounted) return;
    if (resolved == null) {
      final String? code = PlusCode.extract(_plusCodeController.text);
      final bool shortUnresolved =
          code != null && PlusCode.isShortPlusCode(code);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            shortUnresolved
                ? l10n.plusCodeShortNeedsReference
                : l10n.plusCodeOrCoordinatesRequired,
          ),
        ),
      );
      return;
    }

    final Place? original = widget.place;
    final Place place = original == null
        ? Place(
            id: _uuid.v4(),
            name: _nameController.text.trim(),
            notes: _notesController.text.trim(),
            latitude: resolved.latitude,
            longitude: resolved.longitude,
            timestamp: DateTime.now().toUtc(),
          )
        : original.copyWith(
            name: _nameController.text.trim(),
            notes: _notesController.text.trim(),
            latitude: resolved.latitude,
            longitude: resolved.longitude,
          );

    setState(() => _saving = true);
    await ref.read(placesProvider.notifier).save(place);

    messenger.showSnackBar(SnackBar(content: Text(l10n.placeSaved)));
    if (mounted) navigator.pop();
  }

  /// Resolves the coordinates to save from whatever the user provided: a GPS
  /// fix, a latitude/longitude pair, and/or a Plus Code.
  Future<PlusCodePoint?> _resolveCoordinates() async {
    final double? latitude = double.tryParse(_latitudeController.text.trim());
    final double? longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude != null &&
        longitude != null &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180) {
      return PlusCodePoint(latitude: latitude, longitude: longitude);
    }

    final String plusText = _plusCodeController.text;
    final PlusCodePoint? decoded = PlusCode.decodeFlexible(
      plusText,
      reference: _gpsReference,
    );
    if (decoded != null) return decoded;

    // A short code with a locality after the comma ("9G8F+6W, Cairo") is
    // resolved by forward-geocoding the locality, so the import still works
    // with no GPS fix.
    final String? code = PlusCode.extract(plusText);
    if (code != null && PlusCode.isShortPlusCode(code)) {
      final String locality = plusText
          .split(',')
          .skip(1)
          .join(',')
          .trim();
      if (locality.isNotEmpty) {
        final PlusCodePoint? reference = await ref
            .read(geocodingServiceProvider)
            .forward(locality);
        final PlusCodePoint? resolved = PlusCode.decodeFlexible(
          code,
          reference: reference,
        );
        if (resolved != null) return resolved;
      }
    }

    final LocationResult? location = _location;
    if (location is LocationSuccess) {
      return PlusCodePoint(
        latitude: location.latitude,
        longitude: location.longitude,
      );
    }
    return null;
  }

  String? _validateLatitude(String? value) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String text = value?.trim() ?? '';
    // Blank is fine: a Plus Code alone is enough to save.
    if (text.isEmpty) return null;
    final double? parsed = double.tryParse(text);
    if (parsed == null) return l10n.coordinateInvalid;
    if (parsed < -90 || parsed > 90) return l10n.latitudeRange;
    return null;
  }

  String? _validateLongitude(String? value) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final double? parsed = double.tryParse(text);
    if (parsed == null) return l10n.coordinateInvalid;
    if (parsed < -180 || parsed > 180) return l10n.longitudeRange;
    return null;
  }

  String? _validatePlusCode(String? value) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (PlusCode.extract(text) == null) return l10n.plusCodeInvalid;
    return null;
  }

  // --- Build ------------------------------------------------------------------

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
            // 1. Name and quick category tags.
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
              onChanged: _onNameChanged,
            ),
            const SizedBox(height: 12),
            _buildCategoryTags(l10n),

            const SizedBox(height: 16),

            // 2. Coordinates: Smart Plus Code, AI Smart Paste, lat/long.
            _buildCoordinatesCard(l10n),

            const SizedBox(height: 16),

            // 3. Notes and save.
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.fieldNotes,
                hintText: l10n.fieldNotesHint,
                prefixIcon: const Icon(Icons.notes),
              ),
            ),

            if (_suggestion != null) ...<Widget>[
              const SizedBox(height: 16),
              _buildSuggestionCard(l10n),
            ],

            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
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

  bool get _canSave => !_saving && !_pasting && !_capturing;

  Widget _buildCategoryTags(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final String key in _categories)
          FilterChip(
            label: Text('#${_categoryLabel(l10n, key)}'),
            selected: _hasCategory('#${_categoryLabel(l10n, key)}'),
            onSelected: (_) =>
                _toggleCategory('#${_categoryLabel(l10n, key)}'),
          ),
      ],
    );
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

  Widget _buildCoordinatesCard(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.place_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(l10n.locationCoordinates, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            _buildModeSelector(l10n),
            const SizedBox(height: 12),
            if (_mode == LocationEntryMode.gps) ...<Widget>[
              _buildGpsStatus(l10n),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _plusCodeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.plusCode,
                hintText: l10n.plusCodeHint,
                prefixIcon: const Icon(Icons.grid_on),
              ),
              validator: _validatePlusCode,
              onChanged: _onPlusCodeChanged,
            ),
            const SizedBox(height: 12),
            Tooltip(
              message: l10n.aiSmartPasteTooltip,
              child: OutlinedButton.icon(
                onPressed: (_pasting || _saving) ? null : _pasteFromClipboard,
                icon: _pasting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(l10n.aiSmartPaste),
              ),
            ),
            const SizedBox(height: 4),
            _buildCoordinateExpander(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildCoordinateExpander(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    final Duration duration = _reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () {
            Haptics.light();
            setState(() => _coordinatesExpanded = !_coordinatesExpanded);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.coordinateDetails,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                AnimatedRotation(
                  turns: _coordinatesExpanded ? 0.5 : 0,
                  duration: duration,
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: duration,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _coordinatesExpanded
              ? Column(
                  children: <Widget>[
                    const SizedBox(height: 8),
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
                      validator: _validateLatitude,
                      onChanged: (_) {
                        _refreshPlusCode();
                        _scheduleGeocodeFromFields();
                      },
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
                      validator: _validateLongitude,
                      onChanged: (_) {
                        _refreshPlusCode();
                        _scheduleGeocodeFromFields();
                      },
                    ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  void _scheduleGeocodeFromFields() {
    final double? latitude = double.tryParse(_latitudeController.text.trim());
    final double? longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null || longitude == null) return;
    if (latitude.abs() > 90 || longitude.abs() > 180) return;
    _scheduleGeocode(latitude, longitude);
  }

  Widget _buildSuggestionCard(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    final PlaceSuggestion suggestion = _suggestion!;
    final String? title = suggestion.title;
    final String? detail = suggestion.detail;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.suggestionTitle,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _dismissSuggestion,
                  tooltip: l10n.dismissSuggestion,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            if (title != null)
              Text(
                l10n.foundPlace(title),
                style: theme.textTheme.titleSmall,
              ),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                detail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                onPressed: _autoFillFromSuggestion,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: Text(l10n.autoFillNameNotes),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The GPS status shown above the Smart Plus Code field while the current
  /// position is the source of truth.
  Widget _buildGpsStatus(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);

    if (_capturing) {
      return Row(
        children: <Widget>[
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(l10n.fetchingLocation)),
        ],
      );
    }

    switch (_location) {
      case null:
        return const SizedBox.shrink();
      case LocationSuccess(:final latitude, :final longitude, :final accuracy):
        return Column(
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
            if (accuracy != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '±${accuracy.toStringAsFixed(0)} m',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
    );
  }
}
