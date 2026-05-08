import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/news.dart';
import 'package:flutter_application_1/screens/profile.dart';

import '../widget/bottom_nav.dart';
import 'camera.dart';
import 'history.dart';
import 'home.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  List<Widget> get _screens => [
    HomeScreen(
      onHistoryTap: () {
        setState(() => _selectedIndex = 1);
      },
    ),
    const HistoryScreen(),
    const NewsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFF6F8FB),
      body: _screens[_selectedIndex],

      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
        onPressed: () async {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CameraScreen(),
            ),
          );
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 65,
          height: 65,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF4285F4), Color(0xFF34A853)]),
            boxShadow: [
              BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))
            ],
          ),
          child: const Icon(Icons.camera_alt_rounded, size: 30, color: Colors.white),
        ),
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomNavWidget(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}