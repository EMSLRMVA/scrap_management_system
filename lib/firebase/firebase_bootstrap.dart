import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

class FirebaseStatus {
  const FirebaseStatus({required this.isReady, this.message});

  final bool isReady;
  final String? message;
}

class FirebaseBootstrap {
  const FirebaseBootstrap._();

  static Future<FirebaseStatus>? _initialization;

  static Future<FirebaseStatus> initialize({
    Duration timeout = const Duration(seconds: 8),
  }) {
    _initialization ??= _initialize();

    return _initialization!.timeout(
      timeout,
      onTimeout: () => const FirebaseStatus(
        isReady: false,
        message:
            'Firebase is taking too long to start. Check internet/DNS, or continue in offline demo mode.',
      ),
    );
  }

  static Future<FirebaseStatus> _initialize() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        return const FirebaseStatus(isReady: true);
      }
      await _initializeFirebaseApp();

      return const FirebaseStatus(isReady: true);
    } catch (error) {
      return FirebaseStatus(
        isReady: false,
        message:
            'Firebase configuration was not found. Running in offline demo mode. $error',
      );
    }
  }

  static Future<void> _initializeFirebaseApp() {
    if (kIsWeb) {
      return Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    }
    return Firebase.initializeApp();
  }
}
