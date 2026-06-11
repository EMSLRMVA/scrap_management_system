import 'package:firebase_core/firebase_core.dart';

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
            'Firebase is taking too long to start. Check emulator internet/DNS, or continue in offline demo mode.',
      ),
    );
  }

  static Future<FirebaseStatus> _initialize() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        return const FirebaseStatus(isReady: true);
      }
      await Firebase.initializeApp();
      return const FirebaseStatus(isReady: true);
    } catch (error) {
      return FirebaseStatus(
        isReady: false,
        message:
            'Firebase configuration was not found. Running in offline demo mode. $error',
      );
    }
  }
}
