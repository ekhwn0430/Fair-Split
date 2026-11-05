import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 현재 로그인된 유저
  User? get currentUser => _auth.currentUser;

  // 회원가입
  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String name,
    required String accountNumber,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Firestore에 프로필 저장
    await _db.collection('users').doc(credential.user!.uid).set({
      'name': name,
      'accountNumber': accountNumber,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return credential;
  }

  // 로그인
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // 로그아웃
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // 프로필 가져오기
  Future<Map<String, dynamic>?> getUserProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }
}