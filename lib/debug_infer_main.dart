import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'services/diagnosis_service.dart';

/// Chạy: flutter run -d windows -t lib/debug_infer_main.dart
/// (hoặc -d <android_id> khi cắm máy)
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DebugInferApp());
}

class DebugInferApp extends StatelessWidget {
  const DebugInferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: true,
      home: DebugInferPage(),
    );
  }
}

class DebugInferPage extends StatefulWidget {
  const DebugInferPage({super.key});

  @override
  State<DebugInferPage> createState() => _DebugInferPageState();
}

class _DebugInferPageState extends State<DebugInferPage> {
  final _logs = StringBuffer();
  final _service = DiagnosisService();
  bool _running = false;
  String? _roiPath;
  String? _irisPath;
  Map<String, dynamic>? _result;

  void _log(String msg) {
    debugPrint(msg);
    setState(() {
      _logs.writeln(msg);
    });
  }

  Future<String> _makeSyntheticEyeImage() async {
    // Ảnh giả lập mắt: nền xám + đồng tử đen + vòng iris
    final image = img.Image(width: 640, height: 480);
    img.fill(image, color: img.ColorRgb8(180, 180, 180));
    final cx = 320;
    final cy = 240;
    img.fillCircle(image, x: cx, y: cy, radius: 120, color: img.ColorRgb8(70, 50, 40));
    img.fillCircle(image, x: cx, y: cy, radius: 35, color: img.ColorRgb8(10, 10, 10));
    // nhiễu nhẹ
    final rnd = math.Random(42);
    for (var i = 0; i < 2000; i++) {
      final x = rnd.nextInt(640);
      final y = rnd.nextInt(480);
      final v = 100 + rnd.nextInt(80);
      image.setPixelRgba(x, y, v, v, v, 255);
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/debug_eye_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(img.encodeJpg(image, quality: 95));
    return path;
  }

  Future<void> _runPipeline() async {
    if (_running) return;
    setState(() {
      _running = true;
      _logs.clear();
      _result = null;
      _roiPath = null;
      _irisPath = null;
    });

    try {
      _log('=== DEBUG INFER START ===');
      final eyePath = await _makeSyntheticEyeImage();
      _log('Synthetic eye: $eyePath (${await File(eyePath).length()} bytes)');

      _log('1) segmentIris(left)...');
      final seg = await _service.segmentIris(eyePath, eyeSide: 'left');
      _log('irisPath=${seg.irisPath}');
      _log('roiPath=${seg.roiPath}');
      _log('iris exists=${await File(seg.irisPath).exists()} size=${await File(seg.irisPath).length()}');
      _log('roi exists=${await File(seg.roiPath).exists()} size=${await File(seg.roiPath).length()}');
      final roiBytes = await File(seg.roiPath).readAsBytes();
      final roiImg = img.decodeImage(roiBytes);
      if (roiImg != null) {
        var sum = 0;
        var dark = 0;
        var bright = 0;
        for (final p in roiImg) {
          final v = ((p.r + p.g + p.b) / 3).round();
          sum += v;
          if (v < 40) dark++;
          if (v > 100) bright++;
        }
        final n = math.max(1, roiImg.width * roiImg.height);
        _log(
          'roi stats: ${roiImg.width}x${roiImg.height} mean=${(sum / n).toStringAsFixed(1)} '
          'dark%=${(100 * dark / n).toStringAsFixed(0)} bright%=${(100 * bright / n).toStringAsFixed(0)}',
        );
      } else {
        _log('roi stats: DECODE FAILED');
      }
      setState(() {
        _irisPath = seg.irisPath;
        _roiPath = seg.roiPath;
      });

      _log('2) analyzeIris(roi)...');
      final res = await _service.analyzeIris(seg.roiPath);
      _log('RESULT keys=${res.keys.toList()}');
      _log('prediction=${res['prediction']}');
      _log('confidence=${res['confidence']}');
      _log('raw_idx=${res['raw_idx']}');
      _log('probs=${res['probs']}');
      _log('logits=${res['logits']}');
      if (res['error'] != null) {
        _log('ERROR=${res['error']}');
      }
      setState(() => _result = res);

      // Thử thêm: infer trực tiếp ảnh gốc
      _log('3) analyzeIris(full eye) để so sánh...');
      final res2 = await _service.analyzeIris(eyePath);
      _log('FULL prediction=${res2['prediction']} conf=${res2['confidence']} err=${res2['error']} probs=${res2['probs']}');

      _log('=== DEBUG INFER DONE ===');
    } catch (e, st) {
      _log('FATAL: $e');
      _log('$st');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runPipeline());
  }

  @override
  Widget build(BuildContext context) {
    final pred = _result?['prediction']?.toString() ?? '...';
    final conf = _result?['confidence'];
    final err = _result?['error']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Infer ONNX'),
        actions: [
          IconButton(
            onPressed: _running ? null : _runPipeline,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'prediction: $pred | confidence: $conf',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: pred == 'unknown' ? Colors.red : Colors.green,
            ),
          ),
          if (err != null && err.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('error: $err', style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          if (_roiPath != null && File(_roiPath!).existsSync()) ...[
            const Text('ROI:'),
            Image.file(File(_roiPath!), height: 100, fit: BoxFit.contain),
          ],
          if (_irisPath != null && File(_irisPath!).existsSync()) ...[
            const SizedBox(height: 8),
            const Text('Iris:'),
            Image.file(File(_irisPath!), height: 160, fit: BoxFit.contain),
          ],
          const SizedBox(height: 12),
          if (_running) const LinearProgressIndicator(),
          const Text('Logs:', style: TextStyle(fontWeight: FontWeight.bold)),
          SelectableText(
            _logs.toString(),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
