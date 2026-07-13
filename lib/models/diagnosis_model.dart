class RoiResult {
  final String roiName;
  final String unwrappedBmpUrl;
  final double score;
  final String statusColor;

  RoiResult({
    required this.roiName,
    required this.unwrappedBmpUrl,
    required this.score,
    required this.statusColor,
  });

  // Chuyển dữ liệu từ Firebase thành Object Dart
  factory RoiResult.fromMap(Map<String, dynamic> map) {
    return RoiResult(
      roiName: map['roiName'] ?? '',
      unwrappedBmpUrl: map['unwrappedBmpUrl'] ?? '',
      score: (map['score'] ?? 0.0).toDouble(),
      statusColor: map['statusColor'] ?? 'Green',
    );
  }

  // Chuyển Object Dart thành JSON để đẩy lên Firebase
  Map<String, dynamic> toMap() {
    return {
      'roiName': roiName,
      'unwrappedBmpUrl': unwrappedBmpUrl,
      'score': score,
      'statusColor': statusColor,
    };
  }
}

class EyeRecord {
  final bool isScanned;
  final String fullIrisImageUrl;
  final List<RoiResult> roiResults;

  EyeRecord({
    required this.isScanned,
    required this.fullIrisImageUrl,
    required this.roiResults,
  });

  factory EyeRecord.fromMap(Map<String, dynamic> map) {
    return EyeRecord(
      isScanned: map['isScanned'] ?? false,
      fullIrisImageUrl: map['fullIrisImageUrl'] ?? '',
      roiResults: List<RoiResult>.from(
        (map['roiResults'] ?? []).map((x) => RoiResult.fromMap(x)),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isScanned': isScanned,
      'fullIrisImageUrl': fullIrisImageUrl,
      'roiResults': roiResults.map((x) => x.toMap()).toList(),
    };
  }
}

class DiagnosisSession {
  final String diagnosisId;
  final String userId;
  final DateTime timestamp;
  final String overallStatus;
  final EyeRecord? leftEye;
  final EyeRecord? rightEye;

  DiagnosisSession({
    required this.diagnosisId,
    required this.userId,
    required this.timestamp,
    required this.overallStatus,
    this.leftEye,
    this.rightEye,
  });

  // Hàm chuyển đổi từ Map của Firestore thành DiagnosisSession
  factory DiagnosisSession.fromMap(Map<String, dynamic> map, String docId) {
    return DiagnosisSession(
      diagnosisId: docId, // Lấy ID của document trên Firestore
      userId: map['userId'] ?? '',
      timestamp: map['timestamp'] != null
          ? (map['timestamp'] as dynamic).toDate() // Xử lý kiểu Timestamp của Firestore
          : DateTime.now(),
      overallStatus: map['overallStatus'] ?? 'Chưa xác định',
      leftEye: map['leftEye'] != null ? EyeRecord.fromMap(map['leftEye']) : null,
      rightEye: map['rightEye'] != null ? EyeRecord.fromMap(map['rightEye']) : null,
    );
  }

  // Hàm chuyển đổi Object thành Map để đẩy lên Firestore
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      // Không cần đẩy timestamp ở đây nếu bạn dùng FieldValue.serverTimestamp() ở hàm add
      'overallStatus': overallStatus,
      'leftEye': leftEye?.toMap(),
      'rightEye': rightEye?.toMap(),
    };
  }
}