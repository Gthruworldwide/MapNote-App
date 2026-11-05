import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:routenote/src/core/offline/storage_engine.dart';

/// Provider for the storage engine.
final storageEngineProvider = Provider<StorageEngine>((ref) {
  final engine = StorageEngine();
  engine.init();
  return engine;
});