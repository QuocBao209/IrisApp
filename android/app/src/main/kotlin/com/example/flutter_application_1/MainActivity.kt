package com.example.flutter_application_1

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.content.ContentValues
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.NonNull
import com.iritech.iic.IICAPI
import com.iritech.iic.IICConnectListener
import com.iritech.iic.android.AdditionalImageHeader
import com.iritech.iic.android.CaptureCallbackOption
import com.iritech.iic.android.CaptureControlCode
import com.iritech.iic.android.CaptureFlagOption
import com.iritech.iic.android.CaptureHint
import com.iritech.iic.android.CaptureNotification
import com.iritech.iic.android.CaptureStatus
import com.iritech.iic.android.CaptureTimeoutMode
import com.iritech.iic.android.CapturingEventCallback
import com.iritech.iic.android.CommunicationChannel
import com.iritech.iic.android.DeviceInfo
import com.iritech.iic.android.EyeSubType
import com.iritech.iic.android.IICHandle
import com.iritech.iic.android.IICResult
import com.iritech.iic.android.Image
import com.iritech.iic.android.ImageCompressionCriteria
import com.iritech.iic.android.ImageFormat
import com.iritech.iic.android.ImageKind
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.ArrayList

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.iritech.irisaegis/device"
    private val PREVIEW_CHANNEL = "com.iritech.irisaegis/preview"
    private val AUTO_CAPTURE_CHANNEL = "com.iritech.irisaegis/auto_capture"
    private val HINT_CHANNEL = "com.iritech.irisaegis/capture_hint"
    private val TAG = "IriTechPreview"

    private val previewFrameIntervalMs = 100L
    private val previewJpegQuality = 70
    private val previewDownscaleFactor = 2
    private val captureTimeMs = 3000
    private val sessionTimeoutMs = 20000
    private val streamingFrameRate = 15
    private val autoCaptureCooldownMs = 1500L

    private var hDevice: IICHandle? = null
    private var connectedDeviceUri: String? = null
    private var iicApi: IICAPI? = null
    private var deviceInfo: DeviceInfo? = null
    private var previewEventSink: EventChannel.EventSink? = null
    private var autoCaptureEventSink: EventChannel.EventSink? = null
    private var hintEventSink: EventChannel.EventSink? = null
    @Volatile
    private var sdkInitStarted = false
    @Volatile
    private var autoCaptureInProgress = false
    @Volatile
    private var lastAutoCaptureAtMs = 0L

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var previewRunning = false
    @Volatile
    private var captureSessionActive = false
    @Volatile
    private var lastPreviewFrameAtMs = 0L

    private val jpegBuffer = ByteArrayOutputStream(256 * 1024)
    private val connectLock = Any()
    private val jpegFormat = ImageFormat(ImageFormat.MONO_JPEG)

    private val connectListener = object : IICConnectListener {
        override fun onAttach() {}
        override fun onDetach() {}
        override fun onConnect() {}
        override fun onDisconnect() {}
        override fun onCancel() {}
    }

    private val capturingCallback = CapturingEventCallback { _, error, notification, _, _, images ->
        if (error.value != IICResult.OK) {
            Log.w(TAG, "Capture callback error: ${iicErrorMessage(error.value)}")
            mainHandler.post {
                previewEventSink?.error("PREVIEW_FAIL", iicErrorMessage(error.value), null)
            }
            return@CapturingEventCallback
        }

        if (images != null && images.isNotEmpty()) {
            emitPreviewFrame(images[0])
        }

        if (notification != null) {
            handleCaptureNotification(notification)
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        warmUpSdkAsync()

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PREVIEW_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    previewEventSink = events
                    startIrisPreviewStream()
                }

                override fun onCancel(arguments: Any?) {
                    previewEventSink = null
                    stopIrisPreview(keepCaptureSession = false)
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AUTO_CAPTURE_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    autoCaptureEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    autoCaptureEventSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HINT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    hintEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    hintEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "warmUpSdk" -> {
                        warmUpSdkAsync()
                        result.success(null)
                    }
                    "connectDevice", "openDevice" -> {
                        Thread {
                            val connectionStatus = setupIrisConnection()
                            mainHandler.post {
                                if (connectionStatus == "SUCCESS") {
                                    result.success("Kết nối thành công IrisAegis-26T")
                                } else {
                                    result.error("CONN_ERROR", connectionStatus, null)
                                }
                            }
                        }.apply { name = "IrisConnect" }.start()
                    }
                    "disconnectDevice" -> {
                        stopIrisPreview(keepCaptureSession = false)
                        releaseIrisConnection()
                        result.success("Đã ngắt kết nối thiết bị")
                    }
                    "stopPreview" -> {
                        stopIrisPreview(keepCaptureSession = false)
                        result.success(null)
                    }
                    "startPreview" -> {
                        startIrisPreviewStream()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startIrisPreviewStream() {
        if (previewRunning || previewEventSink == null || hDevice == null || iicApi == null) {
            return
        }

        val api = iicApi ?: return
        val handle = hDevice ?: return

        if (!ensureCaptureSession(api, handle)) {
            mainHandler.post {
                previewEventSink?.error("PREVIEW_FAIL", "Không thể khởi động quét Iris", null)
            }
            return
        }

        previewRunning = true
        lastPreviewFrameAtMs = 0L
        Log.i(TAG, "Iris auto-scan started (demo callback mode)")
    }

    private fun buildCaptureCallbackOption(): CaptureCallbackOption {
        return CaptureCallbackOption().apply {
            cbMethod = capturingCallback
            cbParam = null
            receiveStreamingImage = true
            imageDownscaleFactor = previewDownscaleFactor
            streamingImageFormat = jpegFormat
            streamingImageCompressionQuality = previewJpegQuality
            maxFrameRate = streamingFrameRate
        }
    }

    private fun buildCaptureOptionFlags(): Int {
        var flags = CaptureFlagOption.AUTO_CAPTURE or CaptureFlagOption.AUTO_LEDS
        val info = deviceInfo
        if (info != null && info.scannerCapability.supportImageVerticalFlip()) {
            flags = flags or CaptureFlagOption.IMAGE_VERTICAL_FLIP
        }
        return flags
    }

    private fun captureEyeSubType(): EyeSubType {
        val info = deviceInfo
        return if (info != null && info.scannerCapability.isMonocular) {
            EyeSubType(EyeSubType.UNDEF)
        } else {
            EyeSubType(EyeSubType.RIGHT_EYE)
        }
    }

    private fun resultEyeSubTypes(): List<EyeSubType> {
        val info = deviceInfo
        return if (info != null && (info.scannerCapability.isBinocular || info.scannerCapability.isFaceEyes)) {
            listOf(EyeSubType(EyeSubType.RIGHT_EYE), EyeSubType(EyeSubType.LEFT_EYE))
        } else {
            listOf(EyeSubType(EyeSubType.UNDEF))
        }
    }

    private fun emitPreviewFrame(image: Image) {
        val now = System.currentTimeMillis()
        if (now - lastPreviewFrameAtMs < previewFrameIntervalMs) {
            return
        }

        val jpeg = imageToPreviewJpeg(image) ?: return
        lastPreviewFrameAtMs = now

        mainHandler.post {
            if (previewRunning && previewEventSink != null) {
                previewEventSink?.success(jpeg)
            }
        }
    }

    private fun handleCaptureNotification(notification: CaptureNotification) {
        emitCaptureHint(notification)

        val api = iicApi ?: return
        val handle = hDevice ?: return

        when (notification.captureStatus.value) {
            CaptureStatus.CAPTURING -> {
                mainHandler.post {
                    hintEventSink?.success("Đã phát hiện mắt — đang quét mống mắt...")
                }
            }
            CaptureStatus.COMPLETE -> {
                val captured = deliverAutoCapture(api, handle)
                stopCaptureSession(api, handle)
                if (captured) {
                    Log.i(TAG, "Auto-captured iris image")
                }
                if (previewRunning) {
                    mainHandler.postDelayed({
                        if (previewRunning) {
                            ensureCaptureSession(api, handle)
                        }
                    }, 300)
                }
            }
            CaptureStatus.ABORT,
            CaptureStatus.FAILED_TO_CAPTURE,
            -> {
                stopCaptureSession(api, handle)
                if (previewRunning) {
                    mainHandler.postDelayed({
                        if (previewRunning) {
                            ensureCaptureSession(api, handle)
                        }
                    }, 300)
                }
            }
        }
    }

    private fun stopCaptureSession(api: IICAPI, handle: IICHandle) {
        if (!captureSessionActive) return
        api.controlCapture(handle, CaptureControlCode(CaptureControlCode.CANCEL))
        captureSessionActive = false
    }

    private fun emitCaptureHint(notification: CaptureNotification) {
        val hint = notification.captureHint?.value ?: return
        val message = captureHintMessage(hint) ?: return
        mainHandler.post {
            hintEventSink?.success(message)
        }
    }

    private fun captureHintMessage(hint: Int): String? = when (hint) {
        CaptureHint.GOOD -> "Giữ yên — đang quét mống mắt..."
        CaptureHint.MOVE_CLOSER -> "Tiến mắt lại gần thiết bị"
        CaptureHint.MOVE_FARTHER -> "Lùi mắt ra xa một chút"
        CaptureHint.LOOK_STRAIGHT -> "Nhìn thẳng vào camera"
        CaptureHint.OPEN_EYE_FULL -> "Mở to mắt"
        CaptureHint.NO_EYE -> "Đặt mắt vào vùng quét"
        CaptureHint.TOO_BRIGHT -> "Ánh sáng quá mạnh — đổi vị trí"
        CaptureHint.TOO_DARK -> "Thiếu sáng — tăng ánh sáng xung quanh"
        CaptureHint.BAD -> "Điều chỉnh lại vị trí mắt"
        else -> null
    }

    private fun deliverAutoCapture(api: IICAPI, handle: IICHandle): Boolean {
        if (autoCaptureInProgress || autoCaptureEventSink == null) {
            return false
        }

        val now = System.currentTimeMillis()
        if (now - lastAutoCaptureAtMs < autoCaptureCooldownMs) {
            return false
        }

        autoCaptureInProgress = true
        return try {
            for (eye in resultEyeSubTypes()) {
                val imagePath = saveResultImage(api, handle, eye) ?: continue
                lastAutoCaptureAtMs = now
                mainHandler.post {
                    autoCaptureEventSink?.success(imagePath)
                }
                return true
            }
            false
        } catch (e: Exception) {
            Log.w(TAG, "Auto capture failed: ${e.message}")
            false
        } finally {
            autoCaptureInProgress = false
        }
    }

    private fun saveResultImage(api: IICAPI, handle: IICHandle, eyeSubType: EyeSubType): String? {
        val image = Image()
        val imageRet = api.getResultImage(
            handle,
            eyeSubType,
            AdditionalImageHeader(AdditionalImageHeader.HEADER_NONE),
            true,
            ImageFormat(ImageFormat.MONO_JPEG),
            ImageKind(ImageKind.K7),
            ImageCompressionCriteria(ImageCompressionCriteria.QUALITY),
            85,
            image,
        )
        if (imageRet.value != IICResult.OK) {
            Log.w(TAG, "getResultImage failed: ${iicErrorMessage(imageRet.value)}")
            return null
        }

        val imageData = image.imageData ?: return null
        val outputFile = File(cacheDir, "iris_capture_${System.currentTimeMillis()}.jpg")
        outputFile.writeBytes(imageData)

        // Copy to public Downloads so user can see/share the captured image
        copyToDownloadsIfPossible(imageData, outputFile.name)

        return outputFile.absolutePath
    }

    private fun copyToDownloadsIfPossible(imageData: ByteArray, fileName: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Use MediaStore to write into public Downloads without legacy storage permission.
                val resolver = contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }

                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return
                resolver.openOutputStream(uri)?.use { out ->
                    out.write(imageData)
                    out.flush()
                }

                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } else {
                // Legacy fallback: if we can't write to public downloads, ignore and keep cache copy.
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val outFile = File(downloadsDir, fileName)
                outFile.parentFile?.mkdirs()
                outFile.writeBytes(imageData)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Copy to Downloads failed: ${e.message}")
        }
    }

    private fun stopIrisPreview(keepCaptureSession: Boolean) {
        previewRunning = false
        if (!keepCaptureSession) {
            val api = iicApi
            val handle = hDevice
            if (api != null && handle != null) {
                stopCaptureSession(api, handle)
            }
        }
    }

    private fun imageToBitmap(image: Image): Bitmap? {
        val data = image.imageData ?: return null
        if (data.isEmpty()) return null

        val width = image.imageWidth
        val height = image.imageHeight
        if (width > 0 && height > 0 && data.size >= width * height) {
            val pixels = IntArray(width * height)
            for (y in 0 until height) {
                for (x in 0 until width) {
                    val gray = data[y * width + x].toInt() and 0xFF
                    pixels[y * width + x] = (0xFF shl 24) or (gray shl 16) or (gray shl 8) or gray
                }
            }
            return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
        }

        return BitmapFactory.decodeByteArray(data, 0, data.size)
    }

    private fun imageToPreviewJpeg(image: Image): ByteArray? {
        val data = image.imageData ?: return null
        if (data.size >= 2 && data[0] == 0xFF.toByte() && data[1] == 0xD8.toByte()) {
            return data
        }

        val bitmap = imageToBitmap(image) ?: return null
        return compressBitmap(bitmap)
    }

    private fun compressBitmap(bitmap: Bitmap): ByteArray {
        jpegBuffer.reset()
        bitmap.compress(Bitmap.CompressFormat.JPEG, previewJpegQuality, jpegBuffer)
        if (!bitmap.isRecycled) {
            bitmap.recycle()
        }
        return jpegBuffer.toByteArray()
    }

    private fun iicErrorMessage(code: Int): String {
        val name = IICAPI.getErrorName(code)
        return if (name.isNullOrBlank()) "mã lỗi $code" else "$name (mã $code)"
    }

    private fun warmUpSdkAsync() {
        if (sdkInitStarted) return
        sdkInitStarted = true
        Thread {
            try {
                ensureIicApi()
                Log.i(TAG, "Iris SDK pre-initialized")
            } catch (e: Exception) {
                Log.w(TAG, "Iris SDK pre-init failed: ${e.message}")
            }
        }.apply { name = "IrisSdkInit"; isDaemon = true; start() }
    }

    @Synchronized
    private fun ensureIicApi(): IICAPI {
        if (iicApi == null) {
            iicApi = IICAPI.getInstance(applicationContext, connectListener)
        }
        return iicApi!!
    }

    private fun isDeviceStillConnected(): Boolean {
        val api = iicApi ?: return false
        val handle = hDevice ?: return false
        val info = DeviceInfo()
        return api.getDeviceInfo(handle, info).value == IICResult.OK
    }

    private fun ensureCaptureSession(api: IICAPI, handle: IICHandle): Boolean {
        if (captureSessionActive) {
            return true
        }

        val startRet = api.startCapturing(
            handle,
            captureEyeSubType(),
            CaptureTimeoutMode(CaptureTimeoutMode.TIMEBASED),
            captureTimeMs,
            sessionTimeoutMs,
            buildCaptureOptionFlags(),
            buildCaptureCallbackOption(),
        )

        if (startRet.value != IICResult.OK) {
            Log.e(TAG, "startCapturing failed: ${iicErrorMessage(startRet.value)}")
            return false
        }

        captureSessionActive = true
        Log.i(TAG, "startCapturing OK — AUTO_CAPTURE enabled")
        return true
    }

    private fun clearDeviceHandle() {
        val api = iicApi
        val handle = hDevice
        if (api != null && handle != null) {
            api.closeDevice(handle)
        }
        hDevice = null
        connectedDeviceUri = null
        deviceInfo = null
        captureSessionActive = false
    }

    private fun setupIrisConnection(): String {
        synchronized(connectLock) {
            try {
                val api = ensureIicApi()

                if (hDevice != null && isDeviceStillConnected()) {
                    Log.i(TAG, "Reusing existing Iris connection")
                    return "SUCCESS"
                }

                clearDeviceHandle()

                val deviceUris = ArrayList<String>()
                val scanRet = api.scanDevices(CommunicationChannel(CommunicationChannel.USB), deviceUris)

                if (scanRet.value != IICResult.OK) {
                    return "Lỗi quét thiết bị ngoại vi USB (Mã lỗi: ${scanRet.value})"
                }
                if (deviceUris.isEmpty()) {
                    return "Không tìm thấy thiết bị IrisAegis-26T nào được cắm vào!"
                }

                val targetUri = deviceUris[0]
                val handle = IICHandle()
                val openRet = api.openDevice(targetUri, null, handle)
                if (openRet.value != IICResult.OK && openRet.value != IICResult.DEVICE_ALREADY_OPEN) {
                    return "Không thể mở cổng điều khiển thiết bị (Mã lỗi: ${openRet.value})"
                }

                val info = DeviceInfo()
                val infoRet = api.getDeviceInfo(handle, info)
                if (infoRet.value != IICResult.OK) {
                    api.closeDevice(handle)
                    return "Không đọc được thông tin thiết bị (Mã lỗi: ${infoRet.value})"
                }

                hDevice = handle
                connectedDeviceUri = targetUri
                deviceInfo = info
                Log.i(TAG, "Iris device opened: $targetUri, monocular=${info.scannerCapability.isMonocular}")
                return "SUCCESS"
            } catch (e: Exception) {
                return "Lỗi khởi tạo môi trường SDK: ${e.message}"
            }
        }
    }

    private fun releaseIrisConnection() {
        stopIrisPreview(keepCaptureSession = false)
        clearDeviceHandle()
        iicApi?.deinit()
        iicApi = null
        sdkInitStarted = false
    }

    override fun onDestroy() {
        releaseIrisConnection()
        super.onDestroy()
    }
}
