package com.routenote.routenote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps MapNote's daily GPS trackers alive while the
 * app is in the background.
 *
 * Android only delivers location updates to a backgrounded process through a
 * foreground service with the `location` type (declared in AndroidManifest
 * with `android:foregroundServiceType="location"`). The Dart trackers keep
 * owning the actual measurement logic — this service exists so the OS does not
 * freeze the process, and it posts the compact, silent notification the
 * platform requires.
 *
 * Started/stopped from Dart through `ForegroundTrackingService`
 * (`com.routenote.routenote/tracking`).
 */
class LocationTrackingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureNotificationChannel()
        val notification: Notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: Exception) {
            // A denied/revoked location permission makes the platform refuse the
            // foreground promotion; stop cleanly instead of crashing the app.
            stopSelf()
        }
        // Tracking is driven by the Flutter side, so never restart on our own.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        // The toggles went off: the session is over, so the notification must
        // be removed completely — never leave a stale "AutoMotion Active" row.
        dismissNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    /**
     * Removes the tracking notification from the drawer.
     *
     * `stopForeground(STOP_FOREGROUND_REMOVE)` already detaches it from the
     * service, but cancelling by id also covers the case where the service was
     * stopped while the app process kept running.
     */
    private fun dismissNotification() {
        val manager: NotificationManager =
            getSystemService(NotificationManager::class.java) ?: return
        manager.cancel(NOTIFICATION_ID)
    }

    private fun buildNotification(): Notification {
        val openApp: PendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            // Compact single row (icon + title + subtext, one line, minimal
            // height). The standard title/text below stay as the fallback for
            // other surfaces and for accessibility services.
            .setCustomContentView(compactContentView())
            .setCustomBigContentView(compactContentView())
            .setContentTitle(getString(R.string.tracking_notification_title))
            .setContentText(getString(R.string.tracking_notification_text))
            .setContentIntent(openApp)
            // Silent, one-alert-only, never a badge, never mirrored to other
            // devices: tracking is a private, always-on hint, not an alert.
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setOngoing(true)
            .setLocalOnly(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    /**
     * The single-line layout from `notification_tracking_compact.xml`: a 16dp
     * status icon, the "AutoMotion Active" title and the "Tracking distance &
     * speed" subtext on one row, all clamped to one line.
     */
    private fun compactContentView(): RemoteViews =
        RemoteViews(packageName, R.layout.notification_tracking_compact).apply {
            setImageViewResource(R.id.tracking_notification_icon, R.mipmap.ic_launcher)
          }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager: NotificationManager =
            getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        // IMPORTANCE_LOW = silent (no sound, no heads-up) and, with the flags
        // below, no vibration and no badge; VISIBILITY_PRIVATE keeps it off
        // the lock screen.
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.tracking_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.tracking_channel_description)
            setShowBadge(false)
            enableVibration(false)
            enableLights(false)
            setSound(null, null)
            // Lock-screen visibility is set per notification (VISIBILITY_PRIVATE
            // below) because NotificationChannel#setLockscreenVisibility only
            // exists from API 28.
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        /** Notification channel shared by every tracking session. */
        private const val CHANNEL_ID = "mapnote_tracking"

        /** Stable id so re-starts reuse the same ongoing notification. */
        private const val NOTIFICATION_ID = 43011
    }
}
