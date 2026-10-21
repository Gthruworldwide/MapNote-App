// Offline privacy audit of a pulled MapNote Hive box.
//
// Reads the `settings` box from a directory containing `settings.hive` and
// reports the structure of the `health_events` log, the union of every payload
// key it contains, and any coordinate-like content anywhere in the box.
//
// Run with:
//   dart run tool/hive_audit.dart <dir-containing-settings.hive>

import 'dart:io';

import 'package:hive_ce/hive.dart';

/// Keys that would indicate a location leaked into the health log.
const List<String> forbiddenKeys = <String>[
  'latitude',
  'longitude',
  'lat',
  'lng',
  'lon',
  'coords',
  'coordinates',
  'position',
  'geopoint',
  'place_id',
  'placeId',
];

/// A number only counts as a leak when it sits under a coordinate-shaped key.
/// Flagging every small number would drown the signal in false positives
/// (durations, frame counts, millisecond budgets are all < 180).
bool _keyIsCoordinateShaped(String keyName) {
  final String k = keyName.toLowerCase();
  return k.contains('lat') ||
      k.contains('lng') ||
      k.contains('lon') ||
      k.contains('coord') ||
      k.contains('geo') ||
      k.contains('position');
}

/// A bare `{a: 30.04, b: 31.23}` pair under a generic key is the other way a
/// coordinate can hide. Detect two coordinate-range numbers side by side.
bool _isLatLngPair(List<Object?> numbers) {
  if (numbers.length != 2) return false;
  final double a = (numbers[0] as num).toDouble();
  final double b = (numbers[1] as num).toDouble();
  return a.abs() <= 90 && b.abs() <= 180 && a != 0 && b != 0;
}

void _walk(Object? node, String path, List<String> hits) {
  if (node is Map) {
    final List<Object?> bareNumbers = <Object?>[];
    for (final MapEntry<Object?, Object?> entry
        in (node as Map<Object?, Object?>).entries) {
      final Object? key = entry.key;
      final Object? value = entry.value;
      final String keyName = key?.toString() ?? '';
      if (forbiddenKeys.contains(keyName.toLowerCase())) {
        hits.add('FORBIDDEN KEY at $path/$keyName = $value');
      }
      if (value is num && _keyIsCoordinateShaped(keyName)) {
        hits.add('COORDINATE-SHAPED KEY at $path/$keyName = $value');
      }
      if (value is num) bareNumbers.add(value);
      _walk(value, '$path/$keyName', hits);
    }
    if (_isLatLngPair(bareNumbers)) {
      hits.add('LAT/LNG PAIR under $path = $bareNumbers');
    }
  } else if (node is List) {
    for (int i = 0; i < node.length; i++) {
      _walk(node[i], '$path[$i]', hits);
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/hive_audit.dart <dir>');
    exit(2);
  }
  final Directory dir = Directory(args.first);
  if (!dir.existsSync()) {
    stderr.writeln('directory not found: ${dir.path}');
    exit(2);
  }

  Hive.init(dir.path);
  final Box<dynamic> box = await Hive.openBox<dynamic>('settings');

  stdout.writeln('=== TOP-LEVEL KEYS IN settingsBox ===');
  for (final String key in box.keys) {
    final Object? value = box.get(key);
    final int size = value is List ? value.length : 0;
    stdout.writeln('  $key  (${value.runtimeType}${size > 0 ? ', $size entries' : ''})');
  }

  final Object? raw = box.get('health_events');
  if (raw is! List) {
    stdout.writeln('\n=== health_events: NOT A LIST (${raw.runtimeType}) ===');
    await box.close();
    return;
  }

  stdout.writeln('\n=== health_events: ${raw.length} events ===');

  final Map<String, int> typeCounts = <String, int>{};
  final Set<String> dataKeys = <String>{};
  final List<String> hits = <String>[];
  final List<String> messages = <String>[];

  for (final Object? entry in raw) {
    if (entry is! Map) continue;
    final Object? type = entry['type'];
    typeCounts[type?.toString() ?? '?'] =
        (typeCounts[type?.toString() ?? '?'] ?? 0) + 1;
    final Object? data = entry['data'];
    if (data is Map) {
      for (final Object? k in data.keys) {
        dataKeys.add(k.toString());
      }
    }
    final Object? message = entry['message'];
    if (message != null) messages.add(message.toString());
    _walk(entry, 'health_events', hits);
  }

  stdout.writeln('\n--- event types ---');
  final List<String> types = typeCounts.keys.toList()..sort();
  for (final String t in types) {
    stdout.writeln('  ${t.padRight(18)} ${typeCounts[t]}');
  }

  stdout.writeln('\n--- union of `data` payload keys ---');
  final List<String> sorted = dataKeys.toList()..sort();
  stdout.writeln(sorted.isEmpty ? '  (none)' : sorted.map((String k) => '  $k').join('\n'));

  stdout.writeln('\n--- privacy scan over every health event ---');
  if (hits.isEmpty) {
    stdout.writeln('  PASS: no forbidden key and no coordinate-shaped value.');
  } else {
    for (final String h in hits.take(50)) {
      stdout.writeln('  $h');
    }
    stdout.writeln('  total hits: ${hits.length}');
  }

  stdout.writeln('\n--- sample event messages (first 15) ---');
  for (final String m in messages.take(15)) {
    stdout.writeln('  $m');
  }

  // Session state decides whether a cold launch can take the "trusted session"
  // branch (skip the platform restore) or must do the full restore.
  stdout.writeln('\n=== SESSION STATE (drives the cold-launch auth check) ===');
  stdout.writeln('  is_logged_in : ${box.get('is_logged_in')}');
  stdout.writeln('  last_synced  : ${box.get('last_synced')}');
  final Object? user = box.get('auth_user');
  stdout.writeln('  auth_user    : ${user is Map ? user.keys.toList() : user}');
  final Object? rawLast = box.get('last_synced');
  if (rawLast is String) {
    final DateTime? parsed = DateTime.tryParse(rawLast);
    if (parsed != null) {
      final Duration age = DateTime.now().toUtc().difference(parsed.toUtc());
      stdout.writeln('  last_synced age : ${age.inMinutes} min '
          '(trust window = 12 h) -> ${age < const Duration(hours: 12) ? 'TRUSTED (restore skipped)' : 'STALE (full restore)'}');
    }
  }

  await box.close();
}
