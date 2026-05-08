import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'camera.dart';

class ResultScreen extends StatelessWidget {
  final String imagePath;
  final Map<String, dynamic> result;

  const ResultScreen({super.key, required this.imagePath, required this.result});

  @override
  Widget build(BuildContext context) {
    final int score = result['score'] ?? 0;
    final bool isHealthy = score >= 80;
    final String timestamp = DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now());

    final Color themeColor = isHealthy ? Colors.green : Colors.redAccent;
    final Color bgColor = isHealthy ? const Color(0xFFE6F9F0) : const Color(0xFFFEE8E8);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: const Text("Kết quả phân tích"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: themeColor.withOpacity(0.3), width: 2),
              ),
              child: Column(
                children: [
                  Icon(isHealthy ? Icons.check_circle : Icons.warning_amber_rounded, color: themeColor, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    isHealthy ? "Mắt khỏe mạnh" : "Cần lưu ý",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: themeColor),
                  ),
                  const SizedBox(height: 6),
                  Text(result['message'] ?? "", textAlign: TextAlign.center, style: TextStyle(color: themeColor.withOpacity(0.9), fontSize: 15)),
                  const SizedBox(height: 12),
                  Text(timestamp, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _buildScoreCard(score, themeColor),
            const SizedBox(height: 24),

            _buildDetailSection(isHealthy),
            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("Quét lại", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard(int score, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Độ tin cậy", style: TextStyle(fontSize: 16)),
              Text("$score%", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: score / 100,
            color: color,
            backgroundColor: color.withOpacity(0.2),
            minHeight: 10,
            borderRadius: BorderRadius.circular(10),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(bool isHealthy) {
    final items = isHealthy
        ? ["Mống mắt sáng rõ, không có vết rạn.", "Tiếp tục duy trì chế độ sinh hoạt lành mạnh.", "Nên kiểm tra định kỳ sau mỗi 6 tháng."]
        : ["Xuất hiện điểm tối ở vùng gan.", "Có dấu hiệu thiếu ngủ kéo dài.", "Khuyên dùng thêm thực phẩm giàu Vitamin A."];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isHealthy ? "Chỉ số sức khỏe" : "Phát hiện bất thường", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(isHealthy ? Icons.check_circle_rounded : Icons.info_rounded, color: isHealthy ? Colors.green : Colors.redAccent, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(item, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87))),
              ],
            ),
          )),
        ],
      ),
    );
  }
}