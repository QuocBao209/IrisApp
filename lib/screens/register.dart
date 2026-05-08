import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final AuthService _authService = AuthService();

  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateData() {
    if (_nameController.text.trim().isEmpty) return "Họ tên không được để trống";
    if (_idController.text.trim().length < 9) return "Số CCCD không hợp lệ";
    if (!_emailController.text.contains('@gmail.com')) return "Email không đúng định dạng";
    if (_passwordController.text.length < 6) return "Mật khẩu phải từ 6 ký tự";
    return null;
  }

  void _handleRegister() async {
    final error = _validateData();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.registerUser(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      name: _nameController.text.trim(),
      cccd: _idController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result == "success") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result ?? "Lỗi đăng nhập")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              const Icon(Icons.app_registration_rounded, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 10),
              const Text("Đăng ký tài khoản", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),

              _buildTextField(_nameController, "Họ và tên", Icons.person_outline),
              const SizedBox(height: 20),
              _buildTextField(_idController, "Số CCCD", Icons.credit_card_outlined, isNumber: true),
              const SizedBox(height: 20),
              _buildTextField(_emailController, "Email", Icons.email_outlined),
              const SizedBox(height: 20),
              _buildTextField(_passwordController, "Mật khẩu", Icons.lock_outline, isPass: true),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                  onPressed: _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("HOÀN TẤT ĐĂNG KÝ", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPass = false, bool isNumber = false}) {
    return TextField(
      controller: controller,
      obscureText: isPass,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}