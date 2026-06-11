import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../firebase/firebase_bootstrap.dart';
import '../models/app_user.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({required this.firebaseStatus});

  final FirebaseStatus firebaseStatus;
  AppUser? _currentUser;
  bool _busy = false;
  String? _error;

  AppUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get busy => _busy;
  String? get error => _error;

  Future<void> login(String email, String password) async {
    _setBusy(true);
    _currentUser = null;
    _error = 'Use the Scrap System email/password login.';
    _setBusy(false);
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required AppRole role,
  }) async {
    _setBusy(true);
    _currentUser = null;
    _error = 'Use the Scrap System public registration form.';
    _setBusy(false);
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    _setBusy(true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _setBusy(false);
  }

  void switchRole(AppRole role) {
    return;
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }

  bool canAccess(String moduleKey) {
    final user = _currentUser;
    if (user == null) {
      return false;
    }
    final access = AppConstants.roleAccess[user.role] ?? const {};
    return access.contains('*') || access.contains(moduleKey);
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}
