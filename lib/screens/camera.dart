import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/screens/processing.dart';
import 'package:image_picker/image_picker.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _selectedCameraIndex = 0;
  bool _isCapturing = false;
  final ImagePicker _picker = ImagePicker();

  static const _iritechChannel = MethodChannel('com.iritech.irisaegis/device');
  bool _isIriTechConnected = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _connectToIriTechDevice();
  }

  Future<void> _connectToIriTechDevice() async {
    try {
      final String result = await _iritechChannel.invokeMethod('connectedDevice');
      debugPrint("IriTech Log: $result");
      setState(() {
        _isIriTechConnected = true;
      });
    } catch (e) {
      debugPrint("IriTech Log: Chưa cắm máy quét hoặc lỗi kết nối ($e). Sử dụng camera thường.");
      setState(() {
        _isIriTechConnected = false;
      });
    }
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _setupController();
    }
  }

  Future<void> _setupController() async {
    await _controller?.dispose();
    _controller = CameraController(_cameras![_selectedCameraIndex], ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    if (mounted) setState(() {});
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
    }
  }

  Future<void> _captureImage() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      if (_isIriTechConnected) {
        // HƯỚNG A: Có cắm thiết bị -> Ra lệnh chạy API phần cứng thật để kiểm tra phản hồi
        final String? apiResponse = await _iritechChannel.invokeMethod('startCapture');

        if (mounted && apiResponse != null) {
          // Hiện SnackBar màu xanh thông báo kết quả API thành công để nghiệm thu trực tiếp
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Kết quả API: $apiResponse"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        // HƯỚNG B: Không có thiết bị -> Dự phòng bằng Camera mặc định của điện thoại như cũ
        if (_controller == null || !_controller!.value.isInitialized) return;
        final image = await _controller!.takePicture();

        if (mounted) {
          // Nếu dùng camera thường thì vẫn giữ luồng chuyển tiếp để app không bị kẹt UI
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProcessingScreen(imagePath: image.path),
            ),
          );
        }
      }
    } on PlatformException catch (e) {
      debugPrint("Lỗi từ luồng quét phần cứng: ${e.message}");
      if (mounted) {
        // Hiện SnackBar màu đỏ thông báo nếu lệnh gọi API phần cứng bị thất bại
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Lỗi gọi API: ${e.message}"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CameraPreview(_controller!),

          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Chip(
                  avatar: Icon(
                    _isIriTechConnected ? Icons.usb_rounded : Icons.usb_off_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    _isIriTechConnected ? "IrisAegis: ON" : "IrisAegis: OFF",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: _isIriTechConnected ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.7),
                ),
              ),
            ),
          ),

          SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 35),
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
            ),
          ),
          Positioned(bottom: 50, left: 0, right: 0, child: _buildControls()),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.photo_library, color: Colors.white, size: 30),
          onPressed: _pickImageFromGallery,
        ),
        GestureDetector(
          onTap: _captureImage,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  // Đổi màu viền nút sang xanh lá cây nếu nhận diện được máy quét phần cứng
                    color: _isIriTechConnected ? Colors.greenAccent : Colors.white,
                    width: 5
                )
            ),
            child: _isCapturing
                ? const Padding(
              padding: EdgeInsets.all(15.0),
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            )
                : null,
          ),
        ),
        IconButton(icon: const Icon(Icons.flip_camera_ios, color: Colors.white), onPressed: () {
          _selectedCameraIndex = _selectedCameraIndex == 0 ? 1 : 0;
          _setupController();
        }),
      ],
    );
  }
}