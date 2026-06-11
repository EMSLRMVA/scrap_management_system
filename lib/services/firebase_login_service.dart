import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../domain/business_models.dart';

const ownerEmail = 'scrap.emslrmva@gmail.com';

class AuthenticatedProfile {
  const AuthenticatedProfile({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.active,
    this.mobile = '',
  });

  final String uid;
  final String email;
  final String name;
  final UserRole role;
  final bool active;
  final String mobile;
}

class FirebaseLoginService {
  FirebaseLoginService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User? get currentUser => _auth.currentUser;

  Future<AuthenticatedProfile?> currentProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    try {
      return _profileForUser(user, writeLogin: false);
    } on Object {
      await _auth.signOut();
      rethrow;
    }
  }

  Future<AuthenticatedProfile> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _withAuthTimeout(
        _auth.signInWithEmailAndPassword(
          email: _cleanEmail(email),
          password: password,
        ),
      );
      final user = credential.user;
      if (user == null) {
        throw const FirebaseLoginException('Login failed. Try again.');
      }
      return _profileForUser(user, writeLogin: true);
    } on FirebaseAuthException catch (error) {
      throw FirebaseLoginException(_emailAuthError(error));
    } on TimeoutException {
      throw const FirebaseLoginException(
        'Firebase login timed out. Check emulator internet/DNS.',
      );
    }
  }

  Future<AuthenticatedProfile> register({
    required String name,
    required String email,
    required String password,
    required String mobile,
    required bool consentAccepted,
  }) async {
    if (!consentAccepted) {
      throw const FirebaseLoginException('Accept privacy consent to register.');
    }
    if (name.trim().isEmpty) {
      throw const FirebaseLoginException('Name is required.');
    }
    try {
      final credential = await _withAuthTimeout(
        _auth.createUserWithEmailAndPassword(
          email: _cleanEmail(email),
          password: password,
        ),
      );
      final user = credential.user;
      if (user == null) {
        throw const FirebaseLoginException('Registration failed. Try again.');
      }
      await user.updateDisplayName(name.trim());
      final now = FieldValue.serverTimestamp();
      final data = {
        'uid': user.uid,
        'name': name.trim(),
        'email': _cleanEmail(user.email ?? email),
        'mobile': mobile.trim(),
        'role': 'user',
        'active': true,
        'createdAt': now,
        'lastLoginAt': now,
        'lastActiveAt': now,
        'consentAccepted': true,
        'consentAcceptedAt': now,
      };
      await _firestore.collection('users').doc(user.uid).set(data);
      final profile = AuthenticatedProfile(
        uid: user.uid,
        email: _cleanEmail(user.email ?? email),
        name: name.trim(),
        role: UserRole.user,
        active: true,
        mobile: mobile.trim(),
      );
      await _writeActivityLog(
        profile: profile,
        action: 'register',
        screen: 'Registration',
        details: 'New user registered',
      );
      await _writeLoginAndActivityLogs(profile);
      await _writeOwnerNotification(
        type: 'new_user_registered',
        title: 'New user registered',
        body: '${profile.name} (${profile.email}) registered.',
        profile: profile,
      );
      return profile;
    } on FirebaseAuthException catch (error) {
      throw FirebaseLoginException(_emailAuthError(error));
    } on TimeoutException {
      throw const FirebaseLoginException(
        'Firebase registration timed out. Check emulator internet/DNS.',
      );
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _withAuthTimeout(
        _auth.sendPasswordResetEmail(email: _cleanEmail(email)),
      );
    } on FirebaseAuthException catch (error) {
      throw FirebaseLoginException(_emailAuthError(error));
    } on TimeoutException {
      throw const FirebaseLoginException(
        'Firebase password reset timed out. Check emulator internet/DNS.',
      );
    }
  }

  Future<void> setUserActive({
    required String userId,
    required bool active,
    required AuthenticatedProfile owner,
  }) async {
    _requireOwner(owner);
    final snapshot = await _firestore.collection('users').doc(userId).get();
    final data = snapshot.data();
    if ((data?['role'] ?? '').toString() == 'owner' && !active) {
      throw const FirebaseLoginException('Owner account cannot be disabled.');
    }
    await _firestore.collection('users').doc(userId).set({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': owner.uid,
    }, SetOptions(merge: true));
    await _writeActivityLog(
      profile: owner,
      action: active ? 'user_enabled' : 'user_disabled',
      screen: 'Owner Dashboard',
      details: userId,
    );
  }

  Future<void> updateUserProfile({
    required String userId,
    required String name,
    required String mobile,
    required UserRole role,
    required bool active,
    required AuthenticatedProfile owner,
  }) async {
    _requireOwner(owner);
    final snapshot = await _firestore.collection('users').doc(userId).get();
    final data = snapshot.data() ?? <String, dynamic>{};
    final existingRole = (data['role'] ?? '').toString();
    if (existingRole == 'owner' && role != UserRole.owner) {
      throw const FirebaseLoginException('Owner role cannot be changed.');
    }
    if (existingRole == 'owner' && !active) {
      throw const FirebaseLoginException('Owner account cannot be disabled.');
    }
    await _firestore.collection('users').doc(userId).set({
      'name': name.trim(),
      'mobile': mobile.trim(),
      'role': role.name,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': owner.uid,
    }, SetOptions(merge: true));
    await _writeActivityLog(
      profile: owner,
      action: 'user_profile_updated',
      screen: 'Owner Dashboard',
      details: '$userId | ${name.trim()} | ${role.name}',
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchUsers() {
    return _firestore
        .collection('users')
        .orderBy('lastActiveAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchLoginLogs({String? userId}) {
    Query<Map<String, dynamic>> query = _firestore.collection('loginLogs');
    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    }
    return query.orderBy('loginAt', descending: true).limit(50).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchActivityLogs({
    String? userId,
  }) {
    Query<Map<String, dynamic>> query = _firestore.collection('activityLogs');
    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    }
    return query.orderBy('createdAt', descending: true).limit(100).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOwnerNotifications() {
    return _firestore
        .collection('ownerNotifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<void> writeActivityLog({
    required AuthenticatedProfile profile,
    required String action,
    required String screen,
    required String details,
  }) {
    return _writeActivityLog(
      profile: profile,
      action: action,
      screen: screen,
      details: details,
    );
  }

  Future<void> signOut(AuthenticatedProfile profile) async {
    await _writeActivityLog(
      profile: profile,
      action: 'logout',
      screen: 'App',
      details: 'User logged out',
    );
    await _firestore.collection('users').doc(profile.uid).set({
      'lastActiveAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _auth.signOut();
  }

  Future<AuthenticatedProfile> _profileForUser(
    User user, {
    required bool writeLogin,
  }) async {
    final email = _cleanEmail(user.email ?? '');
    if (email.isEmpty) {
      await _auth.signOut();
      throw const FirebaseLoginException('Email login is required.');
    }

    final now = FieldValue.serverTimestamp();
    final userRef = _firestore.collection('users').doc(user.uid);
    if (email == ownerEmail) {
      await userRef.set({
        'uid': user.uid,
        'name': 'Owner',
        'email': ownerEmail,
        'role': 'owner',
        'active': true,
        'lastLoginAt': now,
        'lastActiveAt': now,
      }, SetOptions(merge: true));
      final profile = AuthenticatedProfile(
        uid: user.uid,
        email: ownerEmail,
        name: 'Owner',
        role: UserRole.owner,
        active: true,
      );
      if (writeLogin) {
        await _writeLoginAndActivityLogs(profile);
      }
      return profile;
    }

    final snapshot = await userRef.get();
    if (!snapshot.exists) {
      await _auth.signOut();
      throw const FirebaseLoginException(
        'User profile not found. Please register.',
      );
    }
    final data = snapshot.data() ?? <String, dynamic>{};
    final active = data['active'] != false;
    if (!active) {
      await _auth.signOut();
      throw const FirebaseLoginException(
        'Your account is disabled. Contact admin.',
      );
    }
    await userRef.set({
      'lastLoginAt': now,
      'lastActiveAt': now,
    }, SetOptions(merge: true));

    final storedRole = _roleFromFirestore(data['role']);
    final effectiveRole = storedRole.isOwnerOrAdmin ? UserRole.manager : storedRole;
    if (storedRole.isOwnerOrAdmin) {
      await userRef.set({
        'role': effectiveRole.name,
        'roleCorrectedAt': now,
        'roleCorrectionReason':
            'Only the official owner email can use Owner/Admin permissions.',
      }, SetOptions(merge: true));
    }

    final profile = AuthenticatedProfile(
      uid: user.uid,
      email: (data['email'] ?? email).toString(),
      name: (data['name'] ?? user.displayName ?? 'User').toString(),
      role: effectiveRole,
      active: true,
      mobile: (data['mobile'] ?? '').toString(),
    );
    if (writeLogin) {
      await _writeLoginAndActivityLogs(profile);
      await _writeOwnerNotification(
        type: 'user_login',
        title: 'User logged in',
        body: '${profile.name} (${profile.email}) logged in.',
        profile: profile,
      );
    }
    return profile;
  }

  Future<void> _writeLoginAndActivityLogs(AuthenticatedProfile profile) async {
    final packageInfo = await PackageInfo.fromPlatform();
    await _firestore.collection('loginLogs').add({
      'userId': profile.uid,
      'name': profile.name,
      'email': profile.email,
      'role': profile.role.name,
      'loginAt': FieldValue.serverTimestamp(),
      'deviceInfo': _deviceInfo(),
      'appVersion': '${packageInfo.version}+${packageInfo.buildNumber}',
    });
    await _writeActivityLog(
      profile: profile,
      action: 'login',
      screen: 'Login',
      details: 'Successful email login',
    );
  }

  Future<void> _writeActivityLog({
    required AuthenticatedProfile profile,
    required String action,
    required String screen,
    required String details,
  }) async {
    await _firestore.collection('activityLogs').add({
      'userId': profile.uid,
      'name': profile.name,
      'email': profile.email,
      'role': profile.role.name,
      'action': action,
      'screen': screen,
      'details': details,
      'createdAt': FieldValue.serverTimestamp(),
      'deviceInfo': _deviceInfo(),
    });
  }

  Future<void> _writeOwnerNotification({
    required String type,
    required String title,
    required String body,
    required AuthenticatedProfile profile,
  }) async {
    await _firestore.collection('ownerNotifications').add({
      'type': type,
      'title': title,
      'body': body,
      'userId': profile.uid,
      'name': profile.name,
      'email': profile.email,
      'role': profile.role.name,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  void _requireOwner(AuthenticatedProfile profile) {
    if (!profile.role.isOwnerOrAdmin) {
      throw const FirebaseLoginException('Only Owner/Admin can update users.');
    }
  }
}

class FirebaseLoginException implements Exception {
  const FirebaseLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _cleanEmail(String email) => email.trim().toLowerCase();

Future<T> _withAuthTimeout<T>(Future<T> action) =>
    action.timeout(const Duration(seconds: 12));

UserRole _roleFromFirestore(Object? value) {
  final role = (value ?? 'user').toString();
  switch (role) {
    case 'owner':
      return UserRole.owner;
    case 'admin':
      return UserRole.admin;
    case 'supervisor':
      return UserRole.supervisor;
    case 'manager':
      return UserRole.manager;
    case 'accountant':
      return UserRole.accountant;
    default:
      return UserRole.user;
  }
}

String _emailAuthError(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-email':
      return 'Enter a valid email address.';
    case 'user-disabled':
      return 'Your account is disabled. Contact admin.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Invalid email or password.';
    case 'email-already-in-use':
      return 'This email is already registered.';
    case 'weak-password':
      return 'Password must be at least 6 characters.';
    case 'network-request-failed':
      return 'Network error. Firebase cannot be reached. Check emulator internet/DNS and try again.';
    default:
      return error.message ?? 'Authentication failed.';
  }
}

String _deviceInfo() {
  if (kIsWeb) {
    return 'web ${defaultTargetPlatform.name}';
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}
