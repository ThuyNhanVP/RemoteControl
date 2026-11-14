package com.example.test2

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.ConsumerIrManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private fun reminderIntent(title: String = "", body: String = ""): PendingIntent =
        PendingIntent.getBroadcast(
            this, 7,
            Intent(this, ReminderReceiver::class.java).putExtra("title", title).putExtra("body", body),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val ir = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasIr" -> result.success(ir?.hasIrEmitter() == true)
                    "transmit" -> {
                        val freq = call.argument<Int>("freq") ?: 38000
                        val pattern = call.argument<List<Int>>("pattern")
                        if (ir == null || pattern == null) {
                            result.error("NO_IR", "Thiết bị không có IR hoặc thiếu dữ liệu", null)
                        } else {
                            ir.transmit(freq, pattern.toIntArray())
                            result.success(null)
                        }
                    }
                    // Giờ báo thức kế tiếp (ms) của app đồng hồ, null nếu không có
                    "nextAlarm" -> result.success(am.nextAlarmClock?.triggerTime)
                    "scheduleReminder" -> {
                        val at = call.argument<Number>("at")?.toLong()
                        if (at == null) {
                            result.error("BAD_ARGS", "Thiếu giờ nhắc", null)
                        } else {
                            if (Build.VERSION.SDK_INT >= 33 &&
                                checkSelfPermission("android.permission.POST_NOTIFICATIONS")
                                != PackageManager.PERMISSION_GRANTED
                            ) {
                                requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 1)
                            }
                            // shortcut: báo thức không chính xác tuyệt đối (lệch vài phút khi máy ngủ sâu),
                            // dùng setExactAndAllowWhileIdle nếu cần và xin quyền báo thức chính xác
                            am.setAndAllowWhileIdle(
                                AlarmManager.RTC_WAKEUP, at,
                                reminderIntent(
                                    call.argument<String>("title") ?: "",
                                    call.argument<String>("body") ?: ""
                                )
                            )
                            result.success(null)
                        }
                    }
                    "cancelReminder" -> {
                        am.cancel(reminderIntent())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
