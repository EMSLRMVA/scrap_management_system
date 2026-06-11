import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../screens/app_shell.dart';
import '../screens/admin/admin_screen.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/customer/customer_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/dispatch/dispatch_screen.dart';
import '../screens/expenses/expenses_screen.dart';
import '../screens/invoices/invoices_screen.dart';
import '../screens/ledgers/ledger_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/owner/owner_panel_screen.dart';
import '../screens/profit_loss/profit_loss_screen.dart';
import '../screens/purchase/quick_purchase_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/sales/sales_screen.dart';
import '../screens/seller/seller_screen.dart';
import '../screens/settings/profile_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/stock/stock_screen.dart';
import '../screens/supervisor/supervisor_screen.dart';
import '../screens/voice/voice_screen.dart';

class AppRouter {
  AppRouter(this._authProvider);

  final AuthProvider _authProvider;

  late final GoRouter router = GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: _authProvider,
    redirect: (context, state) {
      final isAuthRoute = {
        '/login',
        '/register',
        '/forgot-password',
      }.contains(state.uri.path);

      if (!_authProvider.isAuthenticated && !isAuthRoute) {
        return '/login';
      }
      if (_authProvider.isAuthenticated && isAuthRoute) {
        return '/dashboard';
      }

      final firstSegment = state.uri.pathSegments.isEmpty
          ? 'dashboard'
          : state.uri.pathSegments.first;
      if (_authProvider.isAuthenticated &&
          !_authProvider.canAccess(firstSegment)) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/dashboard'),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          _route('dashboard', const DashboardScreen()),
          _route('purchase', const QuickPurchaseScreen()),
          _route('sellers', const SellerScreen()),
          _route('customers', const CustomerScreen()),
          _route('stock', const StockScreen()),
          _route('sales', const SalesScreen()),
          _route('expenses', const ExpensesScreen()),
          _route('invoices', const InvoicesScreen()),
          _route('ledgers', const LedgerScreen()),
          _route('profit-loss', const ProfitLossScreen()),
          _route('reports', const ReportsScreen()),
          _route('voice', const VoiceScreen()),
          _route('dispatch', const DispatchScreen()),
          _route('analytics', const AnalyticsScreen()),
          _route('notifications', const NotificationsScreen()),
          _route('owner', const OwnerPanelScreen()),
          _route('admin', const AdminScreen()),
          _route('settings', const SettingsScreen()),
          _route('profile', const ProfileScreen()),
          _route('supervisor', const SupervisorScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri.path}')),
    ),
  );

  static GoRoute _route(String path, Widget screen) {
    return GoRoute(
      path: '/$path',
      pageBuilder: (context, state) => NoTransitionPage(child: screen),
    );
  }
}
