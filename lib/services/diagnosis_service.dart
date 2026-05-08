import 'dart:math';

class DiagnosisService {
  Future<Map<String, dynamic>> analyzeIris(String imagePath) async {
    await Future.delayed(const Duration(seconds: 2, milliseconds: 500));

    final random = Random();
    final bool isHealthy = random.nextBool();
    final int score = isHealthy
        ? 85 + random.nextInt(11)
        : 65 + random.nextInt(21);

    if (isHealthy) {
      return {
        "score": score,
        "status": "Mắt khỏe mạnh",
        "message": "Không có dấu hiệu bất thường. Mống mắt của bạn cho thấy các cơ quan nội tạng đang hoạt động tốt.",
        "color": "green",
        "issues": [],
        "recommendations": [
          "Tiếp tục duy trì chế độ ăn uống lành mạnh",
          "Uống đủ 2-2.5 lít nước mỗi ngày",
          "Ngủ đủ giấc và tập thể dục đều đặn"
        ],
      };
    } else {
      return {
        "score": score,
        "status": "Cần khám ngay",
        "message": "Phát hiện một số dấu hiệu bất thường cần theo dõi và khám chuyên sâu.",
        "color": "red",
        "issues": [
          "Phát hiện dấu hiệu viêm giác mạc nhẹ",
          "Mạch máu bất thường ở vùng gan",
          "Sắc tố mống mắt không đồng đều"
        ],
        "recommendations": [
          "Bổ sung vitamin C và các chất chống oxy hóa",
          "Nên gặp bác sĩ nội soi hoặc chuyên gia gan mật sớm",
          "Hạn chế đồ cay nóng, rượu bia và thức khuya"
        ],
      };
    }
  }
}