import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/history_service.dart';
import 'doctor.dart';
import 'info.dart';
import 'library.dart';
import 'results.dart';
import '../widget/header.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onHistoryTap;

  const HomeScreen({
    super.key,
    required this.onHistoryTap,
  });

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Không thể mở liên kết $urlString');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HeaderWidget(),
            const SizedBox(height: 16),
            _buildRealtimeHealthStatus(),
            const SizedBox(height: 24),
            _buildQuickActions(context),
            const SizedBox(height: 28),
            _buildSectionHeader(context, "Kiến thức về mống mắt"),
            const SizedBox(height: 12),
            _buildArticleList(),
          ],
        ),
      ),
    );
  }

  Widget _buildRealtimeHealthStatus() {
    final historyService = HistoryService();

    return StreamBuilder<QuerySnapshot>(
      stream: historyService.getHistoryStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildNoDataCard();
        }

        final latestData = docs.first.data() as Map<String, dynamic>;
        return _buildHealthStatusCard(context, latestData);
      },
    );
  }

  Widget _buildHealthStatusCard(BuildContext context, Map<String, dynamic> data) {
    final int score = data['score'] ?? 0;
    final String status = data['status'] ?? "Chẩn đoán mống mắt";
    final Timestamp? timestamp = data['timestamp'] as Timestamp?;

    final bool isHealthy = score >= 80;
    final Color themeColor = isHealthy ? Colors.green : Colors.redAccent;
    final List<Color> gradientColors = isHealthy
        ? [const Color(0xFF4285F4), const Color(0xFF5E9EFF)]
        : [const Color(0xFFFF5252), const Color(0xFFFF8A80)];

    String timeAgo = "Vừa xong";
    if (timestamp != null) {
      final diff = DateTime.now().difference(timestamp.toDate());
      if (diff.inHours < 1) {
        timeAgo = "Cập nhật ${diff.inMinutes} phút trước";
      } else if (diff.inHours < 24) {
        timeAgo = "Cập nhật ${diff.inHours} giờ trước";
      } else {
        timeAgo = "Cập nhật ngày ${DateFormat('dd/MM').format(timestamp.toDate())}";
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.25),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 8,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              Text(
                "$score%",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    isHealthy ? "Sức khỏe ổn định" : "Cần lưu ý",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(timeAgo, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ResultScreen(
                          imagePath: data['imagePath'] ?? "",
                          result: data,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        "Xem chi tiết",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Center(
        child: Text(
          "Chưa có dữ liệu chẩn đoán.\nHãy bắt đầu quét ngay!",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return GridView.count(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.55,
      children: [
        _actionCard(
          icon: Icons.history_rounded,
          label: "Lịch sử",
          color: Colors.blue,
          onTap: onHistoryTap,
        ),
        _actionCard(
          icon: Icons.menu_book_rounded,
          label: "Thư viện",
          color: Colors.purple,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryScreen())),
        ),
        _actionCard(
          icon: Icons.person_search_rounded,
          label: "Bác sĩ",
          color: Colors.orange,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DoctorScreen())),
        ),
        _actionCard(
          icon: Icons.info_outline_rounded,
          label: "Thông tin",
          color: Colors.teal,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InfoScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 28,
                  ),
                ),
                const Spacer(),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LibraryScreen()),
            );
          },
          child: const Text("Xem tất cả"),
        ),
      ],
    );
  }

  Widget _buildArticleList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('articles')
          .where('type', isEqualTo: 'knowledge')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();

        List<QueryDocumentSnapshot> docs = snapshot.data!.docs;
        docs.shuffle();
        final randomDocs = docs.take(3).toList();

        if (randomDocs.isEmpty) {
          return const Center(child: Text("Chưa có kiến thức mới", style: TextStyle(color: Colors.grey)));
        }

        return Column(
          children: randomDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _articleCard(data);
          }).toList(),
        );
      },
    );
  }

  Widget _articleCard(Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          if (data['url'] != null) _launchURL(data['url']);
        },
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.remove_red_eye, color: Colors.purple, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['title'] ?? "Tiêu đề bài viết",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      data['category'] ?? "Y tế",
                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}