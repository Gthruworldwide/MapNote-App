package com.routenote.routenote

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel

/**
 * Streams raw accelerometer samples to Dart while a daily tracker needs an
 * independent "is the device moving?" signal.
 *
 * Rationale: when the GPS signal is lost (tunnel, car park, dense city) the
 * trackers still have to know whether the vehicle kept moving, and the GPS
 * cannot answer that. The accelerometer can — the engine/road vibration this
 * listener forwards is classified in Dart (see `MotionClassifier` in
 * `lib/src/services/motion_signal.dart`), which keeps the interesting logic
 * unit-testable.
 *
 * No runtime permission is required for `TYPE_ACCELEROMETER`. The listener is
 * registered only while Dart is subscribed, so nothing is sampled while both
 * tracking toggles are off.
 *
 * Channel: `com.routenote.routenote/motion` (see [SensorMotionSignal] on the
 * Dart side). Every event is a `[x, y, z]` list of doubles in m/s² (gravity
 * included).
 */
class MotionSensorChannel(context: Context) :
    EventChannel.StreamHandler,
    SensorEventListener {

    private val appContext: Context = context.applicationContext
    private val sensorManager: SensorManager? =
        appContext.getSystemService(Context.SENSOR_SERVICE) as? SensorManager

    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val manager = sensorManager
        val accelerometer = manager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (manager == null || accelerometer == null) {
            // No accelerometer (rare): Dart falls back to GPS-speed evidence.
            events?.error("unavailable", "No accelerometer on this device", null)
            return
        }
        eventSink = events
        manager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        sensorManager?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        val sink = eventSink ?: return
        if (event.values.size < 3) return
        sink.success(
            listOf(
                event.values[0].toDouble(),
                event.values[1].toDouble(),
                event.values[2].toDouble(),
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Accuracy changes do not affect the vibration classifier.
    }
}
