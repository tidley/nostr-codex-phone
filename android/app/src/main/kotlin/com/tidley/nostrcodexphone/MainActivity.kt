package com.tidley.nostrcodexphone

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
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
    private val callAudioChannelName = "nostr_codex_phone/call_audio"
    private var hardStopTts: TextToSpeech? = null
    private var pendingHardStop = false
    private var callAudioTrack: AudioTrack? = null
    private var realtimeAudio: RealtimeAudio? = null
    private var realtimeVideo: RealtimeVideo? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureHardStopTts()
        realtimeAudio = RealtimeAudio(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        realtimeVideo = RealtimeVideo(applicationContext, flutterEngine.dartExecutor.binaryMessenger, flutterEngine.renderer)
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
                "replyVibrate" -> {
                    replyVibrate()
                    result.success(null)
                }
                "backgroundDelivery" -> {
                    val enabled = call.argument<Boolean>("enabled") == true
                    if (enabled) {
                        val intent = Intent(this, BackgroundDeliveryService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                    } else {
                        stopService(Intent(this, BackgroundDeliveryService::class.java))
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callAudioChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startCallAudio(call.argument<Int>("sampleRate") ?: 16000)
                    result.success(null)
                }
                "write" -> {
                    val pcm = call.argument<ByteArray>("pcm")
                    if (pcm != null) callAudioTrack?.write(
                        pcm, 0, pcm.size, AudioTrack.WRITE_NON_BLOCKING
                    )
                    result.success(null)
                }
                "stop" -> {
                    stopCallAudio()
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

    private fun startCallAudio(sampleRate: Int) {
        stopCallAudio()
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = true
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(sampleRate / 10)
        callAudioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setBufferSizeInBytes(minBuffer * 2)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
            .also { it.play() }
    }

    private fun stopCallAudio() {
        callAudioTrack?.pause()
        callAudioTrack?.flush()
        callAudioTrack?.release()
        callAudioTrack = null
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        audioManager?.mode = AudioManager.MODE_NORMAL
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

    private fun replyVibrate() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audioManager?.ringerMode == AudioManager.RINGER_MODE_SILENT) return

        val vibrator = currentVibrator() ?: return
        if (!vibrator.hasVibrator()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            vibrator.vibrate(
                VibrationEffect.createWaveform(longArrayOf(0, 180, 70, 120), -1),
                attributes
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(longArrayOf(0, 180, 70, 120), -1)
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
        realtimeAudio?.dispose()
        realtimeAudio = null
        realtimeVideo?.dispose()
        realtimeVideo = null
        stopCallAudio()
        hardStopTts?.stop()
        hardStopTts?.shutdown()
        hardStopTts = null
        super.onDestroy()
    }
}
