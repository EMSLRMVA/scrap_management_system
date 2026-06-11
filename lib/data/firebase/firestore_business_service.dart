import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/business_models.dart';

class FirestoreBusinessService {
  FirestoreBusinessService({FirebaseFirestore? firestore})
    : _providedFirestore = firestore;

  final FirebaseFirestore? _providedFirestore;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  bool get isAvailable => Firebase.apps.isNotEmpty;

  CollectionReference<Map<String, dynamic>> get _sellers =>
      _firestore.collection('sellers');
  CollectionReference<Map<String, dynamic>> get _customers =>
      _firestore.collection('customers');
  CollectionReference<Map<String, dynamic>> get _inventory =>
      _firestore.collection('inventory');
  CollectionReference<Map<String, dynamic>> get _purchases =>
      _firestore.collection('purchases');
  CollectionReference<Map<String, dynamic>> get _sales =>
      _firestore.collection('sales');
  CollectionReference<Map<String, dynamic>> get _expenses =>
      _firestore.collection('expenses');
  CollectionReference<Map<String, dynamic>> get _cashAllocations =>
      _firestore.collection('cash_allocations');
  CollectionReference<Map<String, dynamic>> get _openingStocks =>
      _firestore.collection('openingStocks');
  CollectionReference<Map<String, dynamic>> get _physicalStocks =>
      _firestore.collection('physicalStocks');
  CollectionReference<Map<String, dynamic>> get _stockReminderReceivers =>
      _firestore.collection('stockReminderReceivers');
  CollectionReference<Map<String, dynamic>> get _manualReminderLogs =>
      _firestore.collection('manualReminderLogs');
  CollectionReference<Map<String, dynamic>> get _auditTrail =>
      _firestore.collection('audit_trail');
  CollectionReference<Map<String, dynamic>> get _activities =>
      _firestore.collection('activities');
  CollectionReference<Map<String, dynamic>> get _activityLogs =>
      _firestore.collection('activityLogs');
  CollectionReference<Map<String, dynamic>> get _ownerNotifications =>
      _firestore.collection('ownerNotifications');
  CollectionReference<Map<String, dynamic>> get _ownerViewAsLogs =>
      _firestore.collection('owner_view_as_logs');
  DocumentReference<Map<String, dynamic>> get _dashboard =>
      _firestore.collection('dashboard').doc('statistics');

  Stream<List<Party>> watchSellers() {
    return _sellers
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => _partyFromDoc(doc, PartyKind.seller))
              .toList(),
        );
  }

  Stream<List<Party>> watchCustomers() {
    return _customers
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => _partyFromDoc(doc, PartyKind.customer))
              .toList(),
        );
  }

  Stream<List<MaterialStock>> watchInventory() {
    return _inventory
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_materialFromDoc).toList());
  }

  Stream<List<PurchaseRecord>> watchPurchases() {
    return _purchases
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_purchaseFromDoc).toList());
  }

  Stream<List<SaleRecord>> watchSales() {
    return _sales
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_saleFromDoc).toList());
  }

  Stream<List<ExpenseRecord>> watchExpenses() {
    return _expenses
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_expenseFromDoc).toList());
  }

  Stream<List<CashAllocation>> watchCashAllocations() {
    return _cashAllocations
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_cashAllocationFromDoc).toList());
  }

  Stream<List<OpeningStockRecord>> watchOpeningStocks() {
    return _openingStocks
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_openingStockFromDoc).toList());
  }

  Stream<List<PhysicalStockRecord>> watchPhysicalStocks() {
    return _physicalStocks
        .orderBy('entryDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_physicalStockFromDoc).toList());
  }

  Stream<List<StockReminderReceiver>> watchStockReminderReceivers() {
    return _stockReminderReceivers
        .orderBy('receiverName')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(_stockReminderReceiverFromDoc).toList(),
        );
  }

  Stream<List<ManualReminderLog>> watchManualReminderLogs() {
    return _manualReminderLogs
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(_manualReminderLogFromDoc).toList(),
        );
  }

  Stream<List<AuditEntry>> watchAuditTrail() {
    return _auditTrail
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_auditFromDoc).toList());
  }

  Stream<List<ActivityRecord>> watchActivities() {
    return _activities
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_activityFromDoc).toList());
  }

  Stream<Map<String, dynamic>?> watchDashboardStatistics() {
    return _dashboard.snapshots().map((snapshot) => snapshot.data());
  }

  Future<List<Party>> fetchSellers() async {
    final snapshot = await _sellers
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => _partyFromDoc(doc, PartyKind.seller))
        .toList();
  }

  Future<List<Party>> fetchCustomers() async {
    final snapshot = await _customers
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => _partyFromDoc(doc, PartyKind.customer))
        .toList();
  }

  Future<Party?> getParty(String id, PartyKind kind) async {
    final collection = kind == PartyKind.seller ? _sellers : _customers;
    final snapshot = await collection.doc(id).get();
    if (!snapshot.exists) {
      return null;
    }
    return _partyFromDoc(snapshot, kind);
  }

  Future<void> saveParty(Party party) {
    final collection = party.kind == PartyKind.seller ? _sellers : _customers;
    return collection
        .doc(party.id)
        .set(_partyToMap(party), SetOptions(merge: true));
  }

  Future<void> deleteParty(String id, PartyKind kind) {
    final collection = kind == PartyKind.seller ? _sellers : _customers;
    return collection.doc(id).delete();
  }

  Future<List<MaterialStock>> fetchInventory() async {
    final snapshot = await _inventory.orderBy('name').get();
    return snapshot.docs.map(_materialFromDoc).toList();
  }

  Future<MaterialStock?> getMaterial(String id) async {
    final snapshot = await _inventory.doc(id).get();
    if (!snapshot.exists) {
      return null;
    }
    return _materialFromDoc(snapshot);
  }

  Future<void> saveMaterial(MaterialStock material) {
    return _inventory
        .doc(material.id)
        .set(_materialToMap(material), SetOptions(merge: true));
  }

  Future<void> deleteMaterial(String id) {
    return _inventory.doc(id).delete();
  }

  Future<List<PurchaseRecord>> fetchPurchases() async {
    final snapshot = await _purchases
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map(_purchaseFromDoc).toList();
  }

  Future<PurchaseRecord?> getPurchase(String id) async {
    final snapshot = await _purchases.doc(id).get();
    if (!snapshot.exists) {
      return null;
    }
    return _purchaseFromDoc(snapshot);
  }

  Future<void> savePurchase(PurchaseRecord purchase, Party seller) async {
    final batch = _firestore.batch();
    batch.set(
      _purchases.doc(purchase.id),
      _purchaseToMap(purchase),
      SetOptions(merge: true),
    );
    batch.set(
      _sellers.doc(seller.id),
      _partyToMap(seller),
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> deletePurchase(String id) {
    return _purchases.doc(id).set({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deletePurchasePermanently(String id) {
    return _purchases.doc(id).delete();
  }

  Future<List<SaleRecord>> fetchSales() async {
    final snapshot = await _sales.orderBy('createdAt', descending: true).get();
    return snapshot.docs.map(_saleFromDoc).toList();
  }

  Future<SaleRecord?> getSale(String id) async {
    final snapshot = await _sales.doc(id).get();
    if (!snapshot.exists) {
      return null;
    }
    return _saleFromDoc(snapshot);
  }

  Future<void> saveSale(SaleRecord sale, Party customer) async {
    final batch = _firestore.batch();
    batch.set(_sales.doc(sale.id), _saleToMap(sale), SetOptions(merge: true));
    batch.set(
      _customers.doc(customer.id),
      _partyToMap(customer),
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> deleteSale(String id) {
    return _sales.doc(id).set({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteSalePermanently(String id) {
    return _sales.doc(id).delete();
  }

  Future<List<ExpenseRecord>> fetchExpenses() async {
    final snapshot = await _expenses
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map(_expenseFromDoc).toList();
  }

  Future<void> saveExpense(ExpenseRecord expense) {
    return _expenses.doc(expense.id).set({
      'category': expense.category,
      'amount': expense.amount,
      'expenseDate': Timestamp.fromDate(expense.date),
      'vendorName': expense.vendorName,
      'remarks': expense.remarks,
      'billUploadPath': expense.billUploadPath,
      'photoPath': expense.photoPath,
      'addedBy': expense.addedBy,
      'updatedAt': _timestampOrNull(expense.updatedAt),
      'updatedBy': expense.updatedBy,
      'deletedAt': _timestampOrNull(expense.deletedAt),
      'deletedBy': expense.deletedBy,
      'isDeleted': expense.isDeleted,
      'isApproved': expense.isApproved,
      'createdAt': Timestamp.fromDate(expense.createdAt),
    }, SetOptions(merge: true));
  }

  Future<void> deleteExpense(String id) {
    return _expenses.doc(id).delete();
  }

  Future<void> saveCashAllocation(CashAllocation allocation) {
    return _cashAllocations.doc(allocation.id).set({
      'supervisorName': allocation.supervisorName,
      'amount': allocation.amount,
      'allocationDate': Timestamp.fromDate(allocation.date),
      'paymentMode': allocation.paymentMode,
      'remarks': allocation.remarks,
      'createdBy': allocation.createdBy,
      'createdAt': Timestamp.fromDate(allocation.createdAt),
      'updatedAt': _timestampOrNull(allocation.updatedAt),
      'updatedBy': allocation.updatedBy,
    }, SetOptions(merge: true));
  }

  Future<void> deleteCashAllocation(String id) {
    return _cashAllocations.doc(id).delete();
  }

  Future<void> saveOpeningStock(OpeningStockRecord record) {
    return _openingStocks
        .doc(record.id)
        .set(_openingStockToMap(record), SetOptions(merge: true));
  }

  Future<void> savePhysicalStock(
    PhysicalStockRecord record,
    MaterialStock material,
  ) async {
    final batch = _firestore.batch();
    batch.set(
      _physicalStocks.doc(record.id),
      _physicalStockToMap(record),
      SetOptions(merge: true),
    );
    batch.set(
      _inventory.doc(material.id),
      _materialToMap(material),
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> saveStockReminderReceiver(StockReminderReceiver receiver) {
    return _stockReminderReceivers
        .doc(receiver.id)
        .set(_stockReminderReceiverToMap(receiver), SetOptions(merge: true));
  }

  Future<void> deleteStockReminderReceiver(String id) {
    return _stockReminderReceivers.doc(id).delete();
  }

  Future<void> saveManualReminderLog(ManualReminderLog log) {
    return _manualReminderLogs
        .doc(log.reminderId)
        .set(_manualReminderLogToMap(log), SetOptions(merge: true));
  }

  Future<void> saveAuditEntry(AuditEntry audit) {
    return _auditTrail.doc(audit.id).set({
      'action': audit.action,
      'recordType': audit.recordType,
      'recordId': audit.recordId,
      'field': audit.field,
      'oldValue': audit.oldValue,
      'newValue': audit.newValue,
      'user': audit.user,
      'role': audit.role.name,
      'deviceInfo': audit.deviceInfo,
      'createdAt': Timestamp.fromDate(audit.createdAt),
    }, SetOptions(merge: true));
  }

  Future<void> saveActivity(ActivityRecord activity) {
    return _activities.doc(activity.id).set({
      'title': activity.title,
      'subtitle': activity.subtitle,
      'userName': activity.userName,
      'createdAt': Timestamp.fromDate(activity.createdAt),
    }, SetOptions(merge: true));
  }

  Future<void> saveAppActivityLog({
    required AppUser user,
    required String action,
    required String screen,
    required String details,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? user.email;
    await _activityLogs.add({
      'userId': userId,
      'name': user.name,
      'email': user.email,
      'mobile': user.mobile,
      'role': user.role.name,
      'action': action,
      'screen': screen,
      'details': details,
      'createdAt': FieldValue.serverTimestamp(),
      'deviceInfo': 'Flutter app',
    });
    if (_ownerNotificationActions.contains(action)) {
      await _ownerNotifications.add({
        'type': action,
        'title': _notificationTitle(action),
        'body': '${user.name}: $details',
        'userId': userId,
        'name': user.name,
        'email': user.email,
        'role': user.role.name,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    }
  }

  Future<void> saveOwnerViewAsLog({
    required AppUser owner,
    required String viewedUserName,
    required UserRole viewedUserRole,
    required String event,
  }) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? owner.email;
    return _ownerViewAsLogs.add({
      'owner_user_id': userId,
      'owner_name': owner.name,
      'viewed_user_id': viewedUserName.trim().toLowerCase(),
      'viewed_user_name': viewedUserName,
      'viewed_user_role': viewedUserRole.name,
      'event': event,
      'started_at': event == 'opened' ? FieldValue.serverTimestamp() : null,
      'ended_at': event == 'exited' ? FieldValue.serverTimestamp() : null,
      'device_info': 'Flutter app',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getDashboardStatistics() async {
    final snapshot = await _dashboard.get();
    return snapshot.data();
  }

  Future<void> saveDashboardStatistics(BusinessMetrics metrics) {
    return _dashboard.set({
      'todayPurchase': metrics.todayPurchase,
      'todaySales': metrics.todaySales,
      'cashBalance': metrics.cashBalance,
      'cashWithSupervisor': metrics.cashBalance,
      'cashGiven': metrics.cashGiven,
      'cashUsed': metrics.cashUsed,
      'totalExpense': metrics.totalExpense,
      'scrapPurchaseTotal': metrics.scrapPurchaseTotal,
      'otherPurchaseTotal': metrics.otherPurchaseTotal,
      'inventoryPurchaseTotal': metrics.inventoryPurchaseTotal,
      'adjustmentTotal': metrics.adjustmentTotal,
      'salesCollection': metrics.salesCollection,
      'profitLoss': metrics.profitLoss,
      'pendingPayments': metrics.pendingPayments,
      'stockValue': metrics.stockValue,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> verifyConnectivity() async {
    await _dashboard.set({
      'lastConnectivityCheckAt': FieldValue.serverTimestamp(),
      'source': 'flutter-app',
    }, SetOptions(merge: true));
  }

  Party _partyFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    PartyKind kind,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return Party(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      mobile: (data['mobile'] ?? '').toString(),
      area: (data['area'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
      remarks: (data['remarks'] ?? '').toString(),
      photoPath: (data['photoPath'] ?? data['photoUrl'] ?? '').toString(),
      kind: kind,
      pendingAmount: _num(data['pendingAmount']),
      lastPurchaseAt: _dateOrNull(data['lastPurchaseAt']),
    );
  }

  MaterialStock _materialFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return MaterialStock(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      category: (data['category'] ?? 'General').toString(),
      availableKg: _num(data['availableKg']),
      currentBuyingRate: _num(data['currentBuyingRate']),
      photoPath: (data['photoPath'] ?? data['photoUrl'] ?? '').toString(),
      currentSellingRate: _num(data['currentSellingRate']),
      wastageDeductionPercent: _percent(data['wastageDeductionPercent']),
      isActive: data['isActive'] != false,
      createdBy: (data['createdBy'] ?? 'System').toString(),
      updatedBy: (data['updatedBy'] ?? '').toString(),
      deletedBy: (data['deletedBy'] ?? '').toString(),
      createdAt: _dateOrNull(data['createdAt']),
      updatedAt: _dateOrNull(data['updatedAt']),
      deletedAt: _dateOrNull(data['deletedAt']),
      isDeleted: data['isDeleted'] == true,
    );
  }

  PurchaseRecord _purchaseFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final items = _lineItemsFromData(data);
    final itemOriginalTotal = roundMoneyValue(
      items.fold<double>(
        0,
        (runningTotal, item) => runningTotal + item.componentOriginalAmount,
      ),
    );
    final paidAmount = _num(data['paidAmount']);
    final originalBillAmount =
        _numOrNull(data['originalBillAmount']) ??
        _numOrNull(data['totalAmount']) ??
        itemOriginalTotal;
    final previousBalanceAppliedAmount = _num(
      data['previousBalanceAppliedAmount'],
    );
    final currentSettlementAdjustmentAmount = _num(
      data['currentSettlementAdjustmentAmount'],
    );
    final finalBillAmount =
        _numOrNull(data['finalBillAmount']) ??
        _numOrNull(data['totalAmount']) ??
        roundMoneyValue(
          originalBillAmount +
              previousBalanceAppliedAmount +
              currentSettlementAdjustmentAmount,
        );
    final balanceAmount =
        _numOrNull(data['balanceAmount']) ??
        roundMoneyValue(finalBillAmount - paidAmount);
    final seller = Party(
      id: (data['sellerId'] ?? '').toString(),
      name: (data['sellerName'] ?? '').toString(),
      mobile: (data['sellerMobile'] ?? '').toString(),
      area: (data['sellerArea'] ?? '').toString(),
      address: (data['sellerAddress'] ?? '').toString(),
      remarks: (data['sellerRemarks'] ?? '').toString(),
      photoPath: (data['sellerPhotoPath'] ?? '').toString(),
      kind: PartyKind.seller,
      pendingAmount: _num(data['sellerPendingAmount']),
      lastPurchaseAt: _dateOrNull(data['sellerLastPurchaseAt']),
    );
    return PurchaseRecord(
      id: doc.id,
      invoiceNumber: (data['invoiceNumber'] ?? '').toString(),
      seller: seller,
      items: items,
      paidAmount: paidAmount,
      originalBillAmount: originalBillAmount,
      previousBalanceAppliedAmount: previousBalanceAppliedAmount,
      previousBalanceReferenceIds: _stringList(
        data['previousBalanceReferenceIds'],
      ),
      currentSettlementAdjustmentAmount: currentSettlementAdjustmentAmount,
      finalBillAmount: finalBillAmount,
      balanceAmount: balanceAmount,
      paymentStatus: (data['paymentStatus'] ?? '').toString(),
      settlementStatus: (data['settlementStatus'] ?? 'carry_forward')
          .toString(),
      remarks: (data['remarks'] ?? '').toString(),
      createdAt: _date(data['createdAt']),
      isDeleted: data['isDeleted'] == true,
      deletedAt: _dateOrNull(data['deletedAt']),
      updatedAt: _dateOrNull(data['updatedAt']),
      createdBy: (data['createdBy'] ?? 'System').toString(),
      updatedBy: (data['updatedBy'] ?? '').toString(),
      deletedBy: (data['deletedBy'] ?? '').toString(),
    );
  }

  SaleRecord _saleFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final customer = Party(
      id: (data['customerId'] ?? '').toString(),
      name: (data['customerName'] ?? '').toString(),
      mobile: (data['customerMobile'] ?? '').toString(),
      area: (data['customerArea'] ?? '').toString(),
      address: (data['customerAddress'] ?? '').toString(),
      remarks: (data['customerRemarks'] ?? '').toString(),
      photoPath: (data['customerPhotoPath'] ?? '').toString(),
      kind: PartyKind.customer,
      pendingAmount: _num(data['customerPendingAmount']),
    );
    return SaleRecord(
      id: doc.id,
      invoiceNumber: (data['invoiceNumber'] ?? '').toString(),
      customer: customer,
      items: _lineItemsFromData(data),
      receivedAmount: _num(data['paidAmount'] ?? data['receivedAmount']),
      remarks: (data['remarks'] ?? '').toString(),
      createdAt: _date(data['createdAt']),
      isDeleted: data['isDeleted'] == true,
      deletedAt: _dateOrNull(data['deletedAt']),
      updatedAt: _dateOrNull(data['updatedAt']),
      createdBy: (data['createdBy'] ?? 'System').toString(),
      updatedBy: (data['updatedBy'] ?? '').toString(),
      deletedBy: (data['deletedBy'] ?? '').toString(),
      reminderSentAt: _dateOrNull(data['reminderSentAt']),
      reminderSentBy: (data['reminderSentBy'] ?? '').toString(),
      paymentReceivedAt: _dateOrNull(data['paymentReceivedAt']),
      paymentReceivedBy: (data['paymentReceivedBy'] ?? '').toString(),
    );
  }

  ExpenseRecord _expenseFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ExpenseRecord(
      id: doc.id,
      category: (data['category'] ?? '').toString(),
      amount: _num(data['amount']),
      createdAt: _date(data['createdAt']),
      expenseDate: _dateOrNull(data['expenseDate']),
      vendorName: (data['vendorName'] ?? '').toString(),
      remarks: (data['remarks'] ?? data['note'] ?? '').toString(),
      billUploadPath: (data['billUploadPath'] ?? '').toString(),
      photoPath: (data['photoPath'] ?? '').toString(),
      addedBy: (data['addedBy'] ?? data['createdBy'] ?? 'System').toString(),
      updatedAt: _dateOrNull(data['updatedAt']),
      updatedBy: (data['updatedBy'] ?? '').toString(),
      deletedAt: _dateOrNull(data['deletedAt']),
      deletedBy: (data['deletedBy'] ?? '').toString(),
      isDeleted: data['isDeleted'] == true,
      isApproved: data['isApproved'] == true,
    );
  }

  CashAllocation _cashAllocationFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return CashAllocation(
      id: doc.id,
      supervisorName: (data['supervisorName'] ?? '').toString(),
      amount: _num(data['amount']),
      remarks: (data['remarks'] ?? '').toString(),
      createdBy: (data['createdBy'] ?? 'Owner').toString(),
      createdAt: _date(data['createdAt']),
      allocationDate: _dateOrNull(data['allocationDate']),
      paymentMode: (data['paymentMode'] ?? 'Cash').toString(),
      updatedAt: _dateOrNull(data['updatedAt']),
      updatedBy: (data['updatedBy'] ?? '').toString(),
    );
  }

  OpeningStockRecord _openingStockFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return OpeningStockRecord(
      id: doc.id,
      materialId: (data['materialId'] ?? '').toString(),
      materialName: (data['materialName'] ?? '').toString(),
      openingWeightKg: _num(data['openingWeightKg']),
      openingRate: _num(data['openingRate']),
      openingValue: _num(data['openingValue']),
      date: _date(data['date']),
      remarks: (data['remarks'] ?? '').toString(),
      createdBy: (data['createdBy'] ?? 'Owner').toString(),
      createdAt: _date(data['createdAt']),
      updatedBy: (data['updatedBy'] ?? '').toString(),
      updatedAt: _dateOrNull(data['updatedAt']),
    );
  }

  PhysicalStockRecord _physicalStockFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return PhysicalStockRecord(
      id: doc.id,
      materialId: (data['materialId'] ?? '').toString(),
      materialName: (data['materialName'] ?? '').toString(),
      quantityKg: _num(data['quantityKg']),
      entryDate: _date(data['entryDate']),
      reason: (data['reason'] ?? '').toString(),
      createdBy: (data['createdBy'] ?? 'Owner').toString(),
      createdAt: _date(data['createdAt']),
    );
  }

  StockReminderReceiver _stockReminderReceiverFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawTypes = data['reminderTypes'];
    final types = rawTypes is List
        ? rawTypes.map(_stockReminderType).toSet().toList()
        : <StockReminderType>[_stockReminderType(data['reminderType'])];
    return StockReminderReceiver(
      id: doc.id,
      receiverName: (data['receiverName'] ?? '').toString(),
      role: _stockReminderRole(data['role']),
      whatsAppNumber: (data['whatsAppNumber'] ?? '').toString(),
      isActive: data['isActive'] != false,
      reminderHour: _num(data['reminderHour']).toInt().clamp(0, 23).toInt(),
      reminderMinute: _num(data['reminderMinute']).toInt().clamp(0, 59).toInt(),
      reminderTypes: types.isEmpty ? const [StockReminderType.all] : types,
      createdAt: _date(data['createdAt']),
      updatedAt: _dateOrNull(data['updatedAt']),
    );
  }

  ManualReminderLog _manualReminderLogFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ManualReminderLog(
      reminderId: doc.id,
      receiverName: (data['receiverName'] ?? '').toString(),
      receiverNumber: (data['receiverNumber'] ?? '').toString(),
      role: _stockReminderRole(data['role']),
      messageType: _stockReminderType(data['messageType']),
      messageContent: (data['messageContent'] ?? '').toString(),
      status: _manualReminderStatus(data['status']),
      openedAt: _dateOrNull(data['openedAt']),
      copiedAt: _dateOrNull(data['copiedAt']),
      createdAt: _date(data['createdAt']),
    );
  }

  AuditEntry _auditFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return AuditEntry(
      id: doc.id,
      action: (data['action'] ?? '').toString(),
      recordType: (data['recordType'] ?? '').toString(),
      recordId: (data['recordId'] ?? '').toString(),
      field: (data['field'] ?? '').toString(),
      oldValue: (data['oldValue'] ?? '').toString(),
      newValue: (data['newValue'] ?? '').toString(),
      user: (data['user'] ?? 'System').toString(),
      role: _role(data['role']),
      createdAt: _date(data['createdAt']),
      deviceInfo: (data['deviceInfo'] ?? '').toString(),
    );
  }

  ActivityRecord _activityFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ActivityRecord(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      subtitle: (data['subtitle'] ?? '').toString(),
      userName: (data['userName'] ?? 'System').toString(),
      createdAt: _date(data['createdAt']),
    );
  }

  Map<String, dynamic> _partyToMap(Party party) {
    return {
      'name': party.name,
      'mobile': party.mobile,
      'area': party.area,
      'address': party.address,
      'remarks': party.remarks,
      'photoPath': party.photoPath,
      'pendingAmount': party.pendingAmount,
      'lastPurchaseAt': _timestampOrNull(party.lastPurchaseAt),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _materialToMap(MaterialStock material) {
    return {
      'name': material.name,
      'category': material.category,
      'availableKg': material.availableKg,
      'currentBuyingRate': material.currentBuyingRate,
      'currentSellingRate': material.currentSellingRate,
      'wastageDeductionPercent': material.normalizedWastageDeductionPercent,
      'isActive': material.isActive,
      'photoPath': material.photoPath,
      'stockValue': material.stockValue,
      'createdBy': material.createdBy,
      'updatedBy': material.updatedBy,
      'deletedBy': material.deletedBy,
      'isDeleted': material.isDeleted,
      'createdAt':
          _timestampOrNull(material.createdAt) ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': _timestampOrNull(material.deletedAt),
    };
  }

  Map<String, dynamic> _purchaseToMap(PurchaseRecord purchase) {
    return {
      'invoiceNumber': purchase.invoiceNumber,
      'sellerId': purchase.seller.id,
      'sellerName': purchase.seller.name,
      'sellerMobile': purchase.seller.mobile,
      'sellerArea': purchase.seller.area,
      'sellerAddress': purchase.seller.address,
      'sellerRemarks': purchase.seller.remarks,
      'sellerPhotoPath': purchase.seller.photoPath,
      'sellerPendingAmount': purchase.seller.pendingAmount,
      'sellerLastPurchaseAt': _timestampOrNull(purchase.seller.lastPurchaseAt),
      'items': purchase.items.map(_lineItemToMap).toList(),
      'materialId': purchase.item.materialId,
      'materialName': purchase.item.materialName,
      'weightKg': purchase.item.weightKg,
      'actualWeight': purchase.item.actualWeight,
      'wastageDeductionPercent': purchase.item.wastageDeductionPercent,
      'effectiveWeight': purchase.item.effectiveWeight,
      'rate': purchase.item.rate,
      'ratePerKg': purchase.item.rate,
      'lineAmount': purchase.item.componentFinalAmount,
      'originalBillAmount': purchase.originalBillAmount,
      'previousBalanceAppliedAmount': purchase.previousBalanceAppliedAmount,
      'previousBalanceReferenceIds': purchase.previousBalanceReferenceIds,
      'currentSettlementAdjustmentAmount':
          purchase.currentSettlementAdjustmentAmount,
      'finalBillAmount': purchase.finalBillAmount,
      'totalAmount': purchase.totalAmount,
      'paidAmount': purchase.paidAmount,
      'balanceAmount': purchase.balanceAmount,
      'paymentStatus': purchase.paymentStatus,
      'settlementStatus': purchase.settlementStatus,
      'remarks': purchase.remarks,
      'isDeleted': purchase.isDeleted,
      'createdBy': purchase.createdBy,
      'updatedBy': purchase.updatedBy,
      'deletedBy': purchase.deletedBy,
      'createdAt': Timestamp.fromDate(purchase.createdAt),
      'updatedAt': _timestampOrNull(purchase.updatedAt),
      'deletedAt': _timestampOrNull(purchase.deletedAt),
    };
  }

  Map<String, dynamic> _saleToMap(SaleRecord sale) {
    return {
      'invoiceNumber': sale.invoiceNumber,
      'customerId': sale.customer.id,
      'customerName': sale.customer.name,
      'customerMobile': sale.customer.mobile,
      'customerArea': sale.customer.area,
      'customerAddress': sale.customer.address,
      'customerRemarks': sale.customer.remarks,
      'customerPhotoPath': sale.customer.photoPath,
      'customerPendingAmount': sale.customer.pendingAmount,
      'items': sale.items.map(_lineItemToMap).toList(),
      'materialId': sale.item.materialId,
      'materialName': sale.item.materialName,
      'weightKg': sale.item.weightKg,
      'rate': sale.item.rate,
      'totalWeight': sale.totalWeightKg,
      'totalWeightKg': sale.totalWeightKg,
      'totalAmount': sale.totalAmount,
      'paidAmount': sale.receivedAmount,
      'receivedAmount': sale.receivedAmount,
      'balanceAmount': sale.balanceAmount,
      'remarks': sale.remarks,
      'isDeleted': sale.isDeleted,
      'createdBy': sale.createdBy,
      'updatedBy': sale.updatedBy,
      'deletedBy': sale.deletedBy,
      'reminderSentAt': _timestampOrNull(sale.reminderSentAt),
      'reminderSentBy': sale.reminderSentBy,
      'paymentReceivedAt': _timestampOrNull(sale.paymentReceivedAt),
      'paymentReceivedBy': sale.paymentReceivedBy,
      'createdAt': Timestamp.fromDate(sale.createdAt),
      'updatedAt': _timestampOrNull(sale.updatedAt),
      'deletedAt': _timestampOrNull(sale.deletedAt),
    };
  }

  Map<String, dynamic> _lineItemToMap(LineItem item) {
    return {
      'materialId': item.materialId,
      'materialName': item.materialName,
      'materialPhotoPath': item.materialPhotoPath,
      'weightKg': item.weightKg,
      'actualWeight': item.actualWeight,
      'wastageDeductionPercent': item.wastageDeductionPercent,
      'effectiveWeight': item.effectiveWeight,
      'rate': item.rate,
      'ratePerKg': item.rate,
      'componentOriginalAmount': item.componentOriginalAmount,
      'componentPreviousBalanceAdjustmentAmount':
          item.componentPreviousBalanceAdjustmentAmount,
      'componentSettlementAdjustmentAmount':
          item.componentSettlementAdjustmentAmount,
      'componentFinalAmount': item.componentFinalAmount,
      'lineAmount': item.componentFinalAmount,
      'amount': item.componentFinalAmount,
    };
  }

  Map<String, dynamic> _openingStockToMap(OpeningStockRecord record) {
    return {
      'materialId': record.materialId,
      'materialName': record.materialName,
      'openingWeightKg': record.openingWeightKg,
      'openingRate': record.openingRate,
      'openingValue': record.openingValue,
      'date': Timestamp.fromDate(record.date),
      'remarks': record.remarks,
      'createdBy': record.createdBy,
      'createdAt': Timestamp.fromDate(record.createdAt),
      'updatedBy': record.updatedBy,
      'updatedAt': _timestampOrNull(record.updatedAt),
    };
  }

  Map<String, dynamic> _physicalStockToMap(PhysicalStockRecord record) {
    return {
      'materialId': record.materialId,
      'materialName': record.materialName,
      'quantityKg': record.quantityKg,
      'entryDate': Timestamp.fromDate(record.entryDate),
      'reason': record.reason,
      'createdBy': record.createdBy,
      'createdAt': Timestamp.fromDate(record.createdAt),
    };
  }

  Map<String, dynamic> _stockReminderReceiverToMap(
    StockReminderReceiver receiver,
  ) {
    return {
      'receiverName': receiver.receiverName,
      'role': receiver.role.name,
      'whatsAppNumber': receiver.whatsAppNumber,
      'isActive': receiver.isActive,
      'reminderHour': receiver.reminderHour,
      'reminderMinute': receiver.reminderMinute,
      'reminderTime': receiver.timeKey,
      'reminderTypes': receiver.reminderTypes.map((item) => item.name).toList(),
      'createdAt': Timestamp.fromDate(receiver.createdAt),
      'updatedAt': _timestampOrNull(receiver.updatedAt),
    };
  }

  Map<String, dynamic> _manualReminderLogToMap(ManualReminderLog log) {
    return {
      'reminderId': log.reminderId,
      'receiverName': log.receiverName,
      'receiverNumber': log.receiverNumber,
      'role': log.role.name,
      'messageType': log.messageType.name,
      'messageContent': log.messageContent,
      'status': log.status.name,
      'openedAt': _timestampOrNull(log.openedAt),
      'copiedAt': _timestampOrNull(log.copiedAt),
      'createdAt': Timestamp.fromDate(log.createdAt),
    };
  }

  List<LineItem> _lineItemsFromData(Map<String, dynamic> data) {
    final rawItems = data['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      return rawItems
          .whereType<Map>()
          .map(
            (item) => LineItem(
              materialId: (item['materialId'] ?? '').toString(),
              materialName: (item['materialName'] ?? '').toString(),
              materialPhotoPath: (item['materialPhotoPath'] ?? '').toString(),
              weightKg: _num(item['actualWeight'] ?? item['weightKg']),
              wastageDeductionPercent: _percent(
                item['wastageDeductionPercent'],
              ),
              effectiveWeight: _num(
                item['effectiveWeight'] ?? item['weightKg'],
              ),
              rate: _num(item['ratePerKg'] ?? item['rate']),
              componentOriginalAmount: _numOrNull(
                item['componentOriginalAmount'] ?? item['lineAmount'],
              ),
              componentPreviousBalanceAdjustmentAmount: _num(
                item['componentPreviousBalanceAdjustmentAmount'],
              ),
              componentSettlementAdjustmentAmount: _num(
                item['componentSettlementAdjustmentAmount'],
              ),
              componentFinalAmount: _numOrNull(
                item['componentFinalAmount'] ?? item['amount'],
              ),
            ),
          )
          .toList();
    }
    return [
      LineItem(
        materialId: (data['materialId'] ?? '').toString(),
        materialName: (data['materialName'] ?? '').toString(),
        weightKg: _num(data['actualWeight'] ?? data['weightKg']),
        wastageDeductionPercent: _percent(data['wastageDeductionPercent']),
        effectiveWeight: _num(data['effectiveWeight'] ?? data['weightKg']),
        rate: _num(data['ratePerKg'] ?? data['rate']),
        componentOriginalAmount: _numOrNull(
          data['componentOriginalAmount'] ??
              data['lineAmount'] ??
              data['totalAmount'],
        ),
        componentPreviousBalanceAdjustmentAmount: _num(
          data['componentPreviousBalanceAdjustmentAmount'],
        ),
        componentSettlementAdjustmentAmount: _num(
          data['componentSettlementAdjustmentAmount'],
        ),
        componentFinalAmount: _numOrNull(
          data['componentFinalAmount'] ?? data['lineAmount'],
        ),
      ),
    ];
  }

  Object? _timestampOrNull(DateTime? value) {
    return value == null ? null : Timestamp.fromDate(value);
  }

  double _num(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _numOrNull(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const [];
  }

  double _percent(Object? value) => _num(value).clamp(0, 100).toDouble();

  StockReminderRole _stockReminderRole(Object? value) {
    final key = value?.toString().trim();
    return StockReminderRole.values.firstWhere(
      (item) => item.name == key,
      orElse: () => StockReminderRole.supervisor,
    );
  }

  StockReminderType _stockReminderType(Object? value) {
    final key = value?.toString().trim();
    return StockReminderType.values.firstWhere(
      (item) => item.name == key,
      orElse: () => StockReminderType.all,
    );
  }

  ManualReminderStatus _manualReminderStatus(Object? value) {
    final key = value?.toString().trim();
    return ManualReminderStatus.values.firstWhere(
      (item) => item.name == key,
      orElse: () => ManualReminderStatus.pendingManualSend,
    );
  }

  DateTime _date(Object? value) {
    return _dateOrNull(value) ?? DateTime.now();
  }

  DateTime? _dateOrNull(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse(value?.toString() ?? '');
  }

  UserRole _role(Object? value) {
    final text = value?.toString();
    return UserRole.values.firstWhere(
      (role) => role.name == text,
      orElse: () => UserRole.user,
    );
  }
}

const _ownerNotificationActions = {
  'purchase_created',
  'material_updated',
  'manual_stock_reminder_scheduled',
  'manual_stock_reminder_updated',
};

String _notificationTitle(String action) {
  switch (action) {
    case 'purchase_created':
      return 'Purchase created';
    case 'material_updated':
      return 'Material edited';
    case 'manual_stock_reminder_scheduled':
      return 'Stock reminder scheduled';
    case 'manual_stock_reminder_updated':
      return 'Stock reminder updated';
    default:
      return 'Activity update';
  }
}
