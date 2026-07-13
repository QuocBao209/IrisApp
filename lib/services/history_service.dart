import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 1. Tạo phiên khám cha (chỉ chứa metadata, KHÔNG chứa ảnh nữa)
  Future<String?> createDiagnosisSession() async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    try {
      DocumentReference docRef = await _db.collection('diagnoses').add({
        'userId': uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
      return docRef.id;
    } catch (e) {
      print('Lỗi tạo phiên khám: $e');
      return null;
    }
  }

  // 2. Lưu kết quả từng mắt vào sub-collection — ẢNH LƯU Ở ĐÂY
  Future<void> saveRoiResult({
    required String diagnosisId,
    required String eyeSide,       // 'left' hoặc 'right'
    required String roiName,       // 'Lungs' hoặc 'Liver'
    required String fullIrisPath,  // ảnh mống mắt toàn phần (400x400)
    required String bmpPath,       // ảnh ROI đã trải phẳng
    required String prediction,
    required double confidence,
  }) async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db
          .collection('diagnoses')
          .doc(diagnosisId)
          .collection('roi_results')
          .add({
        'userId': uid,
        'diagnosisId': diagnosisId,
        'eyeSide': eyeSide,
        'roiName': roiName,
        'fullIrisPath': fullIrisPath,
        'bmpPath': bmpPath,
        'prediction': prediction,
        'confidence': confidence,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Lỗi lưu chi tiết vùng $roiName: $e');
    }
  }

  // 3. Stream lịch sử các phiên khám
  Stream<QuerySnapshot> getHistoryStream({int? limit}) {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    Query query = _db
        .collectionGroup('roi_results')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true);

    if (limit != null) query = query.limit(limit);
    return query.snapshots();
  }
}