/// A health snapshot of the running app, as observed locally.
///
/// Every field is a *number* or a coarse enum name. There is deliberately no
/// field that could carry user content — no place, no note, no coordinate, no
/// account id — because this object exists to be summarised into the local
/// health log, and the log must stay privacy-safe by construction rather than
/// by careful call sites.
class DiagnosticSnapshot {
  const DiagnosticSnapshot({
    required this.frames,
    required this.jankyFrames,
    required this.worstBuildMillis,
    required this.worstRasterMillis,
    required this.memoryBytes,
    required this.backgroundFor,
    required this.foregroundFor,
    required this.sampleCount,
  });

  /// An empty snapshot, used before any frame has been timed.
  static const DiagnosticSnapshot empty = DiagnosticSnapshot(
    frames: 0,
    jankyFrames: 0,
    worstBuildMillis: 0,
    worstRasterMillis: 0,
    memoryBytes: 0,
    backgroundFor: Duration.zero,
    foregroundFor: Duration.zero,
    sampleCount: 0,
  );

  /// Frames observed since the window began.
  final int frames;

  /// Frames whose build+raster work exceeded the jank threshold.
  final int jankyFrames;

  /// Slowest single frame build time in the window (ms).
  final double worstBuildMillis;

  /// Slowest single frame raster time in the window (ms).
  final double worstRasterMillis;

  /// Resident set size of the process, in bytes.
  final int memoryBytes;

  /// Time spent backgrounded within the window.
  final Duration backgroundFor;

  /// Time spent foregrounded within the window.
  final Duration foregroundFor;

  /// How many memory samples the window contains.
  final int sampleCount;

  /// Fraction of frames that janked, or 0 with no frames.
  double get jankRatio => frames == 0 ? 0 : jankyFrames / frames;

  /// Memory in mebibytes.
  double get memoryMiB => memoryBytes / (1024 * 1024);

  Map<String, Object?> toData() => <String, Object?>{
        'frames': frames,
        'janky': jankyFrames,
        'jankRatio': double.parse(jankRatio.toStringAsFixed(3)),
        'worstBuildMs': worstBuildMillis.round(),
        'worstRasterMs': worstRasterMillis.round(),
        'memoryMiB': double.parse(memoryMiB.toStringAsFixed(1)),
        'backgroundS': backgroundFor.inSeconds,
        'foregroundS': foregroundFor.inSeconds,
      };
}

/// Where a memory reading comes from.
///
/// Abstracted because `dart:io`'s `ProcessInfo` is unavailable on web and
/// awkward to fake in tests, and because a test must be able to assert the
/// monitor's thresholds without a real process.
typedef MemoryReader = int Function();

/// Locally-observed app health: frame pacing, memory footprint and how much of
/// its life the app spent in the background.
///
/// This is the *on-device* half of the orchestrator's diagnostics. It answers
/// "is our own adaptive stack behaving?" — did the isolate pile up, is the
/// analyser leaking, is the app being janked by its own sensor work — and it
/// answers it **entirely offline**. Nothing here is ever sent anywhere: no
/// telemetry endpoint, no analytics upload, no network call of any kind. The
/// only consumer is the local health log.
///
/// Frame times arrive through [recordFrame]; memory is read through an injected
/// [MemoryReader] (production passes `ProcessInfo.currentRss`) at most once per
/// [memorySampleInterval], so sampling never becomes its own cost.
class SelfDiagnosticMonitor {
  SelfDiagnosticMonitor({
    required this.readMemoryBytes,
    this.jankThresholdMillis = 32,
    this.memorySampleInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
  })  : assert(jankThresholdMillis > 0),
        _clock = clock ?? DateTime.now;

  /// Reads the process RSS in bytes.
  final MemoryReader readMemoryBytes;

  /// A frame whose build+raster total exceeds this is counted as janky. 32 ms
  /// is two frames at 60 Hz, i.e. a visibly dropped frame rather than a
  /// borderline one.
  final double jankThresholdMillis;

  /// How often [readMemoryBytes] may be called.
  final Duration memorySampleInterval;

  final DateTime Function() _clock;

  int _frames = 0;
  int _janky = 0;
  double _worstBuild = 0;
  double _worstRaster = 0;
  int _memoryBytes = 0;
  int _memorySamples = 0;
  DateTime? _lastMemoryAt;
  DateTime? _windowStart;

  Duration _background = Duration.zero;
  Duration _foreground = Duration.zero;
  DateTime? _phaseSince;
  bool _backgrounded = false;

  /// Frames counted in the current window.
  int get frameCount => _frames;

  /// Janky frames counted in the current window.
  int get jankyFrameCount => _janky;

  /// Whether the current window already contains a janky frame — the cheap
  /// signal a caller can poll without building a [DiagnosticSnapshot].
  bool get hasJank => _janky > 0;

  /// Records one rendered frame's timings (milliseconds).
  ///
  /// Called from a `SchedulerBinding.addTimingsCallback` in production, which
  /// hands over the frame timings the engine already measured — so this costs
  /// nothing extra per frame.
  void recordFrame({
    required double buildMillis,
    required double rasterMillis,
    DateTime? at,
  }) {
    _windowStart ??= at ?? _clock();
    _frames += 1;
    if (buildMillis > _worstBuild) _worstBuild = buildMillis;
    if (rasterMillis > _worstRaster) _worstRaster = rasterMillis;
    if (buildMillis + rasterMillis > jankThresholdMillis) _janky += 1;
  }

  /// Reports an app-lifecycle change so background/foreground time is tracked.
  void onLifecycle({required bool backgrounded, DateTime? at}) {
    final DateTime now = at ?? _clock();
    if (_phaseSince != null) {
      final Duration elapsed = now.difference(_phaseSince!);
      if (_backgrounded) {
        _background += elapsed;
      } else {
        _foreground += elapsed;
      }
    }
    _backgrounded = backgrounded;
    _phaseSince = now;
  }

  /// Reads memory, respecting [memorySampleInterval]. Returns the sample or
  /// `null` when the interval has not elapsed.
  ///
  /// A throwing reader is swallowed: a diagnostic must never be the reason the
  /// app fails.
  int? sampleMemory({DateTime? at}) {
    final DateTime now = at ?? _clock();
    final DateTime? last = _lastMemoryAt;
    if (last != null && now.difference(last) < memorySampleInterval) {
      return null;
    }
    int bytes;
    try {
      bytes = readMemoryBytes();
    } catch (_) {
      return null;
    }
    if (bytes < 0) return null;
    _lastMemoryAt = now;
    _memoryBytes = bytes;
    _memorySamples += 1;
    return bytes;
  }

  /// The current window's snapshot without resetting anything.
  DiagnosticSnapshot snapshot({DateTime? at}) {
    final DateTime now = at ?? _clock();
    Duration background = _background;
    Duration foreground = _foreground;
    final DateTime? since = _phaseSince;
    if (since != null) {
      final Duration elapsed = now.difference(since);
      if (_backgrounded) {
        background += elapsed;
      } else {
        foreground += elapsed;
      }
    }
    return DiagnosticSnapshot(
      frames: _frames,
      jankyFrames: _janky,
      worstBuildMillis: _worstBuild,
      worstRasterMillis: _worstRaster,
      memoryBytes: _memoryBytes,
      backgroundFor: background,
      foregroundFor: foreground,
      sampleCount: _memorySamples,
    );
  }

  /// Returns the window's snapshot and starts a fresh one.
  ///
  /// Used by the orchestrator's periodic diagnostic tick: each window is
  /// summarised and logged once, then forgotten, so the monitor holds no
  /// unbounded history and the log stays a ring buffer of windows.
  DiagnosticSnapshot drain({DateTime? at}) {
    final DiagnosticSnapshot result = snapshot(at: at);
    _frames = 0;
    _janky = 0;
    _worstBuild = 0;
    _worstRaster = 0;
    _memorySamples = 0;
    final DateTime now = at ?? _clock();
    _windowStart = now;
    _phaseSince = now;
    _background = Duration.zero;
    _foreground = Duration.zero;
    return result;
  }

  /// Resets every counter, e.g. when a new trip begins.
  void reset({DateTime? at}) {
    final DateTime now = at ?? _clock();
    _frames = 0;
    _janky = 0;
    _worstBuild = 0;
    _worstRaster = 0;
    _memoryBytes = 0;
    _memorySamples = 0;
    _lastMemoryAt = null;
    _windowStart = now;
    _phaseSince = now;
    _background = Duration.zero;
    _foreground = Duration.zero;
  }
}
