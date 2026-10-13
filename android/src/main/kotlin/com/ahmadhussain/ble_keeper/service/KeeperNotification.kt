package com.ahmadhussain.ble_keeper.service

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import com.ahmadhussain.ble_keeper.KeeperConstants
import com.ahmadhussain.ble_keeper.R
import com.ahmadhussain.ble_keeper.core.Session

/**
 * The foreground-service notification. Android requires one for the whole
 * lifetime of a foreground service. Text comes from the most recent
 * keepConnected options, falling back to the plugin's string resources (which
 * the host app can override by defining the same resource names).
 */
internal object KeeperNotification {

    fun build(context: Context, sessions: List<Session>): Notification {
        createChannel(context)
        val options = sessions.lastOrNull()
        val title = options?.notificationTitle ?: appLabel(context)
        val text = options?.notificationText ?: context.resources.getQuantityString(
            R.plurals.ble_keeper_notification_text,
            sessions.size,
            sessions.size,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, KeeperConstants.NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
        }
        builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(resolveIcon(context, options?.notificationIcon))
            .setOngoing(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
        launchIntent(context)?.let { builder.setContentIntent(it) }
        return builder.build()
    }

    fun update(context: Context, sessions: List<Session>) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        nm.notify(KeeperConstants.NOTIFICATION_ID, build(context, sessions))
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            KeeperConstants.NOTIFICATION_CHANNEL_ID,
            context.getString(R.string.ble_keeper_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setShowBadge(false)
        nm.createNotificationChannel(channel)
    }

    /** FLAG_IMMUTABLE: required from Android 12 and prevents other apps from altering the intent. */
    private fun launchIntent(context: Context): PendingIntent? {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun appLabel(context: Context): String =
        context.applicationInfo.loadLabel(context.packageManager).toString()

    /**
     * Resolves a drawable or mipmap from the host app by name. Resource
     * shrinking removes resources only referenced by name, so the app must keep
     * it (see README). Falls back to the plugin's own icon.
     */
    @SuppressLint("DiscouragedApi")
    private fun resolveIcon(context: Context, name: String?): Int {
        if (!name.isNullOrBlank()) {
            val res = context.resources
            val id = res.getIdentifier(name, "drawable", context.packageName).takeIf { it != 0 }
                ?: res.getIdentifier(name, "mipmap", context.packageName)
            if (id != 0) return id
        }
        return R.drawable.ic_ble_keeper_notification
    }
}
