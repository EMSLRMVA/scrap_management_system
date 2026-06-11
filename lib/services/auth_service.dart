import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../models/app_user.dart';

class AuthService {
  AuthService({firebase_auth.FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance;

  final firebase_auth.FirebaseAuth _firebaseAuth;

  Future<AppUser?> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      return null;
    }
    return AppUser(
      id: user.uid,
      name: user.displayName ?? 'Scrap User',
      email: user.email ?? email,
      phone: user.phoneNumber ?? '',
      role: AppRole.owner,
      active: true,
    );
  }

  Future<AppUser?> register({
    required String name,
    required String email,
    required String password,
    required AppRole role,
  }) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.updateDisplayName(name);
    final user = credential.user;
    if (user == null) {
      return null;
    }
    return AppUser(
      id: user.uid,
      name: name,
      email: email,
      phone: '',
      role: role,
      active: true,
    );
  }

  Future<void> sendPasswordReset(String email) {
    return _firebaseAuth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() => _firebaseAuth.signOut();
}
