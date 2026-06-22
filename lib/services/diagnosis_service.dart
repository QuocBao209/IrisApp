// import 'dart:convert';
// import 'package:http/http.dart' as http;
//
// class DiagnosisService {
//   Future<Map<String, dynamic>> analyzeIris(String imagePath) async {
//     const String myPcIp = '192.168.1.41';
//
//     final urlsToTry = [
//       'http://$myPcIp:8000/predict',
//       'http://10.0.2.2:8000/predict',
//       'http://127.0.0.1:8000/predict',
//     ];
//
//     http.Response? response;
//
//     for (final url in urlsToTry) {
//       try {
//         final request = http.MultipartRequest(
//           'POST',
//           Uri.parse(url),
//         );
//
//         request.files.add(
//           await http.MultipartFile.fromPath(
//             'file',
//             imagePath,
//           ),
//         );
//
//         final streamed = await request
//             .send()
//             .timeout(const Duration(seconds: 5));
//
//         response = await http.Response.fromStream(streamed);
//
//         if (response.statusCode == 200) {
//           break;
//         }
//       } catch (_) {
//         continue;
//       }
//     }
//
//     if (response == null || response.statusCode != 200) {
//       return {
//         'prediction': 'unknown',
//         'confidence': 0,
//       };
//     }
//
//     try {
//       final data = json.decode(response.body);
//
//       print('API RESPONSE: $data');
//
//       return {
//         'prediction':
//         data['prediction']?.toString().trim().toLowerCase() ??
//             'unknown',
//
//         'confidence': data['confidence'] ?? 0,
//       };
//     } catch (e) {
//       print('Parse error: $e');
//
//       return {
//         'prediction': 'unknown',
//         'confidence': 0,
//       };
//     }
//   }
// }

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

class DiagnosisService {
  Uint8List? _modelBytes;

  Future<String> segmentIris(String fullEyeImagePath) async {
    try {
      print("[Segmentation] Đang trích xuất mống mắt...");

      final Directory downloadDir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();

      final String baseName = fullEyeImagePath.split(Platform.pathSeparator).last;
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String segmentedName = "iris_${timestamp}_$baseName";
      final String outputPath = '${downloadDir.path}/$segmentedName';

      final String? resultPath = await _runPythonSegmentation(
          fullEyeImagePath,
          outputPath
      );

      if (resultPath != null && await File(resultPath).exists()) {
        print("[Segmentation] Thành công: $resultPath");
        return resultPath;
      }
    } catch (e) {
      print("[Segmentation] Lỗi: $e");
    }

    print("⚠️ [Segmentation] Sử dụng ảnh gốc làm fallback");
    return fullEyeImagePath;
  }

  Future<String?> _runPythonSegmentation(String inputPath, String outputPath) async {
    try {
      const String pythonScriptPath = 'lib/assets/python/iris_segment.py';

      final process = await Process.run(
        'python',
        [pythonScriptPath, inputPath, outputPath],
        runInShell: true,
      );

      if (process.exitCode == 0) {
        final output = process.stdout.trim();
        if (output.isNotEmpty) {
          return output;
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
      for (var element in outputs) { element?.release(); }
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