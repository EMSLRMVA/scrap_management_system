import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/app_branding.dart';
import '../core/enterprise_theme.dart';
import '../core/money_format.dart';
import '../domain/business_models.dart';
import '../domain/stock_calculation.dart';
import '../services/pricing_insight_service.dart';
import 'business_controller.dart';
import 'enterprise_feature_screens.dart';

final aiHistoryProvider =
    NotifierProvider<AiHistoryController, List<AiConversationLog>>(
      AiHistoryController.new,
    );

final aiSettingsProvider = NotifierProvider<AiSettingsController, AiSettings>(
  AiSettingsController.new,
);

class AiSettings {
  const AiSettings({
    this.liveAnalysisEnabled = true,
    this.tickerVisible = true,
    this.criticalScanMinutes = 5,
    this.trendScanMinutes = 15,
    this.deepScanMinutes = 60,
    this.ownerSummaryTime = '09:00 AM',
  });

  final bool liveAnalysisEnabled;
  final bool tickerVisible;
  final int criticalScanMinutes;
  final int trendScanMinutes;
  final int deepScanMinutes;
  final String ownerSummaryTime;

  AiSettings copyWith({
    bool? liveAnalysisEnabled,
    bool? tickerVisible,
    int? criticalScanMinutes,
    int? trendScanMinutes,
    int? deepScanMinutes,
    String? ownerSummaryTime,
  }) {
    return AiSettings(
      liveAnalysisEnabled: liveAnalysisEnabled ?? this.liveAnalysisEnabled,
      tickerVisible: tickerVisible ?? this.tickerVisible,
      criticalScanMinutes: criticalScanMinutes ?? this.criticalScanMinutes,
      trendScanMinutes: trendScanMinutes ?? this.trendScanMinutes,
      deepScanMinutes: deepScanMinutes ?? this.deepScanMinutes,
      ownerSummaryTime: ownerSummaryTime ?? this.ownerSummaryTime,
    );
  }
}

class AiSettingsController extends Notifier<AiSettings> {
  @override
  AiSettings build() => const AiSettings();

  void update(AiSettings settings) {
    state = settings;
  }
}

class AiConversationLog {
  const AiConversationLog({
    required this.prompt,
    required this.answer,
    required this.role,
    required this.sources,
    required this.restricted,
    required this.createdAt,
  });

  final String prompt;
  final String answer;
  final UserRole role;
  final List<String> sources;
  final bool restricted;
  final DateTime createdAt;
}

class AiHistoryController extends Notifier<List<AiConversationLog>> {
  @override
  List<AiConversationLog> build() => const [];

  void add(AiConversationLog log) {
    state = [log, ...state].take(100).toList();
  }
}

class AiInsight {
  const AiInsight({
    required this.title,
    required this.severity,
    required this.category,
    required this.explanation,
    required this.suggestedAction,
    required this.confidence,
    required this.createdAt,
    required this.sources,
    this.ownerOnly = false,
  });

  final String title;
  final String severity;
  final String category;
  final String explanation;
  final String suggestedAction;
  final String confidence;
  final DateTime createdAt;
  final List<String> sources;
  final bool ownerOnly;
}

class AiAnswer {
  const AiAnswer({
    required this.answer,
    required this.explanation,
    required this.sources,
    required this.confidence,
    required this.nextQuestion,
    this.restricted = false,
  });

  final String answer;
  final String explanation;
  final List<String> sources;
  final String confidence;
  final String nextQuestion;
  final bool restricted;

  String get plainText {
    return [
      answer,
      '',
      explanation,
      '',
      'Confidence: $confidence',
      if (sources.isNotEmpty) ...['', 'Sources:', ...sources],
      '',
      'Suggested next question: $nextQuestion',
    ].join('\n');
  }
}

class _AiChatMessage {
  const _AiChatMessage({required this.text, required this.isUser, this.answer});

  final String text;
  final bool isUser;
  final AiAnswer? answer;
}

class AiCopilotEngine {
  const AiCopilotEngine();

  bool get enabled => aiEnabled;

  List<String> suggestedQuestions(UserRole role) {
    if (_isOwner(role)) {
      return const [
        'Today business summary',
        'Profit snapshot',
        'Collection risk',
        'Rate opportunity',
        'Weight loss root cause',
        'Supervisor cash status',
        'Stock responsibility summary',
        'Override approvals pending',
      ];
    }
    return const [
      'My cash balance',
      'Today spending',
      'Missing bills',
      'Purchase summary',
      'Stock variance',
      'To recover',
      'Pending approvals',
      'Material sold out check',
    ];
  }

  List<AiInsight> insightsFor(BusinessState state) {
    final owner = _isOwner(state.user.role);
    final insights = <AiInsight>[];
    insights.addAll(_weightVarianceInsights(state, owner: owner));
    insights.addAll(_slowMovingInsights(state));
    insights.addAll(_duplicateInsights(state));
    if (owner) {
      insights.addAll(_customerRiskInsights(state));
      insights.addAll(_cashFlowInsights(state));
      insights.addAll(_pricingInsights(state));
    }
    return insights
      ..sort((a, b) => _severityRank(b).compareTo(_severityRank(a)));
  }

  AiAnswer answer(BusinessState state, String prompt) {
    final cleaned = _sanitize(prompt);
    if (cleaned.isEmpty) {
      return _notEnough(
        'Ask a question about purchase, sale, stock, customer, supplier, or risk data.',
      );
    }
    final role = state.user.role;
    if (!_isOwner(role) && _isRestrictedFinancialQuestion(cleaned)) {
      return AiAnswer(
        answer:
            'You do not currently have permission to view sales or owner financial data. I can help with purchase, cash, stock responsibility, and operational records.',
        explanation:
            'Sales rates, invoice values, sale weight, sales collection, profit, customer collection exposure, and owner analytics are owner-only.',
        sources: const [],
        confidence: 'High',
        nextQuestion: 'Show stock variance',
        restricted: true,
      );
    }

    final q = cleaned.toLowerCase();
    if (q.contains('cash balance') ||
        q.contains('my cash') ||
        q.contains('cash left')) {
      return _operationalCashAnswer(state);
    }
    if (q.contains('today spending') ||
        q.contains('today spend') ||
        q.contains('diesel') ||
        q.contains('fuel') ||
        q.contains('missing bill') ||
        q.contains('missing receipt') ||
        q.contains('pending settlement')) {
      return _operationalSpendAnswer(state, q);
    }
    if (q.contains('pending approval') ||
        q.contains('rate cap') ||
        q.contains('override')) {
      return _rateApprovalAnswer(state);
    }
    if (q.contains('smart price') ||
        q.contains('pricing') ||
        q.contains('selling rate') ||
        q.contains('sale rate') ||
        q.contains('minimum rate') ||
        q.contains('minimum safe')) {
      return _smartPricingAnswer(state, q);
    }
    if (q.contains('purchase summary') || q.contains('purchase weight')) {
      return _purchaseSummaryAnswer(state);
    }
    if (q.contains('sales amount') ||
        q.contains('sale amount') ||
        q.contains('today sales') ||
        q.contains('today\'s sales')) {
      return _salesAnswer(state);
    }
    if (q.contains('late') ||
        q.contains('delay') ||
        q.contains('customer risk')) {
      return _customerRiskAnswer(state);
    }
    if (q.contains('weight loss') ||
        q.contains('stock low') ||
        q.contains('stock lower') ||
        q.contains('stock mismatch') ||
        q.contains('available stock lower') ||
        q.contains('to recover') ||
        q.contains('sold out')) {
      return _weightVarianceAnswer(state, q);
    }
    if (q.contains('traceability') || q.contains('purchase trace')) {
      return _traceabilityAnswer(state, q);
    }
    if (q.contains('slow') ||
        q.contains('not moved') ||
        q.contains('dead stock')) {
      return _slowMovingAnswer(state);
    }
    if (q.contains('duplicate') ||
        q.contains('fraud') ||
        q.contains('suspicious') ||
        q.contains('anomaly')) {
      return _duplicateAnswer(state);
    }
    if (q.contains('forecast') ||
        q.contains('shortage') ||
        q.contains('reorder')) {
      return _forecastAnswer(state);
    }
    return _businessSummaryAnswer(state);
  }

  AiAnswer _operationalCashAnswer(BusinessState state) {
    final summary = _cashSummaryForCurrentUser(state);
    if (summary == null) {
      return _notEnough(
        'No cash allocation or ledger movement is available for ${state.user.name}.',
      );
    }
    return AiAnswer(
      answer:
          'Your current cash balance appears to be ${money(summary.currentCashBalance)}.',
      explanation:
          'I used opening balance, owner top-ups, purchase-linked cash usage, and other expenses recorded against your name. Sales collections are not added to cash balance.',
      sources: [
        'Cash With Supervisor | ${summary.supervisorName}',
        'Opening ${money(summary.openingBalance)} | Top-up ${money(summary.cashGivenByOwner)}',
        'Purchase used ${money(summary.scrapPurchaseUsed)} | Other expenses ${money(summary.otherExpenses)}',
      ],
      confidence: 'Medium',
      nextQuestion: 'Which expenses are missing bills?',
    );
  }

  AiAnswer _operationalSpendAnswer(BusinessState state, String q) {
    final mine = _recordsForCurrentUser(state);
    final today = DateTime.now();
    final todayExpenses = mine.expenses
        .where((item) => _sameDay(item.date, today))
        .toList();
    final todayPurchases = mine.purchases
        .where((item) => _sameDay(item.createdAt, today))
        .toList();
    final missingBills = mine.expenses
        .where(
          (item) =>
              item.billUploadPath.trim().isEmpty &&
              item.photoPath.trim().isEmpty,
        )
        .toList();
    final categoryFilter = q.contains('fuel') || q.contains('diesel')
        ? 'fuel'
        : null;
    final filteredExpenses = categoryFilter == null
        ? todayExpenses
        : mine.expenses
              .where(
                (item) =>
                    item.category.toLowerCase().contains(categoryFilter) ||
                    item.remarks.toLowerCase().contains(categoryFilter),
              )
              .toList();
    final expenseTotal = filteredExpenses.fold<double>(
      0,
      (sum, item) => sum + item.amount,
    );
    final purchaseTotal = todayPurchases.fold<double>(
      0,
      (sum, item) => sum + item.totalAmount,
    );
    if (q.contains('missing bill') || q.contains('missing receipt')) {
      if (missingBills.isEmpty) {
        return _notEnough(
          'No expense without bill proof is currently found for ${state.user.name}.',
        );
      }
      return AiAnswer(
        answer: '${missingBills.length} expense(s) are missing bill proof.',
        explanation:
            'These entries have no bill upload path and no photo attached. Please upload proof or add a clear note before settlement.',
        sources: missingBills
            .take(6)
            .map(
              (item) =>
                  'Expense | ${shortDate(item.date)} | ${item.category} | ${money(item.amount)}',
            )
            .toList(),
        confidence: 'High',
        nextQuestion: 'Summarize today spending',
      );
    }
    return AiAnswer(
      answer: categoryFilter == null
          ? 'Today spending is ${money(expenseTotal + purchaseTotal)}.'
          : 'Fuel/diesel spending found is ${money(expenseTotal)}.',
      explanation:
          'This uses your recorded expenses and purchase-linked cash payments. Sales invoice values are not included in this operational answer.',
      sources: [
        ...filteredExpenses
            .take(4)
            .map(
              (item) =>
                  'Expense | ${shortDate(item.date)} | ${item.category} | ${money(item.amount)}',
            ),
        ...todayPurchases
            .take(4)
            .map(
              (item) =>
                  'Purchase | ${item.invoiceNumber} | ${shortDate(item.createdAt)} | ${money(item.totalAmount)}',
            ),
      ],
      confidence: filteredExpenses.isEmpty && todayPurchases.isEmpty
          ? 'Low'
          : 'High',
      nextQuestion: 'Which expenses are missing bills?',
    );
  }

  AiAnswer _rateApprovalAnswer(BusinessState state) {
    final rows = <String>[];
    for (final purchase in state.activePurchases) {
      for (final item in purchase.items) {
        final material = state.activeMaterials
            .where((mat) => mat.id == item.materialId)
            .firstOrNull;
        final cap = material?.currentBuyingRate ?? 0;
        if (cap > 0 && item.rate > cap) {
          rows.add(
            '${purchase.invoiceNumber} | ${item.materialName} | Entered ${money(item.rate)} | Cap ${money(cap)} | ${purchase.createdBy}',
          );
        }
      }
    }
    if (rows.isEmpty) {
      return _notEnough(
        'No purchase rate above the current material base rate is detected.',
      );
    }
    return AiAnswer(
      answer: '${rows.length} purchase rate approval review(s) need attention.',
      explanation:
          'I compared purchase item rate against the owner-maintained material buying/base rate. This is a review signal, not an accusation.',
      sources: rows.take(6).toList(),
      confidence: 'Medium',
      nextQuestion: 'Show purchase summary',
    );
  }

  AiAnswer _purchaseSummaryAnswer(BusinessState state) {
    final mine = _recordsForCurrentUser(state);
    final today = DateTime.now();
    final todayPurchases = mine.purchases
        .where((item) => _sameDay(item.createdAt, today))
        .toList();
    final totalWeight = todayPurchases.fold<double>(
      0,
      (sum, item) => sum + item.totalWeightKg,
    );
    final totalAmount = todayPurchases.fold<double>(
      0,
      (sum, item) => sum + item.totalAmount,
    );
    if (todayPurchases.isEmpty) {
      return _notEnough(
        'No purchase entries were found today for ${state.user.name}.',
      );
    }
    return AiAnswer(
      answer: 'Today purchase weight is ${kg(totalWeight)}.',
      explanation:
          'Purchase-side amount is operationally visible for this role. Total purchase cash value today is ${money(totalAmount)}.',
      sources: todayPurchases
          .take(6)
          .map(
            (item) =>
                'Purchase ${item.invoiceNumber} | ${shortDate(item.createdAt)} | ${item.seller.name} | ${kg(item.totalWeightKg)}',
          )
          .toList(),
      confidence: 'High',
      nextQuestion: 'Which purchase entries are above rate cap?',
    );
  }

  AiAnswer _salesAnswer(BusinessState state) {
    final today = DateTime.now();
    final sales = state.activeSales
        .where((sale) => _sameDay(sale.createdAt, today))
        .toList();
    final totalAmount = sales.fold<double>(
      0,
      (sum, sale) => sum + sale.totalAmount,
    );
    final totalWeight = sales.fold<double>(
      0,
      (sum, sale) => sum + sale.totalWeightKg,
    );
    if (_isOwner(state.user.role)) {
      return AiAnswer(
        answer: 'Today\'s sales amount is ${money(totalAmount)}.',
        explanation:
            'This is calculated from ${sales.length} sales invoice(s), with total sale weight ${kg(totalWeight)}.',
        sources: _saleSources(sales, financial: true),
        confidence: sales.isEmpty ? 'Low' : 'High',
        nextQuestion: 'Which customers are likely to delay payment?',
      );
    }
    return AiAnswer(
      answer: 'Today sale weight is ${kg(totalWeight)}.',
      explanation:
          'Supervisor view is limited to operational sale weight and stock movement.',
      sources: _saleSources(sales, financial: false),
      confidence: sales.isEmpty ? 'Low' : 'High',
      nextQuestion: 'Which material has weight loss today?',
    );
  }

  AiAnswer _customerRiskAnswer(BusinessState state) {
    if (!_isOwner(state.user.role)) {
      return const AiAnswer(
        answer:
            'You do not have permission to view this financial information. I can show you the operational weight and stock information instead.',
        explanation:
            'Customer payment risk, pending collection, and financial exposure are owner-only.',
        sources: [],
        confidence: 'High',
        nextQuestion: 'Show material movement trend for last 7 days',
        restricted: true,
      );
    }
    final risky =
        state.customers.where((customer) => customer.pendingAmount > 0).toList()
          ..sort((a, b) => b.pendingAmount.compareTo(a.pendingAmount));
    if (risky.isEmpty) {
      return _notEnough(
        'No customer pending balance is available for credit risk scoring.',
      );
    }
    return AiAnswer(
      answer: '${risky.first.name} should be followed up first.',
      explanation:
          'Highest pending exposure is ${money(risky.first.pendingAmount)}. Risk score is based on pending amount and recent invoice balance.',
      sources: risky
          .take(5)
          .map(
            (item) =>
                'Customer Ledger | ${item.name} | Pending ${money(item.pendingAmount)}',
          )
          .toList(),
      confidence: 'Medium',
      nextQuestion: 'Show 7 day collection forecast',
    );
  }

  AiAnswer _weightVarianceAnswer(BusinessState state, String q) {
    final variances =
        _materialVariances(state)
            .where(
              (item) =>
                  item.difference < -0.01 ||
                  (_isOwner(state.user.role) && item.difference > 0.01),
            )
            .toList()
          ..sort((a, b) => b.difference.abs().compareTo(a.difference.abs()));
    if (variances.isEmpty) {
      return _notEnough(
        'No weight loss or authorized stock variance is currently detected.',
      );
    }
    final target = _materialFromQuestion(state, q);
    final variance = target == null
        ? variances.first
        : variances.firstWhere(
            (item) => item.material.id == target.id,
            orElse: () => variances.first,
          );
    final label = variance.difference < 0 ? 'Weight Loss' : 'Weight Increase';
    return AiAnswer(
      answer:
          '${variance.material.name} $label detected: ${kg(variance.difference.abs())}.',
      explanation:
          'Expected stock is ${kg(variance.expectedStock)} and available physical stock is ${kg(variance.availableStock)}.',
      sources: [
        'Inventory Snapshot | ${variance.material.name} | Available ${kg(variance.availableStock)}',
        'Stock Math | Opening + Purchase - Sale = ${kg(variance.expectedStock)}',
      ],
      confidence: 'High',
      nextQuestion:
          'Show full purchase traceability for ${variance.material.name}',
    );
  }

  AiAnswer _traceabilityAnswer(BusinessState state, String q) {
    final material = _materialFromQuestion(state, q);
    if (material == null) {
      return _notEnough('Please mention a material name for traceability.');
    }
    final purchaseLines = <String>[];
    final saleLines = <String>[];
    for (final purchase in state.activePurchases) {
      for (final item in purchase.items) {
        if (_sameMaterial(item.materialId, item.materialName, material)) {
          purchaseLines.add(
            '${purchase.invoiceNumber} | ${shortDate(purchase.createdAt)} | ${purchase.seller.name} | ${kg(item.weightKg)}',
          );
        }
      }
    }
    for (final sale in state.activeSales) {
      for (final item in sale.items) {
        if (_sameMaterial(item.materialId, item.materialName, material)) {
          saleLines.add(
            '${sale.invoiceNumber} | ${shortDate(sale.createdAt)} | ${sale.customer.name} | ${kg(item.weightKg)}',
          );
        }
      }
    }
    if (purchaseLines.isEmpty && saleLines.isEmpty) {
      return _notEnough(
        'No purchase or sale movement found for ${material.name}.',
      );
    }
    return AiAnswer(
      answer:
          '${material.name} traceability found from existing purchase and sale entries.',
      explanation:
          'Purchases: ${purchaseLines.length}. Sales: ${saleLines.length}. Available stock: ${kg(material.availableKg)}.',
      sources: [...purchaseLines.take(4), ...saleLines.take(4)],
      confidence: 'High',
      nextQuestion: 'Why is ${material.name} stock lower than expected?',
    );
  }

  AiAnswer _slowMovingAnswer(BusinessState state) {
    final insights = _slowMovingInsights(state);
    if (insights.isEmpty) {
      return _notEnough(
        'No slow moving stock detected from current sales history.',
      );
    }
    final first = insights.first;
    return AiAnswer(
      answer: first.title,
      explanation: first.explanation,
      sources: first.sources,
      confidence: first.confidence,
      nextQuestion: 'Which material should I buy more?',
    );
  }

  AiAnswer _duplicateAnswer(BusinessState state) {
    final insights = _duplicateInsights(state);
    if (insights.isEmpty) {
      return _notEnough(
        'No duplicate or unusual repeated entry pattern detected.',
      );
    }
    final first = insights.first;
    return AiAnswer(
      answer: first.title,
      explanation: first.explanation,
      sources: first.sources,
      confidence: first.confidence,
      nextQuestion: 'Show source records for this unusual pattern',
    );
  }

  AiAnswer _forecastAnswer(BusinessState state) {
    final lowStock =
        state.activeMaterials
            .where((material) => material.availableKg <= 50)
            .toList()
          ..sort((a, b) => a.availableKg.compareTo(b.availableKg));
    if (lowStock.isEmpty) {
      return AiAnswer(
        answer:
            'No immediate material shortage is detected from current available stock.',
        explanation:
            'All active materials are above the basic 50 KG operational threshold.',
        sources: state.activeMaterials
            .map(
              (item) =>
                  'Inventory Snapshot | ${item.name} | ${kg(item.availableKg)}',
            )
            .take(5)
            .toList(),
        confidence: 'Medium',
        nextQuestion: 'Which stock is slow moving?',
      );
    }
    return AiAnswer(
      answer: '${lowStock.first.name} is closest to stock shortage.',
      explanation:
          'Available stock is ${kg(lowStock.first.availableKg)}. Review recent movement before buying more.',
      sources: lowStock
          .take(5)
          .map(
            (item) =>
                'Inventory Snapshot | ${item.name} | ${kg(item.availableKg)}',
          )
          .toList(),
      confidence: 'Medium',
      nextQuestion: 'Show purchase traceability for ${lowStock.first.name}',
    );
  }

  AiAnswer _smartPricingAnswer(BusinessState state, String q) {
    if (!_isOwner(state.user.role)) {
      return const AiAnswer(
        answer:
            'You do not have permission to view selling-rate and margin guidance.',
        explanation:
            'Smart pricing uses purchase cost, selling rate, and margin data, so it is owner-only.',
        sources: [],
        confidence: 'High',
        nextQuestion: 'Show stock variance',
        restricted: true,
      );
    }
    final service = const SmartPricingService();
    final material =
        _materialFromQuestion(state, q) ??
        (state.activeMaterials.isEmpty ? null : state.activeMaterials.first);
    final suggestion = service.suggestFor(state, material);
    if (suggestion == null) {
      return _notEnough('Add a material before asking for smart pricing.');
    }
    return AiAnswer(
      answer:
          'Suggested selling rate for ${suggestion.material.name} is ${money(suggestion.suggestedSellingRate)} / KG.',
      explanation:
          'Minimum safe rate is ${money(suggestion.safeMinimumSellingRate)} / KG based on cost rate ${money(suggestion.costRate)} / KG. Last purchase ${money(suggestion.lastPurchaseRate)}, average purchase ${money(suggestion.averagePurchaseRate)}, last sale ${money(suggestion.lastSellingRate)}, average sale ${money(suggestion.averageSellingRate)}.',
      sources: [
        'Material Master | Buy ${money(suggestion.material.currentBuyingRate)} | Sell ${money(suggestion.material.currentSellingRate)}',
        'Purchase History | Last ${money(suggestion.lastPurchaseRate)} | Average ${money(suggestion.averagePurchaseRate)}',
        'Sales History | Last ${money(suggestion.lastSellingRate)} | Average ${money(suggestion.averageSellingRate)}',
      ],
      confidence: suggestion.costRate <= 0 ? 'Low' : 'Medium',
      nextQuestion: 'Which item has low profit sale risk?',
    );
  }

  AiAnswer _businessSummaryAnswer(BusinessState state) {
    final owner = _isOwner(state.user.role);
    final purchaseWeight = state.activePurchases.fold<double>(
      0,
      (sum, item) => sum + item.totalWeightKg,
    );
    final saleWeight = state.activeSales.fold<double>(
      0,
      (sum, item) => sum + item.totalWeightKg,
    );
    final stockWeight = state.activeMaterials.fold<double>(
      0,
      (sum, item) => sum + item.availableKg,
    );
    return AiAnswer(
      answer: 'Here is the grounded business summary from current app data.',
      explanation: owner
          ? 'Purchases ${kg(purchaseWeight)}, sales ${kg(saleWeight)}, available stock ${kg(stockWeight)}, pending payments ${money(state.metrics.pendingPayments)}.'
          : 'Purchases ${kg(purchaseWeight)}, sales ${kg(saleWeight)}, available stock ${kg(stockWeight)}. Financial values are hidden for your role.',
      sources: [
        'Purchase Register | ${state.activePurchases.length} active purchase(s)',
        'Sales Register | ${state.activeSales.length} active sale(s)',
        'Inventory Snapshot | ${state.activeMaterials.length} active material(s)',
      ],
      confidence: state.activePurchases.isEmpty && state.activeSales.isEmpty
          ? 'Low'
          : 'Medium',
      nextQuestion: owner
          ? 'Show top financial risks this week'
          : 'Which material has weight loss today?',
    );
  }

  AiAnswer _notEnough(String explanation) {
    return AiAnswer(
      answer: 'Not enough data available to answer reliably.',
      explanation: explanation,
      sources: const [],
      confidence: 'Low',
      nextQuestion: 'Show current stock summary',
    );
  }

  List<AiInsight> _weightVarianceInsights(
    BusinessState state, {
    required bool owner,
  }) {
    final results = <AiInsight>[];
    for (final variance in _materialVariances(state)) {
      if (variance.difference < -0.01) {
        results.add(
          AiInsight(
            title:
                'Critical: ALERT: ${variance.material.name} weight loss detected: ${kg(variance.difference.abs())}',
            severity: variance.difference.abs() > 100 ? 'Critical' : 'High',
            category: 'Weight Loss',
            explanation:
                'Expected ${kg(variance.expectedStock)}, available ${kg(variance.availableStock)}.',
            suggestedAction:
                'Verify physical stock and review recent purchase/sale entries.',
            confidence: 'High',
            createdAt: DateTime.now(),
            sources: [
              'Inventory Snapshot | ${variance.material.name}',
              'Stock Formula | Opening + Purchase - Sale',
            ],
          ),
        );
      } else if (owner && variance.difference > 0.01) {
        results.add(
          AiInsight(
            title:
                '${variance.material.name} weight increase detected: ${kg(variance.difference)}',
            severity: 'Medium',
            category: 'Weight Increase',
            explanation:
                'Available stock is higher than expected by ${kg(variance.difference)}.',
            suggestedAction:
                'Owner should verify opening stock, adjustment, or missed entry.',
            confidence: 'Medium',
            createdAt: DateTime.now(),
            ownerOnly: true,
            sources: [
              'Inventory Snapshot | ${variance.material.name}',
              'Stock Formula | Opening + Purchase - Sale',
            ],
          ),
        );
      }
    }
    return results;
  }

  List<AiInsight> _slowMovingInsights(BusinessState state) {
    final now = DateTime.now();
    final insights = <AiInsight>[];
    for (final material in state.activeMaterials) {
      DateTime? lastSale;
      for (final sale in state.activeSales) {
        if (sale.items.any(
          (item) => _sameMaterial(item.materialId, item.materialName, material),
        )) {
          if (lastSale == null || sale.createdAt.isAfter(lastSale)) {
            lastSale = sale.createdAt;
          }
        }
      }
      final days = lastSale == null ? 999 : now.difference(lastSale).inDays;
      if (material.availableKg > 0 && days >= 12) {
        insights.add(
          AiInsight(
            title:
                'ALERT: ${material.name} stock has not moved for ${days == 999 ? 'many' : days} days',
            severity: days >= 30 ? 'High' : 'Medium',
            category: 'Slow Moving',
            explanation:
                '${material.name} has ${kg(material.availableKg)} available stock and no recent sale movement.',
            suggestedAction: 'Review demand, storage, and purchase planning.',
            confidence: lastSale == null ? 'Medium' : 'High',
            createdAt: now,
            sources: [
              'Inventory Snapshot | ${material.name} | ${kg(material.availableKg)}',
            ],
          ),
        );
      }
    }
    return insights;
  }

  List<AiInsight> _duplicateInsights(BusinessState state) {
    final insights = <AiInsight>[];
    final seen = <String, PurchaseRecord>{};
    for (final purchase in state.activePurchases) {
      for (final item in purchase.items) {
        final key =
            '${purchase.seller.name}|${item.materialName}|${item.weightKg.toStringAsFixed(2)}|${_dateKey(purchase.createdAt)}';
        final previous = seen[key];
        if (previous != null) {
          insights.add(
            AiInsight(
              title: 'ALERT: Possible duplicate purchase entry detected',
              severity: 'Medium',
              category: 'Duplicate / Fraud',
              explanation:
                  'Same seller, material, weight, and date appeared more than once. This is possibly suspicious and needs review.',
              suggestedAction: 'Compare both purchase records before approval.',
              confidence: 'Medium',
              createdAt: DateTime.now(),
              sources: [
                'Purchase Entry ${previous.invoiceNumber} | ${shortDate(previous.createdAt)}',
                'Purchase Entry ${purchase.invoiceNumber} | ${shortDate(purchase.createdAt)}',
              ],
            ),
          );
        } else {
          seen[key] = purchase;
        }
      }
    }
    return insights;
  }

  List<AiInsight> _customerRiskInsights(BusinessState state) {
    return state.customers
        .where((customer) => customer.pendingAmount > 0)
        .map(
          (customer) => AiInsight(
            title: 'ALERT: Customer risk increasing for ${customer.name}',
            severity: customer.pendingAmount > 50000 ? 'High' : 'Medium',
            category: 'Customer Risk',
            explanation:
                '${customer.name} has pending balance ${money(customer.pendingAmount)}.',
            suggestedAction: 'Send reminder or review credit terms.',
            confidence: 'Medium',
            createdAt: DateTime.now(),
            ownerOnly: true,
            sources: [
              'Customer Ledger | ${customer.name} | ${money(customer.pendingAmount)}',
            ],
          ),
        )
        .toList();
  }

  List<AiInsight> _cashFlowInsights(BusinessState state) {
    if (state.metrics.cashBalance >= 0) {
      return const [];
    }
    return [
      AiInsight(
        title: 'ALERT: Cash flow risk detected',
        severity: 'High',
        category: 'Financial',
        explanation:
            'Current cash balance is ${money(state.metrics.cashBalance)}.',
        suggestedAction: 'Review pending collection and supervisor cash usage.',
        confidence: 'Medium',
        createdAt: DateTime.now(),
        ownerOnly: true,
        sources: ['Cash Ledger | Balance ${money(state.metrics.cashBalance)}'],
      ),
    ];
  }

  List<AiInsight> _pricingInsights(BusinessState state) {
    final service = const SmartPricingService();
    final insights = <AiInsight>[];
    for (final material in state.activeMaterials) {
      final suggestion = service.suggestFor(state, material);
      if (suggestion == null) {
        continue;
      }
      final configuredRate = material.currentSellingRate > 0
          ? material.currentSellingRate
          : material.currentBuyingRate;
      if (!suggestion.isBelowSafeRate(configuredRate)) {
        continue;
      }
      insights.add(
        AiInsight(
          title: '${material.name} selling rate is below safe minimum',
          severity: 'Medium',
          category: 'Pricing',
          explanation:
              'Configured selling rate ${money(configuredRate)} is below minimum safe rate ${money(suggestion.safeMinimumSellingRate)}.',
          suggestedAction:
              'Review sale rate before billing. Suggested rate is ${money(suggestion.suggestedSellingRate)} / KG.',
          confidence: suggestion.costRate <= 0 ? 'Low' : 'Medium',
          createdAt: DateTime.now(),
          ownerOnly: true,
          sources: [
            'Material Master | ${material.name}',
            'Cost Rate | ${money(suggestion.costRate)}',
          ],
        ),
      );
    }
    return insights;
  }

  List<_MaterialVariance> _materialVariances(BusinessState state) {
    return [
      for (final analysis in buildStockAnalyses(state))
        _MaterialVariance(analysis: analysis),
    ];
  }

  MaterialStock? _materialFromQuestion(BusinessState state, String q) {
    final cleaned = q.toLowerCase();
    for (final material in state.activeMaterials) {
      if (cleaned.contains(material.name.toLowerCase())) {
        return material;
      }
    }
    return null;
  }

  bool _sameMaterial(
    String materialId,
    String materialName,
    MaterialStock material,
  ) {
    if (materialId.trim().isNotEmpty && materialId == material.id) {
      return true;
    }
    return materialName.trim().toLowerCase() ==
        material.name.trim().toLowerCase();
  }

  bool _isRestrictedFinancialQuestion(String prompt) {
    final q = prompt.toLowerCase();
    final operationalAllowed =
        q.contains('my cash') ||
        q.contains('cash balance') ||
        q.contains('cash left') ||
        q.contains('expense') ||
        q.contains('spending') ||
        q.contains('spent') ||
        q.contains('diesel') ||
        q.contains('fuel') ||
        q.contains('bill') ||
        q.contains('receipt') ||
        q.contains('settlement') ||
        q.contains('purchase') ||
        q.contains('supplier') ||
        q.contains('stock') ||
        q.contains('weight') ||
        q.contains('to recover') ||
        q.contains('approval') ||
        q.contains('rate cap') ||
        q.contains('override');
    final ownerFinancial =
        q.contains('profit') ||
        q.contains('margin') ||
        q.contains('owner financial') ||
        q.contains('business value') ||
        q.contains('valuation') ||
        q.contains('collection') ||
        q.contains('customer pending') ||
        q.contains('pending collection') ||
        q.contains('credit risk') ||
        q.contains('sale amount') ||
        q.contains('sales amount') ||
        q.contains('invoice amount') ||
        q.contains('invoice value') ||
        q.contains('sale rate') ||
        q.contains('sales rate') ||
        q.contains('selling rate') ||
        q.contains('selling price') ||
        q.contains('customer price') ||
        q.contains('customer billing') ||
        q.contains('payment delay') ||
        q.contains('late payment');
    if (ownerFinancial) {
      return true;
    }
    return !operationalAllowed &&
        (q.contains('selling') ||
            q.contains('sales value') ||
            q.contains('sale value') ||
            q.contains('customer collection'));
  }

  String _sanitize(String prompt) {
    return prompt
        .replaceAll(
          RegExp(
            r'ignore previous|override policy|show hidden|bypass',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  SupervisorCashSummary? _cashSummaryForCurrentUser(BusinessState state) {
    return state.supervisorCashSummaries
        .where((item) => _samePerson(item.supervisorName, state.user.name))
        .firstOrNull;
  }

  _AiOperationalRecords _recordsForCurrentUser(BusinessState state) {
    return _AiOperationalRecords(
      purchases: state.activePurchases
          .where((item) => _samePerson(item.createdBy, state.user.name))
          .toList(),
      expenses: state.activeExpenses
          .where((item) => _samePerson(item.addedBy, state.user.name))
          .toList(),
      sales: state.activeSales
          .where((item) => _samePerson(item.createdBy, state.user.name))
          .toList(),
    );
  }

  List<String> _saleSources(
    Iterable<SaleRecord> sales, {
    required bool financial,
  }) {
    return [
      for (final sale in sales)
        financial
            ? 'Sales Entry ${sale.invoiceNumber} | ${shortDate(sale.createdAt)} | ${sale.customer.name} | ${money(sale.totalAmount)}'
            : 'Sales Entry ${sale.invoiceNumber} | ${shortDate(sale.createdAt)} | ${sale.customer.name} | ${kg(sale.totalWeightKg)}',
    ];
  }

  String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  bool _samePerson(String left, String right) {
    final a = left.trim().toLowerCase();
    final b = right.trim().toLowerCase();
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    return a == b || a.contains(b) || b.contains(a);
  }

  bool _isOwner(UserRole role) => role.isOwnerOrAdmin;

  int _severityRank(AiInsight insight) {
    return switch (insight.severity) {
      'Critical' => 5,
      'High' => 4,
      'Medium' => 3,
      'Low' => 2,
      'Opportunity' => 1,
      _ => 0,
    };
  }
}

class _MaterialVariance {
  const _MaterialVariance({required this.analysis});

  final StockAnalysisResult analysis;

  MaterialStock get material => analysis.material;
  double get expectedStock => analysis.expectedStock;
  double get availableStock => analysis.physicalStock;
  double get difference => availableStock - expectedStock;
}

class _AiOperationalRecords {
  const _AiOperationalRecords({
    required this.purchases,
    required this.expenses,
    required this.sales,
  });

  final List<PurchaseRecord> purchases;
  final List<ExpenseRecord> expenses;
  final List<SaleRecord> sales;
}

class AskAiDashboardButton extends StatelessWidget {
  const AskAiDashboardButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!aiEnabled) {
      return const SizedBox.shrink();
    }
    final tokens = EnterpriseTheme.tokensOf(context);
    return FloatingActionButton.small(
      heroTag: 'ask_ai_dashboard',
      tooltip: 'Ask AI',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const AiChatPanel(compact: true),
      ),
      backgroundColor: tokens.primaryColor,
      foregroundColor: tokens.primaryColor.computeLuminance() > 0.45
          ? const Color(0xFF0F172A)
          : Colors.white,
      child: const Icon(Icons.auto_awesome),
    );
  }
}

class AiInsightTicker extends ConsumerWidget {
  const AiInsightTicker({super.key, this.onOpenInsights});

  final VoidCallback? onOpenInsights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!aiEnabled) {
      return const SizedBox.shrink();
    }
    final settings = ref.watch(aiSettingsProvider);
    if (!settings.tickerVisible || !settings.liveAnalysisEnabled) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(businessProvider);
    final insights = const AiCopilotEngine().insightsFor(state);
    if (insights.isEmpty) {
      return const SizedBox.shrink();
    }
    final ticker = insights
        .take(4)
        .map((item) => '${item.severity}: ${item.title}')
        .join('     |     ');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onOpenInsights,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: EnterpriseTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: EnterpriseTheme.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome_motion,
              size: 18,
              color: EnterpriseTheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ticker,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AiCenterScreen extends StatelessWidget {
  const AiCenterScreen({super.key, this.initialPage = 'home'});

  final String initialPage;

  @override
  Widget build(BuildContext context) {
    if (initialPage == 'insights') {
      return const AiInsightsScreen();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('AI')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'EMSLRMVA AI Copilot',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 6),
                Text(
                  'Internal-data-only intelligence for scrap operations. AI is read-only and role filtered.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.18,
            children: [
              _AiModuleTile(
                'Ask AI',
                Icons.chat_bubble_outline,
                () => _push(context, const AiAskScreen()),
              ),
              _AiModuleTile(
                'AI Insights',
                Icons.auto_awesome_motion,
                () => _push(context, const AiInsightsScreen()),
              ),
              _AiModuleTile(
                'Forecasts',
                Icons.trending_up,
                () => _push(context, const AiForecastsScreen()),
              ),
              _AiModuleTile(
                'Risk Center',
                Icons.warning_amber,
                () => _push(context, const AiRiskCenterScreen()),
              ),
              _AiModuleTile(
                'Knowledge Vault',
                Icons.menu_book,
                () => _push(context, const AiKnowledgeVaultScreen()),
              ),
              _AiModuleTile(
                'AI History',
                Icons.history,
                () => _push(context, const AiHistoryScreen()),
              ),
              _AiModuleTile(
                'AI Settings',
                Icons.tune,
                () => _push(context, const AiSettingsScreen()),
              ),
              _AiModuleTile(
                'AI Feedback',
                Icons.feedback_outlined,
                () => _push(context, const AiFeedbackScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget child) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => child));
  }
}

class _AiModuleTile extends StatelessWidget {
  const _AiModuleTile(this.title, this.icon, this.onTap);

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: FeaturePanel(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: EnterpriseTheme.primary, size: 30),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class AiAskScreen extends StatelessWidget {
  const AiAskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask AI')),
      body: const AiChatPanel(compact: false),
    );
  }
}

class AiChatPanel extends ConsumerStatefulWidget {
  const AiChatPanel({super.key, required this.compact});

  final bool compact;

  @override
  ConsumerState<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends ConsumerState<AiChatPanel> {
  final _input = TextEditingController();
  final _messages = <_AiChatMessage>[];
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  var _speechReady = false;
  var _listening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final ready = await _speech.initialize();
      if (mounted) {
        setState(() => _speechReady = ready);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _speechReady = false);
      }
    }
  }

  @override
  void dispose() {
    _input.dispose();
    unawaited(_tts.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final prompts = const AiCopilotEngine().suggestedQuestions(state.user.role);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final prompt in prompts.take(
              widget.compact ? 3 : prompts.length,
            ))
              ActionChip(
                label: Text(prompt),
                onPressed: () {
                  _input.text = prompt;
                  _ask();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _messages.isEmpty
              ? const EmptyFeatureState(
                  icon: Icons.auto_awesome,
                  title: 'Ask AI',
                  subtitle: 'Answers use only authorized internal app data.',
                )
              : ListView.separated(
                  itemCount: _messages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _AiMessageCard(
                    message: _messages[index],
                    onSpeak: _speak,
                  ),
                ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Ask from app data',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => _ask(),
              ),
            ),
            IconButton(
              tooltip: _speechReady ? 'Voice question' : 'Voice unavailable',
              onPressed: _speechReady ? _toggleListen : null,
              icon: Icon(_listening ? Icons.mic : Icons.mic_none),
            ),
            IconButton(
              tooltip: 'Ask',
              onPressed: _ask,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
    if (widget.compact) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Padding(padding: const EdgeInsets.all(16), child: body),
        ),
      );
    }
    return Padding(padding: const EdgeInsets.all(16), child: body);
  }

  void _ask() {
    final prompt = _input.text.trim();
    if (prompt.isEmpty) {
      return;
    }
    final state = ref.read(businessProvider);
    final answer = const AiCopilotEngine().answer(state, prompt);
    ref
        .read(aiHistoryProvider.notifier)
        .add(
          AiConversationLog(
            prompt: prompt,
            answer: answer.plainText,
            role: state.user.role,
            sources: answer.sources,
            restricted: answer.restricted,
            createdAt: DateTime.now(),
          ),
        );
    setState(() {
      _messages.add(_AiChatMessage(text: prompt, isUser: true));
      _messages.add(
        _AiChatMessage(text: answer.answer, isUser: false, answer: answer),
      );
      _input.clear();
    });
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _listening = false);
      }
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        _input.text = result.recognizedWords;
        if (result.finalResult) {
          setState(() => _listening = false);
        }
      },
    );
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }
}

class _AiMessageCard extends StatelessWidget {
  const _AiMessageCard({required this.message, required this.onSpeak});

  final _AiChatMessage message;
  final ValueChanged<String> onSpeak;

  @override
  Widget build(BuildContext context) {
    final answer = message.answer;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: FeaturePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.isUser ? 'You' : 'AI',
                style: TextStyle(
                  color: message.isUser
                      ? EnterpriseTheme.primary
                      : EnterpriseTheme.success,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(message.text),
              if (answer != null) ...[
                const SizedBox(height: 8),
                Text(
                  answer.explanation,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Confidence: ${answer.confidence}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (answer.sources.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Sources',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  for (final source in answer.sources.take(6))
                    Text(
                      source,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Next: ${answer.nextQuestion}',
                  style: const TextStyle(fontSize: 12),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Copy answer',
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: answer.plainText),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('AI answer copied')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                    IconButton(
                      tooltip: 'Speak answer',
                      onPressed: () => onSpeak(answer.plainText),
                      icon: const Icon(Icons.volume_up),
                    ),
                    IconButton(
                      tooltip: 'Export text',
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(text: answer.plainText),
                      ),
                      icon: const Icon(Icons.ios_share),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AiInsightsScreen extends ConsumerStatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  ConsumerState<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends ConsumerState<AiInsightsScreen> {
  var _tab = 'All';
  static const _tabs = [
    'All',
    'Critical',
    'Weight Loss',
    'Stock Risk',
    'Duplicate / Fraud',
    'Slow Moving',
    'Customer Risk',
    'Supplier Insights',
    'Opportunities',
    'Financial',
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final owner = state.user.role.isOwnerOrAdmin;
    final insights = const AiCopilotEngine()
        .insightsFor(state)
        .where((item) => owner || !item.ownerOnly)
        .where((item) {
          if (_tab == 'All') return true;
          if (_tab == 'Critical') return item.severity == 'Critical';
          if (_tab == 'Opportunities') return item.severity == 'Opportunity';
          return item.category == _tab;
        })
        .toList();
    final visibleTabs = _tabs
        .where((tab) => owner || tab != 'Financial')
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('AI Insights')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (final tab in visibleTabs) ...[
                  ChoiceChip(
                    label: Text(tab),
                    selected: _tab == tab,
                    onSelected: (_) => setState(() => _tab = tab),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: insights.isEmpty
                ? const EmptyFeatureState(
                    icon: Icons.auto_awesome_motion,
                    title: 'No AI insights',
                    subtitle:
                        'The internal rule engine will show alerts when data is available.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: insights.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) =>
                        _AiInsightCard(insight: insights[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({required this.insight});

  final AiInsight insight;

  @override
  Widget build(BuildContext context) {
    final color = switch (insight.severity) {
      'Critical' => EnterpriseTheme.error,
      'High' => EnterpriseTheme.error,
      'Medium' => EnterpriseTheme.warning,
      'Opportunity' => EnterpriseTheme.success,
      _ => EnterpriseTheme.primary,
    };
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  insight.severity,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  insight.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(insight.explanation),
          const SizedBox(height: 6),
          Text(
            'Suggested action: ${insight.suggestedAction}',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Text(
            'Confidence: ${insight.confidence} | ${shortDate(insight.createdAt)}',
            style: const TextStyle(fontSize: 12),
          ),
          if (insight.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final source in insight.sources.take(4))
              Text(
                source,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.check),
                label: const Text('Mark reviewed'),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.snooze),
                label: const Text('Snooze'),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.thumb_up_alt_outlined),
                label: const Text('Useful'),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.thumb_down_alt_outlined),
                label: const Text('Not useful'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AiForecastsScreen extends ConsumerWidget {
  const AiForecastsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    final owner = state.user.role.isOwnerOrAdmin;
    final lowStock = state.activeMaterials
        .where((item) => item.availableKg <= 50)
        .toList();
    return _SimpleAiListScreen(
      title: 'Forecasts',
      items: [
        '7 day stock forecast: ${lowStock.isEmpty ? 'No immediate shortage detected.' : '${lowStock.length} material(s) need review.'}',
        '30 day stock forecast: Review slow moving and low stock materials before new purchase.',
        'Material shortage forecast: ${lowStock.map((item) => item.name).take(5).join(', ').isEmpty ? 'None from current threshold.' : lowStock.map((item) => item.name).take(5).join(', ')}',
        'Weight movement trend: Purchase ${kg(state.activePurchases.fold<double>(0, (sum, item) => sum + item.totalWeightKg))}, sale ${kg(state.activeSales.fold<double>(0, (sum, item) => sum + item.totalWeightKg))}.',
        if (owner)
          '7 day cash flow forecast: Pending collection ${money(state.metrics.pendingPayments)} and cash balance ${money(state.metrics.cashBalance)}.',
        if (owner)
          '30 day collection forecast: Prioritize customers with pending balances.',
      ],
    );
  }
}

class AiRiskCenterScreen extends ConsumerStatefulWidget {
  const AiRiskCenterScreen({super.key});

  @override
  ConsumerState<AiRiskCenterScreen> createState() => _AiRiskCenterScreenState();
}

class _AiRiskCenterScreenState extends ConsumerState<AiRiskCenterScreen> {
  String _filter = 'All';
  static const _filters = [
    'All',
    'Critical',
    'Warning',
    'Payment',
    'Stock',
    'Supervisor',
    'Invoice',
    'Pricing',
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final owner = state.user.role.isOwnerOrAdmin;
    final insights = const AiCopilotEngine()
        .insightsFor(state)
        .where((item) => owner || !item.ownerOnly)
        .where(_matchesFilter)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Risk Center')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                for (final filter in _filters) ...[
                  ChoiceChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: insights.isEmpty
                ? EmptyFeatureState(
                    icon: Icons.warning_amber,
                    title: _filter == 'All'
                        ? 'No AI risks'
                        : 'No $_filter risks',
                    subtitle:
                        'Risks will appear as transactions and stock data grow.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: insights.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) =>
                        _AiInsightCard(insight: insights[index]),
                  ),
          ),
        ],
      ),
    );
  }

  bool _matchesFilter(AiInsight insight) {
    if (_filter == 'All') {
      return true;
    }
    final haystack = [
      insight.title,
      insight.category,
      insight.explanation,
      insight.suggestedAction,
      ...insight.sources,
    ].join(' ').toLowerCase();
    return switch (_filter) {
      'Critical' => insight.severity == 'Critical',
      'Warning' => insight.severity == 'High' || insight.severity == 'Medium',
      'Payment' =>
        haystack.contains('payment') ||
            haystack.contains('pending') ||
            haystack.contains('collection') ||
            haystack.contains('customer risk') ||
            haystack.contains('cash'),
      'Stock' =>
        haystack.contains('stock') ||
            haystack.contains('weight loss') ||
            haystack.contains('slow moving') ||
            haystack.contains('shortage') ||
            haystack.contains('material'),
      'Supervisor' =>
        haystack.contains('supervisor') ||
            haystack.contains('cash') ||
            haystack.contains('settlement'),
      'Invoice' =>
        haystack.contains('invoice') ||
            haystack.contains('duplicate') ||
            haystack.contains('entry'),
      'Pricing' =>
        haystack.contains('rate') ||
            haystack.contains('price') ||
            haystack.contains('margin') ||
            haystack.contains('cap'),
      _ => true,
    };
  }
}

class AiKnowledgeVaultScreen extends StatefulWidget {
  const AiKnowledgeVaultScreen({super.key});

  @override
  State<AiKnowledgeVaultScreen> createState() => _AiKnowledgeVaultScreenState();
}

class _AiKnowledgeVaultScreenState extends State<AiKnowledgeVaultScreen> {
  final _note = TextEditingController();
  final _notes = <String>[
    'Approved operational notes are visible to supervisors.',
    'Owner-confidential notes must not be exposed to operational roles.',
  ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Knowledge Vault')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              children: [
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Owner note / SOP / business rule',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () {
                    if (_note.text.trim().isEmpty) return;
                    setState(() {
                      _notes.insert(0, _note.text.trim());
                      _note.clear();
                    });
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save note'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final note in _notes) ...[
            FeaturePanel(child: Text(note)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class AiHistoryScreen extends ConsumerWidget {
  const AiHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    final owner = state.user.role.isOwnerOrAdmin;
    final history = ref
        .watch(aiHistoryProvider)
        .where((log) => owner || log.role == state.user.role)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('AI History')),
      body: history.isEmpty
          ? const EmptyFeatureState(
              icon: Icons.history,
              title: 'No AI history',
              subtitle: 'Ask AI questions to build a prompt audit trail.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final log = history[index];
                return FeaturePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.prompt,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(log.answer),
                      const SizedBox(height: 6),
                      Text(
                        '${log.role.name.toUpperCase()} | ${shortDate(log.createdAt)} | Restricted: ${log.restricted ? 'Yes' : 'No'}',
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class AiSettingsScreen extends ConsumerWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aiSettingsProvider);
    final controller = ref.read(aiSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('AI Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: settings.liveAnalysisEnabled,
                  onChanged: (value) => controller.update(
                    settings.copyWith(liveAnalysisEnabled: value),
                  ),
                  title: const Text('Enable AI live analysis'),
                ),
                SwitchListTile.adaptive(
                  value: settings.tickerVisible,
                  onChanged: (value) => controller.update(
                    settings.copyWith(tickerVisible: value),
                  ),
                  title: const Text('Show dashboard AI ticker'),
                ),
                _AiSettingLine(
                  'Critical alert scan',
                  '${settings.criticalScanMinutes} minutes',
                ),
                _AiSettingLine(
                  'Trend analysis scan',
                  '${settings.trendScanMinutes} minutes',
                ),
                _AiSettingLine(
                  'Deep anomaly scan',
                  '${settings.deepScanMinutes} minutes',
                ),
                _AiSettingLine('Owner summary time', settings.ownerSummaryTime),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const FeaturePanel(
            child: Text(
              'Phase one AI is read-only. It can answer, analyze, recommend, alert, and log, but it cannot edit, delete, approve, or send WhatsApp automatically.',
            ),
          ),
          const SizedBox(height: 12),
          const FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data Protection Center',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                _AiSettingLine('Daily backup', 'Included in app backup flow'),
                _AiSettingLine('Weekly backup', 'Included in app backup flow'),
                _AiSettingLine('Monthly backup', 'Included in app backup flow'),
                _AiSettingLine('Restore test mode', 'Owner review required'),
                _AiSettingLine(
                  'AI data coverage',
                  'History, insights, settings and audit prompts',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSettingLine extends StatelessWidget {
  const _AiSettingLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(value),
    );
  }
}

class AiFeedbackScreen extends StatefulWidget {
  const AiFeedbackScreen({super.key});

  @override
  State<AiFeedbackScreen> createState() => _AiFeedbackScreenState();
}

class _AiFeedbackScreenState extends State<AiFeedbackScreen> {
  final _feedback = TextEditingController();
  final _items = <String>[];

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Feedback')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              children: [
                TextField(
                  controller: _feedback,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'AI feedback'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () {
                    if (_feedback.text.trim().isEmpty) return;
                    setState(() {
                      _items.insert(0, _feedback.text.trim());
                      _feedback.clear();
                    });
                  },
                  icon: const Icon(Icons.feedback),
                  label: const Text('Submit feedback'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final item in _items) ...[
            FeaturePanel(child: Text(item)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _SimpleAiListScreen extends StatelessWidget {
  const _SimpleAiListScreen({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) => FeaturePanel(child: Text(items[index])),
      ),
    );
  }
}
