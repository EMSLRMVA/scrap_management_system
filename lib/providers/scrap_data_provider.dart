import 'package:flutter/foundation.dart';

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
import '../repositories/scrap_repository.dart';

class ScrapDataProvider extends ChangeNotifier {
  ScrapDataProvider(this._repository);

  final ScrapRepository _repository;

  List<MaterialItem> get materials => _repository.materials;
  List<Party> get sellers => _repository.sellers;
  List<Party> get customers => _repository.customers;
  List<Party> get parties => _repository.parties;
  List<Purchase> get purchases => _repository.purchases;
  List<Sale> get sales => _repository.sales;
  List<Expense> get expenses => _repository.expenses;
  List<Dispatch> get dispatches => _repository.dispatches;
  List<LedgerEntry> get ledgers => _repository.ledgers;
  List<Activity> get activities => _repository.activities;
  List<NotificationItem> get notifications => _repository.notifications;
  DashboardMetrics get metrics => _repository.metrics();
  List<ReportSummary> get reports => _repository.reportSummaries();

  Purchase addPurchase({
    required String sellerId,
    required List<TransactionItem> items,
    required double paidAmount,
    required String createdBy,
  }) {
    final purchase = _repository.addPurchase(
      sellerId: sellerId,
      items: items,
      paidAmount: paidAmount,
      createdBy: createdBy,
    );
    notifyListeners();
    return purchase;
  }

  Sale addSale({
    required String customerId,
    required List<TransactionItem> items,
    required double receivedAmount,
    required String createdBy,
    String? vehicleNumber,
  }) {
    final sale = _repository.addSale(
      customerId: customerId,
      items: items,
      receivedAmount: receivedAmount,
      createdBy: createdBy,
      vehicleNumber: vehicleNumber,
    );
    notifyListeners();
    return sale;
  }

  Party addParty({
    required String name,
    required String phone,
    required String area,
    required PartyType type,
    String? gstNumber,
  }) {
    final party = _repository.addParty(
      name: name,
      phone: phone,
      area: area,
      type: type,
      gstNumber: gstNumber,
    );
    notifyListeners();
    return party;
  }

  Party updateParty(Party party) {
    final updated = _repository.updateParty(party);
    notifyListeners();
    return updated;
  }

  void deleteParty(String partyId) {
    _repository.deleteParty(partyId);
    notifyListeners();
  }

  Expense addExpense({
    required String category,
    required double amount,
    required String createdBy,
    String? note,
  }) {
    final expense = _repository.addExpense(
      category: category,
      amount: amount,
      createdBy: createdBy,
      note: note,
    );
    notifyListeners();
    return expense;
  }

  Dispatch addDispatch({
    required String customerName,
    required String materialName,
    required double weightKg,
    required String vehicleNumber,
    required String driverName,
  }) {
    final dispatch = _repository.addDispatch(
      customerName: customerName,
      materialName: materialName,
      weightKg: weightKg,
      vehicleNumber: vehicleNumber,
      driverName: driverName,
    );
    notifyListeners();
    return dispatch;
  }

  List<LedgerEntry> ledgerFor(String partyId) => _repository.ledgerFor(partyId);
}
