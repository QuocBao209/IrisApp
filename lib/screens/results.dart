import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'camera.dart';

class ResultScreen extends StatelessWidget {
  final String imagePath;
  final String? roiPath;
  final String? irisPath;
  final Map<String, dynamic> result;

  const ResultScreen({
    super.key,
    required this.imagePath,
    this.roiPath,
    this.irisPath,
    required this.result,
  });

  Color _getThemeColor(String prediction) {
    switch (prediction) {
      case 'positive':
        return Colors.red;

      case 'negative':
        return Colors.green;

      default:
        return Colors.orange;
    }
  }

  String _getTitle(String prediction) {
    switch (prediction) {
      case 'negative':
        return 'Khỏe mạnh';

      case 'positive':
        return 'Có dấu hiệu bệnh';

      default:
        return 'Không xác định được, nên đi kiểm tra';
    }
  }

  String _getDescription(String prediction) {
    switch (prediction) {
      case 'negative':
        return 'AI không phát hiện dấu hiệu bất thường liên quan đến phổi từ ảnh mống mắt được cung cấp.';

      case 'positive':
        return 'AI phát hiện dấu hiệu bất thường liên quan đến phổi. Kết quả chỉ mang tính tham khảo và không thay thế chẩn đoán y khoa.';

      default:
        return 'Hệ thống chưa thể đưa ra kết luận. Hãy gặp chuyên khoa để kiểm tra';
    }
  }

  IconData _getIcon(String prediction) {
    switch (prediction) {
      case 'negative':
        return Icons.verified;

      case 'positive':
        return Icons.warning_amber_rounded;

      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dynamic rawValue = result['prediction'];
    print("DEBUG: Giá trị nhận được từ API là: '$rawValue'");
    final String prediction =
    (result['prediction'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final rawConfidence =
    (result['confidence'] ?? 0).toDouble();

    final int confidence = (rawConfidence <= 1.0
        ? (rawConfidence * 100)
        : rawConfidence
    ).clamp(0, 100).round();

    final Color themeColor =
    _getThemeColor(prediction);

    final String title =
    _getTitle(prediction);

    final String description =
    _getDescription(prediction);

    final String timestamp =
    DateFormat('HH:mm dd/MM/yyyy')
        .format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),

      appBar: AppBar(
        title: const Text('Kết quả phân tích'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),

              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: themeColor.withOpacity(0.3),
                  width: 2,
                ),
              ),

              child: Column(
                children: [
                  Icon(
                    _getIcon(prediction),
                    size: 60,
                    color: themeColor,
                  ),

                  const SizedBox(height: 12),

                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: themeColor,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),

                  if ((result['error'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Chi tiết lỗi: ${result['error']}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],

                  if (result['probs'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'probs: ${result['probs']}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                  ],

                  const SizedBox(height: 12),

                  Text(
                    timestamp,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _buildScoreCard(
              confidence,
              themeColor,
            ),

            if (_hasImage(roiPath) || _hasImage(irisPath)) ...[
              const SizedBox(height: 24),
              _buildImageSection(),
            ],

            const SizedBox(height: 24),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),

              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),

              child: const Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lưu ý',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: 12),

                  Text(
                    'AI chỉ mang tính tham khảo. Ảnh ROI cũng được lưu trong thư mục Downloads (tên bắt đầu IrisApp_roi_...).',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                      const CameraScreen(),
                    ),
                  );
                },

                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  const Color(0xFF4285F4),
                  padding:
                  const EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(16),
                  ),
                ),

                child: const Text(
                  'Quét lại',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasImage(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  Widget _buildImageSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ảnh đã cắt',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_hasImage(roiPath)) ...[
            const Text('ROI phổi (đưa vào AI)', style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(roiPath!),
                width: double.infinity,
                height: 120,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_hasImage(irisPath)) ...[
            const Text('Mống mắt toàn phần', style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(irisPath!),
                width: double.infinity,
                height: 180,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreCard(
      int confidence,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),

      child: Column(
        children: [
          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Độ tin cậy của AI',
                style: TextStyle(fontSize: 16),
              ),
              Text(
                '$confidence%',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          LinearProgressIndicator(
            value: confidence / 100,
            minHeight: 10,
            color: color,
            backgroundColor:
            color.withOpacity(0.2),
            borderRadius:
            BorderRadius.circular(10),
          ),
        ],
      ),
    );
  }
}