package com.routenote.routenote

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel

/**
 * Streams raw accelerometer and gyroscope samples to Dart while a daily
 * tracker needs an independent "is the device moving?" signal.
 *
 * Rationale: when the GPS signal is lost (tunnel, car park, dense city) the
 * trackers still have to know whether the vehicle kept moving, and the GPS
 * cannot answer that. The accelerometer and gyroscope can — the engine/road
 * vibration and yaw rate this listener forwards are classified in Dart (see
 * `MotionClassifier` in `lib/src/services/motion_signal.dart` and the dead
 * reckoning in `lib/src/services/dead_reckoning_service.dart`), which keeps
 * the interesting logic unit-testable.
 *
 * No runtime permission is required for `TYPE_ACCELEROMETER` or
 * `TYPE_GYROSCOPE`. Both listeners are registered only while Dart is
 * subscribed, so nothing is sampled while both tracking toggles are off.
 *
 * Channel: `com.routenote.routenote/motion` (see [MotionSensorHub] on the
 * Dart side). Events are `[x, y, z, tag]`, where `tag` is `0` for the
 * accelerometer (m/s², gravity included) and `1` for the gyroscope (rad/s).
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
        if (manager == null) {
            events?.error("unavailable", "No sensor manager on this device", null)
            return
        }
        val accelerometer = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (accelerometer == null) {
            // No accelerometer (rare): Dart falls back to GPS-speed evidence.
            events?.error("unavailable", "No accelerometer on this device", null)
            return
        }
        eventSink = events
        manager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_UI)
        // The gyroscope is optional: dead reckoning degrades to accelerometer
        // only when it is missing, so its absence is not an error.
        manager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)?.let { gyroscope ->
            manager.registerListener(this, gyroscope, SensorManager.SENSOR_DELAY_UI)
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        sensorManager?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        val sink = eventSink ?: return
        if (event.values.size < 3) return
        // Tag each event so the single stream can carry both sensors without
        // a second channel: 0 = accelerometer, 1 = gyroscope.
        val tag = when (event.sensor.type) {
            Sensor.TYPE_GYROSCOPE -> GYROSCOPE_TAG
            else -> ACCELEROMETER_TAG
        }
        sink.success(
            listOf(
                event.values[0].toDouble(),
                event.values[1].toDouble(),
                event.values[2].toDouble(),
                tag,
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Accuracy changes do not affect the vibration classifier.
    }

    private companion object {
        const val ACCELEROMETER_TAG = 0
        const val GYROSCOPE_TAG = 1
    }
}
