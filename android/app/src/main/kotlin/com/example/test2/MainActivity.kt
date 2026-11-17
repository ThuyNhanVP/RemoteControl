package com.example.test2

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.ConsumerIrManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var speechRecognizer: SpeechRecognizer? = null
    private var channel: MethodChannel? = null

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

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir")
        channel = ch

        ch.setMethodCallHandler { call, result ->
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
                    // Lưu lệnh BẬT/TẮT cho ô cài đặt nhanh (IrTileService)
                    "setTile" -> {
                        getSharedPreferences("tile", MODE_PRIVATE).edit()
                            .putString("on", call.argument<String>("on"))
                            .putString("off", call.argument<String>("off"))
                            .putBoolean("powered", call.argument<Boolean>("powered") ?: false)
                            .apply()
                        result.success(null)
                    }
                    "tileOn" -> result.success(
                        getSharedPreferences("tile", MODE_PRIVATE).getBoolean("powered", false)
                    )
                    "cancelReminder" -> {
                        am.cancel(reminderIntent())
                        result.success(null)
                    }
                    // nhận diện giọng nói
                    "isSpeechAvailable" -> {
                        result.success(SpeechRecognizer.isRecognitionAvailable(this))
                    }
                    "startSpeech" -> {
                        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                            != PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), 2)
                            result.error("NO_PERMISSION", "Cần quyền micro để nhận diện giọng nói", null)
                        } else if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                            result.error("UNAVAILABLE", "Thiết bị không hỗ trợ nhận diện giọng nói", null)
                        } else {
                            startListeningSpeech()
                            result.success(null)
                        }
                    }
                    "stopSpeech" -> {
                        stopListeningSpeech()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startListeningSpeech() {
        Handler(Looper.getMainLooper()).post {
            try {
                destroySpeech()
                val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
                speechRecognizer = recognizer

                recognizer.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        channel?.invokeMethod("onSpeechEvent", mapOf("type" to "ready"))
                    }

                    override fun onBeginningOfSpeech() {
                        channel?.invokeMethod("onSpeechEvent", mapOf("type" to "start"))
                    }

                    override fun onRmsChanged(rmsdB: Float) {
                        channel?.invokeMethod("onSpeechEvent", mapOf("type" to "rms", "value" to rmsdB))
                    }

                    override fun onBufferReceived(buffer: ByteArray?) {}

                    override fun onEndOfSpeech() {
                        channel?.invokeMethod("onSpeechEvent", mapOf("type" to "end"))
                    }

                    override fun onError(error: Int) {
                        val msg = when (error) {
                            SpeechRecognizer.ERROR_AUDIO -> "Lỗi thu âm"
                            SpeechRecognizer.ERROR_CLIENT -> "Lỗi phía ứng dụng"
                            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Thiếu quyền truy cập micro"
                            SpeechRecognizer.ERROR_NETWORK -> "Lỗi kết nối mạng"
                            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Hết thời gian kết nối"
                            SpeechRecognizer.ERROR_NO_MATCH -> "Không nghe thấy câu trả lời phù hợp"
                            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Dịch vụ giọng nói đang bận"
                            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Hết thời gian chờ giọng nói"
                            else -> "Lỗi nhận diện giọng nói ($error)"
                        }
                        channel?.invokeMethod("onSpeechEvent", mapOf("type" to "error", "message" to msg))
                    }

                    override fun onResults(results: Bundle?) {
                        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull() ?: ""
                        channel?.invokeMethod("onSpeechEvent", mapOf("type" to "final", "text" to text))
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull() ?: ""
                        channel?.invokeMethod("onSpeechEvent", mapOf("type" to "partial", "text" to text))
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "vi-VN")
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "vi-VN")
                    putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, "vi-VN")
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                }
                recognizer.startListening(intent)
            } catch (e: Exception) {
                channel?.invokeMethod("onSpeechEvent", mapOf("type" to "error", "message" to e.message))
            }
        }
    }

    private fun stopListeningSpeech() {
        try {
            speechRecognizer?.stopListening()
        } catch (_: Exception) {}
    }

    private fun destroySpeech() {
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.destroy()
        } catch (_: Exception) {}
        speechRecognizer = null
    }

    override fun onDestroy() {
        destroySpeech()
        super.onDestroy()
    }
}