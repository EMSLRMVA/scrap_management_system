import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../firebase/firebase_bootstrap.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../routes/app_router.dart';

class ScrapManagementApp extends StatefulWidget {
  const ScrapManagementApp({super.key, required this.firebaseStatus});

  final FirebaseStatus firebaseStatus;

  @override
  State<ScrapManagementApp> createState() => _ScrapManagementAppState();
}

class _ScrapManagementAppState extends State<ScrapManagementApp> {
  late final AppRouter _appRouter;

  @override
  void initState() {
    super.initState();
    _appRouter = AppRouter(context.read<AuthProvider>());
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp.router(
      title: 'Scrap Management System',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: _appRouter.router,
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );
  }
}
