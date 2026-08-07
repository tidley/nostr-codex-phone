package com.tidley.nostrcodexphone

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.os.Process
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max

/** Native 48 kHz, mono, signed-16-bit PCM transport for a future realtime call stack. */
class RealtimeAudio(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methodChannel = MethodChannel(messenger, methodChannelName)
    private val frameChannel = EventChannel(messenger, frameChannelName)
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var frameSink: EventChannel.EventSink? = null
    @Volatile private var recorder: AudioRecord? = null
    private var captureThread: Thread? = null
    @Volatile private var capturing = false
    private var player: AudioTrack? = null

    init {
        methodChannel.setMethodCallHandler(this)
        frameChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startCapture" -> startCapture(result)
            "stopCapture" -> {
                stopCapture()
                result.success(null)
            }
            "playPcm" -> playPcm(call, result)
            "stopPlayback" -> {
                stopPlayback()
                result.success(null)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        frameSink = events
    }

    override fun onCancel(arguments: Any?) {
        frameSink = null
        stopCapture()
    }

    private fun startCapture(result: MethodChannel.Result) {
        if (capturing) {
            result.success(null)
            return
        }
        if (frameSink == null) {
            result.error("no_frame_listener", "Listen for PCM frames before starting capture.", null)
            return
        }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("record_audio_denied", "RECORD_AUDIO permission is not granted.", null)
            return
        }

        val minBufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBufferSize <= 0) {
            result.error("capture_unsupported", "48 kHz mono PCM capture is not supported.", null)
            return
        }

        val audioRecord = AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build(),
            )
            .setBufferSizeInBytes(max(minBufferSize, frameBytes * 4))
            .build()
        if (audioRecord.state != AudioRecord.STATE_INITIALIZED) {
            audioRecord.release()
            result.error("capture_init_failed", "AudioRecord could not initialize.", null)
            return
        }

        recorder = audioRecord
        capturing = true
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = true
        try {
            audioRecord.startRecording()
        } catch (exception: IllegalStateException) {
            capturing = false
            recorder = null
            audioManager.mode = AudioManager.MODE_NORMAL
            audioRecord.release()
            result.error("capture_start_failed", exception.message, null)
            return
        } catch (exception: SecurityException) {
            capturing = false
            recorder = null
            audioManager.mode = AudioManager.MODE_NORMAL
            audioRecord.release()
            result.error("record_audio_denied", exception.message, null)
            return
        }
        captureThread = Thread({ readFrames(audioRecord) }, "RealtimeAudioCapture").apply {
            start()
        }
        result.success(null)
    }

    private fun readFrames(audioRecord: AudioRecord) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
        val frame = ByteArray(frameBytes)
        var offset = 0
        while (capturing && recorder === audioRecord) {
            @Suppress("DEPRECATION")
            val count = audioRecord.read(frame, offset, frame.size - offset)
            if (count > 0) {
                offset += count
                if (offset == frame.size) {
                    val pcm = frame.copyOf()
                    mainHandler.post { frameSink?.success(pcm) }
                    offset = 0
                }
            } else if (count != AudioRecord.ERROR_INVALID_OPERATION && capturing) {
                mainHandler.post {
                    frameSink?.error("capture_read_failed", "AudioRecord read failed: $count", null)
                }
                stopCapture()
                break
            }
        }
    }

    private fun stopCapture() {
        val audioRecord = recorder ?: return
        capturing = false
        recorder = null
        try {
            audioRecord.stop()
        } catch (_: IllegalStateException) {
        }
        audioRecord.release()
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = false
        audioManager.mode = AudioManager.MODE_NORMAL
        val thread = captureThread
        captureThread = null
        if (thread != null && thread !== Thread.currentThread()) thread.join(captureStopJoinMs)
    }

    private fun playPcm(call: MethodCall, result: MethodChannel.Result) {
        val pcm = call.argument<ByteArray>("pcm")
        if (pcm == null || pcm.isEmpty()) {
            result.error("invalid_pcm", "pcm must be a non-empty byte array.", null)
            return
        }
        if (pcm.size % bytesPerSample != 0) {
            result.error("invalid_pcm", "pcm must contain complete signed-16-bit samples.", null)
            return
        }
        val audioTrack = try {
            player ?: createPlayer().also { player = it }
        } catch (exception: IllegalStateException) {
            result.error("playback_unsupported", exception.message, null)
            return
        }
        val written = audioTrack.write(pcm, 0, pcm.size, AudioTrack.WRITE_NON_BLOCKING)
        if (written < 0) {
            result.error("playback_write_failed", "AudioTrack write failed: $written", null)
            return
        }
        result.success(written)
    }

    private fun createPlayer(): AudioTrack {
        val minBufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        check(minBufferSize > 0) { "48 kHz mono PCM playback is not supported." }
        return AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build(),
            )
            .setBufferSizeInBytes(max(minBufferSize, frameBytes * 12))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
            .also { it.play() }
    }

    private fun stopPlayback() {
        val audioTrack = player ?: return
        player = null
        try {
            audioTrack.pause()
            audioTrack.flush()
        } catch (_: IllegalStateException) {
        }
        audioTrack.release()
    }

    fun dispose() {
        stopCapture()
        stopPlayback()
        frameSink = null
        methodChannel.setMethodCallHandler(null)
        frameChannel.setStreamHandler(null)
    }

    companion object {
        private const val methodChannelName = "nostr_codex_phone/realtime_audio"
        private const val frameChannelName = "nostr_codex_phone/realtime_audio_frames"
        const val sampleRate = 48_000
        const val frameDurationMs = 20
        private const val bytesPerSample = 2
        const val frameBytes = sampleRate * frameDurationMs / 1_000 * bytesPerSample
        private const val captureStopJoinMs = 500L
    }
}
