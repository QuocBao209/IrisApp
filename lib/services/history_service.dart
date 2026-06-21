import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> saveResult({
    required String imagePath,
    required String prediction,
    required int confidence,
  }) async {
    final String? uid = _auth.currentUser?.uid;

    if (uid == null) return;

    try {
      await _db.collection('diagnoses').add({
        'userId': uid,
        'imagePath': imagePath,
        'prediction': prediction,
        'confidence': confidence,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Lỗi lưu lịch sử: $e');
    }
  }

  Stream<QuerySnapshot> getHistoryStream({int? limit}) {
    final user = _auth.currentUser;

    if (user == null) {
      return const Stream.empty();
    }

    Query query = _db
        .collection('diagnoses')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true);

    if (limit != null) {
      query = query.limit(limit);
    }

    return query.snapshots();
  }
}