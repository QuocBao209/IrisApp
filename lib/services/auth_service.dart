import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String hashPassword(String password) {
    var bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  Future<String?> registerUser({
    required String email,
    required String password,
    required String name,
    required String cccd,
  }) async {
    User? user;
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      user = userCredential.user;

      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'cccd': cccd,
        'name': name,
        'email': email,
        'password': hashPassword(password),
      });

      return "success";
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {

      if (user != null) await user.delete();
      return "Lỗi đăng ký!";
    }
  }

  Future<String?> loginUser(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return "success";
    } on FirebaseAuthException catch (e) {
      return "Tài khoản hoặc mật khẩu không chính xác.";
    }
  }
}