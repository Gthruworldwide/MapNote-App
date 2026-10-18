package com.routenote.routenote

import android.Manifest
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth, which
// shows the system BiometricPrompt as a fragment.
class MainActivity : FlutterFragmentActivity() {
    private var shortcutsChannel: MethodChannel? = null
    private var pendingPlaceId: String? = null

    // Accelerometer bridge used by the dead-reckoning distance bridge while a
    // daily tracker runs (see MotionSensorChannel / motion_signal.dart).
    private var motionSensorChannel: MotionSensorChannel? = null

    // Foreground tracking service + its runtime permissions (see
    // LocationTrackingService and ForegroundTrackingService on the Dart side).
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var pendingBackgroundLocationResult: MethodChannel.Result? = null
    private lateinit var notificationPermissionLauncher:
        ActivityResultLauncher<String>
    private lateinit var backgroundLocationPermissionLauncher:
        ActivityResultLauncher<String>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Permission launchers have to be registered before the activity is
        // STARTED, so they are created here rather than inside a channel
        // handler. Each request resolves the Dart future that asked for it.
        notificationPermissionLauncher = registerForActivityResult(
            ActivityResultContracts.RequestPermission(),
        ) { granted ->
            pendingNotificationResult?.success(granted)
            pendingNotificationResult = null
        }
        backgroundLocationPermissionLauncher = registerForActivityResult(
            ActivityResultContracts.RequestPermission(),
        ) { granted ->
            pendingBackgroundLocationResult?.success(granted)
            pendingBackgroundLocationResult = null
        }

        addTestCrashButtonIfDebuggable()
    }

    override fun onDestroy() {
        // Never leave Dart awaiting a permission dialog that will not return.
        pendingNotificationResult?.success(false)
        pendingNotificationResult = null
        pendingBackgroundLocationResult?.success(false)
        pendingBackgroundLocationResult = null
        super.onDestroy()
    }

    /**
     * Debug-only "Test Crash" button from the Crashlytics Android get-started
     * guide (Step 3). Pressing it forces an uncaught exception so the first
     * Crashlytics report can be produced and verified. Release and profile
     * builds are left untouched (the activity is not debuggable there).
     *
     * https://firebase.google.com/docs/crashlytics/android/get-started#force_a_test_crash
     */
    private fun addTestCrashButtonIfDebuggable() {
        val isDebuggable =
            (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!isDebuggable) return

        val crashButton = Button(this).apply {
            text = "Test Crash"
            setOnClickListener { throw RuntimeException("Test Crash") }
        }
        addContentView(
            crashButton,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHORTCUT_CHANNEL,
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPin" -> {
                    val id = call.argument<String>("id")
                    val label = call.argument<String>("label")
                    if (id.isNullOrBlank() || label.isNullOrBlank()) {
                        result.error("invalid_args", "id and label are required", null)
                    } else {
                        result.success(requestPinShortcut(id, label))
                    }
                }
                "getInitialPlaceId" -> {
                    val id = pendingPlaceId
                    pendingPlaceId = null
                    result.success(id)
                }
                else -> result.notImplemented()
            }
        }
        shortcutsChannel = channel

        // Foreground tracking service: kept alive while a daily tracker runs.
        val tracking = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TRACKING_CHANNEL,
        )
        tracking.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> result.success(startTrackingService())
                "stopForeground" -> result.success(stopTrackingService())
                "requestNotificationPermission" ->
                    requestNotificationPermission(result)
                "requestBackgroundLocationPermission" ->
                    requestBackgroundLocationPermission(result)
                "getBatteryLevel" -> result.success(readBatteryLevel())
                else -> result.notImplemented()
            }
        }

        // Accelerometer samples for the trackers' movement classifier. Only
        // sampled while Dart is subscribed (i.e. while a tracker is running).
        val motion = MotionSensorChannel(this)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MOTION_CHANNEL,
        ).setStreamHandler(motion)
        motionSensorChannel = motion

        // The app may have been launched cold from a pinned shortcut.
        capturePlaceId(intent, notifyDart = false)
    }

    /** Starts [LocationTrackingService]; false when the OS refuses the start. */
    private fun startTrackingService(): Boolean {
        return try {
            ContextCompat.startForegroundService(
                this,
                Intent(this, LocationTrackingService::class.java),
            )
            true
        } catch (error: Exception) {
            // Android 12+ blocks foreground-service starts from the background:
            // the Dart side simply keeps in-app tracking and retries later.
            false
        }
    }

    private fun stopTrackingService(): Boolean {
        return try {
            stopService(Intent(this, LocationTrackingService::class.java))
            true
        } catch (error: Exception) {
            false
        }
    }

    /**
     * Reads the current battery charge (0…1) from the OS's sticky
     * `ACTION_BATTERY_CHANGED` broadcast — no permission, no plugin.
     *
     * Used by the adaptive sampling manager to stretch the request interval
     * when the battery is low. Returns `-1.0` when the platform refuses to
     * answer, which the Dart side treats as "unknown" (assume healthy) rather
     * than throttling tracking on a guess.
     */
    private fun readBatteryLevel(): Double {
        return try {
            val status = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = status?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = status?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level < 0 || scale <= 0 || scale <= level) -1.0
            else level.toDouble() / scale
        } catch (error: Exception) {
            -1.0
        }
    }

    /**
     * Requests `POST_NOTIFICATIONS` (Android 13+) so the tracking notification
     * is actually visible. Resolves immediately when not needed.
     */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        val permission = "android.permission.POST_NOTIFICATIONS"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            hasPermission(permission)
        ) {
            result.success(true)
            return
        }
        pendingNotificationResult?.success(false)
        pendingNotificationResult = result
        notificationPermissionLauncher.launch(permission)
    }

    /**
     * Requests `ACCESS_BACKGROUND_LOCATION` (Android 10+) so tracking survives
     * the app leaving the foreground. From Android 11 the system only offers
     * "Allow all the time" once foreground location is already granted, so an
     * early request is reported as not granted instead of prompting.
     */
    private fun requestBackgroundLocationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            hasPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        ) {
            result.success(true)
            return
        }
        if (!hasForegroundLocation()) {
            result.success(false)
            return
        }
        pendingBackgroundLocationResult?.success(false)
        pendingBackgroundLocationResult = result
        backgroundLocationPermissionLauncher.launch(
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasForegroundLocation(): Boolean =
        hasPermission(Manifest.permission.ACCESS_FINE_LOCATION) ||
            hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        capturePlaceId(intent, notifyDart = true)
    }

    private fun capturePlaceId(intent: Intent?, notifyDart: Boolean) {
        val id = intent?.getStringExtra(EXTRA_PLACE_ID) ?: return
        if (notifyDart) {
            shortcutsChannel?.invokeMethod("onShortcutTap", id)
        } else {
            pendingPlaceId = id
        }
    }

    private fun requestPinShortcut(id: String, label: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = getSystemService(ShortcutManager::class.java) ?: return false
        if (!manager.isRequestPinShortcutSupported) return false

        val shortcutIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_OPEN_PLACE
            putExtra(EXTRA_PLACE_ID, id)
        }
        val shortcut = ShortcutInfo.Builder(this, "place_$id")
            .setShortLabel(label.take(40))
            .setLongLabel(label)
            .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(shortcutIntent)
            .build()

        manager.requestPinShortcut(shortcut, null)
        return true
    }

    companion object {
        private const val SHORTCUT_CHANNEL = "com.routenote.routenote/shortcuts"

        /** Must match [ForegroundTrackingService.channelName] in Dart. */
        private const val TRACKING_CHANNEL = "com.routenote.routenote/tracking"

        /** Must match [SensorMotionSignal.channelName] in Dart. */
        private const val MOTION_CHANNEL = "com.routenote.routenote/motion"

        private const val EXTRA_PLACE_ID = "com.routenote.routenote.PLACE_ID"
        private const val ACTION_OPEN_PLACE = "com.routenote.routenote.OPEN_PLACE"
    }
}
