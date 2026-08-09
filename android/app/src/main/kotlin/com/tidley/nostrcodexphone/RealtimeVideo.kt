package com.tidley.nostrcodexphone

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Bundle
import android.util.DisplayMetrics
import android.view.Surface
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer

/** Small Camera2/MediaCodec H.264 bridge. Fragments are bounded for FIPS QUIC datagrams. */
class RealtimeVideo(
    private val context: Context,
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "nostr_codex_phone/realtime_video")
    private val frames = EventChannel(messenger, "nostr_codex_phone/realtime_video_frames")
    private val thread = HandlerThread("RealtimeVideo").apply { start() }
    private val handler = Handler(thread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var sink: EventChannel.EventSink? = null
    private var encoder: MediaCodec? = null
    private var camera: CameraDevice? = null
    private var cameraSession: CameraCaptureSession? = null
    private var encoderSurface: Surface? = null
    private var projection: MediaProjection? = null
    private var virtualDisplay: android.hardware.display.VirtualDisplay? = null
    private var pendingScreenResult: MethodChannel.Result? = null
    private var codecConfig = ByteArray(0)
    private var frameSequence = 0
    private val renderers = mutableMapOf<Long, Renderer>()

    init {
        methods.setMethodCallHandler(this)
        frames.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startCapture" -> startCapture(call.argument<String>("source") ?: "camera", result)
            "switchCapture" -> {
                val source = call.argument<String>("source")
                if (source != "camera" && source != "screen") error(result, "invalid_source", "source must be camera or screen.")
                else stopCapture { startCapture(source, result) }
            }
            "stopCapture" -> stopCapture { success(result) }
            "createRenderer" -> success(result, createRenderer())
            "releaseRenderer" -> {
                call.argument<Number>("textureId")?.toLong()?.let { releaseRenderer(it) }
                success(result)
            }
            "pushFragment" -> {
                val id = call.argument<Number>("textureId")?.toLong()
                val fragment = call.argument<ByteArray>("fragment")
                if (id == null || fragment == null) error(result, "invalid_fragment", "textureId and fragment are required.")
                else success(result, renderers[id]?.push(fragment) ?: false)
            }
            "requestKeyFrame" -> handler.post {
                encoder?.setParameters(Bundle().apply {
                    putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
                })
                success(result)
            }
            "dispose" -> { dispose(); success(result) }
            else -> main { result.notImplemented() }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startCapture(source: String, result: MethodChannel.Result) {
        if (encoder != null) { success(result); return }
        if (sink == null) { error(result, "no_frame_listener", "Listen for video fragments before starting capture."); return }
        if (source == "camera" && ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            error(result, "camera_denied", "CAMERA permission is not granted."); return
        }
        if (source == "screen") {
            pendingScreenResult = result
            val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            activity.runOnUiThread {
                activity.startActivityForResult(manager.createScreenCaptureIntent(), screenCaptureRequestCode)
            }
            return
        }
        beginCapture(source, result)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != screenCaptureRequestCode) return false
        val result = pendingScreenResult ?: return true
        pendingScreenResult = null
        if (resultCode != android.app.Activity.RESULT_OK || data == null) {
            error(result, "screen_denied", "Screen capture permission was not granted.")
            return true
        }
        val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        // Android 14+ requires the media-projection foreground service before
        // obtaining the projection token.
        ContextCompat.startForegroundService(context, Intent(context, ScreenShareService::class.java))
        projection = manager.getMediaProjection(resultCode, data)
        beginCapture("screen", result)
        return true
    }

    private fun beginCapture(source: String, result: MethodChannel.Result) {
        handler.post {
            try {
                val codec = MediaCodec.createEncoderByType(mime).also {
                    it.configure(MediaFormat.createVideoFormat(mime, width, height).apply {
                        setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                        setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
                        // Static screen content needs fewer encoded frames than a camera.
                        setInteger(MediaFormat.KEY_FRAME_RATE, if (source == "screen") screenFrameRate else cameraFrameRate)
                        setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                    }, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    encoderSurface = it.createInputSurface()
                    it.start()
                }
                encoder = codec
                if (source == "screen") {
                    if (openScreen()) startEncoder(result)
                    else failStart(result, "screen_capture_failed", "Could not create screen capture.")
                } else {
                    openCamera(
                        onReady = { startEncoder(result) },
                        onFailure = { code, message -> failStart(result, code, message) },
                    )
                }
            } catch (error: Exception) {
                failStart(result, "video_capture_failed", error.message)
            }
        }
    }

    private fun startEncoder(result: MethodChannel.Result) {
        drainEncoder()
        success(result)
    }

    private fun failStart(result: MethodChannel.Result, code: String, message: String?) {
        stopCapture { error(result, code, message) }
    }

    private fun openScreen(): Boolean {
        val surface = encoderSurface ?: return false
        val metrics = context.resources.displayMetrics
        virtualDisplay = projection?.createVirtualDisplay(
            "CodeCallScreen", width, height, metrics.densityDpi,
            android.hardware.display.DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            surface, null, handler,
        )
        return virtualDisplay != null
    }

    @SuppressLint("MissingPermission")
    private fun openCamera(
        onReady: () -> Unit,
        onFailure: (String, String) -> Unit,
    ) {
        var started = false
        var startupResolved = false
        fun failStartup(code: String, message: String) {
            if (startupResolved) return
            startupResolved = true
            onFailure(code, message)
        }
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = manager.cameraIdList.firstOrNull { id ->
            manager.getCameraCharacteristics(id).get(android.hardware.camera2.CameraCharacteristics.LENS_FACING) ==
                android.hardware.camera2.CameraCharacteristics.LENS_FACING_FRONT
        } ?: manager.cameraIdList.first()
        manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
            override fun onOpened(device: CameraDevice) {
                camera = device
                val surface = encoderSurface ?: run {
                    device.close()
                    failStartup("camera_start_failed", "Camera encoder surface is unavailable.")
                    return
                }
                device.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        try {
                            session.setRepeatingRequest(device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                                addTarget(surface)
                                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                            }.build(), null, handler)
                            cameraSession = session
                            started = true
                            startupResolved = true
                            onReady()
                        } catch (error: Exception) {
                            session.close()
                            failStartup("camera_start_failed", error.message ?: "Camera could not start recording.")
                        }
                    }
                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        session.close()
                        failStartup("camera_config_failed", "Camera video session failed.")
                    }
                }, handler)
            }
            override fun onDisconnected(device: CameraDevice) {
                device.close()
                if (started) captureFailed("camera_disconnected", "Camera was disconnected.")
                else failStartup("camera_disconnected", "Camera was disconnected.")
            }
            override fun onError(device: CameraDevice, error: Int) {
                device.close()
                if (started) captureFailed("camera_open_failed", "Camera error $error")
                else failStartup("camera_open_failed", "Camera error $error")
            }
        }, handler)
    }

    private fun captureFailed(code: String, message: String) {
        stopCapture()
        emitError(code, message)
    }

    private fun drainEncoder() {
        val codec = encoder ?: return
        val info = MediaCodec.BufferInfo()
        while (true) {
            val index = codec.dequeueOutputBuffer(info, 0)
            if (index < 0) break
            val bytes = codec.getOutputBuffer(index)?.copy(info.offset, info.size) ?: ByteArray(0)
            val flags = info.flags
            codec.releaseOutputBuffer(index, false)
            if (flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) codecConfig = bytes
            else if (bytes.isNotEmpty()) emitFrame(if (flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0) codecConfig + bytes else bytes, flags, info.presentationTimeUs)
        }
        if (encoder != null) handler.postDelayed({ drainEncoder() }, 5)
    }

    private fun emitFrame(h264: ByteArray, codecFlags: Int, timestampUs: Long) {
        val frame = frameSequence++ and 0xffff
        var offset = 0
        var fragment = 0
        while (offset < h264.size) {
            val count = minOf(maxFragmentBytes, h264.size - offset)
            var flags = if (codecFlags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0) keyFrameFlag else 0
            if (offset + count == h264.size) flags = flags or endOfFrameFlag
            val data = ByteBuffer.allocate(headerBytes + count).apply {
                put(videoVersion.toByte()); put(flags.toByte()); putShort(frame.toShort()); putShort(fragment.toShort()); putInt(timestampUs.toInt()); put(h264, offset, count)
            }.array()
            emitSuccess(data)
            offset += count
            fragment++
        }
    }

    private fun stopCapture(onStopped: (() -> Unit)? = null) {
        handler.post {
            cameraSession?.close(); cameraSession = null
            camera?.close(); camera = null
            virtualDisplay?.release(); virtualDisplay = null
            projection?.stop(); projection = null
            context.stopService(Intent(context, ScreenShareService::class.java))
            encoder?.stop(); encoder?.release(); encoder = null
            encoderSurface?.release(); encoderSurface = null
            codecConfig = ByteArray(0)
            onStopped?.let { callback -> main { callback() } }
        }
    }

    private fun createRenderer(): Long {
        val entry = textures.createSurfaceTexture()
        entry.surfaceTexture().setDefaultBufferSize(width, height)
        renderers[entry.id()] = Renderer(entry)
        return entry.id()
    }

    private fun releaseRenderer(id: Long) { renderers.remove(id)?.release() }

    private fun main(callback: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) callback() else mainHandler.post(callback)
    }

    private fun success(result: MethodChannel.Result, value: Any? = null) = main { result.success(value) }

    private fun error(result: MethodChannel.Result, code: String, message: String?) =
        main { result.error(code, message, null) }

    private fun emitSuccess(value: Any? = null) = main { sink?.success(value) }

    private fun emitError(code: String, message: String?) = main { sink?.error(code, message, null) }

    fun dispose() {
        stopCapture()
        renderers.values.forEach { it.release() }
        renderers.clear()
        methods.setMethodCallHandler(null); frames.setStreamHandler(null); thread.quitSafely()
    }

    private class Renderer(private val entry: TextureRegistry.SurfaceTextureEntry) {
        private val surface = Surface(entry.surfaceTexture())
        private val codec = MediaCodec.createDecoderByType(mime).also {
            it.configure(MediaFormat.createVideoFormat(mime, width, height), surface, null, 0); it.start()
        }
        private var sequence = -1
        private var expectedFragment = 0
        private var frame = java.io.ByteArrayOutputStream()
        private var waitingForKeyFrame = true
        private var keyFrameRequestPending = false

        fun push(fragment: ByteArray): Boolean {
            if (fragment.size <= headerBytes || fragment[0].toInt() != videoVersion) return false
            val sequence = ((fragment[2].toInt() and 0xff) shl 8) or (fragment[3].toInt() and 0xff)
            val part = ((fragment[4].toInt() and 0xff) shl 8) or (fragment[5].toInt() and 0xff)
            val isKeyFrame = fragment[1].toInt() and keyFrameFlag != 0
            if (sequence != this.sequence) {
                if (frame.size() > 0) waitingForKeyFrame = true
                this.sequence = sequence; expectedFragment = 0; frame.reset()
            }
            if (waitingForKeyFrame) {
                if (!isKeyFrame) return requestKeyFrame()
                waitingForKeyFrame = false
                keyFrameRequestPending = false
            }
            if (part != expectedFragment) {
                frame.reset(); expectedFragment = 0; waitingForKeyFrame = true
                return requestKeyFrame()
            }
            frame.write(fragment, headerBytes, fragment.size - headerBytes); expectedFragment++
            if (fragment[1].toInt() and endOfFrameFlag != 0) {
                val index = codec.dequeueInputBuffer(0)
                if (index >= 0) {
                    codec.getInputBuffer(index)?.apply { clear(); put(frame.toByteArray()) }
                    codec.queueInputBuffer(index, 0, frame.size(), 0, 0)
                }
                val info = MediaCodec.BufferInfo()
                while (true) { val output = codec.dequeueOutputBuffer(info, 0); if (output < 0) break; codec.releaseOutputBuffer(output, true) }
                frame.reset(); expectedFragment = 0
            }
            return false
        }
        private fun requestKeyFrame(): Boolean {
            if (keyFrameRequestPending) return false
            keyFrameRequestPending = true
            return true
        }
        fun release() { codec.stop(); codec.release(); surface.release(); entry.release() }
    }

    private fun ByteBuffer.copy(offset: Int, size: Int): ByteArray = duplicate().apply { position(offset); limit(offset + size) }.let { buffer -> ByteArray(size).also { buffer.get(it) } }

    companion object {
        private const val mime = "video/avc"
        // 640x480 is a baseline Camera2 recording size, including on older tablets
        // that reject the previous 640x360 encoder surface.
        private const val width = 640
        private const val height = 480
        private const val cameraFrameRate = 10
        private const val screenFrameRate = 5
        private const val bitRate = 350_000
        private const val videoVersion = 2
        private const val headerBytes = 10
        // Leave room below QUIC's 1200-byte minimum datagram size for transport
        // overhead negotiated by FIPS peers.
        private const val maxFragmentBytes = 1000
        private const val keyFrameFlag = 1
        private const val endOfFrameFlag = 2
        const val screenCaptureRequestCode = 4817
    }
}
