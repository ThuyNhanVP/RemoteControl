package com.example.test2

import android.content.Context
import android.hardware.ConsumerIrManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val ir = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager

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
                    else -> result.notImplemented()
                }
            }
    }
}