import 'dart:async';
import 'dart:io';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/screens/processing.dart';
import 'package:image_picker/image_picker.dart';

import '../models/eye_side.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

enum _IrisConnectionPhase { connecting, connected, disconnected }

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  _IrisConnectionPhase _connectionPhase = _IrisConnectionPhase.connecting;
  bool _isAutoCapturing = false;
  bool _isNavigatingToProcessing = false;
  bool _hasPreviewFrame = false;
  final ValueNotifier<Uint8List?> _previewFrameNotifier = ValueNotifier<Uint8List?>(null);
  StreamSubscription<dynamic>? _previewSubscription;
  StreamSubscription<dynamic>? _autoCaptureSubscription;
  StreamSubscription<dynamic>? _hintSubscription;
  final ImagePicker _picker = ImagePicker();
  DateTime _lastUiFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _minUiFrameIntervalMs = 120;

  EyeSide _selectedEyeSide = EyeSide.left;

  String? _connectionError;

  late AnimationController _fixationController;

  static const _iritechChannel = MethodChannel('com.iritech.irisaegis/device');
  static const _previewStream = EventChannel('com.iritech.irisaegis/preview');
  static const _autoCaptureStream = EventChannel('com.iritech.irisaegis/auto_capture');
  static const _hintStream = EventChannel('com.iritech.irisaegis/capture_hint');

  @override
  void initState() {
    super.initState();

    _fixationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _connectToIriTechDevice();
  }

  @override
  void dispose() {
    _fixationController.dispose();
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
        builder: (_) => ProcessingScreen(
          imagePath: imagePath,
          eyeSide: _selectedEyeSide,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      _isNavigatingToProcessing = false;
      _isAutoCapturing = false;
      _hasPreviewFrame = false;
    });
    _lastUiFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
    _previewFrameNotifier.value = null;

    if (_connectionPhase == _IrisConnectionPhase.connected) {
      _listenAutoCapture();
      _listenIrisPreview();
    }
  }

  void _resumeIrisStreams() {
    _listenAutoCapture();
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
      setState(() {
        _connectionPhase = _IrisConnectionPhase.disconnected;
        _connectionError = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kết nối thiết bị thất bại: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ───────────────────────────────────────────────
  //  Scan chỉ mắt trái hoặc mắt phải từ thiết bị
  // ───────────────────────────────────────────────

  /// Gọi native để scan CHỈ mắt trái qua IriTech SDK
  Future<void> _scanLeftEyeOnly() async {
    try {
      debugPrint('[IriTech] Bắt đầu quét MẮT TRÁI...');
      final String? result = await _iritechChannel.invokeMethod<String>(
        'captureLeftEye',
      );
      debugPrint('[IriTech] captureLeftEye result: $result');

      if (result != null && result.isNotEmpty && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProcessingScreen(
              imagePath: result,
              eyeSide: EyeSide.left,
            ),
          ),
        );
      }
    } on PlatformException catch (e) {
      debugPrint('[IriTech] captureLeftEye error: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi quét mắt trái: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Gọi native để scan CHỈ mắt phải qua IriTech SDK
  Future<void> _scanRightEyeOnly() async {
    try {
      debugPrint('[IriTech] Bắt đầu quét MẮT PHẢI...');
      final String? result = await _iritechChannel.invokeMethod<String>(
        'captureRightEye',
      );
      debugPrint('[IriTech] captureRightEye result: $result');

      if (result != null && result.isNotEmpty && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProcessingScreen(
              imagePath: result,
              eyeSide: EyeSide.right,
            ),
          ),
        );
      }
    } on PlatformException catch (e) {
      debugPrint('[IriTech] captureRightEye error: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi quét mắt phải: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Scan theo eye side đã chọn
  Future<void> _scanSelectedEye() async {
    if (_selectedEyeSide == EyeSide.left) {
      await _scanLeftEyeOnly();
    } else {
      await _scanRightEyeOnly();
    }
  }

  // ───────────────────────────────────────────────
  //  Chọn ảnh từ thư viện
  // ───────────────────────────────────────────────

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
            builder: (_) => ProcessingScreen(
              imagePath: pickedFile.path,
              eyeSide: _selectedEyeSide,
            ),
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

  // ───────────────────────────────────────────────
  //  Widget chọn Mắt trái / Mắt phải
  // ───────────────────────────────────────────────

  Widget _buildEyeSideSelector({bool darkMode = false}) {
    final Color activeBg = const Color(0xFF4285F4);
    final Color inactiveBg = darkMode
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE8EAED);
    final Color activeText = Colors.white;
    final Color inactiveText = darkMode ? Colors.white70 : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: darkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildEyeTab(
            label: 'Mắt trái',
            icon: Icons.visibility,
            isActive: _selectedEyeSide == EyeSide.left,
            activeBg: activeBg,
            inactiveBg: inactiveBg,
            activeText: activeText,
            inactiveText: inactiveText,
            onTap: () => setState(() => _selectedEyeSide = EyeSide.left),
          ),
          const SizedBox(width: 4),
          _buildEyeTab(
            label: 'Mắt phải',
            icon: Icons.visibility,
            isActive: _selectedEyeSide == EyeSide.right,
            activeBg: activeBg,
            inactiveBg: inactiveBg,
            activeText: activeText,
            inactiveText: inactiveText,
            onTap: () => setState(() => _selectedEyeSide = EyeSide.right),
          ),
        ],
      ),
    );
  }

  Widget _buildEyeTab({
    required String label,
    required IconData icon,
    required bool isActive,
    required Color activeBg,
    required Color inactiveBg,
    required Color activeText,
    required Color inactiveText,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(11),
          boxShadow: isActive
              ? [BoxShadow(color: activeBg.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isActive ? activeText : inactiveText),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? activeText : inactiveText,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  //  Build UI
  // ───────────────────────────────────────────────

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
                            ? 'Đang chờ hình ảnh từ IrisAegis...'
                            : 'Preview Iris chỉ hỗ trợ Android',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, height: 1.5),
                      ),
                      if (Platform.isAndroid) ...[
                        const SizedBox(height: 18),
                        _buildEyeSideSelector(darkMode: true),
                      ],
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
                  Colors.black.withValues(alpha: 0.55),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // ── Status chip (top-right) ──
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
          // ── Close button (top-left) — dùng chevron để tránh nhầm với dấu X giữa màn ──
          SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          // ── Eye side selector (bottom) ──
          if (_hasPreviewFrame && !_isAutoCapturing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 150,
              child: Center(
                child: _buildEyeSideSelector(
                  darkMode: true,
                ),
              ),
            ),
          // ── Khối vàng focus góc phải dưới ──
          if (_hasPreviewFrame && !_isAutoCapturing)
            Positioned(
              right: 20,
              bottom: 48,
              child: _buildFocusTarget(),
            ),
          // ── Auto scan indicator ──
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

  /// Khối sáng góc phải — điểm nhìn để căng mắt khi quét
  Widget _buildFocusTarget() {
    return AnimatedBuilder(
      animation: _fixationController,
      builder: (context, _) {
        final pulse = 0.75 + (_fixationController.value * 0.25);
        return Transform.scale(
          scale: pulse,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD54F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD54F).withValues(alpha: 0.65),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
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
                color: Colors.orange.withValues(alpha: 0.12),
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
            const SizedBox(height: 28),
            // ── Hiển thị lỗi kết nối (debug trên APK) ──
            if (_connectionError != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Lỗi kết nối:',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _connectionError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            // ── Eye side selector ──
            _buildEyeSideSelector(darkMode: false),
            const SizedBox(height: 8),
            Text(
              'Đang chọn: ${_selectedEyeSide.label}',
              style: const TextStyle(fontSize: 13, color: Colors.black45),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _pickImageFromGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text('Chọn ảnh ${_selectedEyeSide.label} từ thư viện'),
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
          ? (scanning ? Colors.lightGreen : (live ? Colors.green : Colors.green.withValues(alpha: 0.8)))
          : Colors.red.withValues(alpha: 0.7),
    );
  }
}