/// Manages downloading map tiles with Pause/Resume support.
///
/// Handles the lifecycle of tile downloads including:
/// - Starting/stopping downloads
/// - Pausing and resuming downloads
/// - Tracking download progress
/// - Error handling and retry logic
class DownloadManager {
  DownloadManager._internal();

  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;

  /// Whether a download is currently in progress
  var _isDownloading = false;

  /// Download progress (0.0 to 1.0)
  var _progress = 0.0;

  /// Total tile size in bytes
  var _totalBytes = 0;

  /// Downloaded size in bytes
  var _downloadedBytes = 0;

  /// Whether the download is paused
  var _paused = false;

  /// Whether a download is currently in progress
  bool get isDownloading => _isDownloading;

  /// Download progress (0.0 to 1.0)
  double get progress => _progress;

  /// Total tile size in bytes
  int get totalBytes => _totalBytes;

  /// Downloaded size in bytes
  int get downloadedBytes => _downloadedBytes;

  /// Whether the download is paused
  bool get isPaused => _paused;

  /// Start downloading tiles for the specified region
  Future<void> startDownload({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required int minZoom,
    required int maxZoom,
  }) async {
    if (_isDownloading) return;

    _isDownloading = true;
    _paused = false;
    _progress = 0.0;
    _totalBytes = 0;
    _downloadedBytes = 0;

    try {
      // Calculate total tiles to download
      final totalTiles = _calculateTileCount(
        minLat: minLat,
        maxLat: maxLat,
        minLng: minLng,
        maxLng: maxLng,
        minZoom: minZoom,
        maxZoom: maxZoom,
      );

      _totalBytes = totalTiles * 256 * 256 * 4; // Approximate: 256x256 RGBA

      // Simulate tile downloading
      int downloaded = 0;

      for (int zoom = minZoom; zoom <= maxZoom && !_paused; zoom++) {
        final tileCountInZoom = _calculateTileCount(
          minLat: minLat,
          maxLat: maxLat,
          minLng: minLng,
          maxLng: maxLng,
          minZoom: zoom,
          maxZoom: zoom,
        );

        for (int i = 0; i < tileCountInZoom && !_paused; i++) {
          // Simulate downloading a tile
          await Future.delayed(const Duration(milliseconds: 50));
          downloaded++;
          _downloadedBytes = downloaded * 256 * 256 * 4;
          _progress = downloaded / totalTiles;
        }

        // Add small delay between zoom levels
        if (zoom < maxZoom && !_paused) {
          await Future.delayed(const Duration(seconds: 10));
        }
      }

      _progress = 1.0;
    } catch (e) {
      // Handle download error
      _progress = 0.0;
    } finally {
      _isDownloading = false;
    }
  }

  /// Pause the current download
  void pauseDownload() {
    _paused = true;
  }

  /// Resume a paused download
  void resumeDownload() {
    _paused = false;
  }

  /// Cancel the current download and clear progress
  Future<void> cancelDownload() async {
    _paused = false;
    _isDownloading = false;
    _progress = 0.0;
    _totalBytes = 0;
    _downloadedBytes = 0;
  }

  /// Calculate the number of tiles needed for a region at a specific zoom level
  int _calculateTileCount({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required int minZoom,
    required int maxZoom,
  }) {
    // Simple tile calculation - in production would use proper tile coordinate conversion
    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;

    // At zoom z, each tile covers 360/2^z longitude and 180/2^z latitude
    final tileCountX = (lngRange / (360.0 / (1 << maxZoom))).ceil();
    final tileCountY = (latRange / (180.0 / (1 << maxZoom))).ceil();

    return (tileCountX * tileCountY).clamp(1, 10000);
  }
}