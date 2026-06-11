import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_branding.dart';
import 'core/enterprise_theme.dart';
import 'firebase/firebase_bootstrap.dart';
import 'presentation/enterprise_app.dart';
import 'services/messaging_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FirebaseStartupGate()));
}

class FirebaseStartupGate extends StatefulWidget {
  const FirebaseStartupGate({super.key});

  @override
  State<FirebaseStartupGate> createState() => _FirebaseStartupGateState();
}

class _FirebaseStartupGateState extends State<FirebaseStartupGate> {
  Future<FirebaseStatus>? _startup;
  bool _offlineDemo = false;
  bool _pushPrepared = false;

  @override
  void initState() {
    super.initState();
    _startup = FirebaseBootstrap.initialize();
  }

  void _retry() {
    setState(() {
      _offlineDemo = false;
      _startup = FirebaseBootstrap.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_offlineDemo) {
      return const EnterpriseApp(offlineDemo: true);
    }

    return FutureBuilder<FirebaseStatus>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupShell(
            title: appDisplayName,
            message: 'Starting secure business workspace...',
            loading: true,
          );
        }

        final status = snapshot.data;
        if (status?.isReady == true) {
          _preparePushNotifications();
          return const EnterpriseApp();
        }

        return _StartupShell(
          title: 'Firebase Connection Slow',
          message:
              status?.message ??
              'Firebase could not start. Check emulator internet and try again.',
          onRetry: _retry,
          onOfflineDemo: () => setState(() => _offlineDemo = true),
        );
      },
    );
  }

  void _preparePushNotifications() {
    if (_pushPrepared) {
      return;
    }
    _pushPrepared = true;
    MessagingService().preparePushNotifications();
  }
}

class _StartupShell extends StatelessWidget {
  const _StartupShell({
    required this.title,
    required this.message,
    this.loading = false,
    this.onRetry,
    this.onOfflineDemo,
  });

  final String title;
  final String message;
  final bool loading;
  final VoidCallback? onRetry;
  final VoidCallback? onOfflineDemo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      theme: EnterpriseTheme.light(),
      home: Scaffold(
        backgroundColor: EnterpriseTheme.dashboardBackground,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              EnterpriseTheme.primary,
                              EnterpriseTheme.accent,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.recycling,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF475569)),
                      ),
                      if (loading) ...[
                        const SizedBox(height: 18),
                        const LinearProgressIndicator(minHeight: 4),
                      ] else ...[
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry Firebase'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: onOfflineDemo,
                          icon: const Icon(Icons.offline_bolt),
                          label: const Text('Open Offline Demo'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
