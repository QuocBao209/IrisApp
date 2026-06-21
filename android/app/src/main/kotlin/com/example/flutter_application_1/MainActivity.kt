package com.example.flutter_application_1

import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList

// Gọi trực tiếp thư viện trong file .aar của IriTech
import com.iritech.iic.IICAPI
import com.iritech.iic.IICHandle

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.iritech.irisaegis/device"
    private var hDevice: IICHandle? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connectDevice", "openDevice" -> {
                        val connectionStatus = setupIrisConnection()
                        if (connectionStatus == "SUCCESS") {
                            result.success("Kết nối thành công IrisAegis-26T")
                        } else {
                            result.error("CONN_ERROR", connectionStatus, null)
                        }
                    }
                    "disconnectDevice" -> {
                        releaseIrisConnection()
                        result.success("Đã ngắt kết nối thiết bị")
                    }
                    "startCapture" -> {
                        println("=== IriTech Test API: Bắt đầu kích hoạt nút chụp từ Flutter ===")

                        val currentHandle = hDevice
                        if (currentHandle == null) {
                            println("=== IriTech Test API: THẤT BẠI - hDevice đang bị NULL ===")
                            result.error("API_FAIL", "Thiết bị chưa được mở cổng hoặc chưa connect trước đó!", null)
                            return@setMethodCallHandler
                        }

                        // Gọi hàm API thật từ SDK IriTech để lấy PropertyId số 1 (Ví dụ: kiểm tra Device Info / Status)
                        // Hàm này kiểm tra xem mạch lệnh USB xuống chip của IrisAegis-26T có thông suốt hay không
                        val propertyValue = ByteArray(256)
                        val valueLength = IntArray(1)

                        println("=== IriTech Test API: Đang gọi hàm IIC_GetProperty thật từ SDK ===")
                        val apiRet = IICAPI.IIC_GetProperty(currentHandle, 1, propertyValue, valueLength)

                        if (apiRet == 0) { // 0 tương ứng với mã BERR_OK (Thành công)
                            println("=== IriTech Test API: THÀNH CÔNG - Thiết bị thật phản hồi API tốt! ===")
                            result.success("API_CALL_SUCCESS: Thiết bị thật phản hồi mã code 0")
                        } else {
                            println("=== IriTech Test API: THẤT BẠI - Thiết bị trả về mã lỗi SDK: $apiRet ===")
                            result.error("API_FAIL", "Thiết bị phản hồi lỗi phần cứng, mã lỗi: $apiRet", null)
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    private fun setupIrisConnection(): String {
        val initRet = IICAPI.IIC_Init()
        if (initRet != 0) {
            return "Lỗi khởi tạo môi trường SDK (Mã lỗi: $initRet)"
        }

        val deviceUris = ArrayList<String>()
        val scanRet = IICAPI.IIC_ScanDevice(1, deviceUris)

        if (scanRet != 0) {
            return "Lỗi quét thiết bị ngoại vi USB (Mã lỗi: $scanRet)"
        }
        if (deviceUris.isEmpty()) {
            return "Không tìm thấy thiết bị IrisAegis-26T nào được cắm vào!"
        }

        val targetUri = deviceUris[0]
        hDevice = IICHandle()

        val openRet = IICAPI.IIC_OpenDevice(targetUri, null, hDevice)
        if (openRet != 0) {
            return "Không thể mở cổng điều khiển thiết bị (Mã lỗi: $openRet)"
        }

        return "SUCCESS"
    }

    private fun releaseIrisConnection() {
        hDevice?.let {
            IICAPI.IIC_CloseDevice(it)
            hDevice = null
        }
        IICAPI.IIC_Deinit()
    }

    override fun onDestroy() {
        releaseIrisConnection()
        super.onDestroy()
    }
}