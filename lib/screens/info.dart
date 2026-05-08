import 'package:flutter/material.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: const Text("Thông tin sản phẩm", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
                    ),
                    child: const Icon(Icons.remove_red_eye_rounded, size: 60, color: Color(0xFF4285F4)),
                  ),
                  const SizedBox(height: 16),
                  const Text("Iris Diagnosis AI", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const Text("Phiên bản 1.0.0 (MVP)", style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            _buildSectionTitle("Giới thiệu"),
            _buildInfoCard("Ứng dụng sử dụng trí tuệ nhân tạo (AI) để phân tích cấu trúc và sắc tố mống mắt, hỗ trợ người dùng nhận diện sớm các dấu hiệu bất thường về sức khỏe."),

            const SizedBox(height: 24),
            _buildSectionTitle("Công nghệ sử dụng"),
            _buildInfoCard("* TensorFlow Lite: Xử lý mô hình AI chẩn đoán ngay trên thiết bị.\n* Flutter: Đảm bảo giao diện mượt mà và đa nền tảng.\n* Firebase: Hệ thống lưu trữ và quản lý dữ liệu đám mây bảo mật."),

            const SizedBox(height: 24),
            _buildSectionTitle("Lưu ý quan trọng (Disclaimer)"),
            _buildWarningCard("Kết quả chẩn đoán từ AI chỉ mang tính chất tham khảo. Ứng dụng không thay thế chẩn đoán chuyên môn từ bác sĩ chuyên khoa. Vui lòng tham vấn chuyên gia y tế trước khi thực hiện bất kỳ thay đổi nào về chế độ sinh hoạt hoặc điều trị."),

            const SizedBox(height: 40),
            const Center(
              child: Text("© 2026 Developed by Iris Tech Team", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4285F4))),
    );
  }

  Widget _buildInfoCard(String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Text(content, style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87)),
    );
  }

  Widget _buildWarningCard(String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(content, style: const TextStyle(fontSize: 13, color: Colors.brown, height: 1.4))),
        ],
      ),
    );
  }
}