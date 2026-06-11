import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_branding.dart';
import '../core/enterprise_theme.dart';
import '../core/money_format.dart';
import '../data/firebase/dynamic_page_data_service.dart';
import '../data/firebase/in_app_update_service.dart';
import '../data/supabase/supabase_business_gateway.dart';
import '../domain/business_models.dart';
import '../domain/dynamic_config_models.dart';
import '../domain/stock_calculation.dart';
import '../services/firebase_login_service.dart';
import '../services/notification_service.dart';
import '../utils/graph_popup_guard.dart';
import 'ai_copilot.dart';
import 'business_controller.dart';
import 'dynamic_config_controller.dart';
import 'enterprise_feature_screens.dart';
import 'manual_stock_reminders.dart';
import 'operational_dashboard.dart';
import 'theme_controller.dart';
import 'theme_settings_screen.dart';

const _manualStockReminderNotificationIdsPrefsKey =
    'manual_stock_reminder_notification_ids';
const _paymentReminderNotificationId = 9019;

class EnterpriseApp extends ConsumerWidget {
  const EnterpriseApp({super.key, this.offlineDemo = false});

  final bool offlineDemo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTheme = ref
        .watch(appThemeProvider)
        .maybeWhen(
          data: (theme) => theme,
          orElse: () =>
              EnterpriseTheme.modelForMode(EnterpriseThemeMode.midnightBlue),
        );
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: selectedTheme.toThemeData(),
      darkTheme: selectedTheme.toThemeData(),
      home: offlineDemo
          ? const EnterpriseShell()
          : const OwnerLoginGate(child: EnterpriseShell()),
    );
  }
}

class EnterpriseShell extends ConsumerStatefulWidget {
  const EnterpriseShell({super.key});

  @override
  ConsumerState<EnterpriseShell> createState() => _EnterpriseShellState();
}

class _EnterpriseShellState extends ConsumerState<EnterpriseShell> {
  int _index = 0;
  final _updateService = InAppUpdateService();
  final _notificationService = NotificationService();
  String? _lastUpdatePromptKey;
  Timer? _autoReminderTimer;
  String? _autoReminderScheduleKey;
  bool _checkingAutoReminder = false;
  String? _paymentReminderScheduleKey;
  bool _checkingPaymentReminder = false;
  StreamSubscription<String?>? _notificationTapSub;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(businessProvider.notifier).recordDashboardOpened(),
    );
    Future.microtask(_notificationService.initialize);
    _notificationTapSub = NotificationService.notificationTaps.listen((
      payload,
    ) {
      if (!mounted || payload != 'manual_stock_reminder') {
        if (mounted && payload == 'payment_reminder') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ManualWhatsAppReminderScreen(
                initialType: StockReminderType.pendingPaymentAlert,
              ),
            ),
          );
        }
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ManualWhatsAppReminderScreen()),
      );
    });
  }

  @override
  void dispose() {
    _autoReminderTimer?.cancel();
    _notificationTapSub?.cancel();
    super.dispose();
  }

  Future<void> _handleBack() async {
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Application?'),
        content: Text('Do you want to close $appDisplayName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (shouldExit == true) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(dynamicConfigProvider);
    final state = ref.watch(businessProvider);
    final rawMenu = config.visibleBottomMenu.isEmpty
        ? DynamicConfigState.defaults().visibleBottomMenu
        : config.visibleBottomMenu;
    final roleMenu = _menuForRole(rawMenu);
    final menu = roleMenu.isEmpty
        ? DynamicConfigState.defaults().visibleBottomMenu
              .where((item) => item.routeKey == 'dashboard')
              .toList()
        : roleMenu;
    final selectedIndex = _index >= menu.length ? 0 : _index;
    if (selectedIndex != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _index = selectedIndex);
        }
      });
    }
    final selectedMenu = menu[selectedIndex];
    final page = _pageForMenu(selectedMenu, config);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowUpdatePrompt(config);
      _maybeScheduleAutoReminders(state);
      _maybeSchedulePaymentReminders(state);
    });

    if (config.remote.maintenanceMode) {
      return _MaintenanceScreen(message: config.app.maintenanceMessage);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        body: SafeArea(child: page),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: [
            for (final item in menu)
              NavigationDestination(
                icon: Icon(_outlinedIconFromName(item.icon)),
                selectedIcon: Icon(_iconFromName(item.icon)),
                label: _menuLabel(item),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pageForMenu(
    DynamicMenuItemConfig menuItem,
    DynamicConfigState config,
  ) {
    final page = config.pageFor(menuItem.pageId);
    switch (page.type) {
      case 'dashboard':
        return _PageTint(
          color: EnterpriseTheme.dashboardBackground,
          child: DashboardTab(
            page: page,
            dashboardCards: config.dashboardCards,
            onNavigate: _navigateToRoute,
          ),
        );
      case 'purchase':
        return _PageTint(
          color: EnterpriseTheme.purchaseBackground,
          child: PurchaseTab(page: page),
        );
      case 'sales':
        return _PageTint(
          color: EnterpriseTheme.sellersBackground,
          child: SalesTab(page: page),
        );
      case 'inventory':
        return _PageTint(
          color: EnterpriseTheme.inventoryBackground,
          child: InventoryTab(page: page),
        );
      case 'stock_register':
        return _PageTint(
          color: EnterpriseTheme.inventoryBackground,
          child: const StockRegisterScreen(),
        );
      case 'more':
        return _PageTint(
          color: EnterpriseTheme.settingsBackground,
          child: MoreTab(
            page: page,
            config: config,
            onNavigate: _navigateToRoute,
          ),
        );
      default:
        return _PageTint(
          color: EnterpriseTheme.reportsBackground,
          child: DynamicPageEngine(page: page),
        );
    }
  }

  List<DynamicMenuItemConfig> _menuForRole(List<DynamicMenuItemConfig> menu) {
    return menu.toList();
  }

  String _menuLabel(DynamicMenuItemConfig item) =>
      item.routeKey == 'stock_register' ? 'Analysis' : item.label;

  Future<void> _maybeScheduleAutoReminders(BusinessState state) async {
    if (!mounted || _checkingAutoReminder) {
      return;
    }
    _checkingAutoReminder = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeReceivers = state.stockReminderReceivers
          .where((receiver) => receiver.isActive)
          .toList();
      if (activeReceivers.isEmpty) {
        await _cancelDailyStockReminderNotifications(prefs);
        _autoReminderTimer?.cancel();
        _autoReminderScheduleKey = null;
        return;
      }
      final reminderTimes = _reminderTimesFromReceivers(activeReceivers);
      final now = DateTime.now();
      final todayKey = _reminderDateKey(now);
      final sentSlots =
          prefs.getStringList(autoReminderSentSlotsPrefsKey) ?? [];
      final timeKeys = reminderTimes.map(_reminderTimeKey).join(',');
      final receiverKey = activeReceivers
          .map((receiver) => '${receiver.id}:${receiver.timeKey}')
          .join(',');
      final key = '$receiverKey-$timeKeys-$todayKey-${sentSlots.join(',')}';
      if (_autoReminderScheduleKey == key) {
        return;
      }
      _autoReminderScheduleKey = key;
      _autoReminderTimer?.cancel();
      await _syncDailyStockReminderNotifications(prefs, reminderTimes);

      final timeLabel = reminderTimes.map(_formatReminderTime).join(', ');
      final scheduledNoticeKey =
          '${autoReminderScheduledNoticePrefsKey}_$todayKey';
      if (prefs.getString(scheduledNoticeKey) != timeLabel) {
        ref
            .read(businessProvider.notifier)
            .recordAutoReminderScheduled(timeLabel);
        await prefs.setString(scheduledNoticeKey, timeLabel);
      }

      for (final reminderTime in reminderTimes) {
        final slotKey = '$todayKey ${_reminderTimeKey(reminderTime)}';
        if (sentSlots.contains(slotKey)) {
          continue;
        }
        final target = DateTime(
          now.year,
          now.month,
          now.day,
          reminderTime.hour,
          reminderTime.minute,
        );
        if (!now.isBefore(target)) {
          unawaited(_showManualStockReminderNotification(reminderTime));
          return;
        }
        _autoReminderTimer = Timer(
          target.difference(now),
          () => unawaited(_showManualStockReminderNotification(reminderTime)),
        );
        return;
      }
      _scheduleNextAutoReminder(now, reminderTimes.first);
    } finally {
      _checkingAutoReminder = false;
    }
  }

  Future<void> _maybeSchedulePaymentReminders(BusinessState state) async {
    if (!mounted || _checkingPaymentReminder) {
      return;
    }
    _checkingPaymentReminder = true;
    try {
      final reminders = pendingCustomerPaymentReminders(state);
      if (reminders.isEmpty) {
        if (_paymentReminderScheduleKey != null) {
          await _notificationService.cancel(id: _paymentReminderNotificationId);
          _paymentReminderScheduleKey = null;
        }
        return;
      }
      final totalPending = reminders.fold<double>(
        0,
        (runningTotal, reminder) => runningTotal + reminder.totalPending,
      );
      final scheduleKey =
          '${reminders.length}:${totalPending.toStringAsFixed(0)}';
      if (_paymentReminderScheduleKey == scheduleKey) {
        return;
      }
      _paymentReminderScheduleKey = scheduleKey;
      await _notificationService.scheduleDailyPaymentReminder(
        id: _paymentReminderNotificationId,
        hour: 9,
        minute: 0,
        body:
            '${reminders.length} customer(s) pending ${money(totalPending)}. Tap to prepare WhatsApp reminders.',
      );
      ref
          .read(businessProvider.notifier)
          .recordAutoReminderScheduled('9:00 AM pending payment');
    } finally {
      _checkingPaymentReminder = false;
    }
  }

  Future<void> _syncDailyStockReminderNotifications(
    SharedPreferences prefs,
    List<TimeOfDay> reminderTimes,
  ) async {
    final nextIds = reminderTimes.map(_reminderNotificationId).toSet();
    final existingIds =
        (prefs.getStringList(_manualStockReminderNotificationIdsPrefsKey) ??
                const <String>[])
            .map(int.tryParse)
            .whereType<int>()
            .toSet();
    for (final id in existingIds.difference(nextIds)) {
      await _notificationService.cancel(id: id);
    }
    for (final reminderTime in reminderTimes) {
      await _notificationService.scheduleDailyStockVerificationReminder(
        id: _reminderNotificationId(reminderTime),
        hour: reminderTime.hour,
        minute: reminderTime.minute,
      );
    }
    await prefs.setStringList(
      _manualStockReminderNotificationIdsPrefsKey,
      (nextIds.map((id) => id.toString()).toList()..sort()),
    );
  }

  Future<void> _cancelDailyStockReminderNotifications(
    SharedPreferences prefs,
  ) async {
    final existingIds =
        (prefs.getStringList(_manualStockReminderNotificationIdsPrefsKey) ??
                const <String>[])
            .map(int.tryParse)
            .whereType<int>();
    for (final id in existingIds) {
      await _notificationService.cancel(id: id);
    }
    await prefs.remove(_manualStockReminderNotificationIdsPrefsKey);
  }

  void _scheduleNextAutoReminder(DateTime now, TimeOfDay reminderTime) {
    var nextTarget = DateTime(
      now.year,
      now.month,
      now.day,
      reminderTime.hour,
      reminderTime.minute,
    );
    if (!nextTarget.isAfter(now)) {
      nextTarget = nextTarget.add(const Duration(days: 1));
    }
    _autoReminderTimer?.cancel();
    _autoReminderTimer = Timer(
      nextTarget.difference(now),
      () => unawaited(_showManualStockReminderNotification(reminderTime)),
    );
  }

  Future<void> _showManualStockReminderNotification(
    TimeOfDay reminderTime,
  ) async {
    if (!mounted) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _reminderDateKey(DateTime.now());
    final slotKey = '$todayKey ${_reminderTimeKey(reminderTime)}';
    final sentSlots = prefs.getStringList(autoReminderSentSlotsPrefsKey) ?? [];
    if (sentSlots.contains(slotKey)) {
      return;
    }
    await prefs.setString(autoReminderSentDatePrefsKey, todayKey);
    await prefs.setStringList(
      autoReminderSentSlotsPrefsKey,
      {...sentSlots, slotKey}.toList(),
    );
    await _notificationService.showStockVerificationReminder(
      id: reminderTime.hour * 100 + reminderTime.minute,
    );
    ref
        .read(businessProvider.notifier)
        .recordAutoReminderScheduled(_formatReminderTime(reminderTime));
    if (mounted) {
      _snack(context, 'Manual stock reminder notification shown.');
      _autoReminderScheduleKey = null;
      await _maybeScheduleAutoReminders(ref.read(businessProvider));
    }
  }

  String _reminderDateKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  List<TimeOfDay> _reminderTimesFromReceivers(
    List<StockReminderReceiver> receivers,
  ) {
    final keys = <String, TimeOfDay>{};
    for (final receiver in receivers) {
      keys[receiver.timeKey] = TimeOfDay(
        hour: receiver.reminderHour,
        minute: receiver.reminderMinute,
      );
    }
    final times = keys.values.toList()..sort(_compareReminderTimes);
    return times.isEmpty ? const [TimeOfDay(hour: 9, minute: 0)] : times;
  }

  int _compareReminderTimes(TimeOfDay left, TimeOfDay right) {
    final leftMinutes = left.hour * 60 + left.minute;
    final rightMinutes = right.hour * 60 + right.minute;
    return leftMinutes.compareTo(rightMinutes);
  }

  String _reminderTimeKey(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  int _reminderNotificationId(TimeOfDay time) => time.hour * 100 + time.minute;

  String _formatReminderTime(TimeOfDay time) {
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    final displayHour = time.hour == 0
        ? 12
        : time.hour > 12
        ? time.hour - 12
        : time.hour;
    return '$displayHour:${time.minute.toString().padLeft(2, '0')} $suffix';
  }

  void _navigateToRoute(String routeKey) {
    switch (routeKey) {
      case 'dispatch':
        if (const bool.fromEnvironment('DEVELOPER_MODE')) {
          _showDispatchDialog(context, ref);
        } else {
          _snack(context, 'Dispatch is hidden in normal mode.');
        }
        return;
      case 'add_seller':
        showPartyEditor(context, ref, PartyKind.seller);
        return;
      case 'finance':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CashLedgerScreen()));
        return;
      case 'cash_allocation':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CashAllocationScreen()));
        return;
      case 'cash_with_supervisor':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SupervisorCashLedgerScreen()),
        );
        return;
      case 'supervisor_admin':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OwnerSupervisorAdminScreen()),
        );
        return;
      case 'voice_entry':
        _openVoiceEntryCommand();
        return;
      case 'reports':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ReportCenterScreen()));
        return;
      case 'opening_stock':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OpeningStockScreen()));
        return;
      case 'stock_register':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const StockRegisterScreen()));
        return;
    }

    final menu = ref.read(dynamicConfigProvider).visibleBottomMenu;
    final index = menu.indexWhere((item) => item.routeKey == routeKey);
    if (index >= 0) {
      setState(() => _index = index);
      return;
    }

    DynamicMenuItemConfig? moreItem;
    for (final item in ref.read(dynamicConfigProvider).visibleMoreMenu) {
      if (item.routeKey == routeKey) {
        moreItem = item;
        break;
      }
    }
    if (moreItem != null) {
      final dynamicPage = ref
          .read(dynamicConfigProvider)
          .pageFor(moreItem.pageId);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DynamicPageEngine(page: dynamicPage)),
      );
    }
  }

  Future<void> _openVoiceEntryCommand() async {
    final command = await showVoiceCommandDialog(
      context,
      ref: ref,
      title: 'Business Voice Command',
      helpText:
          'Say open purchase, add purchase, add seller, add material, cash allocation, expense, or go back.',
    );
    if (command == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final text = command.toLowerCase().trim();
    if (text.contains('open inventory')) {
      _navigateToRoute('inventory');
      return;
    }
    if (text.contains('open purchase')) {
      _navigateToRoute('purchase');
      return;
    }
    if (text.contains('add purchase') || text.contains('new purchase')) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PurchaseEditorScreen()));
      return;
    }
    if (text.contains('add seller')) {
      showPartyEditor(context, ref, PartyKind.seller);
      return;
    }
    if (text.contains('add material')) {
      showMaterialEditor(context, ref);
      return;
    }
    if (text.contains('go back') || text == 'back') {
      Navigator.of(context).maybePop();
      return;
    }
    await showBusinessVoiceCommand(context, ref, initialCommand: command);
  }

  Future<void> _maybeShowUpdatePrompt(DynamicConfigState config) async {
    if (!mounted) {
      return;
    }

    AppUpdateDecision decision;
    try {
      decision = await _updateService.check(config);
    } catch (_) {
      return;
    }
    if (!decision.updateRequired || !mounted) {
      return;
    }

    final promptKey =
        '${decision.currentVersionCode}-${decision.latestVersionCode}';
    if (_lastUpdatePromptKey == promptKey) {
      return;
    }
    _lastUpdatePromptKey = promptKey;

    final update = await showDialog<bool>(
      context: context,
      barrierDismissible: !decision.forceUpdate,
      builder: (context) => AlertDialog(
        title: const Text('Update Available'),
        content: Text(
          'Version ${decision.latestVersionName} is available. '
          'Current build: ${decision.currentVersionCode}. '
          'Latest build: ${decision.latestVersionCode}.',
        ),
        actions: [
          if (!decision.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (update == true) {
      final launched = await _updateService.startUpdate(decision);
      if (!launched && mounted) {
        _snack(
          context,
          decision.updateUrl.isEmpty
              ? 'Add apk_update_url in Remote Config or app_config/main.'
              : 'Could not open update link.',
        );
      }
    } else if (decision.forceUpdate) {
      _lastUpdatePromptKey = null;
    }
  }
}

class DashboardTab extends ConsumerWidget {
  const DashboardTab({
    super.key,
    required this.page,
    required this.dashboardCards,
    required this.onNavigate,
  });

  final DynamicPageDefinition page;
  final List<DynamicDashboardCardConfig> dashboardCards;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    final metrics = state.metrics;
    final isOwner = state.user.role.isOwnerOrAdmin;
    if (!isOwner) {
      return OperationalDashboard(
        onNavigate: onNavigate,
        onOpenExpectedStock: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ExpectedClosingStockScreen()),
        ),
        onOpenWeightLoss: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WeightLossSummaryScreen()),
        ),
      );
    }
    final tokens = EnterpriseTheme.tokensOf(context);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month);
    final to = DateTime(now.year, now.month, now.day);
    final scopedState = _weightLossScopedState(state);
    final expectedStockRows = _expectedClosingRows(scopedState, from, to);
    final yesterday = now.subtract(const Duration(days: 1));
    final purchaseYesterday = _purchaseValueForDay(state, yesterday);
    final salesYesterday = _salesValueForDay(state, yesterday);
    final expenseYesterday = _expenseValueForDay(state, yesterday);
    final profitYesterday =
        salesYesterday - purchaseYesterday - expenseYesterday;
    final decisionCards = [
      (
        label: 'Today Purchase',
        value: money(metrics.todayPurchase),
        icon: Icons.shopping_cart,
        color: tokens.primaryColor,
        trend: _trendText(metrics.todayPurchase, purchaseYesterday),
        positive: _trendPositive(metrics.todayPurchase, purchaseYesterday),
        report: 'Purchase Report',
        lowerIsBetter: false,
      ),
      (
        label: 'Today Sales',
        value: money(metrics.todaySales),
        icon: Icons.point_of_sale,
        color: tokens.successColor,
        trend: _trendText(metrics.todaySales, salesYesterday),
        positive: _trendPositive(metrics.todaySales, salesYesterday),
        report: 'Sales Report',
        lowerIsBetter: false,
      ),
      (
        label: 'Cash With Supervisor',
        value: money(metrics.cashBalance),
        icon: Icons.account_balance_wallet,
        color: tokens.warningColor,
        trend: metrics.cashBalance >= 0 ? '+0.0%' : '-0.0%',
        positive: metrics.cashBalance >= 0,
        report: 'Cash Ledger',
        lowerIsBetter: false,
      ),
      (
        label: 'Pending Payments',
        value: money(metrics.pendingPayments),
        icon: Icons.pending_actions,
        color: tokens.dangerColor,
        trend: metrics.pendingPayments > 0 ? '-2.4%' : '+0.0%',
        positive: metrics.pendingPayments <= 0,
        report: 'Seller Ledger',
        lowerIsBetter: true,
      ),
      (
        label: 'Profit/Loss',
        value: money(metrics.profitLoss),
        icon: Icons.trending_up,
        color: metrics.profitLoss >= 0
            ? tokens.successColor
            : tokens.dangerColor,
        trend: _trendText(metrics.profitLoss, profitYesterday),
        positive: metrics.profitLoss >= profitYesterday,
        report: 'Profit/Loss Report',
        lowerIsBetter: false,
      ),
      (
        label: 'Total Expense',
        value: money(metrics.totalExpense),
        icon: Icons.receipt_long,
        color: tokens.chartColors.length > 3
            ? tokens.chartColors[3]
            : tokens.secondaryColor,
        trend: _trendText(metrics.totalExpense, expenseYesterday),
        positive: metrics.totalExpense <= expenseYesterday,
        report: 'Expense Report',
        lowerIsBetter: true,
      ),
    ];
    final dashboardCards = [
      decisionCards[0],
      decisionCards[1],
      decisionCards[4],
      metrics.pendingPayments > 0 ? decisionCards[3] : decisionCards[2],
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: aiEnabled ? const AskAiDashboardButton() : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 86),
        children: [
          _PremiumDashboardHeader(
            title: _dashboardTitle(state.user.role),
            company: state.user.company,
            activityCount: state.activities.length,
            onNotifications: () => _showInfo(
              context,
              'Notifications',
              state.activities.isEmpty
                  ? 'No realtime alerts yet.'
                  : state.activities
                        .take(5)
                        .map((item) => '${item.title}: ${item.subtitle}')
                        .join('\n'),
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.58,
            children: [
              for (final card in dashboardCards)
                _PremiumKpiCard(
                  label: card.label,
                  value: card.value,
                  icon: card.icon,
                  color: card.color,
                  trend: card.trend,
                  trendPositive: card.positive,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReportCenterScreen(
                        initialReport: card.report,
                        initialFilter: 'Today',
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (state.activeSales.any((sale) => sale.isPaymentPending)) ...[
            const SizedBox(height: 10),
            _OwnerPendingPaymentAlertPanel(
              sales: state.activeSales
                  .where((sale) => sale.isPaymentPending)
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          _DashboardExpectedClosingStockPanel(
            rows: expectedStockRows,
            from: from,
            to: to,
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ExpectedClosingStockScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<double?> _showSalePaymentReceivedDialog(
  BuildContext context,
  SaleRecord sale,
) async {
  final pendingAmount = sale.balanceAmount.clamp(0, double.infinity).toDouble();
  final amountText = pendingAmount == pendingAmount.roundToDouble()
      ? pendingAmount.toStringAsFixed(0)
      : pendingAmount.toStringAsFixed(2);
  final amountController = TextEditingController(text: amountText);
  String? errorText;
  final result = await showDialog<double>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('Payment Received'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${sale.customer.name}\nPending: ${money(pendingAmount)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'How much payment received?',
                  prefixText: 'Rs ',
                  errorText: errorText,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter full or partial amount. Only entered amount will be updated.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final amount = _read(amountController);
                if (amount <= 0) {
                  setDialogState(
                    () => errorText = 'Enter amount greater than 0',
                  );
                  return;
                }
                if (amount > pendingAmount) {
                  setDialogState(
                    () => errorText = 'Amount cannot be more than pending',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(amount);
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Accept'),
            ),
          ],
        );
      },
    ),
  );
  amountController.dispose();
  return result;
}

class _OwnerPendingPaymentAlertPanel extends ConsumerStatefulWidget {
  const _OwnerPendingPaymentAlertPanel({required this.sales});

  final List<SaleRecord> sales;

  @override
  ConsumerState<_OwnerPendingPaymentAlertPanel> createState() =>
      _OwnerPendingPaymentAlertPanelState();
}

class _OwnerPendingPaymentAlertPanelState
    extends ConsumerState<_OwnerPendingPaymentAlertPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.sales]
      ..sort((a, b) => b.balanceAmount.compareTo(a.balanceAmount));
    final totalPending = sorted.fold<double>(
      0,
      (runningTotal, sale) =>
          runningTotal + sale.balanceAmount.clamp(0, double.infinity),
    );
    final tickerText = sorted
        .take(8)
        .map(
          (sale) =>
              '${sale.customer.name}: ${money(sale.balanceAmount.clamp(0, double.infinity))} • ${sale.reminderSent ? 'reminder sent' : 'reminder not sent'}',
        )
        .join('     |     ');

    return FeaturePanel(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () =>
            _openPendingPaymentSheet(context, ref, sorted, totalPending),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: EnterpriseTheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.notification_important,
                    color: EnterpriseTheme.error,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Payment Pending Alert',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${sorted.length} bills • ${money(totalPending)}',
                  style: const TextStyle(
                    color: EnterpriseTheme.error,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: EnterpriseTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: EnterpriseTheme.error.withValues(alpha: 0.22),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => FractionalTranslation(
                    translation: Offset(1 - (_controller.value * 2.2), 0),
                    child: child,
                  ),
                  child: Text(
                    tickerText,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      color: EnterpriseTheme.error,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPendingPaymentSheet(
    BuildContext context,
    WidgetRef ref,
    List<SaleRecord> sorted,
    double totalPending,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var visibleSales = [...sorted];
        SaleRecord? undoSale;
        double undoAmount = 0;

        return StatefulBuilder(
          builder: (modalContext, setSheetState) {
            final currentTotalPending = visibleSales.fold<double>(
              0,
              (runningTotal, sale) =>
                  runningTotal + sale.balanceAmount.clamp(0, double.infinity),
            );
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Customer Payment Pending Alerts',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            money(currentTotalPending),
                            style: const TextStyle(
                              color: EnterpriseTheme.error,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      if (undoSale != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: EnterpriseTheme.success.withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: EnterpriseTheme.success.withValues(
                                alpha: 0.28,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: EnterpriseTheme.success,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${money(undoAmount)} received for ${undoSale!.customer.name}.',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  final saleToUndo = undoSale;
                                  if (saleToUndo == null) {
                                    return;
                                  }
                                  ref
                                      .read(businessProvider.notifier)
                                      .undoSalePaymentReceived(saleToUndo);
                                  setSheetState(() {
                                    visibleSales.removeWhere(
                                      (item) => item.id == saleToUndo.id,
                                    );
                                    visibleSales.add(saleToUndo);
                                    visibleSales.sort(
                                      (a, b) => b.balanceAmount.compareTo(
                                        a.balanceAmount,
                                      ),
                                    );
                                    undoSale = null;
                                    undoAmount = 0;
                                  });
                                },
                                child: const Text('UNDO'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Expanded(
                        child: visibleSales.isEmpty
                            ? const Center(
                                child: Text(
                                  'No pending customer payment.',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              )
                            : ListView.separated(
                                itemCount: visibleSales.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (itemContext, index) {
                                  final sale = visibleSales[index];
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: EnterpriseTheme.primary
                                            .withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                sale.customer.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              money(
                                                sale.balanceAmount.clamp(
                                                  0,
                                                  double.infinity,
                                                ),
                                              ),
                                              style: const TextStyle(
                                                color: EnterpriseTheme.error,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${sale.invoiceNumber} | ${sale.items.map((item) => '${item.materialName} ${kg(item.weightKg)} @ ${money(item.rate)}').join(', ')}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          sale.reminderSentAt == null
                                              ? 'Reminder: Not sent'
                                              : 'Reminder: Sent by ${sale.reminderSentBy.isEmpty ? 'staff' : sale.reminderSentBy} on ${shortDate(sale.reminderSentAt!)}',
                                          style: TextStyle(
                                            color: sale.reminderSentAt == null
                                                ? EnterpriseTheme.warning
                                                : EnterpriseTheme.success,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: sale.reminderSent
                                                  ? null
                                                  : () =>
                                                        _sendSalePaymentReminderWhatsApp(
                                                          itemContext,
                                                          ref,
                                                          sale,
                                                          includeAmount: true,
                                                        ),
                                              icon: const Icon(Icons.chat),
                                              label: Text(
                                                sale.reminderSent
                                                    ? 'Reminder Sent'
                                                    : 'Send Reminder',
                                              ),
                                            ),
                                            FilledButton.icon(
                                              onPressed: () async {
                                                final receivedAmount =
                                                    await _showSalePaymentReceivedDialog(
                                                      sheetContext,
                                                      sale,
                                                    );
                                                if (receivedAmount == null) {
                                                  return;
                                                }
                                                ref
                                                    .read(
                                                      businessProvider.notifier,
                                                    )
                                                    .markSalePaymentReceived(
                                                      sale,
                                                      receivedAmount:
                                                          receivedAmount,
                                                    );
                                                final updatedSale = sale
                                                    .copyWith(
                                                      receivedAmount:
                                                          sale.receivedAmount +
                                                          receivedAmount,
                                                      paymentReceivedAt:
                                                          DateTime.now(),
                                                      paymentReceivedBy: ref
                                                          .read(
                                                            businessProvider,
                                                          )
                                                          .user
                                                          .name,
                                                    );
                                                setSheetState(() {
                                                  if (updatedSale
                                                      .isPaymentPending) {
                                                    visibleSales[index] =
                                                        updatedSale;
                                                  } else {
                                                    visibleSales.removeAt(
                                                      index,
                                                    );
                                                  }
                                                  visibleSales.sort(
                                                    (a, b) => b.balanceAmount
                                                        .compareTo(
                                                          a.balanceAmount,
                                                        ),
                                                  );
                                                  undoSale = sale;
                                                  undoAmount = receivedAmount;
                                                });
                                                if (!modalContext.mounted) {
                                                  return;
                                                }
                                                ScaffoldMessenger.of(
                                                  modalContext,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      '${money(receivedAmount)} received for ${sale.customer.name}.',
                                                    ),
                                                    action: SnackBarAction(
                                                      label: 'UNDO',
                                                      onPressed: () => ref
                                                          .read(
                                                            businessProvider
                                                                .notifier,
                                                          )
                                                          .undoSalePaymentReceived(
                                                            sale,
                                                          ),
                                                    ),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(Icons.verified),
                                              label: const Text(
                                                'Payment Received',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PremiumDashboardHeader extends StatelessWidget {
  const _PremiumDashboardHeader({
    required this.title,
    required this.company,
    required this.activityCount,
    required this.onNotifications,
  });

  final String title;
  final String company;
  final int activityCount;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: tokens.resolvedGradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: tokens.primaryColor.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.recycling, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                company,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.resolvedMutedTextColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton.filledTonal(
              tooltip: 'Notifications',
              onPressed: onNotifications,
              icon: const Icon(Icons.notifications_none),
            ),
            if (activityCount > 0)
              Positioned(
                right: 4,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.dangerColor,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: tokens.cardColor),
                  ),
                  child: Text(
                    activityCount > 9 ? '9+' : activityCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ignore: unused_element
class _DashboardGreetingCard extends StatelessWidget {
  const _DashboardGreetingCard({
    required this.userName,
    required this.profitLoss,
  });

  final String userName;
  final double profitLoss;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
        ? 'Good Afternoon'
        : 'Good Evening';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: tokens.resolvedGradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.resolvedBorderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $userName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.isDark ? Colors.white : tokens.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  profitLoss >= 0
                      ? 'Profit is positive. Keep watching stock loss, pending payments, and sales movement.'
                      : 'Profit is negative today. Review expense, purchase rate, and pending collection.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: (tokens.isDark ? Colors.white : tokens.textColor)
                        .withValues(alpha: 0.76),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 74,
            height: 46,
            child: CustomPaint(
              painter: _SparklinePainter(
                color: tokens.secondaryColor,
                fill: tokens.secondaryColor.withValues(alpha: 0.16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumKpiCard extends StatelessWidget {
  const _PremiumKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.trend,
    required this.trendPositive,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String trend;
  final bool trendPositive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final trendColor = trendPositive ? tokens.successColor : tokens.dangerColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tokens.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.resolvedBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: tokens.isDark ? 0.22 : 0.07,
              ),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.68)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const Spacer(),
                Text(
                  trend,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.resolvedMutedTextColor,
                    fontSize: 11,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _DashboardActionStrip extends StatelessWidget {
  const _DashboardActionStrip({
    required this.onLiveActivity,
    required this.onPreview,
    required this.onInsights,
  });

  final VoidCallback onLiveActivity;
  final VoidCallback onPreview;
  final VoidCallback? onInsights;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        children: [
          FilledButton.icon(
            onPressed: onLiveActivity,
            icon: const Icon(Icons.timeline),
            label: const Text('Live Activity'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPreview,
                  icon: const Icon(Icons.preview),
                  label: const Text('View Dashboard As'),
                ),
              ),
              if (onInsights != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onInsights,
                    icon: const Icon(Icons.auto_awesome_motion),
                    label: const Text('AI Alerts'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AiBusinessInsightCard extends StatelessWidget {
  const _AiBusinessInsightCard({required this.metrics, required this.topLoss});

  final BusinessMetrics metrics;
  final _WeightLossSummaryRow? topLoss;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final positiveProfit = metrics.profitLoss >= 0;
    final message = topLoss == null
        ? positiveProfit
              ? 'Business is profitable today. Keep focusing on high margin sales and timely collection.'
              : 'Profit is under pressure. Review purchase rate, expense, and pending payments.'
        : '${topLoss!.material.name} has ${kg(topLoss!.weightLossQty)} weight loss. Please verify physical stock and sales entry.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.resolvedBorderColor),
        gradient: LinearGradient(
          colors: [
            tokens.cardColor,
            Color.alphaBlend(
              tokens.primaryColor.withValues(alpha: 0.10),
              tokens.cardColor,
            ),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tokens.secondaryColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.rocket_launch, color: tokens.secondaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Business Insight',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: TextStyle(
                    color: tokens.resolvedMutedTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _DashboardWeightLossAlertCard extends StatelessWidget {
  const _DashboardWeightLossAlertCard({required this.row, required this.onTap});

  final _WeightLossSummaryRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            tokens.dangerColor.withValues(alpha: tokens.isDark ? 0.20 : 0.10),
            tokens.cardColor,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.dangerColor.withValues(alpha: 0.38)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tokens.dangerColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning_amber, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Critical Alert: ${row.material.name} weight loss detected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.dangerColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${kg(row.weightLossQty)} loss. Last sale ${row.lastSaleLabel}. Please verify stock.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.resolvedMutedTextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: tokens.dangerColor),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _OwnerStockRiskAlertCard extends StatelessWidget {
  const _OwnerStockRiskAlertCard({
    required this.rows,
    required this.logs,
    required this.onTap,
  });

  final List<StockTargetRow> rows;
  final List<ManualReminderLog> logs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final totalLoss = rows.fold<double>(
      0,
      (runningTotal, row) => runningTotal + row.weightLoss,
    );
    final top = rows.isEmpty ? null : rows.first;
    final latestLog = logs.isEmpty ? null : logs.first;
    final status = latestLog == null
        ? 'Pending Manual Send'
        : manualReminderStatusLabel(latestLog.status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: rows.isEmpty
                ? tokens.successColor.withValues(alpha: 0.28)
                : tokens.dangerColor.withValues(alpha: 0.32),
          ),
          gradient: LinearGradient(
            colors: [
              rows.isEmpty
                  ? tokens.successColor.withValues(alpha: 0.08)
                  : tokens.dangerColor.withValues(alpha: 0.12),
              tokens.cardColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  rows.isEmpty ? Icons.verified : Icons.notification_important,
                  color: rows.isEmpty
                      ? tokens.successColor
                      : tokens.dangerColor,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Stock Risk Alerts',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Icon(Icons.chevron_right, color: tokens.resolvedMutedTextColor),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _RiskLine(
                    label: 'Highest Loss Item',
                    value: top?.material.name ?? 'No critical loss',
                  ),
                ),
                Expanded(
                  child: _RiskLine(label: 'Total Loss', value: kg(totalLoss)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _RiskLine(
                    label: 'Critical Items',
                    value: rows.length.toString(),
                  ),
                ),
                Expanded(
                  child: _RiskLine(
                    label: 'Last Reminder',
                    value: latestLog == null
                        ? '-'
                        : shortDate(latestLog.createdAt),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'WhatsApp reminder status: $status',
                style: TextStyle(
                  color: tokens.primaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskLine extends StatelessWidget {
  const _RiskLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.resolvedMutedTextColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _DashboardExpectedClosingStockPanel extends StatelessWidget {
  const _DashboardExpectedClosingStockPanel({
    required this.rows,
    required this.from,
    required this.to,
    required this.onOpen,
  });

  final List<_WeightLossSummaryRow> rows;
  final DateTime from;
  final DateTime to;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final values = rows.map((row) => row.expectedClosingStock).toList();
    final maxValue = values.fold<double>(
      1,
      (largest, value) => value > largest ? value : largest,
    );
    final minValue = values.fold<double>(
      0,
      (smallest, value) => value < smallest ? value : smallest,
    );
    final padding = ((maxValue - minValue).abs() * 0.20).clamp(10, 1000000);
    final statusColors = [
      for (final row in rows) _expectedStockStatusColor(tokens, row),
    ];
    final chartColor = statusColors.isNotEmpty
        ? statusColors.first
        : tokens.primaryColor;
    final chartGradient = statusColors.length > 1
        ? LinearGradient(
            colors: statusColors,
            stops: [
              for (var index = 0; index < statusColors.length; index++)
                index / (statusColors.length - 1),
            ],
          )
        : null;
    final chartWidth = (rows.length * 72)
        .clamp(MediaQuery.of(context).size.width - 64, 1600)
        .toDouble();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StockGraphTitleRow(
            title: 'Expected Closing Stock',
            subtitle:
                '${DateFormat('dd MMM').format(from)} to ${DateFormat('dd MMM yyyy').format(to)}',
            badge: rows.isEmpty ? 'No items' : 'All ${rows.length}',
            badgeColor: tokens.primaryColor,
            onOpen: onOpen,
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const _EmptyState(
              icon: Icons.show_chart,
              title: 'No stock items',
              subtitle: 'Expected closing stock appears after items are added.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 168,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: (rows.length - 1).toDouble().clamp(
                      1,
                      double.infinity,
                    ),
                    minY: minValue - padding,
                    maxY: maxValue + padding,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: tokens.resolvedBorderColor.withValues(
                          alpha: 0.55,
                        ),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      touchCallback: (event, response) {
                        final spots = response?.lineBarSpots;
                        if (!event.isInterestedForInteractions ||
                            spots == null ||
                            spots.isEmpty) {
                          return;
                        }
                        final index = spots.first.x.round();
                        if (index >= 0 && index < rows.length) {
                          _showStockBreakupDetails(
                            context,
                            rows[index],
                            title: 'Expected Closing Stock Details',
                          );
                        }
                      },
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => const Color(0xFF0F172A),
                        getTooltipItems: (spots) => spots.map((spot) {
                          final index = spot.x.round();
                          final safeIndex = index
                              .clamp(0, rows.length - 1)
                              .toInt();
                          final row = rows[safeIndex];
                          return LineTooltipItem(
                            '${row.material.name}\n${kg(row.expectedClosingStock)}\n${_expectedStockStatusLabel(row)}',
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 42,
                          getTitlesWidget: (value, meta) => Text(
                            _compactKg(value),
                            style: TextStyle(
                              color: tokens.resolvedMutedTextColor,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.round();
                            if ((value - index).abs() > 0.001 ||
                                index < 0 ||
                                index >= rows.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Transform.rotate(
                                angle: rows.length > 3 ? -0.55 : 0,
                                child: SizedBox(
                                  width: 64,
                                  child: Text(
                                    _shortItemLabel(rows[index].material.name),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: rows.length > 3
                                        ? TextAlign.right
                                        : TextAlign.center,
                                    style: TextStyle(
                                      color: tokens.resolvedMutedTextColor,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var index = 0; index < rows.length; index++)
                            FlSpot(
                              index.toDouble(),
                              rows[index].expectedClosingStock,
                            ),
                        ],
                        isCurved: rows.length > 2,
                        color: chartGradient == null ? chartColor : null,
                        gradient: chartGradient,
                        barWidth: 3,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, index) {
                            final rowIndex = spot.x.round();
                            final dotColor =
                                rowIndex >= 0 && rowIndex < statusColors.length
                                ? statusColors[rowIndex]
                                : chartColor;
                            return FlDotCirclePainter(
                              radius: 4.8,
                              color: dotColor,
                              strokeWidth: 2,
                              strokeColor: tokens.cardColor,
                            );
                          },
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: chartColor.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Color _expectedStockStatusColor(
  AppThemeModel tokens,
  _WeightLossSummaryRow row,
) {
  if (row.stockDifference < -0.01) {
    return tokens.dangerColor;
  }
  if (row.stockDifference > 0.01) {
    return tokens.successColor;
  }
  return tokens.primaryColor;
}

String _expectedStockStatusLabel(_WeightLossSummaryRow row) {
  if (row.stockDifference < -0.01) {
    return 'Weight Loss';
  }
  if (row.stockDifference > 0.01) {
    return 'Weight Increase';
  }
  return 'No Difference';
}

class _StockGraphTitleRow extends StatelessWidget {
  const _StockGraphTitleRow({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.onOpen,
  });

  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.resolvedMutedTextColor,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            badge,
            style: TextStyle(
              color: badgeColor,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Details',
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new, size: 18),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _DashboardWeightLossMiniTable extends StatelessWidget {
  const _DashboardWeightLossMiniTable({required this.rows});

  final List<_WeightLossSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return _Panel(
      title: 'Weight Loss Breakup',
      child: rows.isEmpty
          ? _EmptyState(
              icon: Icons.table_rows,
              title: 'No critical rows',
              subtitle: 'Positive weight loss rows will appear here.',
            )
          : Column(
              children: [
                for (final row in rows.take(5)) ...[
                  InkWell(
                    onTap: () => _showWeightLossDetails(context, row),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              row.material.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              kg(row.weightLossQty),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: tokens.dangerColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _LossStatusChip(loss: row.weightLossQty),
                        ],
                      ),
                    ),
                  ),
                  if (row != rows.take(5).last)
                    Divider(color: tokens.resolvedBorderColor, height: 1),
                ],
              ],
            ),
    );
  }
}

class _LossStatusChip extends StatelessWidget {
  const _LossStatusChip({required this.loss});

  final double loss;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final label = loss > 100
        ? 'Critical'
        : loss > 25
        ? 'Warning'
        : 'Low';
    final color = loss > 100
        ? tokens.dangerColor
        : loss > 25
        ? tokens.warningColor
        : tokens.successColor;
    return Container(
      width: 74,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ignore: unused_element
class _ProfitOverviewPanel extends StatelessWidget {
  const _ProfitOverviewPanel({required this.state});

  final BusinessState state;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final spots = _profitSpotsForMonth(state);
    final values = spots.map((spot) => spot.y).toList();
    final maxValue = values.fold<double>(
      1,
      (largest, value) => value > largest ? value : largest,
    );
    final minValue = values.fold<double>(
      0,
      (smallest, value) => value < smallest ? value : smallest,
    );
    final padding = ((maxValue - minValue).abs() * 0.18).clamp(100, 1000000);
    final lineColor = state.metrics.profitLoss >= 0
        ? tokens.successColor
        : tokens.dangerColor;
    return _Panel(
      title: 'Profit Overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total Profit',
                  style: TextStyle(
                    color: tokens.resolvedMutedTextColor,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                money(state.metrics.profitLoss),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: LineChart(
              LineChartData(
                minX: 1,
                maxX: spots.isEmpty ? 1 : spots.last.x,
                minY: minValue - padding,
                maxY: maxValue + padding,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: tokens.resolvedBorderColor.withValues(alpha: 0.55),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF0F172A),
                    getTooltipItems: (items) => items
                        .map(
                          (spot) => LineTooltipItem(
                            'Day ${spot.x.toInt()}\n${money(spot.y)}',
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) => Text(
                        _compactMoney(value),
                        style: TextStyle(
                          color: tokens.resolvedMutedTextColor,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 5,
                      getTitlesWidget: (value, meta) {
                        final day = value.toInt();
                        if (day == 1 || day % 5 == 0) {
                          return Text(
                            day.toString().padLeft(2, '0'),
                            style: TextStyle(
                              color: tokens.resolvedMutedTextColor,
                              fontSize: 9,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots.isEmpty ? const [FlSpot(1, 0)] : spots,
                    isCurved: true,
                    color: lineColor,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: lineColor.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _QuickActionsPanel extends StatelessWidget {
  const _QuickActionsPanel({required this.actions});

  final List<_QuickActionSpec> actions;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Quick Actions',
      child: Row(
        children: [
          for (final action in actions)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: action == actions.last ? 0 : 8),
                child: _QuickActionButton(action: action),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickActionSpec {
  const _QuickActionSpec({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.action});

  final _QuickActionSpec action;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(action.icon, color: action.color, size: 19),
          ),
          const SizedBox(height: 6),
          Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.resolvedMutedTextColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.color, required this.fill});

  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [0.18, 0.30, 0.26, 0.48, 0.40, 0.72, 0.60, 0.86];
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y = size.height * (1 - values[index]);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y = size.height * (1 - values[index]);
      canvas.drawCircle(Offset(x, y), 2.4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.fill != fill;
  }
}

class PurchaseTab extends ConsumerWidget {
  const PurchaseTab({super.key, required this.page});

  final DynamicPageDefinition page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    return _ListModule(
      title: page.title,
      subtitle: page.subtitle,
      emptyTitle: 'No purchases saved',
      emptySubtitle: 'Tap New ${page.title} to enter the first supplier bill.',
      buttonLabel: 'New ${page.title}',
      icon: _iconFromName('purchase'),
      onAdd: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PurchaseEditorScreen())),
      children: [
        for (final purchase in state.activePurchases)
          _purchaseTile(context, ref, purchase),
      ],
    );
  }

  Widget _purchaseTile(
    BuildContext context,
    WidgetRef ref,
    PurchaseRecord purchase,
  ) {
    final notifier = ref.read(businessProvider.notifier);
    final canEdit = notifier.canEditPurchase(purchase);
    final editMessage = notifier.purchaseEditExpiredMessage(purchase);
    void openEditor() {
      if (!canEdit) {
        notifier.recordPurchaseEditBlocked(purchase);
        _snack(context, editMessage);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PurchaseEditorScreen(purchase: purchase),
        ),
      );
    }

    return FeatureRecordTile(
      title: purchase.seller.name,
      subtitle:
          '${purchase.invoiceNumber}  |  ${shortDate(purchase.createdAt)}  |  By ${purchase.createdBy}  |  ${purchase.items.map((item) => item.materialName).join(', ')}  |  ${kg(purchase.totalWeightKg)}',
      amount: money(purchase.totalAmount),
      status: purchase.balanceAmount > 0
          ? 'Balance ${money(purchase.balanceAmount)}'
          : 'Paid',
      statusColor: purchase.balanceAmount > 0
          ? EnterpriseTheme.warning
          : EnterpriseTheme.success,
      avatarPath: purchase.seller.photoPath,
      onWhatsApp: () => _sendPurchaseWhatsApp(context, ref, purchase),
      onInvoicePdf: () => showPurchaseInvoicePdfActions(context, ref, purchase),
      onView: () {
        showRecordDetails(
          context,
          purchase.invoiceNumber,
          [
            ['Seller', purchase.seller.name],
            ['Purchase Added By', purchase.createdBy],
            [
              'Items',
              purchase.items
                  .map(
                    (item) =>
                        '${item.materialName} ${kg(item.weightKg)} @ ${money(item.rate)}',
                  )
                  .join('\n'),
            ],
            ['Total Weight', kg(purchase.totalWeightKg)],
            ['Total Amount', money(purchase.totalAmount)],
            ['Date', DateFormat('dd MMM yyyy').format(purchase.createdAt)],
            ['Time', DateFormat('hh:mm a').format(purchase.createdAt)],
            ['Remarks', purchase.remarks],
          ],
          actions: [
            OutlinedButton.icon(
              onPressed: () => _sendPurchaseWhatsApp(context, ref, purchase),
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  showPurchaseInvoicePdfActions(context, ref, purchase),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Invoice PDF'),
            ),
            if (canEdit)
              OutlinedButton.icon(
                onPressed: openEditor,
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  editMessage,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        );
      },
      onEdit: openEditor,
      onDelete: () => _confirm(
        context,
        'Move to Recycle Bin?',
        '${purchase.invoiceNumber} can be restored by owner within ${BusinessController.recycleBinRetention.inDays} days.',
        () => ref.read(businessProvider.notifier).softDeletePurchase(purchase),
      ),
      showEdit: canEdit,
      showDelete: notifier.canModifyPurchase(purchase),
      lockedEditMessage: editMessage,
    );
  }
}

class SalesTab extends ConsumerWidget {
  const SalesTab({super.key, required this.page});

  final DynamicPageDefinition page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    final isOwner = state.user.role.isOwnerOrAdmin;
    final isManager = state.user.role == UserRole.manager;
    final visibleSales = isOwner
        ? state.activeSales
        : isManager
        ? state.activeSales
        : state.activeSales
              .where((sale) => _sameStaffName(sale.createdBy, state.user.name))
              .toList();
    return _ListModule(
      title: page.title,
      subtitle: isOwner
          ? page.subtitle
          : isManager
          ? 'Sales history is visible, but amount and rate details are hidden.'
          : 'Your sales history is visible, but amount and rate details are hidden.',
      emptyTitle: 'No sales invoices',
      emptySubtitle: isOwner
          ? 'Tap New ${page.title} to create a customer invoice.'
          : 'Tap New ${page.title} to create a sale entry. Amount details are owner-only.',
      buttonLabel: 'New ${page.title}',
      icon: _iconFromName('sales'),
      onAdd: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SaleEditorScreen())),
      children: [
        for (final sale in visibleSales)
          _saleTile(context, ref, sale, isOwner, isManager),
      ],
    );
  }

  Widget _saleTile(
    BuildContext context,
    WidgetRef ref,
    SaleRecord sale,
    bool isOwner,
    bool isManager,
  ) {
    final notifier = ref.read(businessProvider.notifier);
    final canModify = notifier.canModifySale(sale);
    final lockedMessage = notifier.saleEditExpiredMessage(sale);
    final paymentStatus = sale.isPaymentPending
        ? 'Payment Pending'
        : 'Payment Received';
    final reminderStatus = sale.reminderSentAt == null
        ? 'Reminder not sent'
        : 'Reminder sent by ${sale.reminderSentBy.isEmpty ? 'staff' : sale.reminderSentBy} on ${shortDate(sale.reminderSentAt!)}';

    void openEditor() {
      if (!canModify) {
        _snack(context, notifier.saleEditExpiredMessage(sale));
        return;
      }
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => SaleEditorScreen(sale: sale)));
    }

    return FeatureRecordTile(
      title: sale.customer.name,
      subtitle:
          '${sale.invoiceNumber}  |  ${shortDate(sale.createdAt)}  |  By ${sale.createdBy}  |  ${sale.items.map((item) => item.materialName).join(', ')}  |  ${kg(sale.totalWeightKg)}',
      amount: isOwner ? money(sale.totalAmount) : '',
      status: isOwner
          ? (sale.isPaymentPending
                ? 'Due ${money(sale.balanceAmount)}'
                : 'Received')
          : paymentStatus,
      statusColor: sale.isPaymentPending
          ? EnterpriseTheme.error
          : EnterpriseTheme.success,
      avatarPath: sale.customer.photoPath,
      onWhatsApp:
          (isOwner || isManager) && sale.isPaymentPending && !sale.reminderSent
          ? () => _sendSalePaymentReminderWhatsApp(
              context,
              ref,
              sale,
              includeAmount: isOwner,
            )
          : null,
      onView: () => showRecordDetails(
        context,
        sale.invoiceNumber,
        [
          ['Customer', sale.customer.name],
          ['Sale Added By', sale.createdBy],
          [
            'Material',
            sale.items
                .map(
                  (item) => isOwner
                      ? '${item.materialName} ${kg(item.weightKg)} @ ${money(item.rate)}'
                      : '${item.materialName} ${kg(item.weightKg)}',
                )
                .join('\n'),
          ],
          ['Total Sale Weight', kg(sale.totalWeightKg)],
          ['Payment Status', paymentStatus],
          ['Reminder Status', reminderStatus],
          if (isOwner) ...[
            ['Invoice Amount', money(sale.totalAmount)],
            ['Paid Amount', money(sale.receivedAmount)],
            ['Pending', money(sale.balanceAmount.clamp(0, double.infinity))],
          ],
          ['Date', shortDate(sale.createdAt)],
          ['Remarks', sale.remarks],
        ],
        actions: [
          if ((isOwner || isManager) &&
              sale.isPaymentPending &&
              !sale.reminderSent)
            OutlinedButton.icon(
              onPressed: () => _sendSalePaymentReminderWhatsApp(
                context,
                ref,
                sale,
                includeAmount: isOwner,
              ),
              icon: const Icon(Icons.notification_important),
              label: const Text('Send Reminder'),
            ),
          if (isOwner) ...[
            OutlinedButton.icon(
              onPressed: () => _sendSaleWhatsApp(context, ref, sale),
              icon: const Icon(Icons.chat),
              label: const Text('Invoice WhatsApp'),
            ),
            OutlinedButton.icon(
              onPressed: () => shareSalesInvoicePdf(context, ref, sale),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Invoice PDF'),
            ),
            if (sale.isPaymentPending)
              FilledButton.icon(
                onPressed: () async {
                  final receivedAmount = await _showSalePaymentReceivedDialog(
                    context,
                    sale,
                  );
                  if (receivedAmount == null) {
                    return;
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  notifier.markSalePaymentReceived(
                    sale,
                    receivedAmount: receivedAmount,
                  );
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${money(receivedAmount)} received for ${sale.customer.name}.',
                      ),
                      action: SnackBarAction(
                        label: 'UNDO',
                        onPressed: () => ref
                            .read(businessProvider.notifier)
                            .undoSalePaymentReceived(sale),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.verified),
                label: const Text('Mark Payment Received'),
              ),
          ],
          if (!canModify)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                lockedMessage,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      onEdit: openEditor,
      onDelete: () {
        if (!canModify) {
          _snack(context, notifier.saleDeleteExpiredMessage(sale));
          return;
        }
        _confirm(
          context,
          'Move to Recycle Bin?',
          '${sale.invoiceNumber} can be restored by owner within ${BusinessController.recycleBinRetention.inDays} days.',
          () => notifier.softDeleteSale(sale),
        );
      },
      showEdit: canModify,
      showDelete: canModify,
      lockedEditMessage: lockedMessage,
    );
  }
}

bool _sameStaffName(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();

class InventoryTab extends ConsumerStatefulWidget {
  const InventoryTab({super.key, required this.page});

  final DynamicPageDefinition page;

  @override
  ConsumerState<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends ConsumerState<InventoryTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final isOwner = state.user.role.isOwnerOrAdmin;
    final materials = state.activeMaterials
        .where((item) => item.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppHeader(
            title: widget.page.title,
            subtitle: widget.page.subtitle,
            trailing: isOwner
                ? IconButton.filled(
                    tooltip: 'Add material',
                    onPressed: () => showMaterialEditor(context, ref),
                    icon: const Icon(Icons.add),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search material',
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: materials.isEmpty
                ? const _EmptyState(
                    icon: Icons.inventory_2,
                    title: 'No matching stock',
                    subtitle: 'Add material or adjust the search filter.',
                  )
                : ListView.separated(
                    itemCount: materials.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final material = materials[index];
                      return _InventoryTile(
                        material: material,
                        canManage: isOwner,
                        onEdit: () => showMaterialEditor(
                          context,
                          ref,
                          existing: material,
                        ),
                        onAdjust: () => showInventoryAdjustmentDialog(
                          context,
                          ref,
                          material,
                        ),
                        onDelete: () => _confirm(
                          context,
                          'Delete Inventory?',
                          '${material.name} will be hidden from active stock and added to the audit trail.',
                          () => ref
                              .read(businessProvider.notifier)
                              .deleteMaterial(material),
                          confirmLabel: 'Delete',
                          successMessage: 'Inventory deleted',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _InventoryTile extends StatelessWidget {
  const _InventoryTile({
    required this.material,
    required this.canManage,
    required this.onEdit,
    required this.onAdjust,
    required this.onDelete,
  });

  final MaterialStock material;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onAdjust;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Column(
        children: [
          Row(
            children: [
              EntityAvatar(path: material.photoPath, icon: Icons.recycling),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${material.category}  |  ${material.isActive ? 'Active' : 'Inactive'}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                canManage
                    ? '${kg(material.availableKg)}\n${money(material.stockValue)}'
                    : kg(material.availableKg),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAdjust,
                    icon: const Icon(Icons.tune),
                    label: const Text('Adjust'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Delete inventory',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class MoreTab extends ConsumerWidget {
  const MoreTab({
    super.key,
    required this.page,
    required this.config,
    required this.onNavigate,
  });

  final DynamicPageDefinition page;
  final DynamicConfigState config;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    final authProfile = ref.watch(authProfileProvider);
    final isOwner =
        authProfile?.role.isOwnerOrAdmin == true ||
        state.user.role.isOwnerOrAdmin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppHeader(title: page.title, subtitle: page.subtitle),
          const SizedBox(height: 14),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.25,
              children: [
                if (isOwner) ...[
                  _ModuleCard(
                    title: 'Owner Dashboard',
                    subtitle: 'Users, login and activity',
                    icon: Icons.supervisor_account,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OwnerSupervisorAdminScreen(),
                      ),
                    ),
                  ),
                  _ModuleCard(
                    title: 'Staff Dashboard View',
                    subtitle: 'View Supervisor and Manager dashboards',
                    icon: Icons.co_present,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StaffDashboardViewScreen(),
                      ),
                    ),
                  ),
                  _ModuleCard(
                    title: 'Permission Center',
                    subtitle: 'Role templates and field access',
                    icon: Icons.admin_panel_settings,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OwnerPermissionCenterScreen(),
                      ),
                    ),
                  ),
                  _ModuleCard(
                    title: 'Owner Expense Center',
                    subtitle: 'Salary, overhead and P&L expense layer',
                    icon: Icons.receipt_long,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OwnerExpenseCenterScreen(),
                      ),
                    ),
                  ),
                ],
                _ModuleCard(
                  title: 'Sellers',
                  subtitle: '${state.sellers.length} accounts',
                  icon: Icons.storefront,
                  onTap: () =>
                      _showPartyManager(context, ref, PartyKind.seller),
                ),
                _ModuleCard(
                  title: 'Customers',
                  subtitle: '${state.customers.length} accounts',
                  icon: Icons.people,
                  onTap: () =>
                      _showPartyManager(context, ref, PartyKind.customer),
                ),
                if (aiEnabled)
                  _ModuleCard(
                    title: 'AI',
                    subtitle: 'Assistant, insights and risk',
                    icon: Icons.auto_awesome,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AiCenterScreen()),
                    ),
                  ),
                if (aiEnabled)
                  _ModuleCard(
                    title: 'Risk Center',
                    subtitle: 'Critical alerts and filters',
                    icon: Icons.warning_amber,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AiRiskCenterScreen(),
                      ),
                    ),
                  ),
                _ModuleCard(
                  title: 'Theme Settings',
                  subtitle: 'Premium app themes',
                  icon: Icons.palette,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ThemeSettingsScreen(),
                    ),
                  ),
                ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Stock Reminder Settings',
                    subtitle: 'Manual WhatsApp receivers',
                    icon: Icons.notifications_active,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StockReminderSettingsScreen(),
                      ),
                    ),
                  ),
                _ModuleCard(
                  title: 'Expected Closing Stock',
                  subtitle: 'Expected stock graph and details',
                  icon: Icons.show_chart,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ExpectedClosingStockScreen(),
                    ),
                  ),
                ),
                _ModuleCard(
                  title: 'Weight Loss Summary',
                  subtitle: 'Loss graph and item breakup',
                  icon: Icons.bar_chart,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WeightLossSummaryScreen(),
                    ),
                  ),
                ),
                for (final item in config.visibleMoreMenu.where(
                  (item) =>
                      isOwner ||
                      (item.routeKey != 'reports' &&
                          item.routeKey != 'finance'),
                ))
                  _ModuleCard(
                    title: item.label,
                    subtitle: config.pageFor(item.pageId).subtitle,
                    icon: _iconFromName(item.icon),
                    onTap: () => onNavigate(item.routeKey),
                  ),
                _ModuleCard(
                  title: 'Security',
                  subtitle: state.user.role.name.toUpperCase(),
                  icon: Icons.verified_user,
                  onTap: () => _showInfo(
                    context,
                    'Role Based Access',
                    'Owner: full access\nUser/Supervisor: app dashboard access\nAccountant: payment and reports',
                  ),
                ),
                _ModuleCard(
                  title: 'Fast Scrap Entry',
                  subtitle: 'Photo and voice mode',
                  icon: Icons.bolt,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FastScrapEntryScreen(),
                    ),
                  ),
                ),
                _ModuleCard(
                  title: 'Document AI Review',
                  subtitle: 'Bill proof and duplicate check',
                  icon: Icons.document_scanner,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DocumentAiReviewScreen(),
                    ),
                  ),
                ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Seller-wise Purchase Report',
                    subtitle: 'Supplier totals and pending',
                    icon: Icons.storefront,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ReportCenterScreen(
                          initialReport: 'Purchase Report',
                          initialFilter: 'Monthly',
                        ),
                      ),
                    ),
                  ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Customer-wise Sales Report',
                    subtitle: 'Customer totals and pending',
                    icon: Icons.people,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ReportCenterScreen(
                          initialReport: 'Sales Report',
                          initialFilter: 'Monthly',
                        ),
                      ),
                    ),
                  ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Confidential Profit Analytics',
                    subtitle: 'Owner only',
                    icon: Icons.lock,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ConfidentialProfitScreen(),
                      ),
                    ),
                  ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Opening Stock',
                    subtitle: 'Starting material balances',
                    icon: Icons.inventory,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OpeningStockScreen(),
                      ),
                    ),
                  ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Cash Ledger',
                    subtitle: money(state.metrics.cashBalance),
                    icon: Icons.account_balance_wallet,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CashLedgerScreen(),
                      ),
                    ),
                  ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Cash Allocation',
                    subtitle: 'Owner to supervisor',
                    icon: Icons.payments,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CashAllocationScreen(),
                      ),
                    ),
                  ),
                _ModuleCard(
                  title: 'Supervisor Expenses',
                  subtitle: '${state.activeExpenses.length} records',
                  icon: Icons.receipt_long,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SupervisorExpenseScreen(),
                    ),
                  ),
                ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Supervisor Balance',
                    subtitle: money(state.metrics.cashBalance),
                    icon: Icons.account_balance,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SupervisorBalanceScreen(),
                      ),
                    ),
                  ),
                _ModuleCard(
                  title: 'Voice Entry',
                  subtitle: 'Hindi, English, Hinglish',
                  icon: Icons.mic,
                  onTap: () => onNavigate('voice_entry'),
                ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Audit Trail',
                    subtitle: '${state.auditTrail.length} entries',
                    icon: Icons.fact_check,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AuditTrailScreen(),
                      ),
                    ),
                  ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Recycle Bin',
                    subtitle:
                        'Restore within ${BusinessController.recycleBinRetention.inDays} days',
                    icon: Icons.restore,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DeletedTransactionsScreen(),
                      ),
                    ),
                  ),
                if (isOwner)
                  _ModuleCard(
                    title: 'Owner Analytics',
                    subtitle: 'Trends and top lists',
                    icon: Icons.analytics,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OwnerAnalyticsScreen(),
                      ),
                    ),
                  ),
                _ModuleCard(
                  title: 'Settings',
                  subtitle: 'Theme, simple mode, backup',
                  icon: Icons.settings,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AppSettingsScreen(),
                    ),
                  ),
                ),
                if (authProfile != null)
                  _ModuleCard(
                    title: 'Logout',
                    subtitle: authProfile.email,
                    icon: Icons.logout,
                    onTap: () async {
                      await FirebaseLoginService().signOut(authProfile);
                      ref.read(authProfileProvider.notifier).clear();
                    },
                  ),
                if (const bool.fromEnvironment('DEVELOPER_MODE')) ...[
                  _ModuleCard(
                    title: 'Firebase Config',
                    subtitle: config.loadedFromFirebase
                        ? 'Realtime active'
                        : 'Using defaults',
                    icon: Icons.cloud_done,
                    onTap: () => _showDynamicConfigStatus(context, config),
                  ),
                  _ModuleCard(
                    title: 'Supabase',
                    subtitle: SupabaseBusinessGateway.isConfigured
                        ? 'Connected'
                        : 'Schema ready',
                    icon: Icons.cloud_sync,
                    onTap: () => _showSupabase(context),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StaffDashboardViewScreen extends ConsumerStatefulWidget {
  const StaffDashboardViewScreen({super.key});

  @override
  ConsumerState<StaffDashboardViewScreen> createState() =>
      _StaffDashboardViewScreenState();
}

class _StaffDashboardViewScreenState
    extends ConsumerState<StaffDashboardViewScreen> {
  final _loginService = FirebaseLoginService();
  String _query = '';
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    if (!state.user.role.isOwnerOrAdmin) {
      return const Scaffold(
        body: SafeArea(
          child: _EmptyState(
            icon: Icons.lock,
            title: 'Owner/Admin only',
            subtitle: 'Staff dashboard monitoring is restricted.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Staff Dashboard View')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _loginService.watchUsers(),
        builder: (context, snapshot) {
          final accounts = _staffAccountsFromDocs(
            snapshot.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[],
          );
          final summaries = _staffDashboardSummaries(state, accounts: accounts)
              .where(_matchesFilter)
              .where((item) {
                final needle = _query.trim().toLowerCase();
                if (needle.isEmpty) {
                  return true;
                }
                return item.name.toLowerCase().contains(needle) ||
                    item.mobile.toLowerCase().contains(needle) ||
                    item.email.toLowerCase().contains(needle);
              })
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _AppHeader(
                title: 'Staff Dashboard View',
                subtitle: 'Open live Supervisor and Manager dashboard preview',
              ),
              const SizedBox(height: 12),
              FeaturePanel(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.privacy_tip_outlined),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Owner can see staff login email and live dashboard. Password is not displayed because Firebase keeps passwords protected. Use Reset Password when staff forgets password.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              if (snapshot.hasError) ...[
                const SizedBox(height: 10),
                FeaturePanel(
                  child: Text(
                    'Registered users could not be loaded. Showing dashboard names from app entries only. ${snapshot.error}',
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search by name/mobile/email',
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(
                      value: 'supervisor',
                      label: Text('Supervisor'),
                    ),
                    ButtonSegment(value: 'manager', label: Text('Manager')),
                    ButtonSegment(value: 'online', label: Text('Online')),
                    ButtonSegment(value: 'today', label: Text('Today Active')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.first),
                ),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  summaries.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (summaries.isEmpty)
                const _EmptyState(
                  icon: Icons.co_present,
                  title: 'No staff activity',
                  subtitle: 'Supervisor and Manager activity will appear here.',
                )
              else
                for (final item in summaries) ...[
                  _StaffDashboardCard(summary: item),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }

  bool _matchesFilter(_StaffDashboardSummary item) {
    return switch (_filter) {
      'supervisor' => item.role == UserRole.supervisor,
      'manager' => item.role == UserRole.manager,
      'online' => item.status == _StaffLiveStatus.online,
      'today' => item.todayActive,
      _ => true,
    };
  }
}

class _StaffDashboardCard extends ConsumerWidget {
  const _StaffDashboardCard({required this.summary});

  final _StaffDashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final statusColor = switch (summary.status) {
      _StaffLiveStatus.online => tokens.successColor,
      _StaffLiveStatus.todayActive => tokens.warningColor,
      _StaffLiveStatus.offline => tokens.resolvedMutedTextColor,
    };

    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                child: Icon(
                  summary.role == UserRole.manager
                      ? Icons.manage_accounts
                      : Icons.supervisor_account,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${summary.role.label}  |  ${summary.mobile.isEmpty ? 'No mobile' : summary.mobile}',
                      style: TextStyle(
                        color: tokens.resolvedMutedTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusDot(label: summary.statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            summary.assignedShop,
            style: TextStyle(
              color: tokens.resolvedMutedTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _StaffCredentialLine(
            icon: Icons.email_outlined,
            label: 'Login Email',
            value: summary.email.isEmpty
                ? 'Not registered in Firebase users'
                : summary.email,
          ),
          const SizedBox(height: 6),
          const _StaffCredentialLine(
            icon: Icons.lock_outline,
            label: 'Password',
            value: 'Hidden / protected. Use Reset Password.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniSummaryChip('Purchase', summary.todayPurchaseCount),
              _MiniSummaryChip('Sales', summary.todaySalesCount),
              _MiniSummaryChip('Payment', summary.todayPaymentCount),
              _MiniSummaryChip('Stock', summary.todayStockUpdateCount),
              _MiniSummaryChip('Pending', summary.todayPendingTaskCount),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Last activity: ${summary.lastActivityLabel}',
            style: TextStyle(color: tokens.resolvedMutedTextColor),
          ),
          Text(
            'Last login: ${summary.lastLoginLabel}',
            style: TextStyle(
              color: tokens.resolvedMutedTextColor,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: summary.email.isEmpty
                    ? null
                    : () async {
                        try {
                          await FirebaseLoginService().sendPasswordReset(
                            summary.email,
                          );
                          if (context.mounted) {
                            _snack(
                              context,
                              'Password reset link sent to ${summary.email}',
                            );
                          }
                        } on Object catch (error) {
                          if (context.mounted) {
                            _snack(context, error.toString());
                          }
                        }
                      },
                icon: const Icon(Icons.password),
                label: const Text('Reset Password'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          _StaffDashboardViewAsScreen(summary: summary),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Live Dashboard'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaffCredentialLine extends StatelessWidget {
  const _StaffCredentialLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tokens.resolvedMutedTextColor),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: tokens.resolvedMutedTextColor,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _StaffDashboardViewAsScreen extends ConsumerStatefulWidget {
  const _StaffDashboardViewAsScreen({required this.summary});

  final _StaffDashboardSummary summary;

  @override
  ConsumerState<_StaffDashboardViewAsScreen> createState() =>
      _StaffDashboardViewAsScreenState();
}

class _StaffDashboardViewAsScreenState
    extends ConsumerState<_StaffDashboardViewAsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(businessProvider.notifier)
          .recordStaffDashboardViewStarted(
            staffName: widget.summary.name,
            staffRole: widget.summary.role,
          ),
    );
  }

  @override
  void dispose() {
    ref
        .read(businessProvider.notifier)
        .recordStaffDashboardViewEnded(
          staffName: widget.summary.name,
          staffRole: widget.summary.role,
        );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.summary.name} Dashboard')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: tokens.primaryColor.withValues(alpha: 0.10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.visibility),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Owner viewing as ${widget.summary.name} - ${widget.summary.role.label}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Exit'),
                    ),
                  ],
                ),
                if (widget.summary.email.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Login email: ${widget.summary.email}',
                    style: TextStyle(
                      color: tokens.resolvedMutedTextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _openStaffPurchaseEditor(context),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('New Purchase'),
                ),
                FilledButton.icon(
                  onPressed: () => _openStaffSaleEditor(context),
                  icon: const Icon(Icons.add_business),
                  label: const Text('New Sale'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openStaffRegister(
                    context,
                    _StaffTransactionKind.purchase,
                  ),
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: const Text('Purchase Register'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _openStaffRegister(context, _StaffTransactionKind.sale),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Sales Register'),
                ),
              ],
            ),
          ),
          Expanded(
            child: OperationalDashboard(
              onNavigate: (routeKey) {
                if (routeKey == 'purchase') {
                  _openStaffRegister(context, _StaffTransactionKind.purchase);
                  return;
                }
                if (routeKey == 'sales') {
                  _openStaffRegister(context, _StaffTransactionKind.sale);
                  return;
                }
              },
              previewRole: widget.summary.role,
              previewName: widget.summary.name,
              previewEmail: widget.summary.email,
              previewMobile: widget.summary.mobile,
              embedded: true,
            ),
          ),
        ],
      ),
    );
  }

  void _openStaffPurchaseEditor(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PurchaseEditorScreen(initialCreatedBy: widget.summary.name),
      ),
    );
  }

  void _openStaffSaleEditor(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleEditorScreen(initialCreatedBy: widget.summary.name),
      ),
    );
  }

  void _openStaffRegister(BuildContext context, _StaffTransactionKind kind) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StaffTransactionRegisterScreen(
          summary: widget.summary,
          kind: kind,
        ),
      ),
    );
  }
}

enum _StaffTransactionKind { purchase, sale }

class _StaffTransactionRegisterScreen extends ConsumerWidget {
  const _StaffTransactionRegisterScreen({
    required this.summary,
    required this.kind,
  });

  final _StaffDashboardSummary summary;
  final _StaffTransactionKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    final purchases = state.activePurchases
        .where((item) => _sameStaffPerson(item.createdBy, summary.name))
        .toList();
    final sales = state.activeSales
        .where((item) => _sameStaffPerson(item.createdBy, summary.name))
        .toList();
    final isPurchase = kind == _StaffTransactionKind.purchase;
    final recordsCount = isPurchase ? purchases.length : sales.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isPurchase ? '${summary.name} Purchases' : '${summary.name} Sales',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => isPurchase
                ? PurchaseEditorScreen(initialCreatedBy: summary.name)
                : SaleEditorScreen(initialCreatedBy: summary.name),
          ),
        ),
        icon: const Icon(Icons.add),
        label: Text(isPurchase ? 'New Purchase' : 'New Sale'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${summary.name} - ${summary.role.label}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Owner view: add, edit, delete and correct Added By for this staff.',
                  style: TextStyle(
                    color: EnterpriseTheme.tokensOf(
                      context,
                    ).resolvedMutedTextColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MiniSummaryChip(
                      isPurchase ? 'Purchases' : 'Sales',
                      recordsCount,
                    ),
                    _MiniSummaryChip(
                      'Today Purchase',
                      summary.todayPurchaseCount,
                    ),
                    _MiniSummaryChip('Today Sales', summary.todaySalesCount),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._transactionTiles(context, ref, purchases, sales, isPurchase),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  List<Widget> _transactionTiles(
    BuildContext context,
    WidgetRef ref,
    List<PurchaseRecord> purchases,
    List<SaleRecord> sales,
    bool isPurchase,
  ) {
    if (isPurchase) {
      if (purchases.isEmpty) {
        return const [
          _EmptyState(
            icon: Icons.shopping_cart,
            title: 'No purchase found',
            subtitle: 'Tap New Purchase to add purchase for this staff.',
          ),
        ];
      }
      return [
        for (final purchase in purchases) ...[
          _staffPurchaseTile(context, ref, purchase),
          const SizedBox(height: 10),
        ],
      ];
    }

    if (sales.isEmpty) {
      return const [
        _EmptyState(
          icon: Icons.receipt_long,
          title: 'No sale found',
          subtitle: 'Tap New Sale to add sale for this staff.',
        ),
      ];
    }
    return [
      for (final sale in sales) ...[
        _staffSaleTile(context, ref, sale),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _staffPurchaseTile(
    BuildContext context,
    WidgetRef ref,
    PurchaseRecord purchase,
  ) {
    final notifier = ref.read(businessProvider.notifier);
    void openEditor() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PurchaseEditorScreen(
            purchase: purchase,
            initialCreatedBy: summary.name,
          ),
        ),
      );
    }

    return FeatureRecordTile(
      title: purchase.seller.name,
      subtitle:
          '${purchase.invoiceNumber}  |  ${shortDate(purchase.createdAt)}  |  By ${purchase.createdBy}  |  ${purchase.items.map((item) => item.materialName).join(', ')}  |  ${kg(purchase.totalWeightKg)}',
      amount: money(purchase.totalAmount),
      status: purchase.balanceAmount > 0
          ? 'Balance ${money(purchase.balanceAmount)}'
          : 'Paid',
      statusColor: purchase.balanceAmount > 0
          ? EnterpriseTheme.warning
          : EnterpriseTheme.success,
      avatarPath: purchase.seller.photoPath,
      icon: Icons.shopping_cart,
      onWhatsApp: () => _sendPurchaseWhatsApp(context, ref, purchase),
      onInvoicePdf: () => showPurchaseInvoicePdfActions(context, ref, purchase),
      onView: () => showRecordDetails(
        context,
        purchase.invoiceNumber,
        [
          ['Seller', purchase.seller.name],
          ['Purchase Added By', purchase.createdBy],
          [
            'Items',
            purchase.items
                .map(
                  (item) =>
                      '${item.materialName} ${kg(item.weightKg)} @ ${money(item.rate)}',
                )
                .join('\n'),
          ],
          ['Total Weight', kg(purchase.totalWeightKg)],
          ['Total Amount', money(purchase.totalAmount)],
          ['Paid Amount', money(purchase.paidAmount)],
          ['Balance', money(purchase.balanceAmount.clamp(0, double.infinity))],
          ['Date', DateFormat('dd MMM yyyy').format(purchase.createdAt)],
          ['Remarks', purchase.remarks],
        ],
        actions: [
          OutlinedButton.icon(
            onPressed: openEditor,
            icon: const Icon(Icons.edit),
            label: const Text('Edit / Correct Added By'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                showPurchaseInvoicePdfActions(context, ref, purchase),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Invoice PDF'),
          ),
          OutlinedButton.icon(
            onPressed: () => _sendPurchaseWhatsApp(context, ref, purchase),
            icon: const Icon(Icons.chat),
            label: const Text('WhatsApp'),
          ),
        ],
      ),
      onEdit: openEditor,
      onDelete: () => _confirm(
        context,
        'Move Purchase to Recycle Bin?',
        '${purchase.invoiceNumber} will be removed from active purchase and reports.',
        () => notifier.softDeletePurchase(purchase),
      ),
      showEdit: true,
      showDelete: true,
    );
  }

  Widget _staffSaleTile(BuildContext context, WidgetRef ref, SaleRecord sale) {
    final notifier = ref.read(businessProvider.notifier);
    void openEditor() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SaleEditorScreen(sale: sale, initialCreatedBy: summary.name),
        ),
      );
    }

    return FeatureRecordTile(
      title: sale.customer.name,
      subtitle:
          '${sale.invoiceNumber}  |  ${shortDate(sale.createdAt)}  |  By ${sale.createdBy}  |  ${sale.items.map((item) => item.materialName).join(', ')}  |  ${kg(sale.totalWeightKg)}',
      amount: money(sale.totalAmount),
      status: sale.balanceAmount > 0
          ? 'Due ${money(sale.balanceAmount)}'
          : 'Received',
      statusColor: sale.balanceAmount > 0
          ? EnterpriseTheme.error
          : EnterpriseTheme.success,
      avatarPath: sale.customer.photoPath,
      icon: Icons.receipt_long,
      onInvoicePdf: () => shareSalesInvoicePdf(context, ref, sale),
      onView: () => showRecordDetails(
        context,
        sale.invoiceNumber,
        [
          ['Customer', sale.customer.name],
          ['Sale Added By', sale.createdBy],
          [
            'Material',
            sale.items
                .map(
                  (item) =>
                      '${item.materialName} ${kg(item.weightKg)} @ ${money(item.rate)}',
                )
                .join('\n'),
          ],
          ['Invoice Amount', money(sale.totalAmount)],
          ['Paid Amount', money(sale.receivedAmount)],
          ['Pending', money(sale.balanceAmount.clamp(0, double.infinity))],
          ['Date', shortDate(sale.createdAt)],
          ['Remarks', sale.remarks],
        ],
        actions: [
          OutlinedButton.icon(
            onPressed: openEditor,
            icon: const Icon(Icons.edit),
            label: const Text('Edit / Correct Added By'),
          ),
          OutlinedButton.icon(
            onPressed: () => shareSalesInvoicePdf(context, ref, sale),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Invoice PDF'),
          ),
        ],
      ),
      onEdit: openEditor,
      onDelete: () => _confirm(
        context,
        'Move Sale to Recycle Bin?',
        '${sale.invoiceNumber} will be removed from active sales and reports.',
        () => notifier.softDeleteSale(sale),
      ),
      showEdit: true,
      showDelete: true,
    );
  }
}

bool _sameStaffPerson(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _MiniSummaryChip extends StatelessWidget {
  const _MiniSummaryChip(this.label, this.count);

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.resolvedBorderColor),
      ),
      child: Text(
        '$label: $count',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

enum _StaffLiveStatus { online, todayActive, offline }

class _StaffAccountInfo {
  const _StaffAccountInfo({
    required this.id,
    required this.name,
    required this.email,
    required this.mobile,
    required this.role,
    required this.active,
    required this.lastLoginAt,
    required this.lastActiveAt,
  });

  final String id;
  final String name;
  final String email;
  final String mobile;
  final UserRole role;
  final bool active;
  final DateTime? lastLoginAt;
  final DateTime? lastActiveAt;

  bool get isStaff => role == UserRole.supervisor || role == UserRole.manager;
}

class _StaffDashboardSummary {
  const _StaffDashboardSummary({
    required this.name,
    required this.role,
    required this.mobile,
    required this.email,
    required this.assignedShop,
    required this.todayPurchaseCount,
    required this.todaySalesCount,
    required this.todayPaymentCount,
    required this.todayStockUpdateCount,
    required this.todayPendingTaskCount,
    required this.lastLoginAt,
    required this.lastActivityAt,
  });

  final String name;
  final UserRole role;
  final String mobile;
  final String email;
  final String assignedShop;
  final int todayPurchaseCount;
  final int todaySalesCount;
  final int todayPaymentCount;
  final int todayStockUpdateCount;
  final int todayPendingTaskCount;
  final DateTime? lastLoginAt;
  final DateTime? lastActivityAt;

  bool get todayActive =>
      lastActivityAt != null &&
      _summarySameDay(lastActivityAt!, DateTime.now());

  _StaffLiveStatus get status {
    final last = lastActivityAt;
    if (last == null) {
      return _StaffLiveStatus.offline;
    }
    if (DateTime.now().difference(last) <= const Duration(minutes: 15)) {
      return _StaffLiveStatus.online;
    }
    return todayActive
        ? _StaffLiveStatus.todayActive
        : _StaffLiveStatus.offline;
  }

  String get statusLabel {
    return switch (status) {
      _StaffLiveStatus.online => 'Online',
      _StaffLiveStatus.todayActive => 'Today Active',
      _StaffLiveStatus.offline => 'Offline',
    };
  }

  String get lastActivityLabel {
    final last = lastActivityAt;
    if (last == null) {
      return '-';
    }
    return DateFormat('dd MMM, hh:mm a').format(last);
  }

  String get lastLoginLabel {
    final last = lastLoginAt;
    if (last == null) {
      return '-';
    }
    return DateFormat('dd MMM, hh:mm a').format(last);
  }
}

List<_StaffAccountInfo> _staffAccountsFromDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  return [
    for (final doc in docs)
      _StaffAccountInfo(
        id: doc.id,
        name: (doc.data()['name'] ?? '').toString().trim(),
        email: (doc.data()['email'] ?? '').toString().trim(),
        mobile: (doc.data()['mobile'] ?? '').toString().trim(),
        role: _staffRoleFromDocValue(doc.data()['role']),
        active: doc.data()['active'] != false,
        lastLoginAt: _staffDateFromFirestore(doc.data()['lastLoginAt']),
        lastActiveAt: _staffDateFromFirestore(doc.data()['lastActiveAt']),
      ),
  ].where((item) => item.name.isNotEmpty && item.isStaff).toList();
}

List<_StaffDashboardSummary> _staffDashboardSummaries(
  BusinessState state, {
  List<_StaffAccountInfo> accounts = const [],
}) {
  final names =
      <String>{
        for (final account in accounts) account.name,
        for (final item in state.supervisorCashSummaries) item.supervisorName,
        for (final item in state.activePurchases) item.createdBy,
        for (final item in state.activeSales) item.createdBy,
        for (final item in state.activeExpenses) item.addedBy,
        for (final item in state.cashAllocations) item.supervisorName,
      }..removeWhere(
        (item) => item.trim().isEmpty || _isOwnerNameForStaffView(item),
      );

  return [
    for (final name in names)
      _buildStaffSummaryForName(state, name, _accountForName(accounts, name)),
  ]..sort((a, b) {
    final left = a.lastActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right = b.lastActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  });
}

_StaffDashboardSummary _buildStaffSummaryForName(
  BusinessState state,
  String name,
  _StaffAccountInfo? account,
) {
  final role = account?.role ?? _staffRoleForName(name);
  final lastActivity = _latestDate([
    account?.lastActiveAt,
    _lastStaffActivityAt(state, name),
  ]);

  return _StaffDashboardSummary(
    name: account?.name ?? name,
    role: role,
    mobile: account?.mobile ?? _staffMobileForName(state, name),
    email: account?.email ?? '',
    assignedShop: _assignedShopForName(state, name),
    todayPurchaseCount: state.activePurchases
        .where(
          (item) =>
              _sameSummaryUser(item.createdBy, name) &&
              _summarySameDay(item.createdAt, DateTime.now()),
        )
        .length,
    todaySalesCount: state.activeSales
        .where(
          (item) =>
              _sameSummaryUser(item.createdBy, name) &&
              _summarySameDay(item.createdAt, DateTime.now()),
        )
        .length,
    todayPaymentCount:
        state.cashAllocations
            .where(
              (item) =>
                  _sameSummaryUser(item.supervisorName, name) &&
                  _summarySameDay(item.createdAt, DateTime.now()),
            )
            .length +
        state.activeSales
            .where(
              (item) =>
                  _sameSummaryUser(item.createdBy, name) &&
                  item.receivedAmount > 0 &&
                  _summarySameDay(item.createdAt, DateTime.now()),
            )
            .length,
    todayStockUpdateCount:
        state.physicalStocks
            .where(
              (item) =>
                  _sameSummaryUser(item.createdBy, name) &&
                  _summarySameDay(item.createdAt, DateTime.now()),
            )
            .length +
        state.openingStocks
            .where(
              (item) =>
                  _sameSummaryUser(item.createdBy, name) &&
                  _summarySameDay(item.createdAt, DateTime.now()),
            )
            .length,
    todayPendingTaskCount: _pendingTaskCountForStaff(state, name),
    lastLoginAt: account?.lastLoginAt,
    lastActivityAt: lastActivity,
  );
}

_StaffAccountInfo? _accountForName(
  List<_StaffAccountInfo> accounts,
  String name,
) {
  for (final account in accounts) {
    if (_sameSummaryUser(account.name, name)) {
      return account;
    }
  }
  return null;
}

DateTime? _latestDate(List<DateTime?> dates) {
  DateTime? latest;
  for (final date in dates.whereType<DateTime>()) {
    if (latest == null || date.isAfter(latest)) {
      latest = date;
    }
  }
  return latest;
}

bool _isOwnerNameForStaffView(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'owner' ||
      normalized == 'admin' ||
      normalized.contains('owner dashboard');
}

UserRole _staffRoleFromDocValue(Object? value) {
  final raw = (value ?? '').toString().trim().toLowerCase();
  for (final role in UserRole.values) {
    if (role.name.toLowerCase() == raw || role.label.toLowerCase() == raw) {
      return role;
    }
  }
  return raw.contains('manager') ? UserRole.manager : UserRole.supervisor;
}

DateTime? _staffDateFromFirestore(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(value.toString());
}

UserRole _staffRoleForName(String name) {
  final normalized = name.toLowerCase();
  return normalized.contains('manager')
      ? UserRole.manager
      : UserRole.supervisor;
}

String _staffMobileForName(BusinessState state, String name) {
  for (final party in [...state.sellers, ...state.customers]) {
    if (_sameSummaryUser(party.name, name) && party.mobile.trim().isNotEmpty) {
      return party.mobile;
    }
  }
  return '';
}

String _assignedShopForName(BusinessState state, String name) {
  for (final party in [...state.sellers, ...state.customers]) {
    if (_sameSummaryUser(party.name, name) && party.area.trim().isNotEmpty) {
      return 'Shop: ${party.area}';
    }
  }
  return 'Shop: Assigned access';
}

int _pendingTaskCountForStaff(BusinessState state, String name) {
  final pendingSales = state.activeSales
      .where(
        (item) =>
            _sameSummaryUser(item.createdBy, name) && item.balanceAmount > 0,
      )
      .length;
  final pendingPurchases = state.activePurchases
      .where(
        (item) =>
            _sameSummaryUser(item.createdBy, name) && item.balanceAmount > 0,
      )
      .length;
  return pendingSales + pendingPurchases;
}

DateTime? _lastStaffActivityAt(BusinessState state, String name) {
  DateTime? latest;

  void check(DateTime? value) {
    if (value == null) {
      return;
    }
    if (latest == null || value.isAfter(latest!)) {
      latest = value;
    }
  }

  for (final item in state.activePurchases) {
    if (_sameSummaryUser(item.createdBy, name)) {
      check(item.updatedAt ?? item.createdAt);
    }
  }
  for (final item in state.activeSales) {
    if (_sameSummaryUser(item.createdBy, name)) {
      check(item.updatedAt ?? item.createdAt);
    }
  }
  for (final item in state.activeExpenses) {
    if (_sameSummaryUser(item.addedBy, name)) {
      check(item.updatedAt ?? item.createdAt);
    }
  }
  for (final item in state.cashAllocations) {
    if (_sameSummaryUser(item.supervisorName, name)) {
      check(item.updatedAt ?? item.createdAt);
    }
  }
  for (final item in state.physicalStocks) {
    if (_sameSummaryUser(item.createdBy, name)) {
      check(item.createdAt);
    }
  }
  for (final item in state.activities) {
    if (_sameSummaryUser(item.userName, name)) {
      check(item.createdAt);
    }
  }
  return latest;
}

class ExpectedClosingStockScreen extends ConsumerStatefulWidget {
  const ExpectedClosingStockScreen({super.key});

  @override
  ConsumerState<ExpectedClosingStockScreen> createState() =>
      _ExpectedClosingStockScreenState();
}

class _ExpectedClosingStockScreenState
    extends ConsumerState<ExpectedClosingStockScreen> {
  late DateTime _from;
  late DateTime _to;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month);
    _to = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final scopedState = _weightLossScopedState(state);
    final rows = _expectedClosingRows(scopedState, _from, _to, query: _query);
    return Scaffold(
      appBar: AppBar(title: const Text('Expected Closing Stock')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AppHeader(
            title: 'Expected Closing Stock',
            subtitle:
                '${DateFormat('dd MMM yyyy').format(_from)} to ${DateFormat('dd MMM yyyy').format(_to)}',
            trailing: IconButton.filledTonal(
              tooltip: 'Refresh',
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: 12),
          _ExpectedClosingFilterPanel(
            from: _from,
            to: _to,
            query: _query,
            onFrom: () => _pickDate(isFrom: true),
            onTo: () => _pickDate(isFrom: false),
            onQueryChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          _ExpectedClosingFullGraph(rows: rows),
          const SizedBox(height: 12),
          _ExpectedClosingSummaryTable(rows: rows),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      final normalized = DateTime(picked.year, picked.month, picked.day);
      if (isFrom) {
        _from = normalized;
        if (_to.isBefore(_from)) {
          _to = _from;
        }
      } else {
        _to = normalized;
        if (_to.isBefore(_from)) {
          _from = _to;
        }
      }
    });
  }
}

class _ExpectedClosingFilterPanel extends StatelessWidget {
  const _ExpectedClosingFilterPanel({
    required this.from,
    required this.to,
    required this.query,
    required this.onFrom,
    required this.onTo,
    required this.onQueryChanged,
  });

  final DateTime from;
  final DateTime to;
  final String query;
  final VoidCallback onFrom;
  final VoidCallback onTo;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onFrom,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(DateFormat('dd MMM yy').format(from)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTo,
                  icon: const Icon(Icons.event),
                  label: Text(DateFormat('dd MMM yy').format(to)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              labelText: 'Search item',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpectedClosingFullGraph extends StatelessWidget {
  const _ExpectedClosingFullGraph({required this.rows});

  final List<_WeightLossSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    if (rows.isEmpty) {
      return const _Panel(
        title: 'Expected Closing Stock Graph',
        child: _EmptyState(
          icon: Icons.show_chart,
          title: 'No stock rows',
          subtitle: 'Adjust the date range or search to view stock items.',
        ),
      );
    }
    final values = rows.map((row) => row.expectedClosingStock).toList();
    final maxValue = values.fold<double>(
      1,
      (largest, value) => value > largest ? value : largest,
    );
    final minValue = values.fold<double>(
      0,
      (smallest, value) => value < smallest ? value : smallest,
    );
    final padding = ((maxValue - minValue).abs() * 0.20).clamp(10, 1000000);
    final chartColor = tokens.chartColors.length > 1
        ? tokens.chartColors[1]
        : tokens.primaryColor;
    final chartWidth = (rows.length * 70)
        .clamp(MediaQuery.of(context).size.width - 32, 1200)
        .toDouble();
    return _Panel(
      title: 'Expected Closing Stock Graph',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: chartWidth,
          height: 330,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (rows.length - 1).toDouble().clamp(1, double.infinity),
              minY: minValue - padding,
              maxY: maxValue + padding,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: tokens.resolvedBorderColor.withValues(alpha: 0.55),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchCallback: (event, response) {
                  final spots = response?.lineBarSpots;
                  if (!event.isInterestedForInteractions ||
                      spots == null ||
                      spots.isEmpty) {
                    return;
                  }
                  final index = spots.first.spotIndex;
                  if (index >= 0 && index < rows.length) {
                    _showStockBreakupDetails(
                      context,
                      rows[index],
                      title: 'Expected Closing Stock Details',
                    );
                  }
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF0F172A),
                  getTooltipItems: (spots) => spots.map((spot) {
                    final row = rows[spot.spotIndex];
                    return LineTooltipItem(
                      '${row.material.name}\n${kg(row.expectedClosingStock)}',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    );
                  }).toList(),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: const Text('KG'),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    getTitlesWidget: (value, meta) => Text(
                      _compactKg(value),
                      style: TextStyle(
                        color: tokens.resolvedMutedTextColor,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 70,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if ((value - index).abs() > 0.001 ||
                          index < 0 ||
                          index >= rows.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Transform.rotate(
                          angle: rows.length > 4 ? -0.70 : 0,
                          child: SizedBox(
                            width: 84,
                            child: Text(
                              _shortItemLabel(rows[index].material.name),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: rows.length > 4
                                  ? TextAlign.right
                                  : TextAlign.center,
                              style: TextStyle(
                                color: tokens.resolvedMutedTextColor,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var index = 0; index < rows.length; index++)
                      FlSpot(
                        index.toDouble(),
                        rows[index].expectedClosingStock,
                      ),
                  ],
                  isCurved: rows.length > 2,
                  color: chartColor,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: chartColor.withValues(alpha: 0.14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpectedClosingSummaryTable extends StatelessWidget {
  const _ExpectedClosingSummaryTable({required this.rows});

  final List<_WeightLossSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return _Panel(
      title: 'Item-wise Details',
      child: rows.isEmpty
          ? const _EmptyState(
              icon: Icons.table_rows,
              title: 'No matching items',
              subtitle: 'Try another date range or item search.',
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Item Name')),
                  DataColumn(label: Text('Month Opening Qty')),
                  DataColumn(label: Text('Total Purchase Qty')),
                  DataColumn(label: Text('Total Sale Qty')),
                  DataColumn(label: Text('Expected Closing Stock')),
                  DataColumn(label: Text('Actual Physical Stock')),
                  DataColumn(label: Text('Stock Difference')),
                  DataColumn(label: Text('Last Purchase Date')),
                  DataColumn(label: Text('Last Sale Date')),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      onSelectChanged: (_) => _showStockBreakupDetails(
                        context,
                        row,
                        title: 'Expected Closing Stock Details',
                      ),
                      cells: [
                        DataCell(Text(row.material.name)),
                        DataCell(Text(kg(row.monthOpeningQty))),
                        DataCell(Text(kg(row.totalPurchaseQty))),
                        DataCell(Text(kg(row.totalSaleQty))),
                        DataCell(Text(kg(row.expectedClosingStock))),
                        DataCell(Text(kg(row.actualPhysicalStock))),
                        DataCell(
                          Text(
                            kg(row.stockDifference),
                            style: TextStyle(
                              color: row.stockDifference < -0.01
                                  ? tokens.dangerColor
                                  : row.stockDifference > 0.01
                                  ? tokens.successColor
                                  : tokens.resolvedMutedTextColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        DataCell(Text(row.lastPurchaseLabel)),
                        DataCell(Text(row.lastSaleLabel)),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

class WeightLossSummaryScreen extends ConsumerStatefulWidget {
  const WeightLossSummaryScreen({super.key});

  @override
  ConsumerState<WeightLossSummaryScreen> createState() =>
      _WeightLossSummaryScreenState();
}

class _WeightLossSummaryScreenState
    extends ConsumerState<WeightLossSummaryScreen> {
  late DateTime _from;
  late DateTime _to;
  String _query = '';
  String _lastAlertKey = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month);
    _to = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final scopedState = _weightLossScopedState(state);
    final rows = _weightLossRows(scopedState, _from, _to, query: _query);
    _scheduleWeightLossAlert(rows);

    return Scaffold(
      appBar: AppBar(title: const Text('Weight Loss Summary')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AppHeader(
            title: 'Weight Loss Summary',
            subtitle:
                '${DateFormat('dd MMM yyyy').format(_from)} to ${DateFormat('dd MMM yyyy').format(_to)}',
            trailing: IconButton.filledTonal(
              tooltip: 'Refresh',
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: 12),
          _ExpectedClosingFilterPanel(
            from: _from,
            to: _to,
            query: _query,
            onFrom: () => _pickDate(isFrom: true),
            onTo: () => _pickDate(isFrom: false),
            onQueryChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          _WeightLossAlertSection(rows: rows),
          const SizedBox(height: 12),
          _WeightLossBarPanel(rows: rows),
          const SizedBox(height: 12),
          _WeightLossSummaryTable(rows: rows),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      final normalized = DateTime(picked.year, picked.month, picked.day);
      if (isFrom) {
        _from = normalized;
        if (_to.isBefore(_from)) {
          _to = _from;
        }
      } else {
        _to = normalized;
        if (_to.isBefore(_from)) {
          _from = _to;
        }
      }
    });
  }

  void _scheduleWeightLossAlert(List<_WeightLossSummaryRow> rows) {
    final alertKey = rows
        .map(
          (row) => '${row.material.id}:${row.weightLossQty.toStringAsFixed(2)}',
        )
        .join('|');
    if (alertKey.isEmpty || alertKey == _lastAlertKey) {
      return;
    }
    _lastAlertKey = alertKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || rows.isEmpty) {
        return;
      }
      final top = rows.first;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${top.material.name} has ${kg(top.weightLossQty)} weight loss. Please verify physical stock and sales entry.',
          ),
        ),
      );
    });
  }
}

class _WeightLossAlertSection extends StatelessWidget {
  const _WeightLossAlertSection({required this.rows});

  final List<_WeightLossSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final highest = rows.isEmpty ? null : rows.first;
    final totalLoss = rows.fold<double>(
      0,
      (runningTotal, row) => runningTotal + row.weightLossQty,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AI Alert Section',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.75,
          children: [
            _MetricCard(
              label: 'Loss Items',
              value: rows.length.toString(),
              icon: Icons.warning_amber,
              color: rows.isEmpty ? tokens.successColor : tokens.dangerColor,
              onTap: () {},
            ),
            _MetricCard(
              label: 'Highest Loss Item',
              value: highest?.material.name ?? '-',
              icon: Icons.trending_down,
              color: tokens.dangerColor,
              onTap: () {},
            ),
            _MetricCard(
              label: 'Total Weight Loss',
              value: kg(totalLoss),
              icon: Icons.scale,
              color: rows.isEmpty ? tokens.successColor : tokens.dangerColor,
              onTap: () {},
            ),
            _MetricCard(
              label: 'Last Sale Date',
              value: highest?.lastSaleLabel ?? '-',
              icon: Icons.sell,
              color: tokens.warningColor,
              onTap: () {},
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Panel(
          child: Row(
            children: [
              Icon(
                rows.isEmpty
                    ? Icons.check_circle
                    : Icons.notification_important,
                color: rows.isEmpty ? tokens.successColor : tokens.dangerColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  highest == null
                      ? 'No weight loss is currently detected.'
                      : '${highest.material.name} has ${kg(highest.weightLossQty)} weight loss. Please verify physical stock and sales entry.',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeightLossBarPanel extends StatelessWidget {
  const _WeightLossBarPanel({required this.rows});

  final List<_WeightLossSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    if (rows.isEmpty) {
      return const _Panel(
        child: _EmptyState(
          icon: Icons.bar_chart,
          title: 'No weight loss items',
          subtitle:
              'Only items with positive weight loss appear in this graph.',
        ),
      );
    }
    final maxLoss = rows.fold<double>(
      0,
      (maxValue, row) =>
          row.weightLossQty > maxValue ? row.weightLossQty : maxValue,
    );
    final showTopValues = rows.length <= 4;
    final palette = tokens.chartColors.isEmpty
        ? [tokens.primaryColor, tokens.secondaryColor, tokens.dangerColor]
        : tokens.chartColors;
    final chartWidth = (rows.length * 62)
        .clamp(MediaQuery.of(context).size.width - 32, 1800)
        .toDouble();

    return _Panel(
      title: 'Weight Loss Summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items are sorted by highest weight loss first.',
            style: TextStyle(
              color: tokens.resolvedMutedTextColor,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              height: 330,
              child: BarChart(
                BarChartData(
                  maxY: (maxLoss * (showTopValues ? 1.28 : 1.12)).clamp(
                    10,
                    double.infinity,
                  ),
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchCallback: (event, response) {
                      final spot = response?.spot;
                      if (!event.isInterestedForInteractions || spot == null) {
                        return;
                      }
                      final index = spot.touchedBarGroupIndex;
                      if (index < 0 || index >= rows.length) {
                        return;
                      }
                      _showWeightLossDetails(context, rows[index]);
                    },
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF0F172A),
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final row = rows[group.x.toInt()];
                        return BarTooltipItem(
                          kg(row.weightLossQty),
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46,
                        getTitlesWidget: (value, meta) => Text(
                          _compactKg(value),
                          style: TextStyle(
                            color: tokens.resolvedMutedTextColor,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 68,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= rows.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Transform.rotate(
                              angle: -0.75,
                              child: SizedBox(
                                width: 82,
                                child: Text(
                                  rows[index].material.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: tokens.resolvedMutedTextColor,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var index = 0; index < rows.length; index++)
                      BarChartGroupData(
                        x: index,
                        showingTooltipIndicators: showTopValues
                            ? const [0]
                            : const [],
                        barRods: [
                          BarChartRodData(
                            toY: rows[index].weightLossQty,
                            width: rows.length <= 4 ? 34 : 22,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                            gradient: LinearGradient(
                              colors: [
                                palette[index % palette.length],
                                palette[index % palette.length].withValues(
                                  alpha: 0.68,
                                ),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (!showTopValues) ...[
            const SizedBox(height: 8),
            Text(
              'Tap a bar to view exact weight loss and full breakup.',
              style: TextStyle(
                color: tokens.resolvedMutedTextColor,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeightLossSummaryTable extends StatelessWidget {
  const _WeightLossSummaryTable({required this.rows});

  final List<_WeightLossSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return _Panel(
      title: 'Item Breakup',
      child: rows.isEmpty
          ? const _EmptyState(
              icon: Icons.table_rows,
              title: 'No summary rows',
              subtitle: 'There are no positive weight loss items to list.',
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Item Name')),
                  DataColumn(label: Text('Month Opening Qty')),
                  DataColumn(label: Text('Total Purchase Qty')),
                  DataColumn(label: Text('Total Sale Qty')),
                  DataColumn(label: Text('Expected Closing Stock')),
                  DataColumn(label: Text('Actual Physical Stock')),
                  DataColumn(label: Text('Weight Loss Qty')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Last Purchase Date')),
                  DataColumn(label: Text('Last Sale Date')),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(Text(row.material.name)),
                        DataCell(Text(kg(row.monthOpeningQty))),
                        DataCell(Text(kg(row.totalPurchaseQty))),
                        DataCell(Text(kg(row.totalSaleQty))),
                        DataCell(Text(kg(row.expectedClosingStock))),
                        DataCell(Text(kg(row.actualPhysicalStock))),
                        DataCell(
                          Text(
                            kg(row.weightLossQty),
                            style: TextStyle(
                              color: tokens.dangerColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        DataCell(_LossStatusChip(loss: row.weightLossQty)),
                        DataCell(Text(row.lastPurchaseLabel)),
                        DataCell(Text(row.lastSaleLabel)),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

class _WeightLossSummaryRow {
  const _WeightLossSummaryRow({
    required this.analysis,
    required this.lastPurchaseDate,
    required this.lastSaleDate,
  });

  final StockAnalysisResult analysis;
  final DateTime? lastPurchaseDate;
  final DateTime? lastSaleDate;

  MaterialStock get material => analysis.material;
  double get monthOpeningQty => analysis.monthOpeningQty;
  double get totalPurchaseQty => analysis.purchaseQty;
  double get totalSaleQty => analysis.saleQty;
  double get expectedClosingStock => analysis.expectedStock;
  double get actualPhysicalStock => analysis.physicalStock;
  double get availableClosingStock => actualPhysicalStock;
  double get stockDifference => actualPhysicalStock - expectedClosingStock;
  double get weightLossQty => analysis.weightLoss;
  String get lossStatus => weightLossQty > 100
      ? 'Critical'
      : weightLossQty > 25
      ? 'Warning'
      : 'Low';
  String get lastPurchaseLabel => _summaryDate(lastPurchaseDate);
  String get lastSaleLabel => _summaryDate(lastSaleDate);
}

BusinessState _weightLossScopedState(BusinessState state) {
  if (state.user.role.isOwnerOrAdmin) {
    return state;
  }
  bool mine(String value) => _sameSummaryUser(value, state.user.name);
  return state.copyWith(
    purchases: state.purchases
        .where((purchase) => mine(purchase.createdBy))
        .toList(),
    sales: state.sales.where((sale) => mine(sale.createdBy)).toList(),
  );
}

List<_WeightLossSummaryRow> _weightLossRows(
  BusinessState state,
  DateTime from,
  DateTime to, {
  String query = '',
}) {
  final rows = _groupedStockSummaryRows(
    state,
    from,
    to,
    query: query,
  ).where((row) => row.weightLossQty > 0).toList();
  rows.sort((a, b) => b.weightLossQty.compareTo(a.weightLossQty));
  return rows;
}

List<_WeightLossSummaryRow> _expectedClosingRows(
  BusinessState state,
  DateTime from,
  DateTime to, {
  String query = '',
}) {
  final rows = _groupedStockSummaryRows(state, from, to, query: query);
  rows.sort((a, b) => b.expectedClosingStock.compareTo(a.expectedClosingStock));
  return rows;
}

List<_WeightLossSummaryRow> _groupedStockSummaryRows(
  BusinessState state,
  DateTime from,
  DateTime to, {
  String query = '',
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final groups = <String, List<MaterialStock>>{};
  for (final material in state.activeMaterials) {
    final normalizedName = _normalizedItemName(material.name);
    if (normalizedQuery.isNotEmpty &&
        !normalizedName.contains(normalizedQuery)) {
      continue;
    }
    final key = normalizedName.isEmpty ? material.id : normalizedName;
    (groups[key] ??= []).add(material);
  }

  return [
    for (final materials in groups.values)
      _combinedStockSummaryRow(state, materials, from, to),
  ];
}

_WeightLossSummaryRow _combinedStockSummaryRow(
  BusinessState state,
  List<MaterialStock> materials,
  DateTime from,
  DateTime to,
) {
  final analyses = [
    for (final material in materials)
      buildStockAnalysis(state, material, from: from, to: to),
  ];
  final primary = materials.first;
  final displayMaterial = primary.copyWith(name: _displayItemName(materials));
  double sum(double Function(StockAnalysisResult analysis) valueFor) {
    return analyses.fold<double>(0, (total, item) => total + valueFor(item));
  }

  return _WeightLossSummaryRow(
    analysis: StockAnalysisResult(
      material: displayMaterial,
      from: from,
      to: to,
      monthOpeningQty: sum((item) => item.monthOpeningQty),
      purchaseQty: sum((item) => item.purchaseQty),
      saleQty: sum((item) => item.saleQty),
      physicalStock: sum((item) => item.physicalStock),
      expectedStock: sum((item) => item.expectedStock),
    ),
    lastPurchaseDate: _lastPurchaseDateForMaterials(state, materials, from, to),
    lastSaleDate: _lastSaleDateForMaterials(state, materials, from, to),
  );
}

String _normalizedItemName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String _displayItemName(List<MaterialStock> materials) {
  final names = materials
      .map((item) => item.name.trim())
      .where((item) => item.isNotEmpty)
      .toList();
  if (names.isEmpty) {
    return 'Item';
  }
  names.sort((a, b) => a.length.compareTo(b.length));
  return names.first;
}

DateTime? _lastPurchaseDateForMaterials(
  BusinessState state,
  List<MaterialStock> materials,
  DateTime from,
  DateTime to,
) {
  DateTime? latest;
  for (final purchase in state.activePurchases) {
    if (!_summaryDateInRange(purchase.createdAt, from, to) ||
        !purchase.items.any((item) => _matchesAnyMaterial(item, materials))) {
      continue;
    }
    if (latest == null || purchase.createdAt.isAfter(latest)) {
      latest = purchase.createdAt;
    }
  }
  return latest;
}

DateTime? _lastSaleDateForMaterials(
  BusinessState state,
  List<MaterialStock> materials,
  DateTime from,
  DateTime to,
) {
  DateTime? latest;
  for (final sale in state.activeSales) {
    if (!_summaryDateInRange(sale.createdAt, from, to) ||
        !sale.items.any((item) => _matchesAnyMaterial(item, materials))) {
      continue;
    }
    if (latest == null || sale.createdAt.isAfter(latest)) {
      latest = sale.createdAt;
    }
  }
  return latest;
}

bool _matchesAnyMaterial(LineItem item, List<MaterialStock> materials) {
  return materials.any(
    (material) =>
        stockMaterialMatches(item.materialId, item.materialName, material),
  );
}

void _showWeightLossDetails(
  BuildContext context,
  _WeightLossSummaryRow row, {
  bool alertMessage = false,
}) {
  _showStockBreakupDetails(
    context,
    row,
    title: '${row.material.name} - Weight Loss Details',
    alertMessage: alertMessage,
  );
}

void _showStockBreakupDetails(
  BuildContext context,
  _WeightLossSummaryRow row, {
  required String title,
  bool alertMessage = false,
}) {
  final tokens = EnterpriseTheme.tokensOf(context);
  final differenceColor = _expectedStockStatusColor(tokens, row);
  GraphPopupGuard.show<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _WeightLossDetailLine('Month Opening Qty', kg(row.monthOpeningQty)),
            _WeightLossDetailLine(
              'Total Purchase Qty',
              kg(row.totalPurchaseQty),
            ),
            _WeightLossDetailLine('Total Sale Qty', kg(row.totalSaleQty)),
            _WeightLossDetailLine(
              'Expected Closing Stock',
              kg(row.expectedClosingStock),
            ),
            _WeightLossDetailLine(
              'Actual Physical Stock',
              kg(row.actualPhysicalStock),
            ),
            _WeightLossDetailLine(
              'Stock Difference',
              kg(row.stockDifference),
              valueColor: differenceColor,
            ),
            if (row.weightLossQty > 0)
              _WeightLossDetailLine(
                'Weight Loss Qty',
                kg(row.weightLossQty),
                valueColor: tokens.dangerColor,
              )
            else if (row.stockDifference > 0.01)
              _WeightLossDetailLine(
                'Weight Increase / Extra Stock',
                kg(row.stockDifference),
                valueColor: tokens.successColor,
              )
            else
              _WeightLossDetailLine(
                'Status',
                'No Difference',
                valueColor: tokens.primaryColor,
              ),
            if (row.weightLossQty > 0)
              _WeightLossDetailLine('Status', row.lossStatus),
            _WeightLossDetailLine('Last Purchase Date', row.lastPurchaseLabel),
            _WeightLossDetailLine('Last Sale Date', row.lastSaleLabel),
            if (alertMessage) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.dangerColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: tokens.dangerColor.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  'Please verify physical stock and sales entry.',
                  style: TextStyle(
                    color: tokens.dangerColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _WeightLossDetailLine extends StatelessWidget {
  const _WeightLossDetailLine(this.label, this.value, {this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: tokens.resolvedMutedTextColor),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? tokens.textColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

bool _summaryDateInRange(DateTime value, DateTime from, DateTime to) {
  final date = DateTime(value.year, value.month, value.day);
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  return !date.isBefore(start) && !date.isAfter(end);
}

bool _sameSummaryUser(String left, String right) {
  final a = left.trim().toLowerCase();
  final b = right.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) {
    return false;
  }
  return a == b || a.contains(b) || b.contains(a);
}

String _summaryDate(DateTime? value) {
  if (value == null) {
    return '-';
  }
  return DateFormat('dd MMM yyyy').format(value);
}

String _compactKg(num value) {
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  return NumberFormat.compact(locale: 'en_IN').format(value);
}

double _purchaseValueForDay(BusinessState state, DateTime date) {
  return state.activePurchases
      .where((purchase) => _summarySameDay(purchase.createdAt, date))
      .fold<double>(
        0,
        (runningTotal, purchase) => runningTotal + purchase.totalAmount,
      );
}

double _salesValueForDay(BusinessState state, DateTime date) {
  return state.activeSales
      .where((sale) => _summarySameDay(sale.createdAt, date))
      .fold<double>(0, (runningTotal, sale) => runningTotal + sale.totalAmount);
}

double _expenseValueForDay(BusinessState state, DateTime date) {
  return state.activeExpenses
      .where((expense) => _summarySameDay(expense.date, date))
      .fold<double>(
        0,
        (runningTotal, expense) => runningTotal + expense.amount,
      );
}

String _trendText(double current, double previous) {
  if (previous.abs() < 0.01) {
    if (current.abs() < 0.01) {
      return '+0.0%';
    }
    return current >= 0 ? '+100%' : '-100%';
  }
  final percent = ((current - previous) / previous.abs()) * 100;
  final sign = percent >= 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(1)}%';
}

bool _trendPositive(double current, double previous) {
  if (previous.abs() < 0.01) {
    return current >= 0;
  }
  return current >= previous;
}

List<FlSpot> _profitSpotsForMonth(BusinessState state) {
  final now = DateTime.now();
  final spots = <FlSpot>[];
  var runningProfit = 0.0;
  for (var day = 1; day <= now.day; day++) {
    final date = DateTime(now.year, now.month, day);
    runningProfit +=
        _salesValueForDay(state, date) -
        _purchaseValueForDay(state, date) -
        _expenseValueForDay(state, date);
    spots.add(FlSpot(day.toDouble(), runningProfit));
  }
  return spots;
}

String _compactMoney(num value) {
  final abs = value.abs();
  final sign = value < 0 ? '-' : '';
  if (abs >= 10000000) {
    return '$sign${(abs / 10000000).toStringAsFixed(1)}Cr';
  }
  if (abs >= 100000) {
    return '$sign${(abs / 100000).toStringAsFixed(1)}L';
  }
  if (abs >= 1000) {
    return '$sign${(abs / 1000).toStringAsFixed(0)}K';
  }
  return '$sign${abs.toStringAsFixed(0)}';
}

String _shortItemLabel(String value) {
  final words = value.trim().split(RegExp(r'\s+'));
  if (words.length <= 2) {
    return value;
  }
  return words.take(2).join(' ');
}

bool _summarySameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

class PurchaseEntryScreen extends ConsumerStatefulWidget {
  const PurchaseEntryScreen({super.key, required this.page});

  final DynamicPageDefinition page;

  @override
  ConsumerState<PurchaseEntryScreen> createState() =>
      _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends ConsumerState<PurchaseEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _rate = TextEditingController();
  final _paid = TextEditingController();
  final _remarks = TextEditingController();
  DateTime _purchaseDate = DateTime.now();
  Party? _seller;
  MaterialStock? _material;

  @override
  void dispose() {
    _weight.dispose();
    _rate.dispose();
    _paid.dispose();
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final amount = _effectivePurchaseWeight * _read(_rate);
    final balance = amount - _read(_paid);

    return Scaffold(
      appBar: AppBar(title: Text('New ${widget.page.title}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _FormDropdown<Party>(
                label: _fieldLabel(widget.page, 'seller', 'Seller'),
                value: _seller,
                items: state.sellers,
                labelOf: (item) => item.name,
                emptyLabel: 'Add seller',
                onAdd: () async {
                  final party = await _showPartyDialog(
                    context,
                    ref,
                    PartyKind.seller,
                  );
                  if (party != null) {
                    setState(() => _seller = party);
                  }
                },
                onChanged: (value) => setState(() => _seller = value),
              ),
              const SizedBox(height: 12),
              _FormDropdown<MaterialStock>(
                label: _fieldLabel(widget.page, 'material', 'Material'),
                value: _material,
                items: state.activeMaterials,
                labelOf: (item) => item.name,
                emptyLabel: 'Add material',
                onAdd: () async {
                  final material = await _showMaterialDialog(context, ref);
                  if (material != null) {
                    setState(() {
                      _material = material;
                      _rate.text = material.currentBuyingRate.toStringAsFixed(
                        0,
                      );
                    });
                  }
                },
                onChanged: (value) {
                  setState(() {
                    _material = value;
                    _rate.text =
                        value?.currentBuyingRate.toStringAsFixed(0) ?? '';
                  });
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickPurchaseDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  'Purchase Date: ${DateFormat('dd MMM yyyy').format(_purchaseDate)}',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select any purchase date: 2 years back to 2 years future.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      controller: _weight,
                      label: _fieldLabel(
                        widget.page,
                        'weightKg',
                        'Weight (KG)',
                      ),
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumberField(
                      controller: _rate,
                      label: _fieldLabel(widget.page, 'rate', 'Rate / KG'),
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (_fieldVisible(widget.page, 'paidAmount')) ...[
                const SizedBox(height: 12),
                _NumberField(
                  controller: _paid,
                  label: _fieldLabel(widget.page, 'paidAmount', 'Paid Amount'),
                  onChanged: () => setState(() {}),
                ),
              ],
              if (_fieldVisible(widget.page, 'remarks')) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarks,
                  decoration: InputDecoration(
                    labelText: _fieldLabel(widget.page, 'remarks', 'Remarks'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _Panel(
                child: Column(
                  children: [
                    _AmountLine(label: 'Bill Amount', value: money(amount)),
                    _AmountLine(
                      label: 'Balance',
                      value: money(balance.clamp(0, double.infinity)),
                      color: balance > 0
                          ? EnterpriseTheme.warning
                          : EnterpriseTheme.success,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openVoiceParser,
                icon: const Icon(Icons.mic),
                label: const Text('Voice Command'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Save Purchase'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPurchaseDate() async {
    final now = DateTime.now();
    final firstAllowedDate = DateTime(now.year - 2, now.month, now.day);
    final lastAllowedDate = DateTime(now.year + 2, now.month, now.day);
    final initialAllowedDate = _purchaseDate.isBefore(firstAllowedDate)
        ? firstAllowedDate
        : _purchaseDate.isAfter(lastAllowedDate)
        ? lastAllowedDate
        : _purchaseDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialAllowedDate,
      firstDate: firstAllowedDate,
      lastDate: lastAllowedDate,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(
      () => _purchaseDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        now.hour,
        now.minute,
        now.second,
      ),
    );
  }

  Future<void> _openVoiceParser() async {
    final command = await _showCommandDialog(context);
    if (command == null) {
      return;
    }
    final draft = parsePurchaseCommand(command);
    if (draft == null) {
      if (mounted) {
        _snack(
          context,
          'Could not parse command. Example: purchase 500 kg coconut shell at 15 rupees',
        );
      }
      return;
    }
    final state = ref.read(businessProvider);
    final match = state.activeMaterials.where(
      (item) => item.name.toLowerCase() == draft.materialName.toLowerCase(),
    );
    setState(() {
      _material = match.isEmpty
          ? state.activeMaterials.firstOrNull
          : match.first;
      _weight.text = draft.weightKg.toStringAsFixed(0);
      _rate.text = draft.rate.toStringAsFixed(0);
    });
  }

  double get _effectivePurchaseWeight {
    final weight = _read(_weight);
    final deduction = _material?.normalizedWastageDeductionPercent ?? 0;
    return (weight - (weight * deduction / 100)).clamp(0, double.infinity);
  }

  void _save() {
    if (_seller == null || _material == null) {
      _snack(context, 'Select seller and material.');
      return;
    }
    final weight = _read(_weight);
    final rate = _read(_rate);
    if (weight <= 0 || rate <= 0) {
      _snack(context, 'Enter valid weight and rate.');
      return;
    }
    final purchase = ref
        .read(businessProvider.notifier)
        .addPurchase(
          seller: _seller!,
          items: [
            LineItem(
              materialId: _material!.id,
              materialName: _material!.name,
              materialPhotoPath: _material!.photoPath,
              weightKg: weight,
              wastageDeductionPercent:
                  _material!.normalizedWastageDeductionPercent,
              effectiveWeight: _effectivePurchaseWeight,
              rate: rate,
            ),
          ],
          paidAmount: _read(_paid),
          purchaseDate: _purchaseDate,
          remarks: _remarks.text,
        );
    _snack(context, '${purchase.invoiceNumber} saved');
    Navigator.of(context).pop();
  }
}

class SalesEntryScreen extends ConsumerStatefulWidget {
  const SalesEntryScreen({super.key, required this.page});

  final DynamicPageDefinition page;

  @override
  ConsumerState<SalesEntryScreen> createState() => _SalesEntryScreenState();
}

class _SalesEntryScreenState extends ConsumerState<SalesEntryScreen> {
  final _weight = TextEditingController();
  final _rate = TextEditingController();
  final _received = TextEditingController();
  final _remarks = TextEditingController();
  Party? _customer;
  MaterialStock? _material;

  @override
  void dispose() {
    _weight.dispose();
    _rate.dispose();
    _received.dispose();
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final amount = _read(_weight) * _read(_rate);
    final balance = amount - _read(_received);

    return Scaffold(
      appBar: AppBar(title: Text('New ${widget.page.title}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _FormDropdown<Party>(
              label: _fieldLabel(widget.page, 'customer', 'Customer'),
              value: _customer,
              items: state.customers,
              labelOf: (item) => item.name,
              emptyLabel: 'Add customer',
              onAdd: () async {
                final party = await _showPartyDialog(
                  context,
                  ref,
                  PartyKind.customer,
                );
                if (party != null) {
                  setState(() => _customer = party);
                }
              },
              onChanged: (value) => setState(() => _customer = value),
            ),
            const SizedBox(height: 12),
            _FormDropdown<MaterialStock>(
              label: _fieldLabel(widget.page, 'material', 'Material'),
              value: _material,
              items: state.activeMaterials,
              labelOf: (item) => item.name,
              emptyLabel: 'Add material',
              onAdd: () async {
                final material = await _showMaterialDialog(context, ref);
                if (material != null) {
                  setState(() => _material = material);
                }
              },
              onChanged: (value) => setState(() => _material = value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    controller: _weight,
                    label: _fieldLabel(widget.page, 'weightKg', 'Weight (KG)'),
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _NumberField(
                    controller: _rate,
                    label: _fieldLabel(widget.page, 'rate', 'Rate / KG'),
                    onChanged: () => setState(() {}),
                  ),
                ),
              ],
            ),
            if (_fieldVisible(widget.page, 'receivedAmount')) ...[
              const SizedBox(height: 12),
              _NumberField(
                controller: _received,
                label: _fieldLabel(
                  widget.page,
                  'receivedAmount',
                  'Received Amount',
                ),
                onChanged: () => setState(() {}),
              ),
            ],
            if (_fieldVisible(widget.page, 'remarks')) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _remarks,
                decoration: InputDecoration(
                  labelText: _fieldLabel(widget.page, 'remarks', 'Remarks'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _Panel(
              child: Column(
                children: [
                  _AmountLine(label: 'Invoice Amount', value: money(amount)),
                  _AmountLine(
                    label: 'Pending',
                    value: money(balance.clamp(0, double.infinity)),
                    color: balance > 0
                        ? EnterpriseTheme.error
                        : EnterpriseTheme.success,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Save Sale'),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (_customer == null || _material == null) {
      _snack(context, 'Select customer and material.');
      return;
    }
    final sale = ref
        .read(businessProvider.notifier)
        .addSale(
          customer: _customer!,
          material: _material!,
          weightKg: _read(_weight),
          rate: _read(_rate),
          receivedAmount: _read(_received),
          remarks: _remarks.text,
        );
    _snack(context, '${sale.invoiceNumber} saved');
    Navigator.of(context).pop();
  }
}

class DynamicPageEngine extends ConsumerStatefulWidget {
  const DynamicPageEngine({super.key, required this.page});

  final DynamicPageDefinition page;

  @override
  ConsumerState<DynamicPageEngine> createState() => _DynamicPageEngineState();
}

class _DynamicPageEngineState extends ConsumerState<DynamicPageEngine> {
  final _dataService = DynamicPageDataService();
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DynamicPageEngine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id) {
      _syncControllers();
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncControllers();
    final fields = widget.page.visibleFields;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppHeader(
            title: widget.page.title,
            subtitle: widget.page.subtitle.isEmpty
                ? 'Firebase dynamic page'
                : widget.page.subtitle,
          ),
          const SizedBox(height: 14),
          if (fields.isNotEmpty)
            _Panel(
              child: Column(
                children: [
                  for (final field in fields) ...[
                    _DynamicFieldInput(
                      field: field,
                      controller: _controllers[field.key]!,
                    ),
                    if (field != fields.last) const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _saveEntry,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ),
          if (fields.isNotEmpty) const SizedBox(height: 14),
          Expanded(
            child: _Panel(
              title: 'Live Data',
              child: widget.page.collection.isEmpty
                  ? const _EmptyState(
                      icon: Icons.dataset,
                      title: 'No collection configured',
                      subtitle: 'Set collection in page_config for this page.',
                    )
                  : StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _dataService.watchCollection(
                        widget.page.collection,
                      ),
                      builder: (context, snapshot) {
                        final rows = snapshot.data ?? const [];
                        if (rows.isEmpty) {
                          return const _EmptyState(
                            icon: Icons.dynamic_form,
                            title: 'No records yet',
                            subtitle: 'Saved entries appear here in real time.',
                          );
                        }
                        return ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const Divider(height: 12),
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            final title = _rowTitle(row, fields);
                            return _CompactRow(
                              icon: _iconFromName(widget.page.type),
                              title: title,
                              subtitle: _rowSubtitle(row, fields),
                              value: '',
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _syncControllers() {
    final fieldKeys = widget.page.visibleFields
        .map((field) => field.key)
        .toSet();
    for (final field in widget.page.visibleFields) {
      _controllers.putIfAbsent(field.key, TextEditingController.new);
    }
    final staleKeys = _controllers.keys
        .where((key) => !fieldKeys.contains(key))
        .toList(growable: false);
    for (final key in staleKeys) {
      _controllers.remove(key)?.dispose();
    }
  }

  Future<void> _saveEntry() async {
    final values = <String, dynamic>{};
    for (final field in widget.page.visibleFields) {
      final raw = _controllers[field.key]?.text.trim() ?? '';
      if (field.required && raw.isEmpty) {
        _snack(context, '${field.label} is required.');
        return;
      }
      values[field.key] = _typedValue(raw, field.type);
    }
    await _dataService.saveEntry(widget.page.collection, values);
    for (final controller in _controllers.values) {
      controller.clear();
    }
    if (mounted) {
      _snack(context, '${widget.page.title} saved');
    }
  }
}

class _DynamicFieldInput extends StatefulWidget {
  const _DynamicFieldInput({required this.field, required this.controller});

  final DynamicFieldConfig field;
  final TextEditingController controller;

  @override
  State<_DynamicFieldInput> createState() => _DynamicFieldInputState();
}

class _DynamicFieldInputState extends State<_DynamicFieldInput> {
  @override
  Widget build(BuildContext context) {
    if (widget.field.options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        initialValue: widget.controller.text.isEmpty
            ? null
            : widget.controller.text,
        decoration: InputDecoration(labelText: widget.field.label),
        items: [
          for (final option in widget.field.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (value) {
          widget.controller.text = value ?? '';
        },
      );
    }

    final isNumber =
        widget.field.type == 'number' ||
        widget.field.type == 'currency' ||
        widget.field.type == 'kg' ||
        widget.field.type == 'rate';
    return TextField(
      controller: widget.controller,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      minLines: widget.field.type == 'multiline' ? 3 : 1,
      maxLines: widget.field.type == 'multiline' ? 5 : 1,
      decoration: InputDecoration(labelText: widget.field.label),
    );
  }
}

class _MaintenanceScreen extends StatelessWidget {
  const _MaintenanceScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _Panel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.construction, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Maintenance Mode',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListModule extends StatelessWidget {
  const _ListModule({
    required this.title,
    required this.subtitle,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.buttonLabel,
    required this.icon,
    required this.onAdd,
    required this.children,
  });

  final String title;
  final String subtitle;
  final String emptyTitle;
  final String emptySubtitle;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAdd,
        icon: Icon(icon),
        label: Text(buttonLabel),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AppHeader(title: title, subtitle: subtitle),
            const SizedBox(height: 14),
            Expanded(
              child: children.isEmpty
                  ? _EmptyState(
                      icon: icon,
                      title: emptyTitle,
                      subtitle: emptySubtitle,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 86),
                      itemCount: children.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) => children[index],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: tokens.resolvedGradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.recycling, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.resolvedMutedTextColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.resolvedBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: tokens.isDark ? 0.24 : 0.07),
            blurRadius: tokens.isDark ? 18 : 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            ExpandedAware(child: child),
          ],
        ),
      ),
    );
  }
}

class ExpandedAware extends StatelessWidget {
  const ExpandedAware({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _PageTint extends StatelessWidget {
  const _PageTint({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final tint = tokens.isDark
        ? tokens.backgroundColor
        : Color.alphaBlend(tokens.primaryColor.withValues(alpha: 0.05), color);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        gradient: tokens.isDark
            ? LinearGradient(
                colors: tokens.resolvedGradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
      child: SizedBox.expand(child: child),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final cardColor = Theme.of(context).cardTheme.color ?? tokens.cardColor;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.resolvedBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: tokens.isDark ? 0.22 : 0.07,
              ),
              blurRadius: 14,
              offset: Offset(0, 7),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.68)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ).copyWith(color: tokens.resolvedMutedTextColor),
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: tokens.primaryColor.withValues(alpha: 0.18),
          child: Icon(icon, color: tokens.primaryColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.resolvedMutedTextColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (value.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: tokens.secondaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ],
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: tokens.primaryColor),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.resolvedMutedTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF64748B)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormDropdown<T> extends StatelessWidget {
  const _FormDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.emptyLabel,
    required this.onAdd,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T item) labelOf;
  final String emptyLabel;
  final Future<void> Function() onAdd;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return OutlinedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: Text(emptyLabel),
      );
    }
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in items)
          DropdownMenuItem<T>(value: item, child: Text(labelOf(item))),
      ],
      onChanged: onChanged,
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

Future<Party?> _showPartyDialog(
  BuildContext context,
  WidgetRef ref,
  PartyKind kind,
) async {
  final name = TextEditingController();
  final mobile = TextEditingController();
  final area = TextEditingController();
  final party = await showModalBottomSheet<Party>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _Sheet(
      title: kind == PartyKind.seller ? 'Add Seller' : 'Add Customer',
      child: Column(
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: mobile,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Mobile Number'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: area,
            decoration: const InputDecoration(labelText: 'Area'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || mobile.text.trim().isEmpty) {
                _snack(context, 'Name and mobile are required.');
                return;
              }
              final created = ref
                  .read(businessProvider.notifier)
                  .addParty(
                    name: name.text,
                    mobile: mobile.text,
                    area: area.text,
                    kind: kind,
                  );
              Navigator.of(context).pop(created);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  mobile.dispose();
  area.dispose();
  return party;
}

Future<MaterialStock?> _showMaterialDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  return showMaterialEditor(context, ref);
}

Future<String?> _showCommandDialog(BuildContext context) async {
  final command = TextEditingController(
    text: 'Purchase 500 kg coconut shell at 15 rupees',
  );
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _Sheet(
      title: 'Voice Command',
      child: Column(
        children: [
          TextField(
            controller: command,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.mic),
              labelText: 'Command text',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(command.text),
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Parse Command'),
          ),
        ],
      ),
    ),
  );
  command.dispose();
  return result;
}

Future<void> _sendPurchaseWhatsApp(
  BuildContext context,
  WidgetRef ref,
  PurchaseRecord purchase,
) {
  return _openWhatsAppToMobile(
    context,
    ref,
    mobile: purchase.seller.mobile,
    message: _purchaseWhatsAppMessage(purchase),
    action: 'whatsapp_purchase_sent',
    screen: 'Purchase',
    details: purchase.invoiceNumber,
  );
}

Future<void> _sendSaleWhatsApp(
  BuildContext context,
  WidgetRef ref,
  SaleRecord sale,
) async {
  final state = ref.read(businessProvider);
  final recipients = _saleWhatsAppRecipients(sale);
  if (recipients.isEmpty) {
    _snack(context, 'No WhatsApp mobile number available.');
    return;
  }

  final message = salesInvoiceWhatsAppMessage(state, sale);
  var opened = 0;
  for (final recipient in recipients) {
    final launched = await _launchWhatsAppNumber(
      context,
      number: recipient.number,
      message: message,
    );
    if (launched) {
      opened++;
    }
  }
  if (opened == 0) {
    return;
  }
  ref
      .read(businessProvider.notifier)
      .recordWhatsAppShared(
        action: 'whatsapp_sales_sent',
        screen: 'Sales',
        details:
            '${sale.invoiceNumber} ${recipients.map((item) => item.label).join(', ')}',
      );
  if (context.mounted) {
    _snack(context, 'WhatsApp opened for $opened recipient(s).');
  }
}

Future<void> _sendSalePaymentReminderWhatsApp(
  BuildContext context,
  WidgetRef ref,
  SaleRecord sale, {
  required bool includeAmount,
}) async {
  if (!sale.isPaymentPending) {
    _snack(context, 'Payment already received for this sale.');
    return;
  }
  if (sale.reminderSent) {
    _snack(
      context,
      'Reminder already sent by ${sale.reminderSentBy.isEmpty ? 'staff' : sale.reminderSentBy}.',
    );
    return;
  }
  final number = _indiaWhatsAppNumber(sale.customer.mobile);
  if (number == null) {
    _snack(context, 'Customer WhatsApp/mobile number not available.');
    return;
  }
  final message = _salePaymentReminderMessage(
    ref.read(businessProvider),
    sale,
    includeAmount: includeAmount,
  );
  final launched = await _launchWhatsAppNumber(
    context,
    number: number,
    message: message,
  );
  if (!launched) {
    return;
  }
  ref
      .read(businessProvider.notifier)
      .markSalePaymentReminderSent(sale, sentWithAmount: includeAmount);
  if (context.mounted) {
    _snack(
      context,
      includeAmount
          ? 'Owner reminder opened with pending amount.'
          : 'Manager reminder opened without amount details.',
    );
  }
}

String _salePaymentReminderMessage(
  BusinessState state,
  SaleRecord sale, {
  required bool includeAmount,
}) {
  final lines = <String>[
    'Dear ${sale.customer.name},',
    '',
    'This is a payment reminder for your scrap sale bill.',
    'Invoice: ${sale.invoiceNumber}',
    'Date: ${DateFormat('dd MMM yyyy').format(sale.createdAt)}',
    'Material / Weight: ${sale.items.map((item) => '${item.materialName} ${kg(item.weightKg)}').join(', ')}',
  ];
  if (includeAmount) {
    lines.addAll([
      '',
      'Bill Amount: ${money(sale.totalAmount)}',
      'Paid Amount: ${money(sale.receivedAmount)}',
      'Pending Amount: ${money(sale.balanceAmount.clamp(0, double.infinity))}',
      '',
      'Payment Details:',
      'GPay / UPI: $paymentUpiMobile',
    ]);
  } else {
    lines.addAll([
      '',
      'Payment status: Pending',
      'Kindly clear the pending bill at the earliest.',
    ]);
  }
  lines.addAll(['', 'Regards,', companyInvoiceName]);
  return lines.join('\n');
}

List<_WhatsAppRecipient> _saleWhatsAppRecipients(SaleRecord sale) {
  final recipients = <_WhatsAppRecipient>[];

  void add(String label, String mobile) {
    final number = _indiaWhatsAppNumber(mobile);
    if (number == null) {
      return;
    }
    recipients.add(_WhatsAppRecipient(label: label, number: number));
  }

  add('Customer', sale.customer.mobile);
  return recipients;
}

Future<bool> _launchWhatsAppNumber(
  BuildContext context, {
  required String number,
  required String message,
}) async {
  final uri = Uri.parse(
    'https://wa.me/$number?text=${Uri.encodeComponent(message)}',
  );
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    _snack(context, 'WhatsApp is not installed.');
  }
  return launched;
}

Future<void> _sendPartyWhatsApp(
  BuildContext context,
  WidgetRef ref,
  Party party,
) {
  final label = party.kind == PartyKind.seller ? 'Seller' : 'Customer';
  return _openWhatsAppToMobile(
    context,
    ref,
    mobile: party.mobile,
    message: [
      appDisplayName,
      '$label Profile',
      '',
      'Name: ${party.name}',
      'Mobile: ${party.mobile}',
      if (party.area.trim().isNotEmpty) 'Area: ${party.area}',
      if (party.address.trim().isNotEmpty) 'Address: ${party.address}',
    ].join('\n'),
    action: 'whatsapp_${party.kind.name}_profile_sent',
    screen: '$label Profile',
    details: party.name,
  );
}

Future<void> _openWhatsAppToMobile(
  BuildContext context,
  WidgetRef ref, {
  required String mobile,
  required String message,
  required String action,
  required String screen,
  required String details,
}) async {
  final number = _indiaWhatsAppNumber(mobile);
  if (number == null) {
    _snack(context, 'Mobile number not available.');
    return;
  }
  final launched = await _launchWhatsAppNumber(
    context,
    number: number,
    message: message,
  );
  if (!launched) {
    return;
  }
  ref
      .read(businessProvider.notifier)
      .recordWhatsAppShared(action: action, screen: screen, details: details);
}

String? _indiaWhatsAppNumber(String mobile) {
  var digits = mobile.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (digits.length == 10) {
    return '91$digits';
  }
  if (digits.length == 12 && digits.startsWith('91')) {
    return digits;
  }
  return null;
}

class _WhatsAppRecipient {
  const _WhatsAppRecipient({required this.label, required this.number});

  final String label;
  final String number;
}

String _purchaseWhatsAppMessage(PurchaseRecord purchase) {
  return [
    'Dear ${purchase.seller.name},',
    '',
    'Thank you.',
    '',
    'Please find attached Purchase Invoice.',
    '',
    'Invoice No:',
    purchase.invoiceNumber,
    '',
    'Date:',
    DateFormat('dd MMM yyyy').format(purchase.createdAt),
    '',
    'Items:',
    for (final item in purchase.items)
      '${item.materialName} - ${kg(item.actualWeight)} - ${money(item.rate)} - ${money(item.amount)}',
    '',
    'Total Weight:',
    kg(purchase.totalWeightKg),
    '',
    'Total Amount:',
    money(purchase.totalAmount),
    '',
    'Regards,',
    companyInvoiceName,
  ].join('\n');
}

void _showPartyManager(BuildContext context, WidgetRef ref, PartyKind kind) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final state = ref.read(businessProvider);
      final isOwner = state.user.role.isOwnerOrAdmin;
      final parties = kind == PartyKind.seller
          ? state.sellers
          : state.customers;
      return _Sheet(
        title: kind == PartyKind.seller ? 'Sellers' : 'Customers',
        child: Column(
          children: [
            FilledButton.icon(
              onPressed: () => showPartyEditor(context, ref, kind),
              icon: const Icon(Icons.add),
              label: Text(
                kind == PartyKind.seller ? 'Add Seller' : 'Add Customer',
              ),
            ),
            const SizedBox(height: 12),
            if (parties.isEmpty)
              const _EmptyState(
                icon: Icons.people,
                title: 'No accounts',
                subtitle: 'Add an account to start ledger tracking.',
              )
            else
              for (final party in parties)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FeaturePanel(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            EntityAvatar(
                              path: party.photoPath,
                              icon: kind == PartyKind.seller
                                  ? Icons.storefront
                                  : Icons.person,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    party.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    '${party.mobile}  |  ${party.area.isEmpty ? 'No area' : party.area}',
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isOwner)
                              Text(
                                money(party.pendingAmount),
                                style: TextStyle(
                                  color: party.pendingAmount > 0
                                      ? EnterpriseTheme.warning
                                      : EnterpriseTheme.success,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _sendPartyWhatsApp(context, ref, party),
                                icon: const Icon(Icons.chat),
                                label: const Text('WhatsApp'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => showPartyEditor(
                                  context,
                                  ref,
                                  kind,
                                  existing: party,
                                ),
                                icon: const Icon(Icons.edit),
                                label: const Text('Edit'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );
}

void _showSupabase(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _Sheet(
      title: 'Supabase Database Schema',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            SupabaseBusinessGateway.isConfigured
                ? 'Supabase environment is configured.'
                : 'Run this schema in Supabase SQL editor, then build with SUPABASE_URL and SUPABASE_ANON_KEY.',
            style: const TextStyle(color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(
                const ClipboardData(text: SupabaseBusinessGateway.schemaSql),
              );
              _snack(context, 'Schema copied');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy Schema SQL'),
          ),
        ],
      ),
    ),
  );
}

void _showDynamicConfigStatus(BuildContext context, DynamicConfigState config) {
  final summary = [
    'Loaded from Firebase: ${config.loadedFromFirebase ? 'Yes' : 'No'}',
    'Maintenance mode: ${config.remote.maintenanceMode ? 'On' : 'Off'}',
    'Force update: ${config.remote.forceUpdate || config.app.forceUpdate ? 'On' : 'Off'}',
    'Latest version code: ${config.remote.latestVersionCode}',
    'Bottom menu: ${config.visibleBottomMenu.map((item) => item.label).join(', ')}',
    'More menu: ${config.visibleMoreMenu.map((item) => item.label).join(', ')}',
    'Pages: ${config.pages.keys.join(', ')}',
  ].join('\n');
  _showInfo(context, 'Firebase Dynamic Config', summary);
}

void _showDispatchDialog(BuildContext context, WidgetRef ref) {
  final material = TextEditingController();
  final customer = TextEditingController();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _Sheet(
      title: 'Dispatch Entry',
      child: Column(
        children: [
          TextField(
            controller: customer,
            decoration: const InputDecoration(labelText: 'Customer'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: material,
            decoration: const InputDecoration(labelText: 'Material'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              ref
                  .read(businessProvider.notifier)
                  .recordDispatch(
                    material: material.text.trim().isEmpty
                        ? 'Material'
                        : material.text,
                    customer: customer.text.trim().isEmpty
                        ? 'Customer'
                        : customer.text,
                  );
              Navigator.of(context).pop();
              _snack(context, 'Dispatch activity saved');
            },
            icon: const Icon(Icons.local_shipping),
            label: const Text('Save Dispatch'),
          ),
        ],
      ),
    ),
  ).whenComplete(() {
    material.dispose();
    customer.dispose();
  });
}

Future<void> _confirm(
  BuildContext context,
  String title,
  String message,
  VoidCallback onConfirm, {
  String confirmLabel = 'Move',
  String successMessage = 'Moved to Recycle Bin',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    onConfirm();
    if (context.mounted) {
      _snack(context, successMessage);
    }
  }
}

void _showInfo(BuildContext context, String title, String message) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

double _read(TextEditingController controller) {
  return double.tryParse(controller.text.trim()) ?? 0;
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _fieldLabel(DynamicPageDefinition page, String key, String fallback) {
  final field = _fieldByKey(page, key);
  if (field == null || field.label.trim().isEmpty) {
    return fallback;
  }
  return field.label;
}

bool _fieldVisible(DynamicPageDefinition page, String key) {
  return _fieldByKey(page, key)?.visible ?? true;
}

DynamicFieldConfig? _fieldByKey(DynamicPageDefinition page, String key) {
  for (final field in page.fields) {
    if (field.key == key) {
      return field;
    }
  }
  return null;
}

String _dashboardTitle(UserRole role) {
  switch (role) {
    case UserRole.owner:
      return 'Owner Dashboard';
    case UserRole.admin:
      return 'Admin Dashboard';
    case UserRole.supervisor:
      return 'Supervisor Dashboard';
    case UserRole.manager:
      return 'Manager Dashboard';
    case UserRole.accountant:
      return 'Accountant Dashboard';
    case UserRole.user:
      return 'User Dashboard';
  }
}

IconData _iconFromName(String value) {
  switch (value) {
    case 'dashboard':
      return Icons.dashboard;
    case 'purchase':
      return Icons.add_shopping_cart;
    case 'sales':
      return Icons.point_of_sale;
    case 'inventory':
      return Icons.inventory_2;
    case 'stock_register':
      return Icons.table_chart;
    case 'more':
      return Icons.apps;
    case 'reports':
    case 'report':
      return Icons.summarize;
    case 'finance':
    case 'wallet':
    case 'cash':
      return Icons.account_balance_wallet;
    case 'account_balance':
      return Icons.account_balance;
    case 'dispatch':
      return Icons.local_shipping;
    case 'voice':
      return Icons.mic;
    case 'seller':
      return Icons.storefront;
    case 'customer':
      return Icons.people;
    case 'security':
      return Icons.verified_user;
    case 'settings':
      return Icons.settings;
    case 'page':
    case 'custom':
    case 'custom_page':
      return Icons.dynamic_form;
    default:
      return Icons.apps;
  }
}

IconData _outlinedIconFromName(String value) {
  switch (value) {
    case 'dashboard':
      return Icons.dashboard_outlined;
    case 'purchase':
      return Icons.shopping_cart_outlined;
    case 'sales':
      return Icons.point_of_sale_outlined;
    case 'inventory':
      return Icons.inventory_2_outlined;
    case 'stock_register':
      return Icons.table_chart_outlined;
    case 'reports':
    case 'report':
      return Icons.summarize_outlined;
    case 'finance':
    case 'wallet':
    case 'cash':
      return Icons.account_balance_wallet_outlined;
    case 'account_balance':
      return Icons.account_balance_outlined;
    case 'voice':
      return Icons.mic_none;
    case 'more':
      return Icons.more_horiz;
    default:
      return Icons.apps_outlined;
  }
}

Object _typedValue(String raw, String type) {
  if (type == 'number' ||
      type == 'currency' ||
      type == 'kg' ||
      type == 'rate') {
    return double.tryParse(raw) ?? 0;
  }
  if (type == 'bool' || type == 'boolean') {
    return raw.toLowerCase() == 'true' ||
        raw == '1' ||
        raw.toLowerCase() == 'yes';
  }
  return raw;
}

String _rowTitle(Map<String, dynamic> row, List<DynamicFieldConfig> fields) {
  if (fields.isEmpty) {
    return row['id']?.toString() ?? 'Record';
  }
  final key = fields.first.key;
  final value = row[key]?.toString();
  return value == null || value.isEmpty ? 'Record' : value;
}

String _rowSubtitle(Map<String, dynamic> row, List<DynamicFieldConfig> fields) {
  final parts = fields
      .skip(1)
      .take(3)
      .map((field) {
        final value = row[field.key]?.toString();
        if (value == null || value.isEmpty) {
          return '';
        }
        return '${field.label}: $value';
      })
      .where((value) => value.isNotEmpty);
  return parts.isEmpty ? row['id']?.toString() ?? '' : parts.join('  |  ');
}
