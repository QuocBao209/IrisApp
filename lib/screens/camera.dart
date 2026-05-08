import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/processing.dart';

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

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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

  Future<void> _captureImage() async {
    if (_isCapturing || _controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isCapturing = true);
    try {
      final image = await _controller!.takePicture();
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProcessingScreen(imagePath: image.path)));
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
          // Nút X quay về Main Screen
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
        IconButton(icon: const Icon(Icons.photo_library, color: Colors.white), onPressed: () {}),
        GestureDetector(
          onTap: _captureImage,
          child: Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5))),
        ),
        IconButton(icon: const Icon(Icons.flip_camera_ios, color: Colors.white), onPressed: () {
          _selectedCameraIndex = _selectedCameraIndex == 0 ? 1 : 0;
          _setupController();
        }),
      ],
    );
  }
}