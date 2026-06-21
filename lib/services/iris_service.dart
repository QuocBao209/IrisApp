import 'package:flutter/services.dart';

class IrisAegisService {
  // Chuỗi định danh khớp chính xác 100% với cấu hình tại MainActivity.kt
  static const _channel = MethodChannel('com.iritech.irisaegis/biometric');

  // Gọi hàm kích hoạt kết nối phần cứng từ giao diện UI
  Future<String> connectToDevice() async {
    try {
      final String result = await _channel.invokeMethod('connectDevice');
      return result;
    } on PlatformException catch (e) {
      return "Lỗi kết nối phần cứng: ${e.message} (Mã định danh lỗi: ${e.code})";
    }
  }

  // Gọi hàm ngắt kết nối dọn dẹp bộ nhớ ngầm
  Future<void> disconnectDevice() async {
    try {
      await _channel.invokeMethod('disconnectDevice');
    } on PlatformException catch (e) {
      print("Lỗi hệ thống khi hủy kết nối: ${e.message}");
    }
  }
}