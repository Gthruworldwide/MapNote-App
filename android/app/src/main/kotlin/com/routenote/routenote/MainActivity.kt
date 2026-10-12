package com.routenote.routenote

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth, which
// shows the system BiometricPrompt as a fragment.
class MainActivity : FlutterFragmentActivity() {
    private var shortcutsChannel: MethodChannel? = null
    private var pendingPlaceId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        addTestCrashButtonIfDebuggable()
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

        // The app may have been launched cold from a pinned shortcut.
        capturePlaceId(intent, notifyDart = false)
    }

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
        private const val EXTRA_PLACE_ID = "com.routenote.routenote.PLACE_ID"
        private const val ACTION_OPEN_PLACE = "com.routenote.routenote.OPEN_PLACE"
    }
}
