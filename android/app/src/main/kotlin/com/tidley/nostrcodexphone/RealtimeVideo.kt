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
    private var sink: EventChannel.EventSink? = null
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
                if (source != "camera" && source != "screen") result.error("invalid_source", "source must be camera or screen.", null)
                else { stopCapture(); handler.post { startCapture(source, result) } }
            }
            "stopCapture" -> { stopCapture(); result.success(null) }
            "createRenderer" -> result.success(createRenderer())
            "releaseRenderer" -> {
                call.argument<Number>("textureId")?.toLong()?.let { releaseRenderer(it) }
                result.success(null)
            }
            "pushFragment" -> {
                val id = call.argument<Number>("textureId")?.toLong()
                val fragment = call.argument<ByteArray>("fragment")
                if (id == null || fragment == null) result.error("invalid_fragment", "textureId and fragment are required.", null)
                else { renderers[id]?.push(fragment); result.success(null) }
            }
            "dispose" -> { dispose(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission")
    private fun startCapture(source: String, result: MethodChannel.Result) {
        if (encoder != null) { result.success(null); return }
        if (sink == null) { result.error("no_frame_listener", "Listen for video fragments before starting capture.", null); return }
        if (source == "camera" && ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            result.error("camera_denied", "CAMERA permission is not granted.", null); return
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
            result.error("screen_denied", "Screen capture permission was not granted.", null)
            return true
        }
        val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        projection = manager.getMediaProjection(resultCode, data)
        ContextCompat.startForegroundService(context, Intent(context, ScreenShareService::class.java))
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
                        setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
                        setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                    }, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    encoderSurface = it.createInputSurface()
                    it.start()
                }
                encoder = codec
                if (source == "screen") openScreen() else openCamera()
                drainEncoder()
                sink?.success(null)
            } catch (error: Exception) {
                stopCapture()
                sink?.error("video_capture_failed", error.message, null)
            }
        }
        result.success(null)
    }

    private fun openScreen() {
        val surface = encoderSurface ?: return
        val metrics = context.resources.displayMetrics
        virtualDisplay = projection?.createVirtualDisplay(
            "CodeCallScreen", width, height, metrics.densityDpi,
            android.hardware.display.DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            surface, null, handler,
        ) ?: run { sink?.error("screen_capture_failed", "Could not create screen capture.", null); null }
    }

    @SuppressLint("MissingPermission")
    private fun openCamera() {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = manager.cameraIdList.firstOrNull { id ->
            manager.getCameraCharacteristics(id).get(android.hardware.camera2.CameraCharacteristics.LENS_FACING) ==
                android.hardware.camera2.CameraCharacteristics.LENS_FACING_FRONT
        } ?: manager.cameraIdList.first()
        manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
            override fun onOpened(device: CameraDevice) {
                camera = device
                val surface = encoderSurface ?: return
                device.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        cameraSession = session
                        session.setRepeatingRequest(device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                            addTarget(surface)
                            set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                        }.build(), null, handler)
                    }
                    override fun onConfigureFailed(session: CameraCaptureSession) { sink?.error("camera_config_failed", "Camera video session failed.", null) }
                }, handler)
            }
            override fun onDisconnected(device: CameraDevice) { device.close() }
            override fun onError(device: CameraDevice, error: Int) { device.close(); sink?.error("camera_open_failed", "Camera error $error", null) }
        }, handler)
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
            sink?.success(data)
            offset += count
            fragment++
        }
    }

    private fun stopCapture() {
        handler.post {
            cameraSession?.close(); cameraSession = null
            camera?.close(); camera = null
            virtualDisplay?.release(); virtualDisplay = null
            projection?.stop(); projection = null
            context.stopService(Intent(context, ScreenShareService::class.java))
            encoder?.stop(); encoder?.release(); encoder = null
            encoderSurface?.release(); encoderSurface = null
            codecConfig = ByteArray(0)
        }
    }

    private fun createRenderer(): Long {
        val entry = textures.createSurfaceTexture()
        entry.surfaceTexture().setDefaultBufferSize(width, height)
        renderers[entry.id()] = Renderer(entry)
        return entry.id()
    }

    private fun releaseRenderer(id: Long) { renderers.remove(id)?.release() }

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

        fun push(fragment: ByteArray) {
            if (fragment.size <= headerBytes || fragment[0].toInt() != videoVersion) return
            val sequence = ((fragment[2].toInt() and 0xff) shl 8) or (fragment[3].toInt() and 0xff)
            val part = ((fragment[4].toInt() and 0xff) shl 8) or (fragment[5].toInt() and 0xff)
            if (sequence != this.sequence) { this.sequence = sequence; expectedFragment = 0; frame.reset() }
            if (part != expectedFragment) { frame.reset(); expectedFragment = 0; return }
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
        }
        fun release() { codec.stop(); codec.release(); surface.release(); entry.release() }
    }

    private fun ByteBuffer.copy(offset: Int, size: Int): ByteArray = duplicate().apply { position(offset); limit(offset + size) }.let { buffer -> ByteArray(size).also { buffer.get(it) } }

    companion object {
        private const val mime = "video/avc"
        private const val width = 640
        private const val height = 360
        private const val frameRate = 10
        private const val bitRate = 500_000
        private const val videoVersion = 2
        private const val headerBytes = 10
        private const val maxFragmentBytes = 1190
        private const val keyFrameFlag = 1
        private const val endOfFrameFlag = 2
        const val screenCaptureRequestCode = 4817
    }
}
