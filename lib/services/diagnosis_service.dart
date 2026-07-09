import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

class _IsolateParams {
  final Uint8List modelBytes;
  final String imagePath;
  _IsolateParams(this.modelBytes, this.imagePath);
}

/// Kết quả tách mống mắt: ảnh toàn phần + dải ROI trải phẳng (.bmp)
class SegmentResult {
  final String irisPath;
  final String roiPath;
  SegmentResult({required this.irisPath, required this.roiPath});
}

class DiagnosisService {
  Uint8List? _modelBytes;

  /// eyeSide: 'left' hoặc 'right' — bắt buộc, quyết định vùng ROI cắt (Phổi trái/phải)
  Future<SegmentResult> segmentIris(String fullEyeImagePath, {required String eyeSide}) async {
    final Directory outputDir = await getApplicationDocumentsDirectory();
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    final String irisOutputPath = '${outputDir.path}/iris_${eyeSide}_$timestamp.jpg';
    final String roiOutputPath = '${outputDir.path}/roi_${eyeSide}_$timestamp.bmp';

    print("[Segmentation] Đang trích xuất mống mắt ($eyeSide)...");

    final SegmentResult? result = await _runPythonSegmentation(
      inputPath: fullEyeImagePath,
      irisOutputPath: irisOutputPath,
      roiOutputPath: roiOutputPath,
      eyeSide: eyeSide,
    );

    if (result != null &&
        await File(result.irisPath).exists() &&
        await File(result.roiPath).exists()) {
      print("[Segmentation] Thành công: ${result.irisPath} | ${result.roiPath}");
      return result;
    }

    // Fallback: nếu segmentation lỗi, dùng lại ảnh gốc cho cả 2 (tránh crash app)
    print("⚠️ [Segmentation] Lỗi xử lý, dùng ảnh gốc làm fallback");
    return SegmentResult(irisPath: fullEyeImagePath, roiPath: fullEyeImagePath);
  }

  Future<SegmentResult?> _runPythonSegmentation({
    required String inputPath,
    required String irisOutputPath,
    required String roiOutputPath,
    required String eyeSide,
  }) async {
    try {
      const String pythonScriptPath = 'lib/assets/python/iris_segment.py';

      final process = await Process.run(
        'python',
        [pythonScriptPath, inputPath, irisOutputPath, roiOutputPath, eyeSide],
        runInShell: true,
      );

      if (process.exitCode == 0) {
        final String stdout = process.stdout.toString().trim();
        if (stdout.isEmpty) {
          print("Python Segmentation: stdout rỗng");
          return null;
        }

        try {
          final Map<String, dynamic> parsed = jsonDecode(stdout);
          return SegmentResult(
            irisPath: parsed['iris_path'] as String,
            roiPath: parsed['roi_path'] as String,
          );
        } catch (e) {
          print("Python Segmentation: parse JSON lỗi - $e | stdout: $stdout");
          return null;
        }
      } else {
        print("Python Segmentation Error: ${process.stderr}");
      }
    } catch (e) {
      print("Không thể chạy Python segmentation script: $e");
    }
    return null;
  }

  Future<void> _initModelBytes() async {
    if (_modelBytes != null) return;
    try {
      final modelData = await rootBundle.load('lib/assets/best_model_quantized.onnx');
      _modelBytes = modelData.buffer.asUint8List();
      print("Đã nạp dữ liệu bytes của mô hình vào bộ nhớ đệm!");
    } catch (e) {
      print("Lỗi đọc bytes mô hình từ assets: $e");
    }
  }

  static Map<String, dynamic> _runInferenceOffline(_IsolateParams params) {
    try {
      final sessionOptions = OrtSessionOptions();
      final session = OrtSession.fromBuffer(params.modelBytes, sessionOptions);

      final imageFile = File(params.imagePath);
      final bytes = imageFile.readAsBytesSync();
      final originalImage = img.decodeImage(bytes);

      if (originalImage == null) throw Exception("Ảnh lỗi.");

      final resizedImage = img.copyResize(originalImage, width: 224, height: 224);
      final inputBuffer = Float32List(1 * 3 * 224 * 224);

      int indexR = 0;
      int indexG = 224 * 224;
      int indexB = 2 * 224 * 224;

      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final pixel = resizedImage.getPixel(x, y);
          double r = pixel.r / 255.0;
          double g = pixel.g / 255.0;
          double b = pixel.b / 255.0;

          inputBuffer[indexR++] = (r - 0.485) / 0.229;
          inputBuffer[indexG++] = (g - 0.456) / 0.224;
          inputBuffer[indexB++] = (b - 0.406) / 0.225;
        }
      }

      final inputShape = [1, 3, 224, 224];
      final inputTensor = OrtValueTensor.createTensorWithDataList(inputBuffer, inputShape);
      final inputs = {'input': inputTensor};

      final runOptions = OrtRunOptions();
      final outputs = session.run(runOptions, inputs);

      final outputTensor = outputs[0]?.value as List<List<double>>;
      final List<double> logits = outputTensor[0];

      inputTensor.release();
      for (var element in outputs) {
        element?.release();
      }
      session.release();

      double maxLogit = logits.reduce(math.max);
      List<double> exps = logits.map((e) => math.exp(e - maxLogit)).toList();
      double sumExps = exps.reduce((a, b) => a + b);
      List<double> probabilities = exps.map((e) => e / sumExps).toList();

      int predictedIdx = 0;
      double maxProb = probabilities[0];
      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          predictedIdx = i;
        }
      }

      String prediction = 'unknown';
      if (predictedIdx == 0) prediction = 'negative';
      else if (predictedIdx == 1) prediction = 'positive';

      int confidence = (maxProb * 100).toInt();
      return {'prediction': prediction, 'confidence': confidence};
    } catch (e) {
      print('Background Inference Error: $e');
      return {'prediction': 'unknown', 'confidence': 0};
    }
  }

  Future<Map<String, dynamic>> analyzeIris(String imagePath) async {
    await _initModelBytes();
    if (_modelBytes == null) {
      return {'prediction': 'unknown', 'confidence': 0};
    }

    return await compute(
      _runInferenceOffline,
      _IsolateParams(_modelBytes!, imagePath),
    );
  }
}