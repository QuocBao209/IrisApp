import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/screens/results.dart';
import '../models/eye_side.dart';
import '../services/diagnosis_service.dart';
import '../services/history_service.dart';

class ProcessingScreen extends StatefulWidget {
  final String imagePath;
  final EyeSide eyeSide;

  const ProcessingScreen({
    super.key,
    required this.imagePath,
    required this.eyeSide,
  });

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
    Map<String, dynamic> res = const {'prediction': 'unknown', 'confidence': 0};
    SegmentResult? segmentResult;

    try {
      await Future.delayed(const Duration(milliseconds: 200));
      final DateTime startTime = DateTime.now();

      segmentResult = await _diagnosisService.segmentIris(
        widget.imagePath,
        eyeSide: widget.eyeSide.value,
      );
      debugPrint('[Processing] seg iris=${segmentResult.irisPath}');
      debugPrint('[Processing] seg roi=${segmentResult.roiPath}');

      res = await _diagnosisService.analyzeIris(segmentResult.roiPath);
      debugPrint('[Processing] analyze => $res');

      // Không để lỗi Firebase/Downloads nuốt mất kết quả AI
      try {
        final rawConfidence = (res['confidence'] ?? 0).toDouble();
        final double finalConfidence = (rawConfidence <= 1.0
                ? (rawConfidence * 100)
                : rawConfidence)
            .clamp(0, 100)
            .toDouble();

        final diagnosisId = await _historyService.createDiagnosisSession();
        if (diagnosisId != null) {
          await _historyService.saveRoiResult(
            diagnosisId: diagnosisId,
            eyeSide: widget.eyeSide.value,
            roiName: 'Lungs',
            fullIrisPath: segmentResult.irisPath,
            bmpPath: segmentResult.roiPath,
            prediction: res['prediction'] ?? 'unknown',
            confidence: finalConfidence,
          );
        }
      } catch (e) {
        debugPrint('[Processing] Lưu Firebase lỗi (bỏ qua): $e');
      }

      try {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        await _saveToDownloads(
          segmentResult.roiPath,
          'IrisApp_roi_${widget.eyeSide.value}_$stamp.jpg',
        );
        await _saveToDownloads(
          segmentResult.irisPath,
          'IrisApp_iris_${widget.eyeSide.value}_$stamp.jpg',
        );
      } catch (e) {
        debugPrint('[Processing] Lưu Downloads lỗi (bỏ qua): $e');
      }

      final int elapsedExecutionTime =
          DateTime.now().difference(startTime).inMilliseconds;
      const int minimumUiDisplayTime = 2500;
      if (elapsedExecutionTime < minimumUiDisplayTime) {
        await Future.delayed(
          Duration(milliseconds: minimumUiDisplayTime - elapsedExecutionTime),
        );
      }
    } catch (e, st) {
      debugPrint('UI Processing Error: $e\n$st');
      res = {
        'prediction': 'unknown',
        'confidence': 0,
        'error': e.toString(),
      };
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          imagePath: widget.imagePath,
          roiPath: segmentResult?.roiPath,
          irisPath: segmentResult?.irisPath,
          result: res,
        ),
      ),
    );
  }

  static const _deviceChannel = MethodChannel('com.iritech.irisaegis/device');

  Future<void> _saveToDownloads(String path, String fileName) async {
    try {
      if (!await File(path).exists()) return;
      final msg = await _deviceChannel.invokeMethod<String>('saveToDownloads', {
        'path': path,
        'fileName': fileName,
      });
      debugPrint('[Downloads] $msg');
    } catch (e) {
      debugPrint('[Downloads] Lỗi lưu $fileName: $e');
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
            const Text("Đang trích xuất mống mắt và phân tích...", style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}