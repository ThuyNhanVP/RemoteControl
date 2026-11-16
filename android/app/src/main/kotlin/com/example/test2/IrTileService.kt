package com.example.test2

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.hardware.ConsumerIrManager
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

// Ô cài đặt nhanh: bật/tắt điều hòa đang dùng mà không cần mở app.
// Lệnh IR do app (Dart) tính sẵn và lưu trong SharedPreferences "tile".
class IrTileService : TileService() {
    private val prefs get() = getSharedPreferences("tile", MODE_PRIVATE)

    override fun onStartListening() = refresh()

    override fun onClick() {
        val on = !prefs.getBoolean("powered", false) // trạng thái muốn chuyển tới
        val cmd = prefs.getString(if (on) "on" else "off", null)
        if (cmd == null) { // app chưa lưu lệnh: mở app để nó lưu
            openApp()
            return
        }
        val ir = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager
        if (ir?.hasIrEmitter() == true) {
            val (freq, body) = cmd.split(";", limit = 2)
            ir.transmit(freq.toInt(), body.split(",").map { it.toInt() }.toIntArray())
            prefs.edit().putBoolean("powered", on).apply()
        }
        refresh()
    }

    private fun openApp() {
        val i = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) ?: return
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION") startActivityAndCollapse(i)
        }
    }

    private fun refresh() {
        val t = qsTile ?: return
        val on = prefs.getBoolean("powered", false)
        t.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        t.label = "Điều hòa"
        t.updateTile()
    }
}