package com.example.nostr_codex_phone

import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "nostr_codex_phone/tts_control"
    private var hardStopTts: TextToSpeech? = null
    private var pendingHardStop = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureHardStopTts()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "hardStop" -> {
                    hardStop()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun ensureHardStopTts() {
        if (hardStopTts != null) return

        hardStopTts =
            TextToSpeech(applicationContext) {
                if (pendingHardStop) {
                    pendingHardStop = false
                    hardStopTts?.stop()
                }
            }
    }

    private fun hardStop() {
        pendingHardStop = true
        ensureHardStopTts()
        hardStopTts?.stop()
    }

    override fun onDestroy() {
        hardStopTts?.stop()
        hardStopTts?.shutdown()
        hardStopTts = null
        super.onDestroy()
    }
}
