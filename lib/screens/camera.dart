import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/screens/processing.dart';
import 'package:image_picker/image_picker.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

enum _IrisConnectionPhase { connecting, connected, disconnected }

class _CameraScreenState extends State<CameraScreen> {
  _IrisConnectionPhase _connectionPhase = _IrisConnectionPhase.connecting;
  bool _isAutoCapturing = false;
  bool _isNavigatingToProcessing = false;
  bool _hasPreviewFrame = false;
  String _captureHint = 'Đặt mắt vào thiết bị — hệ thống tự quét và chụp khi nhận diện mống mắt';
  final ValueNotifier<Uint8List?> _previewFrameNotifier = ValueNotifier<Uint8List?>(null);
  StreamSubscription<dynamic>? _previewSubscription;
  StreamSubscription<dynamic>? _autoCaptureSubscription;
  StreamSubscription<dynamic>? _hintSubscription;
  final ImagePicker _picker = ImagePicker();
  DateTime _lastUiFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _minUiFrameIntervalMs = 120;

  static const _iritechChannel = MethodChannel('com.iritech.irisaegis/device');
  static const _previewStream = EventChannel('com.iritech.irisaegis/preview');
  static const _autoCaptureStream = EventChannel('com.iritech.irisaegis/auto_capture');
  static const _hintStream = EventChannel('com.iritech.irisaegis/capture_hint');

  @override
  void initState() {
    super.initState();
    _connectToIriTechDevice();
  }

  @override
  void dispose() {
    _previewSubscription?.cancel();
    _autoCaptureSubscription?.cancel();
    _hintSubscription?.cancel();
    _previewFrameNotifier.dispose();
    if (_connectionPhase == _IrisConnectionPhase.connected) {
      _iritechChannel.invokeMethod('stopPreview');
    }
    super.dispose();
  }

  void _listenIrisPreview() {
    _previewSubscription?.cancel();
    _previewSubscription = _previewStream.receiveBroadcastStream().listen(
      (event) {
        if (event is! Uint8List || !mounted) return;

        final now = DateTime.now();
        if (now.difference(_lastUiFrameAt).inMilliseconds < _minUiFrameIntervalMs) {
          return;
        }
        _lastUiFrameAt = now;

        _previewFrameNotifier.value = event;
        if (!_hasPreviewFrame && mounted) {
          setState(() => _hasPreviewFrame = true);
        }
      },
      onError: (error) {
        debugPrint('IriTech preview stream error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi preview Iris: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  void _listenCaptureHints() {
    _hintSubscription?.cancel();
    _hintSubscription = _hintStream.receiveBroadcastStream().listen(
      (event) {
        if (event is! String || event.isEmpty || !mounted || _isAutoCapturing) return;
        setState(() => _captureHint = event);
      },
      onError: (error) => debugPrint('IriTech hint stream error: $error'),
    );
  }

  void _listenAutoCapture() {
    _autoCaptureSubscription?.cancel();
    _autoCaptureSubscription = _autoCaptureStream.receiveBroadcastStream().listen(
      (event) {
        if (event is! String || event.isEmpty || !mounted || _isNavigatingToProcessing) {
          return;
        }
        _onAutoCaptured(event);
      },
      onError: (error) {
        debugPrint('IriTech auto capture error: $error');
      },
    );
  }

  Future<void> _onAutoCaptured(String imagePath) async {
    if (_isNavigatingToProcessing || !mounted) return;

    setState(() {
      _isNavigatingToProcessing = true;
      _isAutoCapturing = true;
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(imagePath: imagePath),
      ),
    );

    if (!mounted) return;

    setState(() {
      _isNavigatingToProcessing = false;
      _isAutoCapturing = false;
      _hasPreviewFrame = false;
      _captureHint = 'Đặt mắt vào thiết bị — hệ thống tự quét và chụp khi nhận diện mống mắt';
    });
    _lastUiFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
    _previewFrameNotifier.value = null;

    if (_connectionPhase == _IrisConnectionPhase.connected) {
      _listenAutoCapture();
      _listenCaptureHints();
      _listenIrisPreview();
    }
  }

  void _resumeIrisStreams() {
    _listenAutoCapture();
    _listenCaptureHints();
    _listenIrisPreview();
  }

  Future<void> _connectToIriTechDevice() async {
    if (!mounted) return;
    setState(() => _connectionPhase = _IrisConnectionPhase.connecting);

    try {
      final String result = await _iritechChannel.invokeMethod('connectDevice');
      debugPrint("IriTech Log: $result");
      if (!mounted) return;
      setState(() => _connectionPhase = _IrisConnectionPhase.connected);
      _resumeIrisStreams();
    } catch (e) {
      debugPrint("IriTech Log: Chưa cắm máy quét ($e). Yêu cầu người dùng chọn ảnh thủ công.");
      if (!mounted) return;
      setState(() => _connectionPhase = _IrisConnectionPhase.disconnected);
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
      );

      if (pickedFile != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProcessingScreen(imagePath: pickedFile.path),
          ),
        );
      }
    } catch (e) {
      debugPrint("Lỗi khi chọn ảnh: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Không thể mở thư viện ảnh: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_connectionPhase == _IrisConnectionPhase.disconnected) {
      return _buildGalleryFallbackView();
    }

    return _buildIrisCaptureView(
      isConnecting: _connectionPhase == _IrisConnectionPhase.connecting,
    );
  }

  Widget _buildIrisCaptureView({required bool isConnecting}) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<Uint8List?>(
            valueListenable: _previewFrameNotifier,
            builder: (context, frame, _) {
              if (frame == null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        Platform.isAndroid
                            ? 'Đang chờ hình ảnh từ IrisAegis...\nĐặt mắt vào thiết bị quét'
                            : 'Preview Iris chỉ hỗ trợ Android',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, height: 1.5),
                      ),
                    ],
                  ),
                );
              }
              return Image.memory(
                frame,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                width: double.infinity,
                height: double.infinity,
              );
            },
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [
                  Colors.black.withOpacity(0.55),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildStatusChip(
                  connected: true,
                  live: _hasPreviewFrame,
                  scanning: !_isAutoCapturing && _hasPreviewFrame,
                ),
              ),
            ),
          ),
          SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 35),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 130,
            child: Text(
              _isAutoCapturing
                  ? 'Đã nhận diện mống mắt — đang chuyển sang phân tích...'
                  : _hasPreviewFrame
                      ? _captureHint
                      : 'Góc nhìn trực tiếp từ IrisAegis — đang khởi động camera thiết bị...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: 14,
                height: 1.4,
                shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: _buildAutoScanIndicator(isConnecting: isConnecting),
          ),
          if (isConnecting)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Đang kết nối IrisAegis qua USB...',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAutoScanIndicator({required bool isConnecting}) {
    final active = _hasPreviewFrame && !isConnecting && !_isAutoCapturing;

    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? Colors.greenAccent : Colors.white38,
            width: 4,
          ),
        ),
        child: _isAutoCapturing
            ? const Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              )
            : Icon(
                active ? Icons.visibility_rounded : Icons.remove_red_eye_outlined,
                color: Colors.white,
                size: 30,
              ),
      ),
    );
  }

  Widget _buildGalleryFallbackView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _buildStatusChip(connected: false)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.usb_off_rounded, size: 52, color: Colors.orange),
            ),
            const SizedBox(height: 28),
            const Text(
              'Chưa phát hiện thiết bị Iris',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Không dùng camera điện thoại. Vui lòng cắm IrisAegis-26T qua USB hoặc tự thêm ảnh mống mắt từ thư viện để phân tích.',
              style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _pickImageFromGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Chọn ảnh từ thư viện'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _connectToIriTechDevice(),
              child: const Text('Thử kết nối lại thiết bị Iris'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required bool connected,
    bool live = false,
    bool scanning = false,
  }) {
    String label;
    if (!connected) {
      label = 'IrisAegis: OFF';
    } else if (scanning) {
      label = 'IrisAegis: QUÉT';
    } else if (live) {
      label = 'IrisAegis: LIVE';
    } else {
      label = 'IrisAegis: ON';
    }

    return Chip(
      avatar: Icon(
        connected ? Icons.usb_rounded : Icons.usb_off_rounded,
        color: Colors.white,
        size: 18,
      ),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      backgroundColor: connected
          ? (scanning ? Colors.lightGreen : (live ? Colors.green : Colors.green.withOpacity(0.8)))
          : Colors.red.withOpacity(0.7),
    );
  }
}
