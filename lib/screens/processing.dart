import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/results.dart';
import '../services/diagnosis_service.dart';
import '../services/history_service.dart';

class ProcessingScreen extends StatefulWidget {
  final String imagePath;
  const ProcessingScreen({super.key, required this.imagePath});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _scannerController;
  final DiagnosisService _diagnosisService = DiagnosisService();
  final HistoryService _historyService = HistoryService();

  @override
  void initState() {
    super.initState();
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _performAnalysis();
  }

  void _performAnalysis() async {
    final res = await _diagnosisService.analyzeIris(widget.imagePath);

    await _historyService.saveResult(
      imagePath: widget.imagePath,
      status: res['status'],
      message: res['message'],
      score: res['score'],
    );

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            imagePath: widget.imagePath,
            result: res,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.file(
                    File(widget.imagePath),
                    width: 280,
                    height: 280,
                    fit: BoxFit.cover,
                  ),
                ),
                AnimatedBuilder(
                  animation: _scannerController,
                  builder: (context, child) {
                    return Positioned(
                      top: _scannerController.value * 260,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4285F4),
                          boxShadow: [
                            BoxShadow(color: Colors.blue.withOpacity(0.9), blurRadius: 12, spreadRadius: 2),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 50),
            const CircularProgressIndicator(color: Color(0xFF4285F4)),
            const SizedBox(height: 20),
            const Text("AI đang phân tích mống mắt...", style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}