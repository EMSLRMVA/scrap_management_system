import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_branding.dart';
import '../core/enterprise_theme.dart';
import '../core/money_format.dart';
import '../domain/business_models.dart';
import '../domain/stock_calculation.dart';
import '../utils/graph_popup_guard.dart';
import 'ai_copilot.dart';
import 'business_controller.dart';
import 'enterprise_feature_screens.dart';
import 'manual_stock_reminders.dart';

enum OperationalDashboardMode { focus, detailed }

class OperationalDashboard extends ConsumerStatefulWidget {
  const OperationalDashboard({
    super.key,
    required this.onNavigate,
    this.onOpenExpectedStock,
    this.onOpenWeightLoss,
    this.previewRole,
    this.previewName,
    this.previewEmail,
    this.previewMobile,
    this.embedded = false,
  });

  final ValueChanged<String> onNavigate;
  final VoidCallback? onOpenExpectedStock;
  final VoidCallback? onOpenWeightLoss;
  final UserRole? previewRole;
  final String? previewName;
  final String? previewEmail;
  final String? previewMobile;
  final bool embedded;

  @override
  ConsumerState<OperationalDashboard> createState() =>
      _OperationalDashboardState();
}

class _OperationalDashboardState extends ConsumerState<OperationalDashboard> {
  OperationalDashboardMode _mode = OperationalDashboardMode.focus;
  final _expanded = <String, bool>{
    'tasks': true,
    'cash': true,
    'stock': true,
    'purchase': true,
  };
  bool _loaded = false;
  bool _shortagePopupShown = false;

  String get _userKey {
    final state = ref.read(businessProvider);
    final role = widget.previewRole ?? state.user.role;
    final name = widget.previewName ?? state.user.name;
    return '${role.name}_${name.trim().toLowerCase()}';
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadPrefs);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _userKey;
    final savedMode = prefs.getString('operational_dashboard_mode_$key');
    if (!mounted) {
      return;
    }
    setState(() {
      _mode = savedMode == OperationalDashboardMode.detailed.name
          ? OperationalDashboardMode.detailed
          : OperationalDashboardMode.focus;
      for (final section in _expanded.keys.toList()) {
        _expanded[section] =
            prefs.getBool('operational_dashboard_section_${key}_$section') ??
            true;
      }
      _loaded = true;
    });
  }

  Future<void> _setMode(OperationalDashboardMode mode) async {
    setState(() => _mode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('operational_dashboard_mode_$_userKey', mode.name);
  }

  Future<void> _toggleSection(String key) async {
    setState(() => _expanded[key] = !(_expanded[key] ?? true));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'operational_dashboard_section_${_userKey}_$key',
      _expanded[key] ?? true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final role = widget.previewRole ?? state.user.role;
    final name = widget.previewName ?? state.user.name;
    final email = widget.previewEmail ?? state.user.email;
    final mobile = widget.previewMobile ?? state.user.mobile;
    final isOwnerPreview = role.isOwnerOrAdmin;
    final stats = _OperationalStats.build(state, name);
    final variances = _stockVariances(state, ownerView: isOwnerPreview);
    final shortages = variances.where((item) => item.shortageKg > 0).toList();
    final increases = variances.where((item) => item.surplusKg > 0).toList();
    final criticalShortage = shortages.firstOrNull;
    final topIncrease = isOwnerPreview ? increases.firstOrNull : null;
    final stockRows = stockTargetRows(state);
    final pendingCustomerBills = state.activeSales
        .where((sale) => sale.isPaymentPending)
        .where(
          (sale) =>
              role == UserRole.manager || _samePerson(sale.createdBy, name),
        )
        .toList();

    if (_loaded &&
        !widget.embedded &&
        !_shortagePopupShown &&
        criticalShortage != null) {
      _shortagePopupShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Critical Alert'),
            content: Text(
              'Critical: ALERT: ${criticalShortage.material.name} weight loss detected: ${kg(criticalShortage.shortageKg)}',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Review Dashboard'),
              ),
            ],
          ),
        );
      });
    }

    final content = ListView(
      padding: EdgeInsets.fromLTRB(16, widget.embedded ? 0 : 10, 16, 18),
      children: [
        _OperationalHeader(
          name: name,
          role: role,
          preview: widget.previewRole != null,
          onProfile: () => _openSimpleDetails(context, 'Profile', [
            ['Name', name],
            ['Role', _roleLabel(role)],
            ['Company', state.user.company],
            if (email.trim().isNotEmpty) ['Email', email],
            if (mobile.trim().isNotEmpty) ['Mobile', mobile],
            ['Date', DateFormat('dd MMM yyyy').format(DateTime.now())],
          ]),
        ),
        const SizedBox(height: 12),
        _SupervisorStockRiskTicker(text: stockRiskTickerText(state)),
        const SizedBox(height: 12),
        _OperationalExpectedStockGraph(
          rows: stockRows,
          onDetails: widget.onOpenExpectedStock,
        ),
        const SizedBox(height: 12),
        _SupervisorStockTargetCard(rows: stockRows),
        const SizedBox(height: 12),
        SegmentedButton<OperationalDashboardMode>(
          segments: const [
            ButtonSegment(
              value: OperationalDashboardMode.focus,
              label: Text('Focus Mode'),
              icon: Icon(Icons.center_focus_strong),
            ),
            ButtonSegment(
              value: OperationalDashboardMode.detailed,
              label: Text('Detailed Mode'),
              icon: Icon(Icons.dashboard_customize),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (value) => _setMode(value.first),
        ),
        const SizedBox(height: 12),
        if (aiEnabled) ...[
          const _DashboardAiActions(),
          const SizedBox(height: 10),
          AiInsightTicker(
            onOpenInsights: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AiInsightsScreen())),
          ),
          const SizedBox(height: 12),
        ],
        if (criticalShortage != null) ...[
          _StockShortageBanner(variance: criticalShortage),
          const SizedBox(height: 12),
        ],
        if (topIncrease != null) ...[
          _StockIncreaseBanner(variance: topIncrease),
          const SizedBox(height: 12),
        ],
        if (pendingCustomerBills.isNotEmpty) ...[
          _PendingCustomerBillAlert(
            sales: pendingCustomerBills,
            onOpenSales: () => widget.onNavigate('sales'),
          ),
          const SizedBox(height: 12),
        ],
        _KpiGrid(
          cards: _kpisFor(context, state, stats, shortages),
          detailed: _mode == OperationalDashboardMode.detailed,
        ),
        const SizedBox(height: 12),
        _CollapsibleOperationalSection(
          title: 'Urgent Pending Tasks',
          subtitle: 'Bills, approvals and reconciliation checks',
          expanded: _expanded['tasks'] ?? true,
          onToggle: () => _toggleSection('tasks'),
          child: _TaskList(stats: stats, shortages: shortages),
        ),
        if (_mode == OperationalDashboardMode.detailed) ...[
          const SizedBox(height: 12),
          _CollapsibleOperationalSection(
            title: 'Cash Accountability',
            subtitle: 'Allocation, spending and settlement view',
            expanded: _expanded['cash'] ?? true,
            onToggle: () => _toggleSection('cash'),
            child: _CashAccountabilitySection(stats: stats),
          ),
          const SizedBox(height: 12),
          _CollapsibleOperationalSection(
            title: 'Stock Responsibility',
            subtitle: 'Expected stock vs physical stock',
            expanded: _expanded['stock'] ?? true,
            onToggle: () => _toggleSection('stock'),
            child: _StockResponsibilitySection(
              variances: variances,
              ownerView: isOwnerPreview,
            ),
          ),
          const SizedBox(height: 12),
          _CollapsibleOperationalSection(
            title: 'Purchase Performance',
            subtitle: 'Purchase weight, supplier contribution and cap review',
            expanded: _expanded['purchase'] ?? true,
            onToggle: () => _toggleSection('purchase'),
            child: _PurchasePerformanceSection(state: state, userName: name),
          ),
        ],
      ],
    );

    if (widget.embedded) {
      return content;
    }
    return content;
  }

  List<_OperationalKpi> _kpisFor(
    BuildContext context,
    BusinessState state,
    _OperationalStats stats,
    List<_StockVariance> shortages,
  ) {
    return [
      _OperationalKpi(
        label: 'Cash Allocated',
        value: money(stats.cashGivenByOwner),
        icon: Icons.payments,
        color: EnterpriseTheme.primary,
        onTap: () => _push(context, const CashAllocationScreen()),
      ),
      _OperationalKpi(
        label: 'Cash Balance',
        value: money(stats.currentCashBalance),
        icon: Icons.account_balance_wallet,
        color: EnterpriseTheme.success,
        onTap: () => _push(context, const SupervisorCashLedgerScreen()),
      ),
      _OperationalKpi(
        label: 'Today Spent',
        value: money(stats.todaySpent),
        icon: Icons.receipt_long,
        color: EnterpriseTheme.warning,
        onTap: () => _push(context, const SupervisorExpenseScreen()),
      ),
      _OperationalKpi(
        label: 'Pending Settlement',
        value: money(stats.pendingSettlement),
        icon: Icons.fact_check,
        color: stats.pendingSettlement > 0
            ? EnterpriseTheme.error
            : EnterpriseTheme.success,
        onTap: () => _push(context, const SupervisorExpenseScreen()),
      ),
      _OperationalKpi(
        label: 'Purchase Weight Today',
        value: kg(stats.todayPurchaseWeight),
        icon: Icons.shopping_cart,
        color: const Color(0xFF2563EB),
        onTap: () => widget.onNavigate('purchase'),
      ),
      _OperationalKpi(
        label: 'Sale Weight Today',
        value: kg(stats.todaySaleWeight),
        icon: Icons.local_shipping,
        color: EnterpriseTheme.success,
        onTap: () => widget.onNavigate('sales'),
      ),
      _OperationalKpi(
        label: 'Physical Stock Variance',
        value: kg(
          shortages.fold<double>(0, (sum, item) => sum + item.shortageKg),
        ),
        icon: Icons.inventory_2,
        color: shortages.isEmpty
            ? EnterpriseTheme.success
            : EnterpriseTheme.error,
        onTap: () => _push(context, const StockRegisterScreen()),
      ),
      _OperationalKpi(
        label: 'To Recover',
        value: kg(
          shortages.fold<double>(0, (sum, item) => sum + item.shortageKg),
        ),
        icon: Icons.assignment_late,
        color: shortages.isEmpty
            ? EnterpriseTheme.success
            : EnterpriseTheme.error,
        onTap: () => _openVarianceDetails(context, shortages),
      ),
      _OperationalKpi(
        label: 'Pending Price Approvals',
        value: stats.priceApprovalRequests.toString(),
        icon: Icons.price_check,
        color: stats.priceApprovalRequests > 0
            ? EnterpriseTheme.warning
            : EnterpriseTheme.success,
        onTap: () => _push(
          context,
          OperationalDetailScreen(
            title: 'Pending Price Approvals',
            rows: _priceApprovalRows(state),
            emptyTitle: 'No pending approval requests.',
          ),
        ),
      ),
      _OperationalKpi(
        label: 'Pending Expense Bills',
        value: stats.expensesMissingBills.toString(),
        icon: Icons.upload_file,
        color: stats.expensesMissingBills > 0
            ? EnterpriseTheme.warning
            : EnterpriseTheme.success,
        onTap: () => _push(context, const SupervisorExpenseScreen()),
      ),
      _OperationalKpi(
        label: 'Pending Reconciliation Checks',
        value: shortages.length.toString(),
        icon: Icons.rule,
        color: shortages.isEmpty
            ? EnterpriseTheme.success
            : EnterpriseTheme.error,
        onTap: () => _push(context, const StockRegisterScreen()),
      ),
    ];
  }
}

class _OperationalHeader extends StatelessWidget {
  const _OperationalHeader({
    required this.name,
    required this.role,
    required this.preview,
    required this.onProfile,
  });

  final String name;
  final UserRole role;
  final bool preview;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return FeaturePanel(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: EnterpriseTheme.primary,
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
                  '${_greeting(now)}, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _RoleChip(label: _roleLabel(role)),
                    _RoleChip(label: DateFormat('dd MMM yyyy').format(now)),
                    if (preview) const _RoleChip(label: 'Owner Preview'),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: onProfile,
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
    );
  }
}

class _DashboardAiActions extends StatelessWidget {
  const _DashboardAiActions();

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AiChatPanel(compact: true),
              ),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Ask AI'),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: 'Speak to AI',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const AiChatPanel(compact: true),
            ),
            icon: const Icon(Icons.mic),
          ),
        ],
      ),
    );
  }
}

class _SupervisorStockRiskTicker extends StatefulWidget {
  const _SupervisorStockRiskTicker({required this.text});

  final String text;

  @override
  State<_SupervisorStockRiskTicker> createState() =>
      _SupervisorStockRiskTickerState();
}

class _SupervisorStockRiskTickerState extends State<_SupervisorStockRiskTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final hasCritical = widget.text.contains('Critical');
    final colors = hasCritical
        ? [tokens.dangerColor, tokens.warningColor]
        : [tokens.successColor, tokens.secondaryColor];
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PhysicalStockVerificationScreen(),
        ),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return FractionalTranslation(
                      translation: Offset(1 - (_controller.value * 2), 0),
                      child: child,
                    );
                  },
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
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
}

class _SupervisorStockTargetCard extends StatelessWidget {
  const _SupervisorStockTargetCard({required this.rows});

  final List<StockTargetRow> rows;

  @override
  Widget build(BuildContext context) {
    final totalExpected = rows.fold<double>(
      0,
      (sum, row) => sum + row.expectedStock,
    );
    final criticalCount = rows.where((row) => row.weightLoss > 0).length;
    final pendingCount = rows
        .where((row) => row.physicalStock <= 0 && row.expectedStock > 0)
        .length;
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today Stock Verification Target',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TargetMiniStat(
                  label: 'Items',
                  value: rows.length.toString(),
                ),
              ),
              Expanded(
                child: _TargetMiniStat(
                  label: 'Expected',
                  value: kg(totalExpected),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TargetMiniStat(
                  label: 'Critical',
                  value: criticalCount.toString(),
                ),
              ),
              Expanded(
                child: _TargetMiniStat(
                  label: 'Pending',
                  value: pendingCount.toString(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PhysicalStockVerificationScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.fact_check),
                  label: const Text('Start Verification'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ManualWhatsAppReminderScreen(
                        initialType:
                            StockReminderType.physicalStockVerification,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.send),
                  label: const Text('Send Report'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OperationalExpectedStockGraph extends StatelessWidget {
  const _OperationalExpectedStockGraph({required this.rows, this.onDetails});

  final List<StockTargetRow> rows;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return _OperationalStockGraphCard(
      title: 'Expected Closing Stock',
      rows: rows,
      color: tokens.primaryColor,
      colorFor: (row) => _operationalExpectedStockStatusColor(tokens, row),
      statusLabelFor: _operationalExpectedStockStatusLabel,
      valueFor: (row) => row.expectedStock,
      emptyText: 'Expected stock appears after items are added.',
      onTapRow: (row) => _showOperationalStockDetails(context, row),
      onDetails:
          onDetails ??
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StockRegisterScreen()),
          ),
    );
  }
}

class _OperationalStockGraphCard extends StatelessWidget {
  const _OperationalStockGraphCard({
    required this.title,
    required this.rows,
    required this.color,
    this.colorFor,
    this.statusLabelFor,
    required this.valueFor,
    required this.emptyText,
    required this.onTapRow,
    required this.onDetails,
  });

  final String title;
  final List<StockTargetRow> rows;
  final Color color;
  final Color Function(StockTargetRow row)? colorFor;
  final String Function(StockTargetRow row)? statusLabelFor;
  final double Function(StockTargetRow row) valueFor;
  final String emptyText;
  final ValueChanged<StockTargetRow> onTapRow;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final values = rows.map(valueFor).toList();
    final maxValue = values.fold<double>(
      1,
      (largest, value) => value > largest ? value : largest,
    );
    final minValue = values.fold<double>(
      0,
      (smallest, value) => value < smallest ? value : smallest,
    );
    final padding = ((maxValue - minValue).abs() * 0.20).clamp(10, 1000000);
    final rowColors = [for (final row in rows) colorFor?.call(row) ?? color];
    final chartColor = rowColors.isNotEmpty ? rowColors.first : color;
    final chartGradient = rowColors.length > 1
        ? LinearGradient(
            colors: rowColors,
            stops: [
              for (var index = 0; index < rowColors.length; index++)
                index / (rowColors.length - 1),
            ],
          )
        : null;
    final chartWidth = (rows.length * 72)
        .clamp(MediaQuery.of(context).size.width - 32, 1500)
        .toDouble();
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(onPressed: onDetails, child: const Text('Details')),
            ],
          ),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            Text(
              emptyText,
              style: TextStyle(
                color: tokens.resolvedMutedTextColor,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 150,
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
                        final index = spots.first.spotIndex;
                        if (index >= 0 && index < rows.length) {
                          onTapRow(rows[index]);
                        }
                      },
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => const Color(0xFF0F172A),
                        getTooltipItems: (spots) => spots.map((spot) {
                          final row = rows[spot.spotIndex];
                          final status = statusLabelFor?.call(row);
                          return LineTooltipItem(
                            status == null
                                ? '${row.material.name}\n${kg(valueFor(row))}'
                                : '${row.material.name}\n${kg(valueFor(row))}\n$status',
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
                            _compactOperationalKg(value),
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
                                    _shortOperationalLabel(
                                      rows[index].material.name,
                                    ),
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
                            FlSpot(index.toDouble(), valueFor(rows[index])),
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
                                rowIndex >= 0 && rowIndex < rowColors.length
                                ? rowColors[rowIndex]
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
                          color: chartColor.withValues(alpha: 0.14),
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

Color _operationalExpectedStockStatusColor(
  AppThemeModel tokens,
  StockTargetRow row,
) {
  if (row.difference < -0.01) {
    return tokens.dangerColor;
  }
  if (row.difference > 0.01) {
    return tokens.successColor;
  }
  return tokens.primaryColor;
}

String _operationalExpectedStockStatusLabel(StockTargetRow row) {
  if (row.difference < -0.01) {
    return 'Weight Loss';
  }
  if (row.difference > 0.01) {
    return 'Weight Increase';
  }
  return 'No Difference';
}

void _showOperationalStockDetails(BuildContext context, StockTargetRow row) {
  final tokens = EnterpriseTheme.tokensOf(context);
  final differenceColor = row.difference < -0.01
      ? tokens.dangerColor
      : row.difference > 0.01
      ? tokens.successColor
      : tokens.primaryColor;
  GraphPopupGuard.show<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FeatureSheet(
      title: '${row.material.name} - Stock Details',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OperationalDetailLine('Month Opening Qty', kg(row.openingStock)),
          _OperationalDetailLine('Total Purchase Qty', kg(row.purchaseQty)),
          _OperationalDetailLine('Total Sale Qty', kg(row.saleQty)),
          _OperationalDetailLine(
            'Expected Closing Stock',
            kg(row.expectedStock),
          ),
          _OperationalDetailLine(
            'Actual Physical Stock',
            kg(row.physicalStock),
          ),
          _OperationalDetailLine(
            'Stock Difference',
            kg(row.difference),
            valueColor: differenceColor,
          ),
          if (row.weightLoss > 0)
            _OperationalDetailLine(
              'Weight Loss Qty',
              kg(row.weightLoss),
              valueColor: tokens.dangerColor,
            ),
          _OperationalDetailLine('Last Purchase Date', row.lastPurchaseLabel),
          _OperationalDetailLine('Last Sale Date', row.lastSaleLabel),
          _OperationalDetailLine('Status', row.statusLabel),
        ],
      ),
    ),
  );
}

class _OperationalDetailLine extends StatelessWidget {
  const _OperationalDetailLine(this.label, this.value, {this.valueColor});

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

String _compactOperationalKg(num value) {
  final abs = value.abs();
  if (abs >= 100000) {
    return '${(value / 100000).toStringAsFixed(1)}L';
  }
  if (abs >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);
}

String _shortOperationalLabel(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.length <= 2) {
    return value;
  }
  return '${parts.first} ${parts[1]}';
}

class _TargetMiniStat extends StatelessWidget {
  const _TargetMiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.resolvedBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: tokens.resolvedMutedTextColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: EnterpriseTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: EnterpriseTheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: EnterpriseTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.cards, required this.detailed});

  final List<_OperationalKpi> cards;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final visible = detailed ? cards : cards.take(6).toList();
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: [
        for (final card in visible)
          _OperationalKpiCard(
            label: card.label,
            value: card.value,
            icon: card.icon,
            color: card.color,
            onTap: card.onTap,
          ),
      ],
    );
  }
}

class _OperationalKpi {
  const _OperationalKpi({
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
}

class _OperationalKpiCard extends StatelessWidget {
  const _OperationalKpiCard({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: FeaturePanel(
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 16,
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

class _CollapsibleOperationalSection extends StatelessWidget {
  const _CollapsibleOperationalSection({
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          if (expanded) ...[const SizedBox(height: 12), child],
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.stats, required this.shortages});

  final _OperationalStats stats;
  final List<_StockVariance> shortages;

  @override
  Widget build(BuildContext context) {
    final tasks = <_TaskItem>[
      if (stats.expensesMissingBills > 0)
        _TaskItem(
          icon: Icons.upload_file,
          title: '${stats.expensesMissingBills} expenses without bill proof',
          subtitle: 'Upload bill or add notes before settlement.',
          color: EnterpriseTheme.warning,
        ),
      if (stats.pendingSettlement > 0)
        _TaskItem(
          icon: Icons.fact_check,
          title: 'Cash settlement pending',
          subtitle: '${money(stats.pendingSettlement)} needs owner review.',
          color: EnterpriseTheme.error,
        ),
      if (shortages.isNotEmpty)
        _TaskItem(
          icon: Icons.inventory,
          title: '${shortages.length} stock checks need acknowledgement',
          subtitle: 'Open reconciliation and verify physical count.',
          color: EnterpriseTheme.error,
        ),
      if (stats.priceApprovalRequests > 0)
        _TaskItem(
          icon: Icons.price_check,
          title: '${stats.priceApprovalRequests} rate cap reviews pending',
          subtitle: 'Purchase rate appears above approved material base.',
          color: EnterpriseTheme.warning,
        ),
    ];
    if (tasks.isEmpty) {
      return const EmptyFeatureState(
        icon: Icons.task_alt,
        title: 'No urgent pending tasks',
        subtitle: 'Cash, bills, and stock checks are clean for now.',
      );
    }
    return Column(
      children: [
        for (final task in tasks) ...[
          _TaskTile(task: task),
          if (task != tasks.last) const Divider(height: 18),
        ],
      ],
    );
  }
}

class _TaskItem {
  const _TaskItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final _TaskItem task;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: task.color.withValues(alpha: 0.12),
          child: Icon(task.icon, color: task.color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                task.subtitle,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CashAccountabilitySection extends StatelessWidget {
  const _CashAccountabilitySection({required this.stats});

  final _OperationalStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TwoColumnLines(
          lines: [
            ['Opening cash', money(stats.openingBalance)],
            ['Top-ups received', money(stats.cashGivenByOwner)],
            ['Recorded expenses', money(stats.otherExpenses)],
            ['Purchase-linked cash', money(stats.scrapPurchaseUsed)],
            ['Unsubmitted bills', money(stats.missingBillAmount)],
            ['Pending settlement', money(stats.pendingSettlement)],
            ['Returned cash', money(0)],
            ['Final balance', money(stats.currentCashBalance)],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _push(context, const SupervisorExpenseScreen()),
                icon: const Icon(Icons.add),
                label: const Text('Add Expense'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _push(context, const SupervisorCashLedgerScreen()),
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text('View Ledger'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StockResponsibilitySection extends StatelessWidget {
  const _StockResponsibilitySection({
    required this.variances,
    required this.ownerView,
  });

  final List<_StockVariance> variances;
  final bool ownerView;

  @override
  Widget build(BuildContext context) {
    final visible = variances
        .where((item) => ownerView || item.shortageKg > 0)
        .take(5)
        .toList();
    if (visible.isEmpty) {
      return const EmptyFeatureState(
        icon: Icons.inventory_2,
        title: 'No unresolved stock variance found.',
        subtitle: 'System stock and physical stock are matching.',
      );
    }
    return Column(
      children: [
        for (final variance in visible) ...[
          _StockVarianceTile(variance: variance, ownerView: ownerView),
          if (variance != visible.last) const Divider(height: 18),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _push(context, const StockRegisterScreen()),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Reconciliation'),
          ),
        ),
      ],
    );
  }
}

class _StockShortageBanner extends StatelessWidget {
  const _StockShortageBanner({required this.variance});

  final _StockVariance variance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EnterpriseTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: EnterpriseTheme.error.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CRITICAL STOCK ALERT',
            style: TextStyle(
              color: EnterpriseTheme.error,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Critical: ALERT: ${variance.material.name} weight loss detected: ${kg(variance.shortageKg)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _StockIncreaseBanner extends StatelessWidget {
  const _StockIncreaseBanner({required this.variance});

  final _StockVariance variance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EnterpriseTheme.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: EnterpriseTheme.success.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: EnterpriseTheme.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${variance.material.name} weight increase detected: ${kg(variance.surplusKg)}',
              style: const TextStyle(
                color: EnterpriseTheme.success,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockVarianceTile extends StatelessWidget {
  const _StockVarianceTile({required this.variance, required this.ownerView});

  final _StockVariance variance;
  final bool ownerView;

  @override
  Widget build(BuildContext context) {
    final shortage = variance.shortageKg > 0;
    final surplus = variance.surplusKg > 0;
    final color = shortage
        ? EnterpriseTheme.error
        : surplus
        ? EnterpriseTheme.success
        : EnterpriseTheme.success;
    final status = shortage
        ? 'Weight Loss'
        : surplus
        ? 'Weight Increase'
        : 'Matched';
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(Icons.inventory_2, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                variance.material.name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                ownerView
                    ? 'System ${kg(variance.expectedKg)} | Physical ${kg(variance.physicalKg)} | Variance ${kg(variance.varianceKg)}'
                    : 'System ${kg(variance.expectedKg)} | Physical ${kg(variance.physicalKg)}',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          shortage
              ? kg(variance.shortageKg)
              : surplus
              ? kg(variance.surplusKg)
              : status,
          textAlign: TextAlign.right,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _PurchasePerformanceSection extends StatelessWidget {
  const _PurchasePerformanceSection({
    required this.state,
    required this.userName,
  });

  final BusinessState state;
  final String userName;

  @override
  Widget build(BuildContext context) {
    final purchases = state.activePurchases
        .where((item) => _samePerson(item.createdBy, userName))
        .toList();
    final weekWeight = purchases
        .where((item) => DateTime.now().difference(item.createdAt).inDays <= 6)
        .fold<double>(0, (sum, item) => sum + item.totalWeightKg);
    final materialWeights = <String, double>{};
    final supplierWeights = <String, double>{};
    DateTime? lastPurchase;
    for (final purchase in purchases) {
      if (lastPurchase == null || purchase.createdAt.isAfter(lastPurchase)) {
        lastPurchase = purchase.createdAt;
      }
      supplierWeights[purchase.seller.name] =
          (supplierWeights[purchase.seller.name] ?? 0) + purchase.totalWeightKg;
      for (final item in purchase.items) {
        materialWeights[item.materialName] =
            (materialWeights[item.materialName] ?? 0) + item.weightKg;
      }
    }
    return Column(
      children: [
        _TwoColumnLines(
          lines: [
            ['Week purchase weight', kg(weekWeight)],
            [
              'Last purchase time',
              lastPurchase == null ? 'No purchase' : shortDate(lastPurchase),
            ],
            ['Rate cap reviews', _priceApprovalRows(state).length.toString()],
          ],
        ),
        const SizedBox(height: 12),
        _MiniRanking(
          title: 'Purchase trend by material',
          data: materialWeights,
        ),
        const SizedBox(height: 10),
        _MiniRanking(
          title: 'Supplier-wise purchase contribution',
          data: supplierWeights,
        ),
      ],
    );
  }
}

class _MiniRanking extends StatelessWidget {
  const _MiniRanking({required this.title, required this.data});

  final String title;
  final Map<String, double> data;

  @override
  Widget build(BuildContext context) {
    final rows = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EnterpriseTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Text(
              'No data',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
            )
          else
            for (final row in rows.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Expanded(child: Text(row.key)),
                    Text(
                      kg(row.value),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _TwoColumnLines extends StatelessWidget {
  const _TwoColumnLines({required this.lines});

  final List<List<String>> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final line in lines) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  line[0],
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ),
              Text(
                line[1],
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          if (line != lines.last) const Divider(height: 18),
        ],
      ],
    );
  }
}

class OperationalDetailScreen extends StatelessWidget {
  const OperationalDetailScreen({
    super.key,
    required this.title,
    required this.rows,
    required this.emptyTitle,
  });

  final String title;
  final List<List<String>> rows;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: rows.isEmpty
          ? EmptyFeatureState(
              icon: Icons.inbox,
              title: emptyTitle,
              subtitle: 'No action is required right now.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final row = rows[index];
                return FeaturePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.first,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      for (final cell in row.skip(1))
                        Text(
                          cell,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class OwnerDashboardPreviewScreen extends ConsumerStatefulWidget {
  const OwnerDashboardPreviewScreen({super.key});

  @override
  ConsumerState<OwnerDashboardPreviewScreen> createState() =>
      _OwnerDashboardPreviewScreenState();
}

class _OwnerDashboardPreviewScreenState
    extends ConsumerState<OwnerDashboardPreviewScreen> {
  UserRole _role = UserRole.supervisor;
  String _name = 'Supervisor Template';

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(businessProvider.notifier)
          .recordSecurityEvent('Owner preview-as opened', _role.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final names = {
      'Supervisor Template',
      'Manager Template',
      for (final item in state.supervisorCashSummaries) item.supervisorName,
      for (final item in state.activePurchases) item.createdBy,
      for (final item in state.activeExpenses) item.addedBy,
    }.where((item) => item.trim().isNotEmpty).toList();
    if (!names.contains(_name)) {
      _name = names.first;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('View Dashboard As')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<UserRole>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(
                        value: UserRole.supervisor,
                        child: Text('Supervisor'),
                      ),
                      DropdownMenuItem(
                        value: UserRole.manager,
                        child: Text('Manager'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _role = value;
                        _name = value == UserRole.manager
                            ? 'Manager Template'
                            : 'Supervisor Template';
                      });
                      ref
                          .read(businessProvider.notifier)
                          .recordSecurityEvent(
                            'Owner preview-as changed',
                            value.name,
                          );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _name,
                    decoration: const InputDecoration(labelText: 'User'),
                    items: [
                      for (final name in names)
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _name = value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: OperationalDashboard(
              onNavigate: (_) {},
              previewRole: _role,
              previewName: _name,
              embedded: true,
            ),
          ),
        ],
      ),
    );
  }
}

class OwnerPermissionCenterScreen extends ConsumerStatefulWidget {
  const OwnerPermissionCenterScreen({super.key});

  @override
  ConsumerState<OwnerPermissionCenterScreen> createState() =>
      _OwnerPermissionCenterScreenState();
}

class _OwnerPermissionCenterScreenState
    extends ConsumerState<OwnerPermissionCenterScreen> {
  String _template = 'Operational Supervisor';
  final _toggles = <String, bool>{
    'Purchase entry': true,
    'Purchase edit within policy': true,
    'Supervisor expenses': true,
    'Cash ledger own view': true,
    'Stock reconciliation': true,
    'AI operational scope': true,
    'Sales outflow weight': true,
    'Export operational reports': false,
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(businessProvider.notifier)
          .recordSecurityEvent('Permission Center opened', _template),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permission Center')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Role Template',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _template,
                  decoration: const InputDecoration(labelText: 'Preset'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Operational Supervisor',
                      child: Text('Operational Supervisor'),
                    ),
                    DropdownMenuItem(
                      value: 'Purchase Lead',
                      child: Text('Purchase Lead'),
                    ),
                    DropdownMenuItem(
                      value: 'Manager Weight Control',
                      child: Text('Manager Weight Control'),
                    ),
                    DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _template = value);
                    ref
                        .read(businessProvider.notifier)
                        .recordSecurityEvent(
                          'Permission template selected',
                          value,
                        );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Operational Permissions',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                for (final entry in _toggles.entries)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: entry.value,
                    title: Text(entry.key),
                    onChanged: (value) {
                      setState(() => _toggles[entry.key] = value);
                      ref
                          .read(businessProvider.notifier)
                          .recordSecurityEvent(
                            'Permission changed',
                            '${entry.key}: $value',
                          );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hard-Restricted by Default',
                  style: TextStyle(
                    color: EnterpriseTheme.error,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Supervisor and Manager roles cannot see sales rate, sales amount, invoice value, profit, margin, customer pending collection value, or owner financial analytics in standard presets.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OwnerExpenseCenterScreen extends ConsumerWidget {
  const OwnerExpenseCenterScreen({super.key});

  static const _ownerCategories = [
    'Salary / Wages',
    'Owner Running Business Expense',
    'Rent',
    'Utility',
    'Fuel',
    'Vehicle',
    'Office/Admin',
    'Interest / Finance Cost',
    'Repair / Maintenance',
    'Misc Owner Expense',
    'Other Business Expense',
    'Manual Adjustment',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    final ownerExpenses = state.activeExpenses
        .where((item) => _ownerCategories.contains(item.category))
        .toList();
    final total = ownerExpenses.fold<double>(
      0,
      (sum, item) => sum + item.amount,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Owner Expense Center')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showOwnerExpenseDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: _TwoColumnLines(
              lines: [
                ['Monthly owner expense summary', money(total)],
                [
                  'Salary summary',
                  money(_categoryTotal(ownerExpenses, 'Salary / Wages')),
                ],
                [
                  'Business overhead summary',
                  money(
                    total - _categoryTotal(ownerExpenses, 'Salary / Wages'),
                  ),
                ],
                ['P&L impact summary', money(total)],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (ownerExpenses.isEmpty)
            const EmptyFeatureState(
              icon: Icons.receipt_long,
              title: 'No owner expenses recorded',
              subtitle: 'Owner-only expenses will appear here.',
            )
          else
            for (final expense in ownerExpenses) ...[
              FeaturePanel(
                child: Row(
                  children: [
                    const Icon(
                      Icons.receipt_long,
                      color: EnterpriseTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.category,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${shortDate(expense.date)} | ${expense.vendorName.isEmpty ? expense.addedBy : expense.vendorName}',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      money(expense.amount),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  static double _categoryTotal(List<ExpenseRecord> expenses, String category) {
    return expenses
        .where((item) => item.category == category)
        .fold<double>(0, (sum, item) => sum + item.amount);
  }
}

Future<void> _showOwnerExpenseDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final amount = TextEditingController();
  final vendor = TextEditingController();
  final notes = TextEditingController();
  var category = OwnerExpenseCenterScreen._ownerCategories.first;
  var expenseDate = DateTime.now();
  var includeInPl = true;
  var recurring = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: 'Owner Expense',
        child: Column(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: expenseDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) {
                  setState(() => expenseDate = picked);
                }
              },
              icon: const Icon(Icons.calendar_month),
              label: Text(shortDate(expenseDate)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final item in OwnerExpenseCenterScreen._ownerCategories)
                  DropdownMenuItem(value: item, child: Text(item)),
              ],
              onChanged: (value) =>
                  setState(() => category = value ?? category),
            ),
            const SizedBox(height: 10),
            NumberText(controller: amount, label: 'Amount', onChanged: () {}),
            const SizedBox(height: 10),
            TextField(
              controller: vendor,
              decoration: const InputDecoration(labelText: 'Paid by / vendor'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: includeInPl,
              title: const Text('Include in P&L'),
              onChanged: (value) => setState(() => includeInPl = value),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: recurring,
              title: const Text('Recurring expense'),
              onChanged: (value) => setState(() => recurring = value),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                final value = double.tryParse(amount.text.trim()) ?? 0;
                if (value <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a positive amount.')),
                  );
                  return;
                }
                ref
                    .read(businessProvider.notifier)
                    .addExpense(
                      category: category,
                      amount: value,
                      expenseDate: expenseDate,
                      vendorName: vendor.text,
                      remarks: [
                        if (notes.text.trim().isNotEmpty) notes.text.trim(),
                        'Include in P&L: ${includeInPl ? 'Yes' : 'No'}',
                        'Recurring: ${recurring ? 'Yes' : 'No'}',
                      ].join(' | '),
                      addedBy: 'Owner',
                    );
                ref
                    .read(businessProvider.notifier)
                    .recordSecurityEvent(
                      'Owner expense entered',
                      '$category ${money(value)}',
                    );
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.save),
              label: const Text('Save Owner Expense'),
            ),
          ],
        ),
      ),
    ),
  );
  amount.dispose();
  vendor.dispose();
  notes.dispose();
}

class _PendingCustomerBillAlert extends StatelessWidget {
  const _PendingCustomerBillAlert({
    required this.sales,
    required this.onOpenSales,
  });

  final List<SaleRecord> sales;
  final VoidCallback onOpenSales;

  @override
  Widget build(BuildContext context) {
    final sorted = [...sales]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notification_important,
                color: EnterpriseTheme.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${sorted.length} customer bill${sorted.length == 1 ? '' : 's'} pending',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed: onOpenSales,
                child: const Text('Open Sales'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final sale in sorted.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.receipt_long, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${sale.customer.name} | ${kg(sale.totalWeightKg)} | ${sale.reminderSent ? 'Reminder sent' : 'Reminder not sent'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          const Text(
            'Amount details are hidden. Send reminder from Sales history if reminder is not sent.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _OperationalStats {
  const _OperationalStats({
    required this.openingBalance,
    required this.cashGivenByOwner,
    required this.scrapPurchaseUsed,
    required this.otherExpenses,
    required this.currentCashBalance,
    required this.todaySpent,
    required this.pendingSettlement,
    required this.missingBillAmount,
    required this.expensesMissingBills,
    required this.todayPurchaseWeight,
    required this.todaySaleWeight,
    required this.priceApprovalRequests,
  });

  final double openingBalance;
  final double cashGivenByOwner;
  final double scrapPurchaseUsed;
  final double otherExpenses;
  final double currentCashBalance;
  final double todaySpent;
  final double pendingSettlement;
  final double missingBillAmount;
  final int expensesMissingBills;
  final double todayPurchaseWeight;
  final double todaySaleWeight;
  final int priceApprovalRequests;

  static _OperationalStats build(BusinessState state, String userName) {
    bool mine(String value) => _samePerson(value, userName);
    final summary = state.supervisorCashSummaries
        .where((item) => mine(item.supervisorName))
        .firstOrNull;
    final today = DateTime.now();
    final purchases = state.activePurchases.where(
      (item) => mine(item.createdBy),
    );
    final expenses = state.activeExpenses.where((item) => mine(item.addedBy));
    final todayPurchases = purchases.where(
      (item) => _sameDay(item.createdAt, today),
    );
    final todayExpenses = expenses.where((item) => _sameDay(item.date, today));
    final sales = state.activeSales.where((item) => mine(item.createdBy));
    final todaySales = sales.where((item) => _sameDay(item.createdAt, today));
    final missingBills = expenses
        .where(
          (item) =>
              item.billUploadPath.trim().isEmpty &&
              item.photoPath.trim().isEmpty,
        )
        .toList();
    final rateReviews = _priceApprovalRows(state)
        .where(
          (row) => row.any(
            (cell) => cell.toLowerCase().contains(userName.toLowerCase()),
          ),
        )
        .length;
    return _OperationalStats(
      openingBalance: summary?.openingBalance ?? 0,
      cashGivenByOwner: summary?.cashGivenByOwner ?? 0,
      scrapPurchaseUsed:
          summary?.scrapPurchaseUsed ??
          purchases.fold<double>(0, (sum, item) => sum + item.totalAmount),
      otherExpenses:
          summary?.otherExpenses ??
          expenses.fold<double>(0, (sum, item) => sum + item.amount),
      currentCashBalance: summary?.currentCashBalance ?? 0,
      todaySpent:
          todayPurchases.fold<double>(
            0,
            (sum, item) => sum + item.totalAmount,
          ) +
          todayExpenses.fold<double>(0, (sum, item) => sum + item.amount),
      pendingSettlement: missingBills.fold<double>(
        0,
        (sum, item) => sum + item.amount,
      ),
      missingBillAmount: missingBills.fold<double>(
        0,
        (sum, item) => sum + item.amount,
      ),
      expensesMissingBills: missingBills.length,
      todayPurchaseWeight: todayPurchases.fold<double>(
        0,
        (sum, item) => sum + item.totalWeightKg,
      ),
      todaySaleWeight: todaySales.fold<double>(
        0,
        (sum, item) => sum + item.totalWeightKg,
      ),
      priceApprovalRequests: rateReviews,
    );
  }
}

class _StockVariance {
  const _StockVariance({required this.analysis});

  final StockAnalysisResult analysis;

  MaterialStock get material => analysis.material;
  double get expectedKg => analysis.expectedStock;
  double get physicalKg => analysis.physicalStock;
  double get varianceKg => analysis.difference;
  double get shortageKg => analysis.weightLoss;
  double get surplusKg => analysis.weightIncrease;
}

List<_StockVariance> _stockVariances(
  BusinessState state, {
  required bool ownerView,
}) {
  final rows =
      [
        for (final analysis in buildStockAnalyses(state))
          _StockVariance(analysis: analysis),
      ].where((item) {
        if (item.shortageKg > 0) {
          return true;
        }
        return ownerView && item.surplusKg > 0;
      }).toList();
  rows.sort((a, b) => b.varianceKg.abs().compareTo(a.varianceKg.abs()));
  return rows;
}

List<List<String>> _priceApprovalRows(BusinessState state) {
  final rows = <List<String>>[];
  for (final purchase in state.activePurchases) {
    for (final item in purchase.items) {
      final material = state.activeMaterials
          .where((mat) => mat.id == item.materialId)
          .firstOrNull;
      final cap = material?.currentBuyingRate ?? 0;
      if (cap > 0 && item.rate > cap) {
        rows.add([
          purchase.invoiceNumber,
          '${item.materialName} requested by ${purchase.createdBy}',
          'Entered ${money(item.rate)} | Cap ${money(cap)}',
          shortDate(purchase.createdAt),
        ]);
      }
    }
  }
  return rows;
}

void _openVarianceDetails(
  BuildContext context,
  List<_StockVariance> shortages,
) {
  _push(
    context,
    OperationalDetailScreen(
      title: 'To Recover',
      emptyTitle: 'No unresolved stock variance found.',
      rows: [
        for (final item in shortages)
          [
            item.material.name,
            'System Stock: ${kg(item.expectedKg)}',
            'Physical Stock: ${kg(item.physicalKg)}',
            'Weight Loss: ${kg(item.shortageKg)}',
          ],
      ],
    ),
  );
}

void _openSimpleDetails(
  BuildContext context,
  String title,
  List<List<String>> rows,
) {
  _push(
    context,
    OperationalDetailScreen(
      title: title,
      rows: rows.map((row) => [row[0], row[1]]).toList(),
      emptyTitle: 'No details available.',
    ),
  );
}

void _push(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

bool _samePerson(String left, String right) {
  final a = left.trim().toLowerCase();
  final b = right.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) {
    return false;
  }
  return a == b || a.contains(b) || b.contains(a);
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _greeting(DateTime now) {
  if (now.hour < 12) {
    return 'Good morning';
  }
  if (now.hour < 17) {
    return 'Good afternoon';
  }
  return 'Good evening';
}

String _roleLabel(UserRole role) {
  return switch (role) {
    UserRole.owner => 'Owner',
    UserRole.admin => 'Admin',
    UserRole.supervisor => 'Supervisor',
    UserRole.manager => 'Manager',
    UserRole.accountant => 'Accountant',
    UserRole.user => 'User',
  };
}
