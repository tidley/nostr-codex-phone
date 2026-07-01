package com.tidley.nostrcodexphone

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import android.view.HapticFeedbackConstants
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
                "hapticTap" -> {
                    hapticTap()
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

    private fun hapticTap() {
        window.decorView.performHapticFeedback(
            HapticFeedbackConstants.KEYBOARD_TAP,
            HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
        )

        val vibrator = currentVibrator() ?: return
        if (!vibrator.hasVibrator()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(48, VibrationEffect.DEFAULT_AMPLITUDE)
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(48)
        }
    }

    private fun currentVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    override fun onDestroy() {
        hardStopTts?.stop()
        hardStopTts?.shutdown()
        hardStopTts = null
        super.onDestroy()
    }
}
