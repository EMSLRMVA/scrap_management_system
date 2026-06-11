import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_branding.dart';
import '../core/money_format.dart';
import '../data/firebase/firestore_business_service.dart';
import '../domain/business_models.dart';
import '../domain/stock_calculation.dart';

final businessProvider = NotifierProvider<BusinessController, BusinessState>(
  BusinessController.new,
);

class BusinessController extends Notifier<BusinessState> {
  static const recycleBinRetention = Duration(days: 30);
  static const editDeleteWindow = Duration(hours: 1);

  final _firestore = FirestoreBusinessService();
  final _subscriptions = <StreamSubscription<Object?>>[];

  @override
  BusinessState build() {
    ref.onDispose(() {
      for (final subscription in _subscriptions) {
        subscription.cancel();
      }
      _subscriptions.clear();
    });

    if (_firestore.isAvailable) {
      Future.microtask(_startFirestoreRealtime);
    }
    Future.microtask(purgeExpiredRecycleBin);

    return BusinessState.empty();
  }

  void setAuthenticatedUser({
    required String name,
    required String email,
    String mobile = '',
    required UserRole role,
  }) {
    state = state.copyWith(
      user: AppUser(
        name: name,
        mobile: mobile,
        email: email,
        company: appDisplayName,
        role: role,
      ),
    );
    recordSecurityEvent(
      '${role.name} login',
      '$name authenticated with email/password',
    );
  }

  void recordSecurityEvent(String action, String detail) {
    _activity(action, detail);
    _audit(
      action,
      'security',
      state.user.email.isEmpty ? state.user.mobile : state.user.email,
      {
        'Detail': ['', detail],
      },
    );
  }

  Party addParty({
    required String name,
    required String mobile,
    required PartyKind kind,
    String area = '',
    String address = '',
    String remarks = '',
    String photoPath = '',
  }) {
    final party = Party(
      id: _id(kind.name),
      name: name.trim(),
      mobile: mobile.trim(),
      area: area.trim(),
      address: address.trim(),
      remarks: remarks.trim(),
      photoPath: photoPath,
      kind: kind,
    );

    state = kind == PartyKind.seller
        ? state.copyWith(sellers: [party, ...state.sellers])
        : state.copyWith(customers: [party, ...state.customers]);
    _activity(
      '${kind == PartyKind.seller ? 'Seller' : 'Customer'} added',
      party.name,
    );
    _audit('${kind.name} created', kind.name, party.id, {
      'Summary': ['', '${party.name} ${party.mobile}'],
    });
    _appActivityLog(
      action: kind == PartyKind.seller ? 'seller_added' : 'customer_added',
      screen: kind == PartyKind.seller ? 'Sellers' : 'Customers',
      details: '${party.name} ${party.mobile}',
    );
    _safeSync(() => _firestore.saveParty(party));
    _syncDashboard();
    return party;
  }

  void updateParty(Party party) {
    state = party.kind == PartyKind.seller
        ? state.copyWith(
            sellers: state.sellers
                .map((item) => item.id == party.id ? party : item)
                .toList(),
          )
        : state.copyWith(
            customers: state.customers
                .map((item) => item.id == party.id ? party : item)
                .toList(),
          );
    _activity('Party edited', party.name);
    _audit('${party.kind.name} edited', party.kind.name, party.id, {
      'Name': ['', party.name],
      'Mobile': ['', party.mobile],
      'Area': ['', party.area],
    });
    _appActivityLog(
      action: party.kind == PartyKind.seller
          ? 'seller_updated'
          : 'customer_updated',
      screen: party.kind == PartyKind.seller ? 'Sellers' : 'Customers',
      details: '${party.name} ${party.mobile}',
    );
    _safeSync(() => _firestore.saveParty(party));
    _syncDashboard();
  }

  void deleteParty(String id, PartyKind kind) {
    state = kind == PartyKind.seller
        ? state.copyWith(
            sellers: state.sellers.where((item) => item.id != id).toList(),
          )
        : state.copyWith(
            customers: state.customers.where((item) => item.id != id).toList(),
          );
    _activity('Party removed', kind.name);
    _safeSync(() => _firestore.deleteParty(id, kind));
    _syncDashboard();
  }

  MaterialStock addMaterial({
    required String name,
    required String category,
    required double rate,
    String photoPath = '',
    double currentSellingRate = 0,
    double wastageDeductionPercent = 0,
    bool isActive = true,
  }) {
    final material = MaterialStock(
      id: _id('mat'),
      name: name.trim(),
      category: category.trim().isEmpty ? 'General' : category.trim(),
      availableKg: 0,
      currentBuyingRate: rate,
      photoPath: photoPath,
      currentSellingRate: currentSellingRate,
      wastageDeductionPercent: wastageDeductionPercent.clamp(0, 100).toDouble(),
      isActive: isActive,
      createdAt: DateTime.now(),
      createdBy: state.user.name,
    );
    state = state.copyWith(materials: [material, ...state.materials]);
    _activity('Material added', material.name);
    _audit('Material created', 'inventory', material.id, {
      'Summary': ['', '${material.name} ${money(material.currentBuyingRate)}'],
    });
    _appActivityLog(
      action: 'material_added',
      screen: 'Inventory',
      details: material.name,
    );
    _safeSync(() => _firestore.saveMaterial(material));
    _syncDashboard();
    return material;
  }

  void updateMaterial(MaterialStock material) {
    if (_blockEditIfNeeded(
      moduleName: 'Inventory',
      entryId: material.id,
      entryLabel: material.name,
      createdAt: _entryCreatedAt(material.createdAt),
    )) {
      return;
    }
    final original = state.materials.firstWhere(
      (item) => item.id == material.id,
      orElse: () => material,
    );
    final updated = material.copyWith(
      updatedAt: DateTime.now(),
      updatedBy: state.user.name,
    );
    state = state.copyWith(
      materials: state.materials
          .map((item) => item.id == material.id ? updated : item)
          .toList(),
    );
    _activity('Material edited', updated.name);
    _audit('Material edited', 'inventory', updated.id, {
      'Name': [original.name, updated.name],
      'Category': [original.category, updated.category],
      'Current Buying Rate': [
        money(original.currentBuyingRate),
        money(updated.currentBuyingRate),
      ],
      'Selling Rate': [
        money(original.currentSellingRate),
        money(updated.currentSellingRate),
      ],
      'Wastage Deduction': [
        '${original.normalizedWastageDeductionPercent.toStringAsFixed(2)}%',
        '${updated.normalizedWastageDeductionPercent.toStringAsFixed(2)}%',
      ],
      'Active': [
        original.isActive ? 'Yes' : 'No',
        updated.isActive ? 'Yes' : 'No',
      ],
    });
    _appActivityLog(
      action: 'material_updated',
      screen: 'Inventory',
      details:
          '${updated.name}: deduction ${original.normalizedWastageDeductionPercent.toStringAsFixed(2)}% to ${updated.normalizedWastageDeductionPercent.toStringAsFixed(2)}%',
    );
    _safeSync(() => _firestore.saveMaterial(updated));
    _syncDashboard();
  }

  void deleteMaterial(MaterialStock material) {
    if (material.isDeleted) {
      return;
    }
    if (_blockDeleteIfNeeded(
      moduleName: 'Inventory',
      entryId: material.id,
      entryLabel: material.name,
      createdAt: _entryCreatedAt(material.createdAt),
    )) {
      return;
    }
    final deleted = material.copyWith(
      isDeleted: true,
      isActive: false,
      deletedAt: DateTime.now(),
      deletedBy: state.user.name,
      updatedAt: DateTime.now(),
      updatedBy: state.user.name,
    );
    state = state.copyWith(
      materials: state.materials
          .map((item) => item.id == material.id ? deleted : item)
          .toList(),
    );
    _activity('Material deleted', material.name);
    _audit('Material deleted', 'inventory', material.id, {
      'Deleted': ['No', 'Yes'],
      'Deleted By': ['', state.user.name],
    });
    _safeSync(() => _firestore.saveMaterial(deleted));
    _syncDashboard();
  }

  void adjustMaterialStock({
    required MaterialStock material,
    required double availableKg,
    required String reason,
    DateTime? entryDate,
  }) {
    final now = DateTime.now();
    final normalizedKg = availableKg.clamp(0, double.infinity).toDouble();
    final record = PhysicalStockRecord(
      id: _id('physical-stock'),
      materialId: material.id,
      materialName: material.name,
      quantityKg: normalizedKg,
      entryDate: entryDate ?? now,
      reason: reason.trim(),
      createdBy: state.user.name,
      createdAt: now,
    );
    final updated = material.copyWith(
      availableKg: normalizedKg,
      updatedAt: now,
      updatedBy: state.user.name,
    );
    state = state.copyWith(
      materials: state.materials
          .map((item) => item.id == material.id ? updated : item)
          .toList(),
      physicalStocks: [record, ...state.physicalStocks],
    );
    _activity(
      'Physical stock entered',
      '${updated.name} ${kg(updated.availableKg)}',
    );
    _audit('Physical stock entered', 'inventory', updated.id, {
      'Available KG': [kg(material.availableKg), kg(updated.availableKg)],
      'Reason': ['', reason.trim()],
      'Entry Date': ['', shortDate(record.entryDate)],
    });
    _safeSync(() => _firestore.savePhysicalStock(record, updated));
    _syncDashboard();
  }

  PurchaseRecord addPurchase({
    required Party seller,
    required List<LineItem> items,
    required double paidAmount,
    DateTime? purchaseDate,
    String? createdBy,
    String remarks = '',
    double previousBalanceAppliedAmount = 0,
    List<String> previousBalanceReferenceIds = const [],
    double currentSettlementAdjustmentAmount = 0,
    String settlementStatus = 'carry_forward',
  }) {
    final createdAt = purchaseDate ?? DateTime.now();
    final calculation = _calculatePurchaseAmounts(
      items: items,
      paidAmount: paidAmount,
      previousBalanceAppliedAmount: previousBalanceAppliedAmount,
      previousBalanceReferenceIds: previousBalanceReferenceIds,
      currentSettlementAdjustmentAmount: currentSettlementAdjustmentAmount,
      settlementStatus: settlementStatus,
    );
    final purchase = PurchaseRecord(
      id: _id('pur'),
      invoiceNumber: _nextInvoice('PUR', state.purchases.length, createdAt),
      seller: seller,
      items: calculation.items,
      paidAmount: calculation.paidAmount,
      originalBillAmount: calculation.originalBillAmount,
      previousBalanceAppliedAmount: calculation.previousBalanceAppliedAmount,
      previousBalanceReferenceIds: calculation.previousBalanceReferenceIds,
      currentSettlementAdjustmentAmount:
          calculation.currentSettlementAdjustmentAmount,
      finalBillAmount: calculation.finalBillAmount,
      balanceAmount: calculation.balanceAmount,
      paymentStatus: _purchasePaymentStatus(calculation.balanceAmount),
      settlementStatus: calculation.settlementStatus,
      remarks: remarks.trim(),
      createdAt: createdAt,
      createdBy: _effectiveEntryCreator(createdBy),
    );
    final updatedSeller = _partyWithBalance(
      state.sellers,
      seller,
      purchase.ledgerDelta,
      lastPurchaseAt: createdAt,
    );
    final sellers = _replaceParty(state.sellers, updatedSeller);
    final savedPurchase = purchase.copyWith(seller: updatedSeller);

    state = state.copyWith(
      sellers: sellers,
      purchases: [savedPurchase, ...state.purchases],
    );
    _activity(
      'Purchase Created',
      '${savedPurchase.invoiceNumber} ${seller.name} ${money(savedPurchase.totalAmount)}',
    );
    _audit('Purchase Created', 'purchase', savedPurchase.id, {
      'Invoice': ['', savedPurchase.invoiceNumber],
      'Seller': ['', savedPurchase.seller.name],
      'Items': ['', _itemsSummary(savedPurchase.items)],
      'Original Amount': ['', money(savedPurchase.originalBillAmount)],
      'Previous Balance Applied': [
        '',
        money(savedPurchase.previousBalanceAppliedAmount),
      ],
      'Settlement Adjustment': [
        '',
        money(savedPurchase.currentSettlementAdjustmentAmount),
      ],
      'Final Amount': ['', money(savedPurchase.finalBillAmount)],
      'Purchase Date': ['', shortDate(savedPurchase.createdAt)],
      'Purchase Added By': ['', savedPurchase.createdBy],
    });
    _appActivityLog(
      action: 'purchase_created',
      screen: 'Purchase',
      details:
          '${savedPurchase.invoiceNumber} ${savedPurchase.seller.name} ${money(savedPurchase.totalAmount)}',
    );
    _safeSync(() => _firestore.savePurchase(savedPurchase, updatedSeller));
    _syncDashboard();
    return savedPurchase;
  }

  PurchaseRecord editPurchase({
    required PurchaseRecord original,
    required Party seller,
    required List<LineItem> items,
    required double paidAmount,
    DateTime? purchaseDate,
    String? createdBy,
    String remarks = '',
    double? originalBillAmount,
    double previousBalanceAppliedAmount = 0,
    List<String> previousBalanceReferenceIds = const [],
    double currentSettlementAdjustmentAmount = 0,
    String settlementStatus = 'carry_forward',
  }) {
    if (_blockEditIfNeeded(
      moduleName: 'Purchase',
      entryId: original.id,
      entryLabel: original.invoiceNumber,
      createdAt: original.createdAt,
    )) {
      return original;
    }
    var sellers = state.sellers;
    sellers = _replaceParty(
      sellers,
      _partyWithBalance(sellers, original.seller, -original.ledgerDelta),
    );
    final calculation = _calculatePurchaseAmounts(
      items: items,
      paidAmount: paidAmount,
      originalBillAmount: originalBillAmount,
      previousBalanceAppliedAmount: previousBalanceAppliedAmount,
      previousBalanceReferenceIds: previousBalanceReferenceIds,
      currentSettlementAdjustmentAmount: currentSettlementAdjustmentAmount,
      settlementStatus: settlementStatus,
    );
    final updatedSeller = _partyWithBalance(
      sellers,
      seller,
      calculation.ledgerDelta,
    );
    sellers = _replaceParty(sellers, updatedSeller);
    final updated = original.copyWith(
      seller: updatedSeller,
      items: calculation.items,
      paidAmount: calculation.paidAmount,
      originalBillAmount: calculation.originalBillAmount,
      previousBalanceAppliedAmount: calculation.previousBalanceAppliedAmount,
      previousBalanceReferenceIds: calculation.previousBalanceReferenceIds,
      currentSettlementAdjustmentAmount:
          calculation.currentSettlementAdjustmentAmount,
      finalBillAmount: calculation.finalBillAmount,
      balanceAmount: calculation.balanceAmount,
      paymentStatus: _purchasePaymentStatus(calculation.balanceAmount),
      settlementStatus: calculation.settlementStatus,
      createdAt: purchaseDate ?? original.createdAt,
      createdBy: _effectiveEntryCreator(createdBy ?? original.createdBy),
      remarks: remarks.trim(),
      updatedAt: DateTime.now(),
      updatedBy: state.user.name,
    );

    state = state.copyWith(
      sellers: sellers,
      purchases: state.purchases
          .map((item) => item.id == original.id ? updated : item)
          .toList(),
    );
    _activity(
      'Purchase Edited',
      '${updated.invoiceNumber} ${money(updated.totalAmount)}',
    );
    _audit('Purchase Edited', 'purchase', updated.id, {
      'Seller': [original.seller.name, updated.seller.name],
      'Items': [_itemsSummary(original.items), _itemsSummary(updated.items)],
      'Paid Amount': [money(original.paidAmount), money(updated.paidAmount)],
      'Original Bill Amount': [
        money(original.originalBillAmount),
        money(updated.originalBillAmount),
      ],
      'Previous Balance Applied': [
        money(original.previousBalanceAppliedAmount),
        money(updated.previousBalanceAppliedAmount),
      ],
      'Settlement Adjustment': [
        money(original.currentSettlementAdjustmentAmount),
        money(updated.currentSettlementAdjustmentAmount),
      ],
      'Final Bill Amount': [
        money(original.finalBillAmount),
        money(updated.finalBillAmount),
      ],
      'Purchase Date': [
        shortDate(original.createdAt),
        shortDate(updated.createdAt),
      ],
      'Purchase Added By': [original.createdBy, updated.createdBy],
      'Remarks': [original.remarks, updated.remarks],
    });
    _recordAdminOverrideIfNeeded(
      moduleName: 'Purchase',
      entryId: updated.id,
      entryLabel: updated.invoiceNumber,
      createdAt: original.createdAt,
      action: 'ADMIN_OVERRIDE_EDIT',
      reason: 'Owner/Admin edited after 1 hour',
    );
    _appActivityLog(
      action: 'purchase_updated',
      screen: 'Purchase',
      details: '${updated.invoiceNumber} ${money(updated.totalAmount)}',
    );
    _safeSync(() => _firestore.savePurchase(updated, updatedSeller));
    _syncDashboard();
    return updated;
  }

  void softDeletePurchase(PurchaseRecord purchase) {
    if (purchase.isDeleted) {
      return;
    }
    if (_blockDeleteIfNeeded(
      moduleName: 'Purchase',
      entryId: purchase.id,
      entryLabel: purchase.invoiceNumber,
      createdAt: purchase.createdAt,
    )) {
      return;
    }
    final deleted = purchase.copyWith(
      isDeleted: true,
      deletedAt: DateTime.now(),
      deletedBy: state.user.name,
    );
    final seller = _partyWithBalance(
      state.sellers,
      purchase.seller,
      -purchase.ledgerDelta,
    );
    final sellers = _replaceParty(state.sellers, seller);

    state = state.copyWith(
      sellers: sellers,
      purchases: state.purchases
          .map((item) => item.id == purchase.id ? deleted : item)
          .toList(),
    );
    _activity('Purchase Moved to Recycle Bin', purchase.invoiceNumber);
    _audit('Purchase Moved to Recycle Bin', 'purchase', purchase.id, {
      'Deleted': ['No', 'Yes'],
      'Amount': [money(purchase.totalAmount), money(0)],
    });
    _recordAdminOverrideIfNeeded(
      moduleName: 'Purchase',
      entryId: purchase.id,
      entryLabel: purchase.invoiceNumber,
      createdAt: purchase.createdAt,
      action: 'ADMIN_OVERRIDE_DELETE',
      reason: 'Owner/Admin deleted after 1 hour',
    );
    _safeSync(() => _firestore.savePurchase(deleted, seller));
    _syncDashboard();
  }

  void restorePurchase(PurchaseRecord purchase) {
    if (!purchase.isDeleted) {
      return;
    }
    if (isRecycleBinExpired(purchase.deletedAt)) {
      purgeExpiredRecycleBin();
      return;
    }
    final restored = purchase.copyWith(
      isDeleted: false,
      clearDeletedAt: true,
      clearDeletedBy: true,
      updatedAt: DateTime.now(),
      updatedBy: state.user.name,
    );
    final seller = _partyWithBalance(
      state.sellers,
      purchase.seller,
      purchase.ledgerDelta,
      lastPurchaseAt: DateTime.now(),
    );
    state = state.copyWith(
      sellers: _replaceParty(state.sellers, seller),
      purchases: state.purchases
          .map(
            (item) => item.id == purchase.id
                ? restored.copyWith(seller: seller)
                : item,
          )
          .toList(),
    );
    _activity('Purchase Restored', purchase.invoiceNumber);
    _audit('Purchase Restored', 'purchase', purchase.id, {
      'Deleted': ['Yes', 'No'],
    });
    _safeSync(
      () => _firestore.savePurchase(restored.copyWith(seller: seller), seller),
    );
    _syncDashboard();
  }

  SaleRecord addSale({
    required Party customer,
    required MaterialStock material,
    required double weightKg,
    required double rate,
    required double receivedAmount,
    String remarks = '',
  }) {
    final item = LineItem(
      materialId: material.id,
      materialName: material.name,
      materialPhotoPath: material.photoPath,
      weightKg: weightKg,
      rate: rate,
    );
    return addSaleItems(
      customer: customer,
      items: [item],
      receivedAmount: receivedAmount,
      remarks: remarks,
    );
  }

  SaleRecord addSaleItems({
    required Party customer,
    required List<LineItem> items,
    required double receivedAmount,
    DateTime? saleDate,
    String? createdBy,
    String remarks = '',
  }) {
    final createdAt = saleDate ?? DateTime.now();
    final sale = SaleRecord(
      id: _id('sale'),
      invoiceNumber: _nextInvoice('SALE', state.sales.length, createdAt),
      customer: customer,
      items: items,
      receivedAmount: receivedAmount,
      remarks: remarks.trim(),
      createdAt: createdAt,
      createdBy: _effectiveEntryCreator(createdBy),
    );
    final updatedCustomer = _partyWithBalance(
      state.customers,
      customer,
      sale.balanceAmount,
    );
    final customers = _replaceParty(state.customers, updatedCustomer);
    final savedSale = sale.copyWith(customer: updatedCustomer);

    state = state.copyWith(
      customers: customers,
      sales: [savedSale, ...state.sales],
    );
    _activity(
      'Sale Created',
      '${savedSale.invoiceNumber} ${customer.name} ${money(savedSale.totalAmount)}',
    );
    _audit('Sale Created', 'sale', savedSale.id, {
      'Invoice': ['', savedSale.invoiceNumber],
      'Customer': ['', savedSale.customer.name],
      'Items': ['', _itemsSummary(savedSale.items)],
      'Amount': ['', money(savedSale.totalAmount)],
      'Sale Date': ['', shortDate(savedSale.createdAt)],
      'Sale Added By': ['', savedSale.createdBy],
    });
    _appActivityLog(
      action: 'sale_created',
      screen: 'Sales',
      details:
          '${savedSale.invoiceNumber} ${savedSale.customer.name} ${money(savedSale.totalAmount)}',
    );
    _safeSync(() => _firestore.saveSale(savedSale, updatedCustomer));
    _syncDashboard();
    return savedSale;
  }

  SaleRecord editSale({
    required SaleRecord original,
    required Party customer,
    required List<LineItem> items,
    required double receivedAmount,
    DateTime? saleDate,
    String? createdBy,
    String remarks = '',
  }) {
    if (_blockEditIfNeeded(
      moduleName: 'Sales',
      entryId: original.id,
      entryLabel: original.invoiceNumber,
      createdAt: original.createdAt,
    )) {
      return original;
    }
    var customers = state.customers;
    customers = _replaceParty(
      customers,
      _partyWithBalance(customers, original.customer, -original.balanceAmount),
    );
    final updatedCustomer = _partyWithBalance(
      customers,
      customer,
      items.fold<double>(0, (sum, item) => sum + item.amount) - receivedAmount,
    );
    customers = _replaceParty(customers, updatedCustomer);
    final updated = original.copyWith(
      customer: updatedCustomer,
      items: items,
      receivedAmount: receivedAmount,
      createdAt: saleDate ?? original.createdAt,
      createdBy: _effectiveEntryCreator(createdBy ?? original.createdBy),
      remarks: remarks.trim(),
      updatedAt: DateTime.now(),
      updatedBy: state.user.name,
    );

    state = state.copyWith(
      customers: customers,
      sales: state.sales
          .map((item) => item.id == original.id ? updated : item)
          .toList(),
    );
    _activity(
      'Sale Edited',
      '${updated.invoiceNumber} ${money(updated.totalAmount)}',
    );
    _audit('Sale Edited', 'sale', updated.id, {
      'Customer': [original.customer.name, updated.customer.name],
      'Items': [_itemsSummary(original.items), _itemsSummary(updated.items)],
      'Paid Amount': [
        money(original.receivedAmount),
        money(updated.receivedAmount),
      ],
      'Invoice Amount': [
        money(original.totalAmount),
        money(updated.totalAmount),
      ],
      'Sale Date': [
        shortDate(original.createdAt),
        shortDate(updated.createdAt),
      ],
      'Sale Added By': [original.createdBy, updated.createdBy],
      'Remarks': [original.remarks, updated.remarks],
    });
    _recordAdminOverrideIfNeeded(
      moduleName: 'Sales',
      entryId: updated.id,
      entryLabel: updated.invoiceNumber,
      createdAt: original.createdAt,
      action: 'ADMIN_OVERRIDE_EDIT',
      reason: 'Owner/Admin edited after 1 hour',
    );
    _appActivityLog(
      action: 'sale_updated',
      screen: 'Sales',
      details:
          '${updated.invoiceNumber} ${updated.customer.name} ${money(updated.totalAmount)}',
    );
    _safeSync(() => _firestore.saveSale(updated, updatedCustomer));
    _syncDashboard();
    return updated;
  }

  void softDeleteSale(SaleRecord sale) {
    if (sale.isDeleted) {
      return;
    }
    if (!canModifySale(sale)) {
      _activity(
        'Sale delete blocked',
        'Only Owner/Admin or Manager can delete sales within the allowed time.',
      );
      return;
    }
    if (_blockDeleteIfNeeded(
      moduleName: 'Sales',
      entryId: sale.id,
      entryLabel: sale.invoiceNumber,
      createdAt: sale.createdAt,
    )) {
      return;
    }
    final deleted = sale.copyWith(
      isDeleted: true,
      deletedAt: DateTime.now(),
      deletedBy: state.user.name,
    );
    final customer = _partyWithBalance(
      state.customers,
      sale.customer,
      -sale.balanceAmount,
    );
    final customers = _replaceParty(state.customers, customer);

    state = state.copyWith(
      customers: customers,
      sales: state.sales
          .map((item) => item.id == sale.id ? deleted : item)
          .toList(),
    );
    _activity('Sale Moved to Recycle Bin', sale.invoiceNumber);
    _audit('Sale Moved to Recycle Bin', 'sale', sale.id, {
      'Deleted': ['No', 'Yes'],
      'Amount': [money(sale.totalAmount), money(0)],
    });
    _recordAdminOverrideIfNeeded(
      moduleName: 'Sales',
      entryId: sale.id,
      entryLabel: sale.invoiceNumber,
      createdAt: sale.createdAt,
      action: 'ADMIN_OVERRIDE_DELETE',
      reason: 'Owner/Admin deleted after 1 hour',
    );
    _safeSync(() => _firestore.saveSale(deleted, customer));
    _syncDashboard();
  }

  void markSalePaymentReminderSent(
    SaleRecord sale, {
    required bool sentWithAmount,
  }) {
    final now = DateTime.now();
    final updated = sale.copyWith(
      reminderSentAt: now,
      reminderSentBy: state.user.name,
      updatedAt: now,
      updatedBy: state.user.name,
    );
    state = state.copyWith(
      sales: state.sales
          .map((item) => item.id == sale.id ? updated : item)
          .toList(),
    );
    _activity(
      sentWithAmount
          ? 'Owner payment reminder sent'
          : 'Manager payment reminder sent',
      '${sale.customer.name} | ${sale.invoiceNumber} | ${sentWithAmount ? money(sale.balanceAmount.clamp(0, double.infinity)) : 'amount hidden'}',
    );
    _audit('Payment Reminder Sent', 'sale', sale.id, {
      'Reminder Sent By': [sale.reminderSentBy, state.user.name],
      'Reminder Sent At': [
        sale.reminderSentAt == null ? '' : shortDate(sale.reminderSentAt!),
        shortDate(now),
      ],
      'Amount Shared': ['', sentWithAmount ? 'Yes' : 'No'],
    });
    _appActivityLog(
      action: sentWithAmount
          ? 'owner_payment_reminder_sent'
          : 'manager_payment_reminder_sent',
      screen: 'Sales Reminder',
      details:
          '${sale.customer.name} | ${sale.invoiceNumber} | by ${state.user.name}',
    );
    _safeSync(() => _firestore.saveSale(updated, updated.customer));
  }

  void markSalePaymentReceived(SaleRecord sale, {double? receivedAmount}) {
    if (!state.user.role.isOwnerOrAdmin) {
      _activity(
        'Payment update blocked',
        'Only Owner/Admin can mark sale payment received.',
      );
      return;
    }
    if (!sale.isPaymentPending) {
      return;
    }
    final now = DateTime.now();
    final previousBalance = sale.balanceAmount
        .clamp(0, double.infinity)
        .toDouble();
    final paymentNow = (receivedAmount ?? previousBalance)
        .clamp(0, previousBalance)
        .toDouble();
    if (paymentNow <= 0) {
      _activity(
        'Payment update blocked',
        'Enter payment amount greater than zero.',
      );
      return;
    }
    final updatedSale = sale.copyWith(
      receivedAmount: sale.receivedAmount + paymentNow,
      paymentReceivedAt: now,
      paymentReceivedBy: state.user.name,
      updatedAt: now,
      updatedBy: state.user.name,
    );
    final remainingPending = updatedSale.balanceAmount
        .clamp(0, double.infinity)
        .toDouble();
    final updatedCustomer = _partyWithBalance(
      state.customers,
      sale.customer,
      -paymentNow,
    );
    final savedSale = updatedSale.copyWith(customer: updatedCustomer);
    state = state.copyWith(
      customers: _replaceParty(state.customers, updatedCustomer),
      sales: state.sales
          .map((item) => item.id == sale.id ? savedSale : item)
          .toList(),
    );
    _activity(
      'Sale payment received',
      '${sale.customer.name} | ${sale.invoiceNumber} | ${money(paymentNow)} received',
    );
    _audit('Sale Payment Received', 'sale', sale.id, {
      'Paid Amount': [
        money(sale.receivedAmount),
        money(updatedSale.receivedAmount),
      ],
      'Received Now': ['', money(paymentNow)],
      'Pending': [money(previousBalance), money(remainingPending)],
      'Updated By': ['', state.user.name],
    });
    _appActivityLog(
      action: 'sale_payment_received',
      screen: 'Sales',
      details:
          '${sale.customer.name} | ${sale.invoiceNumber} | ${money(paymentNow)} received',
    );
    _safeSync(() => _firestore.saveSale(savedSale, updatedCustomer));
    _syncDashboard();
  }

  void undoSalePaymentReceived(SaleRecord originalSale) {
    if (!state.user.role.isOwnerOrAdmin) {
      _activity(
        'Payment undo blocked',
        'Only Owner/Admin can undo sale payment received.',
      );
      return;
    }
    SaleRecord? currentSale;
    for (final item in state.sales) {
      if (item.id == originalSale.id) {
        currentSale = item;
        break;
      }
    }
    if (currentSale == null) {
      return;
    }
    final now = DateTime.now();
    final receivedToUndo =
        (currentSale.receivedAmount - originalSale.receivedAmount)
            .clamp(0, double.infinity)
            .toDouble();
    if (receivedToUndo <= 0) {
      return;
    }
    final updatedCustomer = _partyWithBalance(
      state.customers,
      currentSale.customer,
      receivedToUndo,
    );
    final restoredSale = currentSale.copyWith(
      customer: updatedCustomer,
      receivedAmount: originalSale.receivedAmount,
      paymentReceivedAt: originalSale.paymentReceivedAt,
      clearPaymentReceivedAt: originalSale.paymentReceivedAt == null,
      paymentReceivedBy: originalSale.paymentReceivedBy,
      updatedAt: now,
      updatedBy: state.user.name,
    );
    state = state.copyWith(
      customers: _replaceParty(state.customers, updatedCustomer),
      sales: state.sales
          .map((item) => item.id == originalSale.id ? restoredSale : item)
          .toList(),
    );
    _activity(
      'Sale payment received undone',
      '${originalSale.customer.name} | ${originalSale.invoiceNumber} | ${money(receivedToUndo)} restored as pending',
    );
    _audit('Sale Payment Received Undo', 'sale', originalSale.id, {
      'Paid Amount': [
        money(currentSale.receivedAmount),
        money(originalSale.receivedAmount),
      ],
      'Undo Amount': [money(receivedToUndo), money(0)],
      'Pending': [
        money(currentSale.balanceAmount),
        money(originalSale.balanceAmount),
      ],
      'Updated By': ['', state.user.name],
    });
    _appActivityLog(
      action: 'sale_payment_received_undo',
      screen: 'Sales',
      details:
          '${originalSale.customer.name} | ${originalSale.invoiceNumber} | ${money(receivedToUndo)} restored as pending',
    );
    _safeSync(() => _firestore.saveSale(restoredSale, updatedCustomer));
    _syncDashboard();
  }

  void restoreSale(SaleRecord sale) {
    if (!sale.isDeleted) {
      return;
    }
    if (isRecycleBinExpired(sale.deletedAt)) {
      purgeExpiredRecycleBin();
      return;
    }
    final restored = sale.copyWith(
      isDeleted: false,
      clearDeletedAt: true,
      clearDeletedBy: true,
      updatedAt: DateTime.now(),
      updatedBy: state.user.name,
    );
    final customer = _partyWithBalance(
      state.customers,
      sale.customer,
      sale.balanceAmount,
    );
    state = state.copyWith(
      customers: _replaceParty(state.customers, customer),
      sales: state.sales
          .map(
            (item) => item.id == sale.id
                ? restored.copyWith(customer: customer)
                : item,
          )
          .toList(),
    );
    _activity('Sale Restored', sale.invoiceNumber);
    _audit('Sale Restored', 'sale', sale.id, {
      'Deleted': ['Yes', 'No'],
    });
    _safeSync(
      () =>
          _firestore.saveSale(restored.copyWith(customer: customer), customer),
    );
    _syncDashboard();
  }

  CashAllocation addCashAllocation({
    required String supervisorName,
    required double amount,
    DateTime? allocationDate,
    String paymentMode = 'Cash',
    String remarks = '',
  }) {
    if (!state.user.role.isOwnerOrAdmin) {
      _activity(
        'Cash allocation blocked',
        'Only Owner/Admin can allocate cash to supervisor/manager accounts.',
      );
      return CashAllocation(
        id: _id('cash-denied'),
        supervisorName: supervisorName.trim(),
        amount: 0,
        allocationDate: allocationDate,
        paymentMode: paymentMode,
        remarks: remarks.trim(),
        createdAt: DateTime.now(),
        createdBy: state.user.name,
      );
    }
    final allocation = CashAllocation(
      id: _id('cash'),
      supervisorName: supervisorName.trim().isEmpty
          ? 'Mohit Kumar'
          : supervisorName.trim(),
      amount: amount,
      allocationDate: allocationDate,
      paymentMode: paymentMode,
      remarks: remarks.trim(),
      createdAt: DateTime.now(),
      createdBy: state.user.name,
    );
    state = state.copyWith(
      cashAllocations: [allocation, ...state.cashAllocations],
    );
    _activity(
      'Cash Added',
      '${allocation.supervisorName} ${money(allocation.amount)}',
    );
    _audit('Cash Added', 'cash', allocation.id, {
      'Cash Given': ['', money(allocation.amount)],
      'Supervisor': ['', allocation.supervisorName],
      'Payment Mode': ['', allocation.paymentMode],
      'Date': ['', shortDate(allocation.date)],
    });
    _appActivityLog(
      action: 'payment_created',
      screen: 'Cash Allocation',
      details: '${allocation.supervisorName} ${money(allocation.amount)}',
    );
    _safeSync(() => _firestore.saveCashAllocation(allocation));
    _syncDashboard();
    return allocation;
  }

  void updateCashAllocation(CashAllocation allocation) {
    if (!_canManageCashAllocation(allocation.supervisorName)) {
      _activity(
        'Cash allocation edit blocked',
        'Only Owner/Admin or the same Manager account can edit cash allocation.',
      );
      return;
    }
    if (state.user.role != UserRole.manager &&
        _blockEditIfNeeded(
          moduleName: 'Payment',
          entryId: allocation.id,
          entryLabel: allocation.supervisorName,
          createdAt: allocation.createdAt,
        )) {
      return;
    }
    final original = state.cashAllocations.firstWhere(
      (item) => item.id == allocation.id,
      orElse: () => allocation,
    );
    final updated = allocation.copyWith(
      updatedAt: DateTime.now(),
      updatedBy: state.user.name,
    );
    state = state.copyWith(
      cashAllocations: state.cashAllocations
          .map((item) => item.id == allocation.id ? updated : item)
          .toList(),
    );
    _activity(
      'Cash Allocation Edited',
      '${updated.supervisorName} ${money(updated.amount)}',
    );
    _audit('Cash Allocation Edited', 'cash', updated.id, {
      'Supervisor': [original.supervisorName, updated.supervisorName],
      'Amount': [money(original.amount), money(updated.amount)],
      'Payment Mode': [original.paymentMode, updated.paymentMode],
      'Date': [shortDate(original.date), shortDate(updated.date)],
      'Remarks': [original.remarks, updated.remarks],
    });
    _safeSync(() => _firestore.saveCashAllocation(updated));
    _syncDashboard();
  }

  void deleteCashAllocation(CashAllocation allocation) {
    if (!_canManageCashAllocation(allocation.supervisorName)) {
      _activity(
        'Cash allocation delete blocked',
        'Only Owner/Admin or the same Manager account can delete cash allocation.',
      );
      return;
    }
    if (state.user.role != UserRole.manager &&
        _blockDeleteIfNeeded(
          moduleName: 'Payment',
          entryId: allocation.id,
          entryLabel: allocation.supervisorName,
          createdAt: allocation.createdAt,
        )) {
      return;
    }
    state = state.copyWith(
      cashAllocations: state.cashAllocations
          .where((item) => item.id != allocation.id)
          .toList(),
    );
    _activity(
      'Cash Allocation Deleted',
      '${allocation.supervisorName} ${money(allocation.amount)}',
    );
    _audit('Cash Allocation Deleted', 'cash', allocation.id, {
      'Deleted Amount': [money(allocation.amount), money(0)],
      'Deleted By': ['', state.user.name],
    });
    _safeSync(() => _firestore.deleteCashAllocation(allocation.id));
    _syncDashboard();
  }

  void correctStaffNameAcrossCashRecords({
    required String oldName,
    required String newName,
  }) {
    if (!state.user.role.isOwnerOrAdmin) {
      _activity(
        'Staff name correction blocked',
        'Only Owner/Admin can correct supervisor/manager record names.',
      );
      return;
    }
    final from = oldName.trim();
    final to = newName.trim();
    if (from.isEmpty || to.isEmpty || _samePerson(from, to)) {
      return;
    }
    final now = DateTime.now();
    final updatedCashAllocations = state.cashAllocations.map((item) {
      if (!_samePerson(item.supervisorName, from)) {
        return item;
      }
      return item.copyWith(
        supervisorName: to,
        updatedAt: now,
        updatedBy: state.user.name,
      );
    }).toList();
    final updatedPurchases = state.purchases.map((item) {
      if (!_samePerson(item.createdBy, from)) {
        return item;
      }
      return item.copyWith(
        createdBy: to,
        updatedAt: now,
        updatedBy: state.user.name,
      );
    }).toList();
    final updatedSales = state.sales.map((item) {
      if (!_samePerson(item.createdBy, from)) {
        return item;
      }
      return item.copyWith(
        createdBy: to,
        updatedAt: now,
        updatedBy: state.user.name,
      );
    }).toList();
    final updatedExpenses = state.expenses.map((item) {
      if (!_samePerson(item.addedBy, from)) {
        return item;
      }
      return item.copyWith(
        addedBy: to,
        updatedAt: now,
        updatedBy: state.user.name,
      );
    }).toList();

    state = state.copyWith(
      cashAllocations: updatedCashAllocations,
      purchases: updatedPurchases,
      sales: updatedSales,
      expenses: updatedExpenses,
    );
    _activity('Staff name corrected', '$from → $to');
    _audit('Staff Name Corrected', 'cash', _id('staff-name'), {
      'Old Name': [from, to],
      'Corrected By': ['', state.user.name],
    });

    for (final allocation in updatedCashAllocations.where(
      (item) =>
          _samePerson(item.supervisorName, to) &&
          item.updatedAt == now &&
          item.updatedBy == state.user.name,
    )) {
      _safeSync(() => _firestore.saveCashAllocation(allocation));
    }
    for (final purchase in updatedPurchases.where(
      (item) =>
          _samePerson(item.createdBy, to) &&
          item.updatedAt == now &&
          item.updatedBy == state.user.name,
    )) {
      _safeSync(() => _firestore.savePurchase(purchase, purchase.seller));
    }
    for (final sale in updatedSales.where(
      (item) =>
          _samePerson(item.createdBy, to) &&
          item.updatedAt == now &&
          item.updatedBy == state.user.name,
    )) {
      _safeSync(() => _firestore.saveSale(sale, sale.customer));
    }
    for (final expense in updatedExpenses.where(
      (item) =>
          _samePerson(item.addedBy, to) &&
          item.updatedAt == now &&
          item.updatedBy == state.user.name,
    )) {
      _safeSync(() => _firestore.saveExpense(expense));
    }
    _syncDashboard();
  }

  OpeningStockRecord addOpeningStock({
    required MaterialStock material,
    required double openingWeightKg,
    double openingRate = 0,
    double openingValue = 0,
    DateTime? date,
    String remarks = '',
  }) {
    if (!state.user.role.isOwnerOrAdmin) {
      _activity(
        'Month opening blocked',
        'Only Owner/Admin can create month opening stock',
      );
      return OpeningStockRecord(
        id: _id('opening-denied'),
        materialId: material.id,
        materialName: material.name,
        openingWeightKg: 0,
        date: date ?? DateTime.now(),
        createdBy: state.user.name,
        createdAt: DateTime.now(),
      );
    }
    final now = DateTime.now();
    final normalizedWeight = openingWeightKg
        .clamp(0, double.infinity)
        .toDouble();
    final normalizedRate = openingRate.clamp(0, double.infinity).toDouble();
    final normalizedValue = openingValue > 0
        ? openingValue
        : normalizedWeight * normalizedRate;
    final selectedDate = date ?? now;
    final existing = latestMonthOpeningStock(state, material, selectedDate);
    if (existing != null) {
      final updated = existing.copyWith(
        materialId: material.id,
        materialName: material.name,
        openingWeightKg: normalizedWeight,
        openingRate: normalizedRate,
        openingValue: normalizedValue,
        date: selectedDate,
        remarks: remarks.trim(),
      );
      updateOpeningStock(updated);
      return updated;
    }
    final record = OpeningStockRecord(
      id: _id('opening'),
      materialId: material.id,
      materialName: material.name,
      openingWeightKg: normalizedWeight,
      openingRate: normalizedRate,
      openingValue: normalizedValue,
      date: selectedDate,
      remarks: remarks.trim(),
      createdBy: state.user.name,
      createdAt: now,
    );
    state = state.copyWith(openingStocks: [record, ...state.openingStocks]);
    _activity(
      'Month opening stock added',
      '${material.name} ${kg(normalizedWeight)}',
    );
    _audit('Month opening stock added', 'openingStock', record.id, {
      'Material': ['', record.materialName],
      'Month Opening Qty': ['', kg(record.openingWeightKg)],
      'Month Opening Rate': ['', money(record.openingRate)],
      'Month Opening Value': ['', money(record.openingValue)],
    });
    _appActivityLog(
      action: 'opening_stock_added',
      screen: 'Opening Stock',
      details: '${record.materialName} ${kg(record.openingWeightKg)}',
    );
    _safeSync(() => _firestore.saveOpeningStock(record));
    _syncDashboard();
    return record;
  }

  void updateOpeningStock(OpeningStockRecord record) {
    if (!state.user.role.isOwnerOrAdmin) {
      _activity(
        'Month opening blocked',
        'Only Owner/Admin can update month opening stock',
      );
      return;
    }
    if (_blockEditIfNeeded(
      moduleName: 'Opening Stock',
      entryId: record.id,
      entryLabel: record.materialName,
      createdAt: record.createdAt,
    )) {
      return;
    }
    final original = state.openingStocks.firstWhere(
      (item) => item.id == record.id,
      orElse: () => record,
    );
    final updated = record.copyWith(
      updatedAt: DateTime.now(),
      updatedBy: state.user.name,
    );
    state = state.copyWith(
      openingStocks: state.openingStocks
          .map((item) => item.id == updated.id ? updated : item)
          .toList(),
    );
    _activity(
      'Month opening stock updated',
      '${updated.materialName} ${kg(updated.openingWeightKg)}',
    );
    _audit('Month opening stock updated', 'openingStock', updated.id, {
      'Material': [original.materialName, updated.materialName],
      'Month Opening Qty': [
        kg(original.openingWeightKg),
        kg(updated.openingWeightKg),
      ],
      'Month Opening Rate': [
        money(original.openingRate),
        money(updated.openingRate),
      ],
      'Month Opening Value': [
        money(original.openingValue),
        money(updated.openingValue),
      ],
    });
    _appActivityLog(
      action: 'opening_stock_updated',
      screen: 'Opening Stock',
      details: '${updated.materialName} ${kg(updated.openingWeightKg)}',
    );
    _safeSync(() => _firestore.saveOpeningStock(updated));
    _syncDashboard();
  }

  ExpenseRecord addExpense({
    required String category,
    required double amount,
    DateTime? expenseDate,
    String vendorName = '',
    String remarks = '',
    String billUploadPath = '',
    String photoPath = '',
    String? addedBy,
  }) {
    final expense = ExpenseRecord(
      id: _id('exp'),
      category: category.trim(),
      amount: amount,
      expenseDate: expenseDate,
      vendorName: vendorName.trim(),
      remarks: remarks.trim(),
      billUploadPath: billUploadPath,
      photoPath: photoPath,
      addedBy: (addedBy == null || addedBy.trim().isEmpty)
          ? state.user.name
          : addedBy.trim(),
      createdAt: DateTime.now(),
    );
    state = state.copyWith(expenses: [expense, ...state.expenses]);
    _activity('Expense recorded', '${expense.category} - ${money(amount)}');
    _audit('Expense Added', 'expense', expense.id, {
      'Category': ['', expense.category],
      'Amount': ['', money(expense.amount)],
      'Vendor': ['', expense.vendorName],
      'Added By': ['', expense.addedBy],
      'Date': ['', shortDate(expense.date)],
    });
    _safeSync(() => _firestore.saveExpense(expense));
    _syncDashboard();
    return expense;
  }

  void updateExpense(ExpenseRecord expense) {
    if (_blockEditIfNeeded(
      moduleName: 'Expense',
      entryId: expense.id,
      entryLabel: expense.category,
      createdAt: expense.createdAt,
    )) {
      return;
    }
    final original = state.expenses.firstWhere(
      (item) => item.id == expense.id,
      orElse: () => expense,
    );
    final updated = expense.copyWith(
      updatedAt: DateTime.now(),
      updatedBy: state.user.name,
    );
    state = state.copyWith(
      expenses: state.expenses
          .map((item) => item.id == expense.id ? updated : item)
          .toList(),
    );
    _activity('Expense edited', '${updated.category} ${money(updated.amount)}');
    _audit('Expense Edited', 'expense', updated.id, {
      'Category': [original.category, updated.category],
      'Amount': [money(original.amount), money(updated.amount)],
      'Vendor': [original.vendorName, updated.vendorName],
      'Remarks': [original.remarks, updated.remarks],
      'Date': [shortDate(original.date), shortDate(updated.date)],
    });
    _safeSync(() => _firestore.saveExpense(updated));
    _syncDashboard();
  }

  void deleteExpense(ExpenseRecord expense) {
    if (_blockDeleteIfNeeded(
      moduleName: 'Expense',
      entryId: expense.id,
      entryLabel: expense.category,
      createdAt: expense.createdAt,
    )) {
      return;
    }
    if (expense.isApproved && !state.user.role.isOwnerOrAdmin) {
      return;
    }
    final deleted = expense.copyWith(
      isDeleted: true,
      deletedAt: DateTime.now(),
      deletedBy: state.user.name,
      updatedAt: DateTime.now(),
      updatedBy: state.user.name,
    );
    state = state.copyWith(
      expenses: state.expenses
          .map((item) => item.id == expense.id ? deleted : item)
          .toList(),
    );
    _activity(
      'Expense deleted',
      '${expense.category} ${money(expense.amount)}',
    );
    _audit('Expense Deleted', 'expense', expense.id, {
      'Deleted': ['No', 'Yes'],
      'Amount': [money(expense.amount), money(0)],
    });
    _safeSync(() => _firestore.saveExpense(deleted));
    _syncDashboard();
  }

  void recordDispatch({required String material, required String customer}) {
    _activity('Dispatch Created', '$material to $customer');
    _audit('Dispatch Created', 'dispatch', _id('dispatch'), {
      'Material': ['', material],
      'Customer': ['', customer],
    });
    _syncDashboard();
  }

  void recordReportViewed(String report) {
    recordReportAction(
      action: 'report_opened',
      reportName: report,
      filterType: 'Today',
      dateRange: '',
    );
  }

  void recordReportAction({
    required String action,
    required String reportName,
    required String filterType,
    required String dateRange,
  }) {
    final trackedAction = action == 'report_opened'
        ? 'scrap_report_opened'
        : action;
    final label = switch (action) {
      'report_graph_viewed' => 'Report graph viewed',
      'report_pdf_exported' => 'Report PDF exported',
      'report_excel_exported' => 'Report Excel exported',
      'report_printed' => 'Report printed',
      _ => 'Scrap Report opened',
    };
    final details = [
      'reportName: $reportName',
      'filterType: $filterType',
      if (dateRange.trim().isNotEmpty) 'dateRange: $dateRange',
    ].join(' | ');
    _activity(label, details);
    _appActivityLog(
      action: trackedAction,
      screen: 'Scrap Report',
      details: details,
    );
  }

  void recordCashWithSupervisorViewed() {
    _activity(
      'Cash With Supervisor viewed',
      'Owner opened supervisor cash ledger',
    );
    _appActivityLog(
      action: 'cash_with_supervisor_viewed',
      screen: 'Cash With Supervisor',
      details: 'Owner opened supervisor cash ledger',
    );
  }

  void recordAutoReminderScheduled(String timeLabel) {
    final message =
        'Manual stock verification reminder scheduled at $timeLabel.';
    _activity('Manual stock reminder scheduled', message);
    _appActivityLog(
      action: 'manual_stock_reminder_scheduled',
      screen: 'Stock Reminder Settings',
      details: message,
    );
  }

  void recordAutoReminderSent(List<String> statusLines) {
    final details = statusLines.join(' | ');
    _activity('Manual stock reminders updated', details);
    _appActivityLog(
      action: 'manual_stock_reminder_updated',
      screen: 'Manual WhatsApp Reminder',
      details: details,
    );
  }

  void recordDashboardOpened() {
    _activity('Dashboard opened', state.user.role.name);
    _appActivityLog(
      action: 'dashboard_opened',
      screen: 'Dashboard',
      details: state.user.role.name,
    );
  }

  void recordStaffDashboardViewStarted({
    required String staffName,
    required UserRole staffRole,
  }) {
    if (!state.user.role.isOwnerOrAdmin) {
      _activity(
        'Staff dashboard view blocked',
        '${state.user.name} attempted to view $staffName',
      );
      _appActivityLog(
        action: 'staff_dashboard_view_blocked',
        screen: 'Staff Dashboard View',
        details: staffName,
      );
      return;
    }
    final details = '${state.user.name} viewing $staffName (${staffRole.name})';
    _activity('Owner opened staff dashboard', details);
    _audit('OWNER_VIEW_AS_OPENED', 'owner_view_as_logs', staffName, {
      'Owner': ['', state.user.name],
      'Viewed User': ['', staffName],
      'Viewed Role': ['', staffRole.name],
      'Action Status': ['', 'success'],
    });
    _appActivityLog(
      action: 'owner_view_as_dashboard_opened',
      screen: 'Staff Dashboard View',
      details: details,
    );
    _safeSync(
      () => _firestore.saveOwnerViewAsLog(
        owner: state.user,
        viewedUserName: staffName,
        viewedUserRole: staffRole,
        event: 'opened',
      ),
    );
  }

  void recordStaffDashboardViewEnded({
    required String staffName,
    required UserRole staffRole,
  }) {
    if (!state.user.role.isOwnerOrAdmin) {
      return;
    }
    final details = '${state.user.name} exited $staffName (${staffRole.name})';
    _activity('Owner exited staff dashboard', details);
    _audit('OWNER_VIEW_AS_EXITED', 'owner_view_as_logs', staffName, {
      'Owner': ['', state.user.name],
      'Viewed User': ['', staffName],
      'Viewed Role': ['', staffRole.name],
      'Action Status': ['', 'success'],
    });
    _appActivityLog(
      action: 'owner_view_as_dashboard_exited',
      screen: 'Staff Dashboard View',
      details: details,
    );
    _safeSync(
      () => _firestore.saveOwnerViewAsLog(
        owner: state.user,
        viewedUserName: staffName,
        viewedUserRole: staffRole,
        event: 'exited',
      ),
    );
  }

  void recordActivityFeedOpened() {
    _activity('Activity feed opened', 'Live Recent Activity');
    _appActivityLog(
      action: 'activity_feed_opened',
      screen: 'Live Recent Activity',
      details: 'Dashboard activity feed opened',
    );
  }

  void recordThemeChanged(String themeName) {
    _activity('Theme changed', themeName);
    _appActivityLog(
      action: 'theme_changed',
      screen: 'Settings',
      details: themeName,
    );
  }

  void recordVoiceActivity(String action, String details) {
    final title = switch (action) {
      'voice_started' => 'Voice started',
      'voice_command_recognized' => 'Voice command recognized',
      'voice_command_failed' => 'Voice command failed',
      'voice_purchase_saved' => 'Voice purchase saved',
      _ => 'Voice activity',
    };
    _activity(title, details);
    _appActivityLog(action: action, screen: 'Voice Purchase', details: details);
  }

  bool canModifyPurchase(PurchaseRecord purchase) {
    final role = state.user.role;
    return role.isOwnerOrAdmin || role.isTimedEditor;
  }

  bool canEditPurchase(PurchaseRecord purchase) {
    return canEditEntry(purchase.createdAt);
  }

  String purchaseEditExpiredMessage(PurchaseRecord purchase) {
    if (canEditPurchase(purchase)) {
      return '';
    }
    return 'Editing time expired. Purchase entry can be edited only within 1 hour.';
  }

  bool canModifySale(SaleRecord sale) {
    final role = state.user.role;
    if (role.isOwnerOrAdmin) {
      return true;
    }
    if (role == UserRole.manager) {
      return DateTime.now().difference(sale.createdAt) <= editDeleteWindow;
    }
    return false;
  }

  String saleEditExpiredMessage(SaleRecord sale) {
    if (canModifySale(sale)) {
      return '';
    }
    if (state.user.role == UserRole.supervisor) {
      return 'Supervisor can add sales, but only Manager/Owner can edit sales.';
    }
    return editExpiredMessage;
  }

  String saleDeleteExpiredMessage(SaleRecord sale) {
    if (canModifySale(sale)) {
      return '';
    }
    if (state.user.role == UserRole.supervisor) {
      return 'Supervisor can add sales, but only Manager/Owner can delete sales.';
    }
    return deleteExpiredMessage;
  }

  bool canEditEntry(DateTime createdAt) {
    return _canEditDeleteEntry(createdAt);
  }

  bool canDeleteEntry(DateTime createdAt) {
    return _canEditDeleteEntry(createdAt);
  }

  String get lockedEditDeleteMessage => 'Edit/Delete locked after 1 hour';

  String get editExpiredMessage =>
      'Edit time expired. You can edit this entry only within 1 hour. Please contact Owner/Admin.';

  String get deleteExpiredMessage =>
      'Delete time expired. You can delete this entry only within 1 hour. Please contact Owner/Admin.';

  String get editDeleteExpiredMessage =>
      'You cannot edit/delete this entry after 1 hour. Please contact Owner/Admin.';

  void recordPurchaseEditBlocked(PurchaseRecord purchase) {
    _blockEditIfNeeded(
      moduleName: 'Purchase',
      entryId: purchase.id,
      entryLabel: purchase.invoiceNumber,
      createdAt: purchase.createdAt,
    );
  }

  void recordWhatsAppShared({
    required String action,
    required String screen,
    required String details,
  }) {
    _activity('WhatsApp shared', details);
    _appActivityLog(action: action, screen: screen, details: details);
  }

  void recordPurchaseInvoiceGenerated(PurchaseRecord purchase) {
    final generatedAt = DateTime.now().toIso8601String();
    final detail =
        '${state.user.name} | ${state.user.role.name} | ${purchase.invoiceNumber} | ${purchase.seller.name} | $generatedAt';
    _activity('Purchase Invoice Generated', detail);
    _audit('Purchase Invoice Generated', 'purchase', purchase.id, {
      'User': ['', state.user.name],
      'Role': ['', state.user.role.name],
      'Purchase No': ['', purchase.invoiceNumber],
      'Seller Name': ['', purchase.seller.name],
      'Date-Time': ['', generatedAt],
    });
    _appActivityLog(
      action: 'purchase_invoice_generated',
      screen: 'Purchase',
      details: detail,
    );
  }

  StockReminderReceiver addStockReminderReceiver({
    required String receiverName,
    required StockReminderRole role,
    required String whatsAppNumber,
    required int reminderHour,
    required int reminderMinute,
    required List<StockReminderType> reminderTypes,
    bool isActive = true,
  }) {
    final receiver = StockReminderReceiver(
      id: _id('stock-reminder'),
      receiverName: receiverName.trim(),
      role: role,
      whatsAppNumber: whatsAppNumber.trim(),
      isActive: isActive,
      reminderHour: reminderHour.clamp(0, 23).toInt(),
      reminderMinute: reminderMinute.clamp(0, 59).toInt(),
      reminderTypes: reminderTypes.isEmpty
          ? const [StockReminderType.all]
          : reminderTypes,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      stockReminderReceivers: [receiver, ...state.stockReminderReceivers],
    );
    _activity(
      'Manual stock reminder receiver added',
      '${receiver.receiverName} | ${receiver.whatsAppNumber}',
    );
    _appActivityLog(
      action: 'manual_stock_reminder_receiver_added',
      screen: 'Stock Reminder Settings',
      details: '${receiver.receiverName} ${receiver.timeKey}',
    );
    _safeSync(() => _firestore.saveStockReminderReceiver(receiver));
    return receiver;
  }

  void updateStockReminderReceiver(StockReminderReceiver receiver) {
    final updated = receiver.copyWith(updatedAt: DateTime.now());
    state = state.copyWith(
      stockReminderReceivers: state.stockReminderReceivers
          .map((item) => item.id == receiver.id ? updated : item)
          .toList(),
    );
    _activity(
      'Manual stock reminder receiver updated',
      '${updated.receiverName} | ${updated.whatsAppNumber}',
    );
    _appActivityLog(
      action: 'manual_stock_reminder_receiver_updated',
      screen: 'Stock Reminder Settings',
      details: '${updated.receiverName} ${updated.timeKey}',
    );
    _safeSync(() => _firestore.saveStockReminderReceiver(updated));
  }

  void deleteStockReminderReceiver(String id) {
    StockReminderReceiver? existing;
    for (final item in state.stockReminderReceivers) {
      if (item.id == id) {
        existing = item;
        break;
      }
    }
    state = state.copyWith(
      stockReminderReceivers: state.stockReminderReceivers
          .where((item) => item.id != id)
          .toList(),
    );
    _activity(
      'Manual stock reminder receiver deleted',
      existing?.receiverName ?? id,
    );
    _safeSync(() => _firestore.deleteStockReminderReceiver(id));
  }

  ManualReminderLog createManualReminderLog({
    required StockReminderReceiver receiver,
    required StockReminderType messageType,
    required String messageContent,
    ManualReminderStatus status = ManualReminderStatus.pendingManualSend,
  }) {
    final log = ManualReminderLog(
      reminderId: _id('manual-reminder'),
      receiverName: receiver.receiverName,
      receiverNumber: receiver.whatsAppNumber,
      role: receiver.role,
      messageType: messageType,
      messageContent: messageContent,
      status: status,
      openedAt: status == ManualReminderStatus.whatsappOpened
          ? DateTime.now()
          : null,
      copiedAt: status == ManualReminderStatus.messageCopied
          ? DateTime.now()
          : null,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      manualReminderLogs: [log, ...state.manualReminderLogs].take(100).toList(),
    );
    _activity(
      'Manual WhatsApp reminder prepared',
      '${receiver.receiverName} | ${_manualReminderStatusLabel(status)}',
    );
    _safeSync(() => _firestore.saveManualReminderLog(log));
    return log;
  }

  void updateManualReminderLogStatus(
    String reminderId,
    ManualReminderStatus status,
  ) {
    ManualReminderLog? updated;
    final now = DateTime.now();
    final next = state.manualReminderLogs.map((item) {
      if (item.reminderId != reminderId) {
        return item;
      }
      updated = item.copyWith(
        status: status,
        openedAt: status == ManualReminderStatus.whatsappOpened
            ? now
            : item.openedAt,
        copiedAt: status == ManualReminderStatus.messageCopied
            ? now
            : item.copiedAt,
      );
      return updated!;
    }).toList();
    if (updated == null) {
      return;
    }
    state = state.copyWith(manualReminderLogs: next);
    _activity(
      'Manual WhatsApp reminder status',
      '${updated!.receiverName} | ${_manualReminderStatusLabel(status)}',
    );
    _safeSync(() => _firestore.saveManualReminderLog(updated!));
  }

  void recordPurchaseInvoiceShared({
    required PurchaseRecord purchase,
    required String shareMethod,
  }) {
    final sharedAt = DateTime.now().toIso8601String();
    final detail =
        '${state.user.name} | ${state.user.role.name} | ${purchase.invoiceNumber} | ${purchase.seller.name} | $shareMethod | $sharedAt';
    _activity('Purchase Invoice Shared', detail);
    _audit('Purchase Invoice Shared', 'purchase', purchase.id, {
      'User': ['', state.user.name],
      'Role': ['', state.user.role.name],
      'Purchase No': ['', purchase.invoiceNumber],
      'Seller Name': ['', purchase.seller.name],
      'Share Method': ['', shareMethod],
      'Date-Time': ['', sharedAt],
    });
    _appActivityLog(
      action: 'purchase_invoice_shared',
      screen: 'Purchase',
      details: detail,
    );
  }

  void recordSaleItemAdded() {
    _activity('Sale item added', 'New Sale item line added');
    _appActivityLog(
      action: 'sale_item_added',
      screen: 'New Sale',
      details: 'New Sale item line added',
    );
  }

  void recordSaleItemRemoved({required String materialName}) {
    _activity('Sale item removed', materialName);
    _appActivityLog(
      action: 'sale_item_removed',
      screen: 'New Sale',
      details: materialName,
    );
  }

  void recordConfidentialProfitViewed() {
    _activity('Confidential Profit viewed', 'Owner opened analytics');
    _appActivityLog(
      action: 'confidential_profit_viewed',
      screen: 'Confidential Profit Analytics',
      details: 'Owner opened analytics',
    );
  }

  void recordUnauthorizedConfidentialAccess() {
    _activity(
      'Unauthorized confidential access',
      '${state.user.name} attempted confidential profit',
    );
    _appActivityLog(
      action: 'unauthorized_confidential_access_attempt',
      screen: 'Confidential Profit Analytics',
      details: '${state.user.name} attempted confidential profit',
    );
  }

  bool isRecycleBinExpired(DateTime? deletedAt) {
    if (deletedAt == null) {
      return false;
    }
    return DateTime.now().difference(deletedAt) >= recycleBinRetention;
  }

  void purgeExpiredRecycleBin() {
    final expiredPurchaseIds = state.deletedPurchases
        .where((item) => isRecycleBinExpired(item.deletedAt))
        .map((item) => item.id)
        .toSet();
    final expiredSaleIds = state.deletedSales
        .where((item) => isRecycleBinExpired(item.deletedAt))
        .map((item) => item.id)
        .toSet();
    if (expiredPurchaseIds.isEmpty && expiredSaleIds.isEmpty) {
      return;
    }

    state = state.copyWith(
      purchases: state.purchases
          .where((item) => !expiredPurchaseIds.contains(item.id))
          .toList(),
      sales: state.sales
          .where((item) => !expiredSaleIds.contains(item.id))
          .toList(),
    );

    for (final id in expiredPurchaseIds) {
      _safeSync(() => _firestore.deletePurchasePermanently(id));
    }
    for (final id in expiredSaleIds) {
      _safeSync(() => _firestore.deleteSalePermanently(id));
    }
    final removedCount = expiredPurchaseIds.length + expiredSaleIds.length;
    _activity(
      'Recycle Bin Purged',
      '$removedCount expired record${removedCount == 1 ? '' : 's'} permanently deleted',
    );
    _syncDashboard();
  }

  void _activity(String title, String subtitle) {
    final entry = ActivityRecord(
      id: _id('act'),
      title: title,
      subtitle: subtitle,
      userName: state.user.name,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      activities: [entry, ...state.activities].take(50).toList(),
    );
    _safeSync(() => _firestore.saveActivity(entry));
  }

  void _appActivityLog({
    required String action,
    required String screen,
    required String details,
  }) {
    _safeSync(
      () => _firestore.saveAppActivityLog(
        user: state.user,
        action: action,
        screen: screen,
        details: details,
      ),
    );
  }

  void _audit(
    String action,
    String recordType,
    String recordId,
    Map<String, List<String>> changes,
  ) {
    final entries = <AuditEntry>[];
    for (final entry in changes.entries) {
      final oldValue = entry.value.isEmpty ? '' : entry.value.first;
      final newValue = entry.value.length < 2 ? '' : entry.value[1];
      if (oldValue == newValue && oldValue.isNotEmpty) {
        continue;
      }
      entries.add(
        AuditEntry(
          id: _id('audit'),
          action: action,
          recordType: recordType,
          recordId: recordId,
          field: entry.key,
          oldValue: oldValue,
          newValue: newValue,
          user: state.user.name,
          role: state.user.role,
          createdAt: DateTime.now(),
          deviceInfo: 'Flutter app',
        ),
      );
    }
    if (entries.isEmpty) {
      return;
    }
    state = state.copyWith(
      auditTrail: [...entries, ...state.auditTrail].take(200).toList(),
    );
    for (final entry in entries) {
      _safeSync(() => _firestore.saveAuditEntry(entry));
    }
  }

  void _startFirestoreRealtime() {
    if (_subscriptions.isNotEmpty) {
      return;
    }

    _safeSync(() => _firestore.verifyConnectivity());
    _subscriptions.addAll([
      _firestore.watchSellers().listen((items) {
        state = state.copyWith(sellers: items);
        _syncDashboard();
      }),
      _firestore.watchCustomers().listen((items) {
        state = state.copyWith(customers: items);
        _syncDashboard();
      }),
      _firestore.watchInventory().listen((items) {
        state = state.copyWith(materials: items);
        _syncDashboard();
      }),
      _firestore.watchPurchases().listen((items) {
        state = state.copyWith(purchases: items);
        purgeExpiredRecycleBin();
        _syncDashboard();
      }),
      _firestore.watchSales().listen((items) {
        state = state.copyWith(sales: items);
        purgeExpiredRecycleBin();
        _syncDashboard();
      }),
      _firestore.watchExpenses().listen((items) {
        state = state.copyWith(expenses: items);
        _syncDashboard();
      }),
      _firestore.watchCashAllocations().listen((items) {
        state = state.copyWith(cashAllocations: items);
        _syncDashboard();
      }),
      _firestore.watchOpeningStocks().listen((items) {
        state = state.copyWith(openingStocks: items);
        _syncDashboard();
      }),
      _firestore.watchPhysicalStocks().listen((items) {
        state = state.copyWith(physicalStocks: items);
        _syncDashboard();
      }),
      _firestore.watchStockReminderReceivers().listen((items) {
        state = state.copyWith(stockReminderReceivers: items);
      }),
      _firestore.watchManualReminderLogs().listen((items) {
        state = state.copyWith(manualReminderLogs: items);
      }),
      _firestore.watchAuditTrail().listen((items) {
        state = state.copyWith(auditTrail: items);
      }),
      _firestore.watchActivities().listen((items) {
        state = state.copyWith(activities: items);
      }),
      _firestore.watchDashboardStatistics().listen((_) {}),
    ]);
  }

  void _syncDashboard() {
    _safeSync(() => _firestore.saveDashboardStatistics(state.metrics));
  }

  void _safeSync(Future<void> Function() action) {
    if (!_firestore.isAvailable) {
      return;
    }
    unawaited(
      action().catchError((Object error) {
        final entry = ActivityRecord(
          id: _id('sync'),
          title: 'Firebase sync pending',
          subtitle: error.toString(),
          userName: state.user.name,
          createdAt: DateTime.now(),
        );
        state = state.copyWith(
          activities: [entry, ...state.activities].take(50).toList(),
        );
      }),
    );
  }

  String _manualReminderStatusLabel(ManualReminderStatus status) {
    return switch (status) {
      ManualReminderStatus.pendingManualSend => 'Pending Manual Send',
      ManualReminderStatus.whatsappOpened => 'WhatsApp Opened',
      ManualReminderStatus.messageCopied => 'Message Copied',
      ManualReminderStatus.sentManually => 'Sent Manually',
      ManualReminderStatus.cancelled => 'Cancelled',
    };
  }

  Party _partyWithBalance(
    List<Party> parties,
    Party party,
    double delta, {
    DateTime? lastPurchaseAt,
  }) {
    final current = parties.where((item) => item.id == party.id);
    final base = current.isEmpty ? party : current.first;
    return base.copyWith(
      pendingAmount: roundMoneyValue(base.pendingAmount + delta),
      lastPurchaseAt: lastPurchaseAt,
    );
  }

  _PurchaseCalculation _calculatePurchaseAmounts({
    required List<LineItem> items,
    required double paidAmount,
    double? originalBillAmount,
    required double previousBalanceAppliedAmount,
    required List<String> previousBalanceReferenceIds,
    required double currentSettlementAdjustmentAmount,
    required String settlementStatus,
  }) {
    final cleanPaid = paidAmount < 0 ? 0.0 : roundMoneyValue(paidAmount);
    final cleanPrevious = roundMoneyValue(previousBalanceAppliedAmount);
    final cleanSettlement = roundMoneyValue(currentSettlementAdjustmentAmount);
    final computedOriginal = roundMoneyValue(
      items.fold<double>(0, (sum, item) => sum + item.componentOriginalAmount),
    );
    final cleanOriginal = roundMoneyValue(
      originalBillAmount ?? computedOriginal,
    );
    final adjustedItems = _distributePurchaseAdjustments(
      items,
      originalBillAmount: cleanOriginal,
      previousBalanceAppliedAmount: cleanPrevious,
      currentSettlementAdjustmentAmount: cleanSettlement,
    );
    final finalBillAmount = roundMoneyValue(
      cleanOriginal + cleanPrevious + cleanSettlement,
    );
    final balanceAmount = roundMoneyValue(finalBillAmount - cleanPaid);
    return _PurchaseCalculation(
      items: adjustedItems,
      paidAmount: cleanPaid,
      originalBillAmount: cleanOriginal,
      previousBalanceAppliedAmount: cleanPrevious,
      previousBalanceReferenceIds: previousBalanceReferenceIds,
      currentSettlementAdjustmentAmount: cleanSettlement,
      finalBillAmount: finalBillAmount,
      balanceAmount: balanceAmount,
      settlementStatus: settlementStatus,
    );
  }

  List<LineItem> _distributePurchaseAdjustments(
    List<LineItem> items, {
    required double originalBillAmount,
    required double previousBalanceAppliedAmount,
    required double currentSettlementAdjustmentAmount,
  }) {
    if (items.isEmpty) {
      return const [];
    }
    final originalAmounts = [
      for (final item in items) roundMoneyValue(item.componentOriginalAmount),
    ];
    final previousShares = _allocateAdjustment(
      originalAmounts,
      previousBalanceAppliedAmount,
    );
    final settlementShares = _allocateAdjustment(
      originalAmounts,
      currentSettlementAdjustmentAmount,
    );
    final totalAdjustment = roundMoneyValue(
      previousBalanceAppliedAmount + currentSettlementAdjustmentAmount,
    );
    final targetFinalTotal = roundMoneyValue(
      originalBillAmount + totalAdjustment,
    );
    final adjusted = <LineItem>[];
    for (var index = 0; index < items.length; index++) {
      final componentFinalAmount = roundMoneyValue(
        originalAmounts[index] +
            previousShares[index] +
            settlementShares[index],
      );
      adjusted.add(
        items[index].copyWith(
          componentOriginalAmount: originalAmounts[index],
          componentPreviousBalanceAdjustmentAmount: previousShares[index],
          componentSettlementAdjustmentAmount: settlementShares[index],
          componentFinalAmount: componentFinalAmount,
        ),
      );
    }
    final adjustedTotal = roundMoneyValue(
      adjusted.fold<double>(0, (sum, item) => sum + item.componentFinalAmount),
    );
    final diff = roundMoneyValue(targetFinalTotal - adjustedTotal);
    if (diff.abs() > 0.001) {
      final largestIndex = _largestAmountIndex(originalAmounts);
      adjusted[largestIndex] = adjusted[largestIndex].copyWith(
        componentFinalAmount: roundMoneyValue(
          adjusted[largestIndex].componentFinalAmount + diff,
        ),
      );
    }
    return adjusted;
  }

  List<double> _allocateAdjustment(List<double> amounts, double adjustment) {
    if (amounts.isEmpty) {
      return const [];
    }
    final total = roundMoneyValue(
      amounts.fold<double>(0, (sum, amount) => sum + amount),
    );
    if (total.abs() <= 0.01 || adjustment.abs() <= 0.001) {
      return List<double>.filled(amounts.length, 0);
    }
    final shares = [
      for (final amount in amounts)
        roundMoneyValue(adjustment * amount / total),
    ];
    final allocated = roundMoneyValue(
      shares.fold<double>(0, (sum, amount) => sum + amount),
    );
    final diff = roundMoneyValue(adjustment - allocated);
    if (diff.abs() > 0.001) {
      shares[_largestAmountIndex(amounts)] = roundMoneyValue(
        shares[_largestAmountIndex(amounts)] + diff,
      );
    }
    return shares;
  }

  int _largestAmountIndex(List<double> amounts) {
    var largestIndex = 0;
    for (var index = 1; index < amounts.length; index++) {
      if (amounts[index].abs() > amounts[largestIndex].abs()) {
        largestIndex = index;
      }
    }
    return largestIndex;
  }

  String _purchasePaymentStatus(double balanceAmount) {
    if (balanceAmount.abs() <= 0.01) {
      return 'paid';
    }
    return balanceAmount > 0 ? 'pending' : 'advance';
  }

  List<Party> _replaceParty(List<Party> parties, Party party) {
    var found = false;
    final next = parties.map((item) {
      if (item.id == party.id) {
        found = true;
        return party;
      }
      return item;
    }).toList();
    return found ? next : [party, ...next];
  }

  String _effectiveEntryCreator(String? createdBy) {
    final value = createdBy?.trim() ?? '';
    return value.isEmpty ? state.user.name : value;
  }

  bool _canManageCashAllocation(String supervisorName) {
    final role = state.user.role;
    if (role.isOwnerOrAdmin) {
      return true;
    }
    return role == UserRole.manager &&
        _samePerson(supervisorName, state.user.name);
  }

  bool _samePerson(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase();

  bool _canEditDeleteEntry(DateTime createdAt) {
    final role = state.user.role;
    if (role.isOwnerOrAdmin) {
      return true;
    }
    if (role.isTimedEditor) {
      return DateTime.now().difference(createdAt) <= editDeleteWindow;
    }
    return false;
  }

  DateTime _entryCreatedAt(DateTime? createdAt) {
    return createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _blockEditIfNeeded({
    required String moduleName,
    required String entryId,
    required String entryLabel,
    required DateTime createdAt,
  }) {
    if (canEditEntry(createdAt)) {
      return false;
    }
    _recordBlockedEditDelete(
      moduleName: moduleName,
      entryId: entryId,
      entryLabel: entryLabel,
      actionType: 'EDIT_BLOCKED_TIME_EXPIRED',
      message: editExpiredMessage,
    );
    return true;
  }

  bool _blockDeleteIfNeeded({
    required String moduleName,
    required String entryId,
    required String entryLabel,
    required DateTime createdAt,
  }) {
    if (canDeleteEntry(createdAt)) {
      return false;
    }
    _recordBlockedEditDelete(
      moduleName: moduleName,
      entryId: entryId,
      entryLabel: entryLabel,
      actionType: 'DELETE_BLOCKED_TIME_EXPIRED',
      message: deleteExpiredMessage,
    );
    return true;
  }

  void _recordBlockedEditDelete({
    required String moduleName,
    required String entryId,
    required String entryLabel,
    required String actionType,
    required String message,
  }) {
    _activity('$moduleName blocked', '$entryLabel: $message');
    _audit(actionType, moduleName.toLowerCase(), entryId, {
      'Entry': [entryLabel, entryLabel],
      'Attempted By': ['', state.user.name],
      'Role': ['', state.user.role.name],
      'Action Status': ['', 'blocked'],
      'Reason': ['', message],
    });
    _appActivityLog(
      action:
          '${moduleName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${actionType.toLowerCase()}',
      screen: moduleName,
      details: '$entryLabel | $message',
    );
  }

  void _recordAdminOverrideIfNeeded({
    required String moduleName,
    required String entryId,
    required String entryLabel,
    required DateTime createdAt,
    required String action,
    required String reason,
  }) {
    if (!state.user.role.isOwnerOrAdmin ||
        DateTime.now().difference(createdAt) <= editDeleteWindow) {
      return;
    }
    _audit(action, moduleName.toLowerCase(), entryId, {
      'Entry': [entryLabel, entryLabel],
      'Attempted By': ['', state.user.name],
      'Role': ['', state.user.role.name],
      'Action Status': ['', 'success'],
      'Reason': ['', reason],
    });
    _appActivityLog(
      action:
          '${moduleName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${action.toLowerCase()}',
      screen: moduleName,
      details: '$entryLabel | $reason',
    );
  }

  String _itemsSummary(List<LineItem> items) {
    return items
        .map(
          (item) =>
              '${item.materialName} ${kg(item.weightKg)} x ${money(item.rate)}',
        )
        .join(', ');
  }

  String _nextInvoice(String prefix, int count, DateTime date) {
    return '$prefix-${invoiceDate(date)}-${(count + 1).toString().padLeft(3, '0')}';
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

class _PurchaseCalculation {
  const _PurchaseCalculation({
    required this.items,
    required this.paidAmount,
    required this.originalBillAmount,
    required this.previousBalanceAppliedAmount,
    required this.previousBalanceReferenceIds,
    required this.currentSettlementAdjustmentAmount,
    required this.finalBillAmount,
    required this.balanceAmount,
    required this.settlementStatus,
  });

  final List<LineItem> items;
  final double paidAmount;
  final double originalBillAmount;
  final double previousBalanceAppliedAmount;
  final List<String> previousBalanceReferenceIds;
  final double currentSettlementAdjustmentAmount;
  final double finalBillAmount;
  final double balanceAmount;
  final String settlementStatus;

  double get ledgerDelta => roundMoneyValue(
    originalBillAmount + currentSettlementAdjustmentAmount - paidAmount,
  );
}

class VoicePurchaseDraft {
  const VoicePurchaseDraft({
    required this.materialName,
    required this.weightKg,
    required this.rate,
    this.sellerName = '',
    this.paidAmount = 0,
    this.remarks = '',
    this.applyPreviousBalance = false,
    this.resetForm = false,
  });

  final String materialName;
  final double weightKg;
  final double rate;
  final String sellerName;
  final double paidAmount;
  final String remarks;
  final bool applyPreviousBalance;
  final bool resetForm;
}

sealed class BusinessVoiceDraft {
  const BusinessVoiceDraft();
}

class VoiceCashAllocationDraft extends BusinessVoiceDraft {
  const VoiceCashAllocationDraft({
    required this.supervisorName,
    required this.amount,
    required this.paymentMode,
  });

  final String supervisorName;
  final double amount;
  final String paymentMode;
}

class VoiceSupervisorExpenseDraft extends BusinessVoiceDraft {
  const VoiceSupervisorExpenseDraft({
    required this.supervisorName,
    required this.category,
    required this.amount,
    required this.remarks,
  });

  final String supervisorName;
  final String category;
  final double amount;
  final String remarks;
}

BusinessVoiceDraft? parseBusinessVoiceCommand(String command) {
  final text = _normalizeVoiceText(command);
  if (text.isEmpty) {
    return null;
  }
  final amount = _firstNumber(text);
  if (amount == null || amount <= 0) {
    return null;
  }

  final isAllocation =
      text.contains('allocate') ||
      text.contains('allocation') ||
      text.contains('cash do') ||
      text.contains('cash de') ||
      (text.contains('cash') &&
          (text.contains(' to ') || text.contains(' ko ')));
  if (isAllocation) {
    return VoiceCashAllocationDraft(
      supervisorName: _supervisorFromAllocation(text),
      amount: amount,
      paymentMode: _paymentModeFromText(text),
    );
  }

  final isExpense =
      text.contains('spent') ||
      text.contains('expense') ||
      text.contains('kharcha') ||
      text.contains('transport') ||
      text.contains('loading') ||
      text.contains('scrap purchase') ||
      text.contains('other purchase') ||
      text.contains('inventory purchase') ||
      text.contains('misc');
  if (!isExpense) {
    return null;
  }

  return VoiceSupervisorExpenseDraft(
    supervisorName: _supervisorFromExpense(text),
    category: _categoryFromVoiceText(text),
    amount: amount,
    remarks: command.trim(),
  );
}

VoicePurchaseDraft? parsePurchaseCommand(String command) {
  final text = _normalizeVoiceText(command)
      .replaceAll(',', ' ')
      .replaceAll('\u20b9', ' ')
      .replaceAll('₹', ' ')
      .replaceAll('rs.', 'rs')
      .replaceAll(RegExp(r'\bsave\b'), ' ')
      .trim();
  final weightMatch = RegExp(
    r'(\d+(?:\.\d+)?)\s*(kg|kgs|kilo|kilos|kilogram|kilograms)\b',
  ).firstMatch(text);
  final rateMatch = RegExp(
    r'(?:at|rate|dar|bhav)\s*(?:rs|rupees|rupaye|inr)?\s*(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*(?:rs|rupees|rupaye|inr)\b',
  ).firstMatch(text);
  if (weightMatch == null) {
    return null;
  }
  final numbers = RegExp(r'\d+(?:\.\d+)?').allMatches(text).toList();
  final rawRate = rateMatch == null
      ? (numbers.length < 2 ? null : numbers.last.group(0))
      : rateMatch.group(1) ?? rateMatch.group(2);
  if (rawRate == null) {
    return null;
  }
  final sellerFromMatch = RegExp(r'\bfrom\s+([a-z ]+)$').firstMatch(text);
  final sellerSeMatch = RegExp(r'^([a-z ]+?)\s+se\s+').firstMatch(text);
  final sellerName = sellerFromMatch != null
      ? _titleCase(sellerFromMatch.group(1)!)
      : sellerSeMatch != null
      ? _titleCase(sellerSeMatch.group(1)!)
      : '';
  final material = text
      .replaceAll(RegExp(r'purchase|add|buy|material|maal'), '')
      .replaceAll(RegExp(r'\bfrom\s+[a-z ]+$'), '')
      .replaceAll(RegExp(r'^[a-z ]+?\s+se\s+'), '')
      .replaceAll(
        RegExp(r'\d+(?:\.\d+)?\s*(kg|kgs|kilo|kilos|kilogram|kilograms)\b'),
        '',
      )
      .replaceAll(
        RegExp(
          r'(?:at|rate|dar|bhav)\s*(?:rs|rupees|rupaye|inr)?\s*\d+(?:\.\d+)?',
        ),
        '',
      )
      .replaceAll(RegExp(r'\d+(?:\.\d+)?\s*(rs|rupees|rupaye|inr)\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return VoicePurchaseDraft(
    materialName: material.isEmpty ? 'Material' : _titleCase(material),
    weightKg: double.parse(weightMatch.group(1)!),
    rate: double.parse(rawRate),
    sellerName: sellerName,
    applyPreviousBalance: _wantsPreviousBalanceApplied(text),
  );
}

VoicePurchaseDraft? parseSmartPurchaseCommand(String command) {
  final text = _normalizeSmartVoiceText(
    command,
  ).replaceAll(RegExp(r'\bsave\b'), ' ').trim();
  if (text.isEmpty) {
    return null;
  }
  if (_isClearPurchaseCommand(text)) {
    return const VoicePurchaseDraft(
      materialName: '',
      weightKg: 0,
      rate: 0,
      resetForm: true,
    );
  }
  final sellerField = _fieldAfterLabel(
    text,
    ['seller', 'supplier', 'from'],
    stopLabels: [
      'material',
      'weight',
      'rate',
      'paid',
      'amount',
      'remarks',
      'apply',
      'previous',
      'save',
    ],
  );
  final materialField = _fieldAfterLabel(
    text,
    ['material', 'maal', 'item'],
    stopLabels: [
      'weight',
      'rate',
      'paid',
      'amount',
      'seller',
      'remarks',
      'apply',
      'previous',
      'save',
    ],
  );
  final weight =
      _numberAfterLabel(text, ['weight', 'wajan']) ??
      double.tryParse(
        RegExp(
              r'(\d+(?:\.\d+)?)\s*(kg|kgs|kilo|kilos|kilogram|kilograms)\b',
            ).firstMatch(text)?.group(1) ??
            '',
      );
  final rate = _numberAfterLabel(text, ['rate', 'dar', 'bhav']);
  final paid = _numberAfterLabel(text, [
    'paid amount',
    'paid',
    'payment',
    'amount',
  ]);
  final remarks = _fieldAfterLabel(
    text,
    ['remarks', 'remark', 'note'],
    stopLabels: ['save'],
  );
  if (weight == null || weight <= 0 || rate == null || rate <= 0) {
    return parsePurchaseCommand(text);
  }
  final material = materialField.isEmpty
      ? _fieldAfterLabel(
          text,
          ['purchase', 'buy', 'add'],
          stopLabels: [
            'weight',
            'rate',
            'paid',
            'amount',
            'seller',
            'remarks',
            'apply',
            'previous',
          ],
        )
      : materialField;
  return VoicePurchaseDraft(
    sellerName: _titleCase(sellerField),
    materialName: material.isEmpty ? 'Material' : _titleCase(material),
    weightKg: weight,
    rate: rate,
    paidAmount: paid ?? 0,
    remarks: remarks,
    applyPreviousBalance: _wantsPreviousBalanceApplied(text),
  );
}

String normalizeSmartVoiceCommand(String command) =>
    _normalizeSmartVoiceText(command);

double? voiceNumberFromText(String command) =>
    _firstNumber(_normalizeSmartVoiceText(command));

String _normalizeVoiceText(String command) {
  return command
      .toLowerCase()
      .replaceAll(',', ' ')
      .replaceAll('\u20b9', ' ')
      .replaceAll('₹', ' ')
      .replaceAll('rs.', 'rs')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _normalizeSmartVoiceText(String command) {
  return _replaceNumberWords(command)
      .toLowerCase()
      .replaceAll(',', ' ')
      .replaceAll('\u20b9', ' ')
      .replaceAll('rs.', 'rs')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _wantsPreviousBalanceApplied(String text) {
  return (text.contains('apply') ||
          text.contains('adjust') ||
          text.contains('add') ||
          text.contains('reduce')) &&
      text.contains('previous') &&
      text.contains('balance');
}

bool _isClearPurchaseCommand(String text) {
  return text == 'clear' ||
      text == 'reset' ||
      text == 'clear purchase' ||
      text == 'reset purchase' ||
      text == 'reset form';
}

double? _firstNumber(String text) {
  final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(text);
  return match == null ? null : double.tryParse(match.group(0)!);
}

double? _numberAfterLabel(String text, List<String> labels) {
  for (final label in labels) {
    final match = RegExp(
      '\\b${RegExp.escape(label)}\\b\\s*(?:is|hai|rs|rupees|rupaye|inr)?\\s*(\\d+(?:\\.\\d+)?)',
    ).firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
  }
  return null;
}

String _fieldAfterLabel(
  String text,
  List<String> labels, {
  required List<String> stopLabels,
}) {
  for (final label in labels) {
    final match = RegExp(
      '\\b${RegExp.escape(label)}\\b\\s+(.+)',
    ).firstMatch(text);
    if (match == null) {
      continue;
    }
    var value = match.group(1)!.trim();
    for (final stop in stopLabels) {
      final stopMatch = RegExp(
        '\\b${RegExp.escape(stop)}\\b',
      ).firstMatch(value);
      if (stopMatch != null) {
        value = value.substring(0, stopMatch.start).trim();
      }
    }
    value = value
        .replaceAll(RegExp(r'\b(is|hai|ko|se|from)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _replaceNumberWords(String input) {
  final tokens = input.toLowerCase().split(RegExp(r'\s+'));
  final output = <String>[];
  var index = 0;
  while (index < tokens.length) {
    final parsed = _parseNumberWords(tokens, index);
    if (parsed == null) {
      output.add(tokens[index]);
      index++;
    } else {
      output.add(parsed.value.toStringAsFixed(0));
      index = parsed.nextIndex;
    }
  }
  return output.join(' ');
}

({double value, int nextIndex})? _parseNumberWords(
  List<String> tokens,
  int start,
) {
  const small = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };
  var total = 0;
  var current = 0;
  var index = start;
  var used = false;
  while (index < tokens.length) {
    final token = tokens[index].replaceAll(RegExp(r'[^a-z]'), '');
    if (small.containsKey(token)) {
      current += small[token]!;
      used = true;
    } else if (token == 'hundred') {
      current = (current == 0 ? 1 : current) * 100;
      used = true;
    } else if (token == 'thousand') {
      total += (current == 0 ? 1 : current) * 1000;
      current = 0;
      used = true;
    } else {
      break;
    }
    index++;
  }
  if (!used) {
    return null;
  }
  return (value: (total + current).toDouble(), nextIndex: index);
}

String _paymentModeFromText(String text) {
  if (text.contains('upi')) {
    return 'UPI';
  }
  if (text.contains('bank')) {
    return 'Bank';
  }
  if (text.contains('other')) {
    return 'Other';
  }
  return 'Cash';
}

String _supervisorFromAllocation(String text) {
  final toMatch = RegExp(r'\b(?:to|ko)\s+([a-z ]+)$').firstMatch(text);
  if (toMatch != null) {
    final cleaned = toMatch.group(1)!.replaceAll(RegExp(r'\bcash\b'), '');
    return _titleCase(cleaned.trim().isEmpty ? 'Supervisor' : cleaned);
  }
  final prefixMatch = RegExp(
    r'^([a-z ]+?)\s+(?:ko|ke liye)\s+',
  ).firstMatch(text);
  if (prefixMatch != null) {
    return _titleCase(prefixMatch.group(1)!);
  }
  return 'Supervisor';
}

String _supervisorFromExpense(String text) {
  final spentMatch = RegExp(
    r'^([a-z ]+?)\s+(?:spent|ne|paid|kharcha)',
  ).firstMatch(text);
  if (spentMatch != null) {
    return _titleCase(spentMatch.group(1)!);
  }
  return 'Supervisor';
}

String _categoryFromVoiceText(String text) {
  if (text.contains('scrap')) {
    return 'Scrap Purchase';
  }
  if (text.contains('other purchase')) {
    return 'Other Purchase';
  }
  if (text.contains('inventory')) {
    return 'Inventory Purchase';
  }
  if (text.contains('transport')) {
    return 'Transport Expense';
  }
  if (text.contains('loading') || text.contains('labour')) {
    return 'Loading Expense';
  }
  return 'Miscellaneous Expense';
}

String _titleCase(String value) {
  return value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
