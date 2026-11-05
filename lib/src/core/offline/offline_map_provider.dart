import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:routenote/src/core/offline/download_manager.dart';
import 'package:routenote/src/core/offline/storage_engine.dart';

/// Riverpod provider for offline map state management.
///
/// Provides state for:
/// - Download progress tracking
/// - Download control (start/pause/cancel)
/// - Storage management
class OfflineMapNotifier extends Notifier<MapOfflineState> {
  final DownloadManager _downloadManager = DownloadManager();
  final StorageEngine _storageEngine = StorageEngine();

  @override
  MapOfflineState build() {
    return MapOfflineState();
  }

  /// Initialize the storage engine
  Future<void> init() async {
    await _storageEngine.init();
    state = state.copyWith(storageInitialized: true);
  }

  /// Start downloading maps for the specified region
  Future<void> startDownload({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required int minZoom,
    required int maxZoom,
  }) async {
    state = state.copyWith(status: DownloadStatus.downloading);
    await _downloadManager.startDownload(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    state = state.copyWith(
      status: DownloadStatus.idle,
      progress: _downloadManager.progress,
      totalBytes: _downloadManager.totalBytes,
      downloadedBytes: _downloadManager.downloadedBytes,
    );
  }

  /// Pause the current download
  void pauseDownload() {
    _downloadManager.pauseDownload();
    state = state.copyWith(isPaused: true);
  }

  /// Resume a paused download
  void resumeDownload() {
    _downloadManager.resumeDownload();
    state = state.copyWith(isPaused: false);
  }

  /// Cancel the current download
  Future<void> cancelDownload() async {
    await _downloadManager.cancelDownload();
    state = state.copyWith(
      status: DownloadStatus.idle,
      isPaused: false,
      progress: 0.0,
      totalBytes: 0,
      downloadedBytes: 0,
    );
  }

  /// Get the progress percentage as a string
  String getProgressPercentage() {
    if (_downloadManager.totalBytes == 0) return '0%';
    final percent =
        (_downloadManager.downloadedBytes / _downloadManager.totalBytes * 100)
            .clamp(0, 100);
    return '${percent.toInt()}%';
  }

  /// Get the total storage size
  Future<String> getTotalStorageSize() async {
    final size = await _storageEngine.getTotalStorageSize();
    return '${(size / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  /// Check if a specific tile is downloaded
  bool isTileDownloaded({
    required int zoom,
    required int x,
    required int y,
  }) {
    return _storageEngine.tileExists(
      zoom: zoom,
      x: x,
      y: y,
    );
  }

  /// Get available zoom levels for a tile position
  List<int>? getAvailableZoomLevels(int x, int y) {
    return _storageEngine.getAvailableZoomLevels(x, y);
  }
}

/// State model for offline map state
class MapOfflineState {
  MapOfflineState()
      : storageInitialized = false,
        status = DownloadStatus.idle,
        progress = 0.0,
        totalBytes = 0,
        downloadedBytes = 0,
        isPaused = false,
        error = '';

  bool storageInitialized;
  DownloadStatus status;
  double progress;
  int totalBytes;
  int downloadedBytes;
  bool isPaused;
  String error;

  MapOfflineState copyWith({
    bool? storageInitialized,
    DownloadStatus? status,
    double? progress,
    int? totalBytes,
    int? downloadedBytes,
    bool? isPaused,
    String? error,
  }) => MapOfflineState()
    ..storageInitialized = storageInitialized ?? this.storageInitialized
    ..status = status ?? this.status
    ..progress = progress ?? this.progress
    ..totalBytes = totalBytes ?? this.totalBytes
    ..downloadedBytes = downloadedBytes ?? this.downloadedBytes
    ..isPaused = isPaused ?? this.isPaused
    ..error = error ?? this.error;
}

/// Download status enum
enum DownloadStatus {
  idle,
  downloading,
  paused,
  completed,
  failed,
}

/// Riverpod provider for the offline map notifier
final offlineMapProvider = NotifierProvider<OfflineMapNotifier, MapOfflineState>(() {
  final notifier = OfflineMapNotifier();
  notifier.init();
  return notifier;
});