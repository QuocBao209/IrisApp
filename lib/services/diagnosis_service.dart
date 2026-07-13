import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'iris_segmenter_dart.dart';

/// Kết quả tách mống mắt: ảnh toàn phần + dải ROI trải phẳng (.bmp)
class SegmentResult {
  final String irisPath;
  final String roiPath;
  SegmentResult({required this.irisPath, required this.roiPath});
}

class DiagnosisService {
  Uint8List? _modelBytes;
  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  final IrisSegmenterDart _dartSegmenter = IrisSegmenterDart();

  Future<void> _ensureSession() async {
    await _initModelBytes();
    if (_modelBytes == null) {
      throw Exception('Không load được model ONNX từ assets');
    }
    if (_session != null) return;

    OrtEnv.instance.init();
    _sessionOptions = OrtSessionOptions()
      ..setIntraOpNumThreads(2)
      ..setInterOpNumThreads(1);
    _session = OrtSession.fromBuffer(_modelBytes!, _sessionOptions!);
    debugPrint(
      '[ONNX] session ready | inputs=${_session!.inputNames} | outputs=${_session!.outputNames}',
    );
  }

  /// eyeSide: 'left' hoặc 'right' — ROI phổi trái/phải
  Future<SegmentResult> segmentIris(
    String fullEyeImagePath, {
    required String eyeSide,
  }) async {
    final Directory outputDir = await getApplicationDocumentsDirectory();
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String irisOutputPath = '${outputDir.path}/iris_${eyeSide}_$timestamp.jpg';
    final String roiOutputPath = '${outputDir.path}/roi_${eyeSide}_$timestamp.jpg';

    debugPrint('[Segmentation] ROI phổi ($eyeSide)...');

    try {
      final bytes = await File(fullEyeImagePath).readAsBytes();
      final result = _dartSegmenter.process(bytes, eyeSide: eyeSide);
      // Ghi thẳng bytes đã encode quality 100 — không decode/encode lại (tránh mất nét).
      await File(irisOutputPath).writeAsBytes(result.irisJpeg, flush: true);
      await File(roiOutputPath).writeAsBytes(result.roiBmp, flush: true);
      debugPrint('[Segmentation] Dart OK');
      return SegmentResult(irisPath: irisOutputPath, roiPath: roiOutputPath);
    } catch (e) {
      debugPrint('[Segmentation] Dart lỗi: $e — thử Python');
    }

    final py = await _runPythonSegmentation(
      inputPath: fullEyeImagePath,
      irisOutputPath: irisOutputPath,
      roiOutputPath: roiOutputPath,
      eyeSide: eyeSide,
    );
    if (py != null) return py;

    debugPrint('⚠️ [Segmentation] Fallback ảnh gốc');
    return SegmentResult(irisPath: fullEyeImagePath, roiPath: fullEyeImagePath);
  }

  Future<SegmentResult?> _runPythonSegmentation({
    required String inputPath,
    required String irisOutputPath,
    required String roiOutputPath,
    required String eyeSide,
  }) async {
    try {
      const pythonScriptPath = 'lib/assets/python/iris_segment.py';
      final process = await Process.run(
        'python',
        [pythonScriptPath, inputPath, irisOutputPath, roiOutputPath, eyeSide],
        runInShell: true,
      );
      if (process.exitCode != 0) {
        debugPrint('Python Segmentation Error: ${process.stderr}');
        return null;
      }
      final stdout = process.stdout.toString().trim();
      if (stdout.isEmpty) return null;
      final parsed = jsonDecode(stdout) as Map<String, dynamic>;
      return SegmentResult(
        irisPath: parsed['iris_path'] as String,
        roiPath: parsed['roi_path'] as String,
      );
    } catch (e) {
      debugPrint('Không chạy được Python: $e');
      return null;
    }
  }

  Future<void> _initModelBytes() async {
    if (_modelBytes != null) return;
    final modelData =
        await rootBundle.load('lib/assets/best_model_quantized.onnx');
    _modelBytes = modelData.buffer.asUint8List();
    debugPrint('[ONNX] loaded ${_modelBytes!.length} bytes');
  }

  List<double> _flattenToDoubles(Object? v) {
    if (v == null) return const <double>[];
    if (v is double) return <double>[v];
    if (v is num) return <double>[v.toDouble()];
    if (v is List) {
      final out = <double>[];
      for (final e in v) {
        out.addAll(_flattenToDoubles(e));
      }
      return out;
    }
    throw Exception('Unsupported output type: ${v.runtimeType}');
  }

  Map<String, dynamic> _inferSync(String imagePath) {
    final session = _session!;
    final imageFile = File(imagePath);
    if (!imageFile.existsSync()) {
      throw Exception('File ảnh không tồn tại: $imagePath');
    }

    final bytes = imageFile.readAsBytesSync();
    final originalImage = img.decodeImage(bytes);
    if (originalImage == null) {
      throw Exception('Không decode được ảnh (${bytes.length} bytes)');
    }

    final resized = img.copyResize(originalImage, width: 224, height: 224);
    final inputBuffer = Float32List(1 * 3 * 224 * 224);
    var indexR = 0;
    var indexG = 224 * 224;
    var indexB = 2 * 224 * 224;

    for (var y = 0; y < 224; y++) {
      for (var x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r / 255.0;
        final g = pixel.g / 255.0;
        final b = pixel.b / 255.0;
        inputBuffer[indexR++] = (r - 0.485) / 0.229;
        inputBuffer[indexG++] = (g - 0.456) / 0.224;
        inputBuffer[indexB++] = (b - 0.406) / 0.225;
      }
    }

    // Truyền Float32List trực tiếp (đúng dtype float32 cho model)
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputBuffer,
      [1, 3, 224, 224],
    );
    final inputName =
        session.inputNames.isNotEmpty ? session.inputNames.first : 'input';
    final runOptions = OrtRunOptions();
    final outputs = session.run(runOptions, {inputName: inputTensor});

    try {
      final logits = _flattenToDoubles(outputs.first?.value);
      debugPrint('[ONNX] raw logits=$logits');
      if (logits.isEmpty) {
        throw Exception('Model output rỗng');
      }

      final maxLogit = logits.reduce(math.max);
      final exps = logits.map((e) => math.exp(e - maxLogit)).toList();
      final sumExps = exps.reduce((a, b) => a + b);
      final probabilities = exps.map((e) => e / sumExps).toList();
      debugPrint('[ONNX] softmax=$probabilities');

      var predictedIdx = 0;
      var maxProb = probabilities[0];
      for (var i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          predictedIdx = i;
        }
      }

      // output shape [batch, 3]: 0=negative, 1=positive, 2=fallback theo max(0,1)
      late String prediction;
      if (predictedIdx == 0) {
        prediction = 'negative';
      } else if (predictedIdx == 1) {
        prediction = 'positive';
      } else if (probabilities.length >= 2) {
        if (probabilities[0] >= probabilities[1]) {
          prediction = 'negative';
          maxProb = probabilities[0];
        } else {
          prediction = 'positive';
          maxProb = probabilities[1];
        }
      } else {
        prediction = 'unknown';
      }

      final confidence = (maxProb * 100).round();
      debugPrint(
        '[ONNX] => prediction=$prediction confidence=$confidence% idx=$predictedIdx',
      );
      return {
        'prediction': prediction,
        'confidence': confidence,
        'raw_idx': predictedIdx,
        'probs': probabilities,
        'logits': logits,
      };
    } finally {
      inputTensor.release();
      for (final o in outputs) {
        o?.release();
      }
      runOptions.release();
    }
  }

  Future<Map<String, dynamic>> analyzeIris(String imagePath) async {
    try {
      await _ensureSession();
      // Chạy trên isolate chính — compute()+FFI OrtEnv thường fail trên Android
      return _inferSync(imagePath);
    } catch (e, st) {
      debugPrint('[ONNX] Inference Error: $e\n$st');
      return {
        'prediction': 'unknown',
        'confidence': 0,
        'error': e.toString(),
      };
    }
  }
}
