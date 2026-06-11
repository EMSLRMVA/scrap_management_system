import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/activity.dart';
import '../models/dashboard_metrics.dart';
import '../models/dispatch.dart';
import '../models/expense.dart';
import '../models/ledger_entry.dart';
import '../models/material_item.dart';
import '../models/notification_item.dart';
import '../models/party.dart';
import '../models/purchase.dart';
import '../models/report_summary.dart';
import '../models/sale.dart';
import '../models/transaction_item.dart';

class ScrapRepository {
  ScrapRepository({
    required List<MaterialItem> materials,
    required List<Party> parties,
    required List<Purchase> purchases,
    required List<Sale> sales,
    required List<Expense> expenses,
    required List<Dispatch> dispatches,
    required List<LedgerEntry> ledgers,
    required List<Activity> activities,
    required List<NotificationItem> notifications,
  }) : _materials = materials,
       _parties = parties,
       _purchases = purchases,
       _sales = sales,
       _expenses = expenses,
       _dispatches = dispatches,
       _ledgers = ledgers,
       _activities = activities,
       _notifications = notifications;

  final _uuid = const Uuid();
  final List<MaterialItem> _materials;
  final List<Party> _parties;
  final List<Purchase> _purchases;
  final List<Sale> _sales;
  final List<Expense> _expenses;
  final List<Dispatch> _dispatches;
  final List<LedgerEntry> _ledgers;
  final List<Activity> _activities;
  final List<NotificationItem> _notifications;

  factory ScrapRepository.seeded() {
    final now = DateTime.now();
    final materials = [
      const MaterialItem(
        id: 'coconut-shell',
        name: 'Coconut Shell',
        category: 'Agro Scrap',
        openingStockKg: 2500,
        purchasedKg: 2700,
        soldKg: 700,
        currentBuyingRate: 15,
        currentSellingRate: 18,
        lowStockThresholdKg: 250,
      ),
      const MaterialItem(
        id: 'pet-bottle',
        name: 'PET Bottle',
        category: 'Plastic',
        openingStockKg: 600,
        purchasedKg: 900,
        soldKg: 300,
        currentBuyingRate: 20,
        currentSellingRate: 26,
        lowStockThresholdKg: 200,
        wastageDeductionPercent: 10,
      ),
      const MaterialItem(
        id: 'cardboard',
        name: 'Cardboard',
        category: 'Paper',
        openingStockKg: 500,
        purchasedKg: 800,
        soldKg: 350,
        currentBuyingRate: 8,
        currentSellingRate: 10,
        lowStockThresholdKg: 200,
        wastageDeductionPercent: 5,
      ),
      const MaterialItem(
        id: 'iron',
        name: 'Iron',
        category: 'Metal',
        openingStockKg: 400,
        purchasedKg: 600,
        soldKg: 300,
        currentBuyingRate: 26,
        currentSellingRate: 34,
        lowStockThresholdKg: 150,
      ),
      const MaterialItem(
        id: 'plastic',
        name: 'Plastic',
        category: 'Plastic',
        openingStockKg: 250,
        purchasedKg: 120,
        soldKg: 70,
        currentBuyingRate: 12,
        currentSellingRate: 18,
        lowStockThresholdKg: 100,
        wastageDeductionPercent: 10,
      ),
      const MaterialItem(
        id: 'aluminium',
        name: 'Aluminium',
        category: 'Metal',
        openingStockKg: 160,
        purchasedKg: 90,
        soldKg: 50,
        currentBuyingRate: 105,
        currentSellingRate: 128,
        lowStockThresholdKg: 80,
      ),
    ];

    final parties = [
      const Party(
        id: 'seller-ramesh',
        name: 'Ramesh Scrap',
        phone: '9876543210',
        area: 'Peelamedu',
        type: PartyType.seller,
        gstNumber: '33ABCDE1234F1ZS',
        openingBalance: 5000,
      ),
      const Party(
        id: 'seller-suresh',
        name: 'Suresh Traders',
        phone: '9123456789',
        area: 'Gandhipuram',
        type: PartyType.seller,
        openingBalance: 1800,
      ),
      const Party(
        id: 'customer-sharma',
        name: 'Sharma Recyclers',
        phone: '9988776655',
        area: 'Tiruppur',
        type: PartyType.customer,
        gstNumber: '33AAHCS9876Q1Z0',
        openingBalance: 30000,
      ),
      const Party(
        id: 'customer-green',
        name: 'Green Alloy Works',
        phone: '9090909090',
        area: 'Coimbatore',
        type: PartyType.customer,
        openingBalance: 12000,
      ),
    ];

    final purchases = [
      Purchase(
        id: 'purchase-1',
        invoiceNumber:
            'INV-${now.year}${now.month.toString().padLeft(2, '0')}30-001',
        sellerId: 'seller-ramesh',
        sellerName: 'Ramesh Scrap',
        createdAt: now.subtract(const Duration(hours: 1)),
        items: const [
          TransactionItem(
            materialId: 'coconut-shell',
            materialName: 'Coconut Shell',
            weightKg: 150,
            rate: 15,
          ),
          TransactionItem(
            materialId: 'pet-bottle',
            materialName: 'PET Bottle',
            weightKg: 25,
            rate: 20,
          ),
          TransactionItem(
            materialId: 'cardboard',
            materialName: 'Cardboard',
            weightKg: 10,
            rate: 8,
          ),
        ],
        paidAmount: 2000,
        createdBy: 'Mahesh Kumar',
      ),
      Purchase(
        id: 'purchase-2',
        invoiceNumber:
            'INV-${now.year}${now.month.toString().padLeft(2, '0')}29-101',
        sellerId: 'seller-suresh',
        sellerName: 'Suresh Traders',
        createdAt: now.subtract(const Duration(days: 1, hours: 4)),
        items: const [
          TransactionItem(
            materialId: 'iron',
            materialName: 'Iron',
            weightKg: 80,
            rate: 25,
          ),
          TransactionItem(
            materialId: 'plastic',
            materialName: 'Plastic',
            weightKg: 50,
            rate: 10,
          ),
        ],
        paidAmount: 2500,
        createdBy: 'Suresh Kumar',
      ),
    ];

    final sales = [
      Sale(
        id: 'sale-1',
        invoiceNumber:
            'SAL-${now.year}${now.month.toString().padLeft(2, '0')}30-001',
        customerId: 'customer-sharma',
        customerName: 'Sharma Recyclers',
        createdAt: now.subtract(const Duration(hours: 2)),
        items: const [
          TransactionItem(
            materialId: 'coconut-shell',
            materialName: 'Coconut Shell',
            weightKg: 300,
            rate: 18,
          ),
          TransactionItem(
            materialId: 'pet-bottle',
            materialName: 'PET Bottle',
            weightKg: 200,
            rate: 26,
          ),
          TransactionItem(
            materialId: 'cardboard',
            materialName: 'Cardboard',
            weightKg: 150,
            rate: 10,
          ),
        ],
        receivedAmount: 95000,
        createdBy: 'Mahesh Kumar',
        vehicleNumber: 'TN38AB1123',
      ),
      Sale(
        id: 'sale-2',
        invoiceNumber:
            'SAL-${now.year}${now.month.toString().padLeft(2, '0')}28-017',
        customerId: 'customer-green',
        customerName: 'Green Alloy Works',
        createdAt: now.subtract(const Duration(days: 2)),
        items: const [
          TransactionItem(
            materialId: 'iron',
            materialName: 'Iron',
            weightKg: 220,
            rate: 34,
          ),
          TransactionItem(
            materialId: 'aluminium',
            materialName: 'Aluminium',
            weightKg: 60,
            rate: 128,
          ),
        ],
        receivedAmount: 10000,
        createdBy: 'Ravi Kumar',
      ),
    ];

    final expenses = [
      Expense(
        id: 'expense-1',
        category: 'Rent',
        amount: 5000,
        createdAt: now,
        createdBy: 'Mahesh Kumar',
      ),
      Expense(
        id: 'expense-2',
        category: 'Logistics / Transport',
        amount: 1500,
        createdAt: now.subtract(const Duration(hours: 3)),
        createdBy: 'Mahesh Kumar',
      ),
      Expense(
        id: 'expense-3',
        category: 'Food',
        amount: 900,
        createdAt: now.subtract(const Duration(days: 1)),
        createdBy: 'Suresh Kumar',
      ),
    ];

    final dispatches = [
      Dispatch(
        id: 'dispatch-1',
        customerName: 'Sharma Recyclers',
        materialName: 'Coconut Shell',
        weightKg: 500,
        vehicleNumber: 'TN70AB1123',
        driverName: 'Lokesh',
        status: DispatchStatus.loaded,
        createdAt: now.subtract(const Duration(minutes: 40)),
      ),
      Dispatch(
        id: 'dispatch-2',
        customerName: 'Green Alloy Works',
        materialName: 'Iron',
        weightKg: 220,
        vehicleNumber: 'TN38CD4477',
        driverName: 'Karthik',
        status: DispatchStatus.inTransit,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
    ];

    final ledgers = <LedgerEntry>[
      LedgerEntry(
        id: 'ledger-2',
        partyId: 'seller-ramesh',
        partyName: 'Ramesh Scrap',
        date: now,
        description: 'Cash paid',
        direction: LedgerDirection.debit,
        amount: 2000,
        balanceAfter: 5830,
      ),
      LedgerEntry(
        id: 'ledger-1',
        partyId: 'seller-ramesh',
        partyName: 'Ramesh Scrap',
        date: now.subtract(const Duration(hours: 1)),
        description: 'Purchase bill INV-001',
        direction: LedgerDirection.credit,
        amount: 2830,
        balanceAfter: 7830,
      ),
      LedgerEntry(
        id: 'ledger-3',
        partyId: 'customer-sharma',
        partyName: 'Sharma Recyclers',
        date: now,
        description: 'Sale invoice SAL-001',
        direction: LedgerDirection.debit,
        amount: 121500,
        balanceAfter: 151500,
      ),
    ];

    final activities = [
      Activity(
        id: 'activity-1',
        message: 'Purchase 150 KG Coconut Shell',
        actor: 'Mahesh Kumar',
        createdAt: now.subtract(const Duration(minutes: 30)),
      ),
      Activity(
        id: 'activity-2',
        message: 'Dispatched 200 KG Iron',
        actor: 'Suresh Kumar',
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      Activity(
        id: 'activity-3',
        message: 'Payment received from Sharma Recyclers',
        actor: 'Ramesh',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
    ];

    final notifications = [
      NotificationItem(
        id: 'notification-1',
        title: 'Payment reminder',
        message: 'Ramesh Scrap has pending balance of Rs 5,830.',
        type: NotificationType.payment,
        createdAt: now,
      ),
      NotificationItem(
        id: 'notification-2',
        title: 'Dispatch reminder',
        message: 'TN70AB1123 is loaded and ready for dispatch.',
        type: NotificationType.dispatch,
        createdAt: now.subtract(const Duration(minutes: 25)),
      ),
    ];

    return ScrapRepository(
      materials: materials,
      parties: parties,
      purchases: purchases,
      sales: sales,
      expenses: expenses,
      dispatches: dispatches,
      ledgers: ledgers,
      activities: activities,
      notifications: notifications,
    );
  }

  List<MaterialItem> get materials => List.unmodifiable(_materials);
  List<Party> get parties => List.unmodifiable(_parties);
  List<Party> get sellers =>
      _parties.where((party) => party.type == PartyType.seller).toList();
  List<Party> get customers =>
      _parties.where((party) => party.type == PartyType.customer).toList();
  List<Purchase> get purchases => List.unmodifiable(_purchases);
  List<Sale> get sales => List.unmodifiable(_sales);
  List<Expense> get expenses => List.unmodifiable(_expenses);
  List<Dispatch> get dispatches => List.unmodifiable(_dispatches);
  List<LedgerEntry> get ledgers => List.unmodifiable(_ledgers);
  List<Activity> get activities => List.unmodifiable(_activities);
  List<NotificationItem> get notifications => List.unmodifiable(_notifications);

  DashboardMetrics metrics() {
    final todayPurchases = _purchases.where((item) => _isToday(item.createdAt));
    final todaySales = _sales.where((item) => _isToday(item.createdAt));
    final todayExpenses = _expenses.where((item) => _isToday(item.createdAt));

    final purchaseValue = todayPurchases.fold<double>(
      0,
      (total, item) => total + item.totalAmount,
    );
    final salesValue = todaySales.fold<double>(
      0,
      (total, item) => total + item.totalAmount,
    );
    final expenseValue = todayExpenses.fold<double>(
      0,
      (total, item) => total + item.amount,
    );
    final pending =
        _purchases.fold<double>(
          0,
          (total, item) => total + item.balanceAmount.clamp(0, double.infinity),
        ) +
        _sales.fold<double>(
          0,
          (total, item) => total + item.balanceAmount.clamp(0, double.infinity),
        );

    return DashboardMetrics(
      todayPurchaseKg: todayPurchases.fold(
        0,
        (total, item) => total + item.totalWeightKg,
      ),
      todayPurchaseValue: purchaseValue,
      todaySalesKg: todaySales.fold(
        0,
        (total, item) => total + item.totalWeightKg,
      ),
      todaySalesValue: salesValue,
      pendingPayments: pending,
      todayExpenses: expenseValue,
      netProfit: salesValue - purchaseValue - expenseValue,
      stockValue: _materials.fold(0, (total, item) => total + item.stockValue),
      invoiceCount: _purchases.length + _sales.length,
      vendorCount: sellers.length,
      customerCount: customers.length,
    );
  }

  Purchase addPurchase({
    required String sellerId,
    required List<TransactionItem> items,
    required double paidAmount,
    required String createdBy,
  }) {
    final seller = _parties.firstWhere((party) => party.id == sellerId);
    final purchase = Purchase(
      id: _uuid.v4(),
      invoiceNumber: _nextNumber(AppConfig.invoicePrefix, _purchases.length),
      sellerId: seller.id,
      sellerName: seller.name,
      createdAt: DateTime.now(),
      items: items,
      paidAmount: paidAmount,
      createdBy: createdBy,
    );
    _purchases.insert(0, purchase);
    _applyPurchaseStock(items);
    _addLedger(
      partyId: seller.id,
      partyName: seller.name,
      description: 'Purchase ${purchase.invoiceNumber}',
      direction: LedgerDirection.credit,
      amount: purchase.totalAmount,
    );
    if (paidAmount > 0) {
      _addLedger(
        partyId: seller.id,
        partyName: seller.name,
        description: 'Payment against ${purchase.invoiceNumber}',
        direction: LedgerDirection.debit,
        amount: paidAmount,
      );
    }
    _addActivity('Purchase saved for ${seller.name}', createdBy);
    return purchase;
  }

  Sale addSale({
    required String customerId,
    required List<TransactionItem> items,
    required double receivedAmount,
    required String createdBy,
    String? vehicleNumber,
  }) {
    final customer = _parties.firstWhere((party) => party.id == customerId);
    final sale = Sale(
      id: _uuid.v4(),
      invoiceNumber: _nextNumber(AppConfig.salePrefix, _sales.length),
      customerId: customer.id,
      customerName: customer.name,
      createdAt: DateTime.now(),
      items: items,
      receivedAmount: receivedAmount,
      createdBy: createdBy,
      vehicleNumber: vehicleNumber,
    );
    _sales.insert(0, sale);
    _applySaleStock(items);
    _addLedger(
      partyId: customer.id,
      partyName: customer.name,
      description: 'Sale ${sale.invoiceNumber}',
      direction: LedgerDirection.debit,
      amount: sale.totalAmount,
    );
    if (receivedAmount > 0) {
      _addLedger(
        partyId: customer.id,
        partyName: customer.name,
        description: 'Receipt against ${sale.invoiceNumber}',
        direction: LedgerDirection.credit,
        amount: receivedAmount,
      );
    }
    _addActivity('Sale saved for ${customer.name}', createdBy);
    return sale;
  }

  Party addParty({
    required String name,
    required String phone,
    required String area,
    required PartyType type,
    String? gstNumber,
  }) {
    final party = Party(
      id: _uuid.v4(),
      name: name,
      phone: phone,
      area: area,
      type: type,
      gstNumber: gstNumber,
    );
    _parties.insert(0, party);
    _addActivity('${type.label} added: $name', 'System');
    return party;
  }

  Party updateParty(Party party) {
    final index = _parties.indexWhere((item) => item.id == party.id);
    if (index != -1) {
      _parties[index] = party;
      _addActivity('${party.type.label} updated: ${party.name}', 'System');
    }
    return party;
  }

  void deleteParty(String partyId) {
    final index = _parties.indexWhere((party) => party.id == partyId);
    if (index == -1) {
      return;
    }
    final party = _parties.removeAt(index);
    _addActivity('${party.type.label} removed: ${party.name}', 'System');
  }

  Expense addExpense({
    required String category,
    required double amount,
    required String createdBy,
    String? note,
  }) {
    final expense = Expense(
      id: _uuid.v4(),
      category: category,
      amount: amount,
      createdAt: DateTime.now(),
      createdBy: createdBy,
      note: note,
    );
    _expenses.insert(0, expense);
    _addActivity('Expense added: $category', createdBy);
    return expense;
  }

  Dispatch addDispatch({
    required String customerName,
    required String materialName,
    required double weightKg,
    required String vehicleNumber,
    required String driverName,
  }) {
    final dispatch = Dispatch(
      id: _uuid.v4(),
      customerName: customerName,
      materialName: materialName,
      weightKg: weightKg,
      vehicleNumber: vehicleNumber,
      driverName: driverName,
      status: DispatchStatus.loaded,
      createdAt: DateTime.now(),
    );
    _dispatches.insert(0, dispatch);
    _addActivity('Dispatch created for $customerName', 'Supervisor');
    return dispatch;
  }

  List<LedgerEntry> ledgerFor(String partyId) {
    return _ledgers.where((entry) => entry.partyId == partyId).toList();
  }

  List<ReportSummary> reportSummaries() {
    final now = DateTime.now();
    return [
      _summary('Daily Report', now.subtract(const Duration(days: 1)), now),
      _summary('Weekly Report', now.subtract(const Duration(days: 7)), now),
      _summary('Monthly Report', DateTime(now.year, now.month), now),
      _summary('Yearly Report', DateTime(now.year), now),
    ];
  }

  void _applyPurchaseStock(List<TransactionItem> items) {
    for (final item in items) {
      final index = _materials.indexWhere(
        (material) => material.id == item.materialId,
      );
      if (index == -1) {
        continue;
      }
      final material = _materials[index];
      _materials[index] = material.copyWith(
        purchasedKg: material.purchasedKg + item.weightKg,
        currentBuyingRate: item.rate,
      );
    }
  }

  void _applySaleStock(List<TransactionItem> items) {
    for (final item in items) {
      final index = _materials.indexWhere(
        (material) => material.id == item.materialId,
      );
      if (index == -1) {
        continue;
      }
      final material = _materials[index];
      _materials[index] = material.copyWith(
        soldKg: material.soldKg + item.weightKg,
        currentSellingRate: item.rate,
      );
    }
  }

  void _addLedger({
    required String partyId,
    required String partyName,
    required String description,
    required LedgerDirection direction,
    required double amount,
  }) {
    final existing = _ledgers.where((entry) => entry.partyId == partyId);
    final balance = existing.isEmpty ? 0 : existing.first.balanceAfter;
    final signed = direction == LedgerDirection.credit ? amount : -amount;
    _ledgers.insert(
      0,
      LedgerEntry(
        id: _uuid.v4(),
        partyId: partyId,
        partyName: partyName,
        date: DateTime.now(),
        description: description,
        direction: direction,
        amount: amount,
        balanceAfter: balance + signed,
      ),
    );
  }

  void _addActivity(String message, String actor) {
    _activities.insert(
      0,
      Activity(
        id: _uuid.v4(),
        message: message,
        actor: actor,
        createdAt: DateTime.now(),
      ),
    );
  }

  ReportSummary _summary(String title, DateTime from, DateTime to) {
    final purchases = _purchases
        .where(
          (item) => item.createdAt.isAfter(from) && item.createdAt.isBefore(to),
        )
        .fold<double>(0, (total, item) => total + item.totalAmount);
    final sales = _sales
        .where(
          (item) => item.createdAt.isAfter(from) && item.createdAt.isBefore(to),
        )
        .fold<double>(0, (total, item) => total + item.totalAmount);
    final expenses = _expenses
        .where(
          (item) => item.createdAt.isAfter(from) && item.createdAt.isBefore(to),
        )
        .fold<double>(0, (total, item) => total + item.amount);
    return ReportSummary(
      title: title,
      purchase: purchases,
      sales: sales,
      expense: expenses,
      profit: sales - purchases - expenses,
      generatedAt: DateTime.now(),
    );
  }

  String _nextNumber(String prefix, int currentCount) {
    final now = DateTime.now();
    return '$prefix-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(currentCount + 1).toString().padLeft(3, '0')}';
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}
