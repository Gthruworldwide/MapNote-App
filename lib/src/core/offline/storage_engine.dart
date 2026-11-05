import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

/// Storage engine for offline map tiles.
///
/// Handles saving and retrieving map tiles locally using the device's
/// document directory. Supports efficient storage and retrieval of
/// tile images for offline map viewing.
class StorageEngine {
  StorageEngine._internal();

  static final StorageEngine _instance = StorageEngine._internal();
  factory StorageEngine() => _instance;

  /// Base directory for storing offline maps
  late final String _baseDirectory;

  /// Initialize the storage engine and determine the base directory
  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _baseDirectory = '${directory.path}/offline_maps';
    await _ensureDirectoryExists();
  }

  /// Ensure the offline maps directory exists
  Future<void> _ensureDirectoryExists() async {
    final directory = io.Directory(_baseDirectory);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  /// Get the path for a specific zoom level and tile coordinates
  String getTilePath({
    required int zoom,
    required int x,
    required int y,
  }) {
    return '$_baseDirectory/zoom=$zoom/x=$x/y=$y.png';
  }

  /// Save a tile image to local storage
  Future<void> saveTile({
    required int zoom,
    required int x,
    required int y,
    required Uint8List imageData,
  }) async {
    final path = getTilePath(zoom: zoom, x: x, y: y);
    final file = io.File(path);
    await file.writeAsBytes(imageData);
  }

  /// Retrieve a tile image from local storage
  Uint8List? getTile({
    required int zoom,
    required int x,
    required int y,
  }) {
    final path = getTilePath(zoom: zoom, x: x, y: y);
    final file = io.File(path);
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
  }

  /// Check if a tile is available in local storage
  bool tileExists({
    required int zoom,
    required int x,
    required int y,
  }) {
    final path = getTilePath(zoom: zoom, x: x, y: y);
    return io.File(path).existsSync();
  }

  /// List all available zoom levels for a given tile position
  List<int>? getAvailableZoomLevels(int x, int y) {
    final levels = <int>[];
    for (int z = 0; z <= 20; z++) {
      if (tileExists(zoom: z, x: x, y: y)) {
        levels.add(z);
      }
    }
    return levels.isNotEmpty ? levels : null;
  }

  /// Get total storage size in bytes for all offline maps
  Future<int> getTotalStorageSize() async {
    final directory = io.Directory(_baseDirectory);
    if (!await directory.exists()) return 0;

    final List<io.File> files = [];
    directory.list().forEach((object) {
      if (object is io.File) {
        files.add(object);
      }
    });
    int total = 0;
    for (final file in files) {
      total += file.lengthSync();
    }
    return total;
  }

  /// Clear all offline maps and free storage
  Future<void> clearAll() async {
    final directory = io.Directory(_baseDirectory);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// Get the base directory path
  String get baseDirectory => _baseDirectory;
}