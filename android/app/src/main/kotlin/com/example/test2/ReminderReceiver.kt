package com.example.test2

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// Hiện thông báo khi đến giờ nhắc (cần Android 8+ cho kênh thông báo)
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel("remind", "Nhắc bật điều hòa", NotificationManager.IMPORTANCE_DEFAULT)
        )
        val open = PendingIntent.getActivity(
            c, 0, c.packageManager.getLaunchIntentForPackage(c.packageName),
            PendingIntent.FLAG_IMMUTABLE
        )
        nm.notify(
            1,
            Notification.Builder(c, "remind")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(i.getStringExtra("title"))
                .setContentText(i.getStringExtra("body"))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
        )
    }
}
