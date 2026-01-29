import 'package:flutter/material.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Các bộ điều khiển để lấy dữ liệu từ ô nhập
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

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
              const Text("Thông tin sẽ được dùng để quản lý hồ sơ sức khỏe"),
              const SizedBox(height: 40),

              // 1. Ô nhập Họ và Tên
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: "Họ và tên",
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // 2. Ô nhập CCCD (Số định danh)
              TextField(
                controller: _idController,
                keyboardType: TextInputType.number, // Hiện bàn phím số
                decoration: InputDecoration(
                  labelText: "Số CCCD",
                  prefixIcon: const Icon(Icons.credit_card_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // 3. Ô nhập Email
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: "Email",
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // 4. Ô nhập Mật khẩu
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: "Mật khẩu",
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 30),

              // Nút xác nhận Đăng ký
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {
                    // Hiển thị thử dữ liệu đã nhập ở tab Run của Android Studio
                    print("Họ tên: ${_nameController.text}");
                    print("CCCD: ${_idController.text}");
                  },
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
}