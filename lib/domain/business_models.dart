import '../core/money_format.dart';
import '../core/app_branding.dart';

double roundMoneyValue(num value) {
  final asDouble = value.toDouble();
  if (asDouble.isNaN || asDouble.isInfinite) {
    return 0;
  }
  return (asDouble * 100).roundToDouble() / 100;
}

enum UserRole { owner, admin, supervisor, manager, accountant, user }

extension UserRoleAccess on UserRole {
  bool get isOwnerOrAdmin => this == UserRole.owner;
  bool get isTimedEditor =>
      this == UserRole.manager || this == UserRole.supervisor;

  String get label {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.admin:
        return 'Admin';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.manager:
        return 'Manager';
      case UserRole.accountant:
        return 'Accountant';
      case UserRole.user:
        return 'User';
    }
  }
}

enum PartyKind { seller, customer }

enum StockReminderRole { supervisor, manager, owner, other }

enum StockReminderType {
  dailyStockTarget,
  physicalStockVerification,
  weightLossAlert,
  pendingPaymentAlert,
  all,
}

enum ManualReminderStatus {
  pendingManualSend,
  whatsappOpened,
  messageCopied,
  sentManually,
  cancelled,
}

class AppUser {
  const AppUser({
    required this.name,
    required this.company,
    required this.role,
    this.mobile = '',
    this.email = '',
  });

  final String name;
  final String company;
  final UserRole role;
  final String mobile;
  final String email;

  AppUser copyWith({
    String? name,
    String? company,
    UserRole? role,
    String? mobile,
    String? email,
  }) {
    return AppUser(
      name: name ?? this.name,
      company: company ?? this.company,
      role: role ?? this.role,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
    );
  }
}

class Party {
  const Party({
    required this.id,
    required this.name,
    required this.mobile,
    required this.kind,
    this.area = '',
    this.address = '',
    this.remarks = '',
    this.photoPath = '',
    this.pendingAmount = 0,
    this.lastPurchaseAt,
  });

  final String id;
  final String name;
  final String mobile;
  final PartyKind kind;
  final String area;
  final String address;
  final String remarks;
  final String photoPath;
  final double pendingAmount;
  final DateTime? lastPurchaseAt;

  Party copyWith({
    String? name,
    String? mobile,
    PartyKind? kind,
    String? area,
    String? address,
    String? remarks,
    String? photoPath,
    double? pendingAmount,
    DateTime? lastPurchaseAt,
  }) {
    return Party(
      id: id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      kind: kind ?? this.kind,
      area: area ?? this.area,
      address: address ?? this.address,
      remarks: remarks ?? this.remarks,
      photoPath: photoPath ?? this.photoPath,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      lastPurchaseAt: lastPurchaseAt ?? this.lastPurchaseAt,
    );
  }
}

class MaterialStock {
  const MaterialStock({
    required this.id,
    required this.name,
    required this.category,
    required this.availableKg,
    required this.currentBuyingRate,
    this.photoPath = '',
    this.currentSellingRate = 0,
    this.wastageDeductionPercent = 0,
    this.isActive = true,
    this.createdBy = 'System',
    this.updatedBy = '',
    this.deletedBy = '',
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.isDeleted = false,
  });

  final String id;
  final String name;
  final String category;
  final double availableKg;
  final double currentBuyingRate;
  final String photoPath;
  final double currentSellingRate;
  final double wastageDeductionPercent;
  final bool isActive;
  final String createdBy;
  final String updatedBy;
  final String deletedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final bool isDeleted;

  double get stockValue => availableKg * currentBuyingRate;
  double get normalizedWastageDeductionPercent =>
      wastageDeductionPercent.clamp(0, 100).toDouble();

  MaterialStock copyWith({
    String? name,
    String? category,
    double? availableKg,
    double? currentBuyingRate,
    String? photoPath,
    double? currentSellingRate,
    double? wastageDeductionPercent,
    bool? isActive,
    String? createdBy,
    String? updatedBy,
    String? deletedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    bool? isDeleted,
  }) {
    return MaterialStock(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      availableKg: availableKg ?? this.availableKg,
      currentBuyingRate: currentBuyingRate ?? this.currentBuyingRate,
      photoPath: photoPath ?? this.photoPath,
      currentSellingRate: currentSellingRate ?? this.currentSellingRate,
      wastageDeductionPercent:
          wastageDeductionPercent ?? this.wastageDeductionPercent,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      deletedBy: deletedBy ?? this.deletedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

class LineItem {
  const LineItem({
    required this.materialId,
    required this.materialName,
    required this.weightKg,
    required this.rate,
    this.materialPhotoPath = '',
    this.wastageDeductionPercent = 0,
    double? effectiveWeight,
    double? componentOriginalAmount,
    this.componentPreviousBalanceAdjustmentAmount = 0,
    this.componentSettlementAdjustmentAmount = 0,
    double? componentFinalAmount,
  }) : effectiveWeight = effectiveWeight ?? weightKg,
       _componentOriginalAmount = componentOriginalAmount,
       _componentFinalAmount = componentFinalAmount;

  final String materialId;
  final String materialName;
  final double weightKg;
  final double rate;
  final String materialPhotoPath;
  final double wastageDeductionPercent;
  final double effectiveWeight;
  final double? _componentOriginalAmount;
  final double componentPreviousBalanceAdjustmentAmount;
  final double componentSettlementAdjustmentAmount;
  final double? _componentFinalAmount;

  double get actualWeight => weightKg;
  double get componentOriginalAmount =>
      roundMoneyValue(_componentOriginalAmount ?? effectiveWeight * rate);
  double get componentAdjustmentAmount => roundMoneyValue(
    componentPreviousBalanceAdjustmentAmount +
        componentSettlementAdjustmentAmount,
  );
  double get componentFinalAmount => roundMoneyValue(
    _componentFinalAmount ??
        componentOriginalAmount + componentAdjustmentAmount,
  );
  double get amount => componentFinalAmount;

  LineItem copyWith({
    String? materialId,
    String? materialName,
    double? weightKg,
    double? rate,
    String? materialPhotoPath,
    double? wastageDeductionPercent,
    double? effectiveWeight,
    double? componentOriginalAmount,
    double? componentPreviousBalanceAdjustmentAmount,
    double? componentSettlementAdjustmentAmount,
    double? componentFinalAmount,
  }) {
    return LineItem(
      materialId: materialId ?? this.materialId,
      materialName: materialName ?? this.materialName,
      weightKg: weightKg ?? this.weightKg,
      rate: rate ?? this.rate,
      materialPhotoPath: materialPhotoPath ?? this.materialPhotoPath,
      wastageDeductionPercent:
          wastageDeductionPercent ?? this.wastageDeductionPercent,
      effectiveWeight: effectiveWeight ?? this.effectiveWeight,
      componentOriginalAmount:
          componentOriginalAmount ?? _componentOriginalAmount,
      componentPreviousBalanceAdjustmentAmount:
          componentPreviousBalanceAdjustmentAmount ??
          this.componentPreviousBalanceAdjustmentAmount,
      componentSettlementAdjustmentAmount:
          componentSettlementAdjustmentAmount ??
          this.componentSettlementAdjustmentAmount,
      componentFinalAmount: componentFinalAmount ?? _componentFinalAmount,
    );
  }
}

class PurchaseRecord {
  const PurchaseRecord({
    required this.id,
    required this.invoiceNumber,
    required this.seller,
    required this.items,
    required this.paidAmount,
    required this.createdAt,
    double? originalBillAmount,
    this.previousBalanceAppliedAmount = 0,
    this.previousBalanceReferenceIds = const [],
    this.currentSettlementAdjustmentAmount = 0,
    double? finalBillAmount,
    double? balanceAmount,
    String paymentStatus = '',
    this.settlementStatus = 'carry_forward',
    this.remarks = '',
    this.isDeleted = false,
    this.deletedAt,
    this.updatedAt,
    this.createdBy = 'System',
    this.updatedBy = '',
    this.deletedBy = '',
  }) : _originalBillAmount = originalBillAmount,
       _finalBillAmount = finalBillAmount,
       _balanceAmount = balanceAmount,
       _paymentStatus = paymentStatus;

  final String id;
  final String invoiceNumber;
  final Party seller;
  final List<LineItem> items;
  final double paidAmount;
  final double? _originalBillAmount;
  final double previousBalanceAppliedAmount;
  final List<String> previousBalanceReferenceIds;
  final double currentSettlementAdjustmentAmount;
  final double? _finalBillAmount;
  final double? _balanceAmount;
  final String _paymentStatus;
  final String settlementStatus;
  final DateTime createdAt;
  final String remarks;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime? updatedAt;
  final String createdBy;
  final String updatedBy;
  final String deletedBy;

  LineItem get item => items.isEmpty
      ? const LineItem(
          materialId: '',
          materialName: 'Material',
          weightKg: 0,
          rate: 0,
        )
      : items.first;

  double get lineOriginalAmount => roundMoneyValue(
    items.fold(0, (sum, item) => sum + item.componentOriginalAmount),
  );
  double get originalBillAmount =>
      roundMoneyValue(_originalBillAmount ?? lineOriginalAmount);
  double get finalBillAmount => roundMoneyValue(
    _finalBillAmount ??
        originalBillAmount +
            previousBalanceAppliedAmount +
            currentSettlementAdjustmentAmount,
  );
  double get totalAmount => finalBillAmount;
  double get balanceAmount =>
      roundMoneyValue(_balanceAmount ?? finalBillAmount - paidAmount);
  double get ledgerDelta => roundMoneyValue(
    originalBillAmount + currentSettlementAdjustmentAmount - paidAmount,
  );
  String get paymentStatus {
    if (_paymentStatus.trim().isNotEmpty) {
      return _paymentStatus;
    }
    if (balanceAmount.abs() <= 0.01) {
      return 'paid';
    }
    return balanceAmount > 0 ? 'pending' : 'advance';
  }

  bool get hasPreviousBalanceApplied =>
      previousBalanceAppliedAmount.abs() > 0.01;
  double get totalWeightKg => items.fold(0, (sum, item) => sum + item.weightKg);

  PurchaseRecord copyWith({
    Party? seller,
    List<LineItem>? items,
    double? paidAmount,
    double? originalBillAmount,
    double? previousBalanceAppliedAmount,
    List<String>? previousBalanceReferenceIds,
    double? currentSettlementAdjustmentAmount,
    double? finalBillAmount,
    double? balanceAmount,
    String? paymentStatus,
    String? settlementStatus,
    DateTime? createdAt,
    String? remarks,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
    String? deletedBy,
    bool clearDeletedBy = false,
  }) {
    return PurchaseRecord(
      id: id,
      invoiceNumber: invoiceNumber,
      seller: seller ?? this.seller,
      items: items ?? this.items,
      paidAmount: paidAmount ?? this.paidAmount,
      originalBillAmount: originalBillAmount ?? _originalBillAmount,
      previousBalanceAppliedAmount:
          previousBalanceAppliedAmount ?? this.previousBalanceAppliedAmount,
      previousBalanceReferenceIds:
          previousBalanceReferenceIds ?? this.previousBalanceReferenceIds,
      currentSettlementAdjustmentAmount:
          currentSettlementAdjustmentAmount ??
          this.currentSettlementAdjustmentAmount,
      finalBillAmount: finalBillAmount ?? _finalBillAmount,
      balanceAmount: balanceAmount ?? _balanceAmount,
      paymentStatus: paymentStatus ?? _paymentStatus,
      settlementStatus: settlementStatus ?? this.settlementStatus,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      deletedBy: clearDeletedBy ? '' : deletedBy ?? this.deletedBy,
    );
  }
}

enum SellerLedgerEntryType {
  purchaseBill,
  payment,
  previousBalanceApplied,
  settlementAdjustment,
  extraPaid,
  lessPaid,
  manualAdjustment,
}

extension SellerLedgerEntryTypeLabel on SellerLedgerEntryType {
  String get label {
    switch (this) {
      case SellerLedgerEntryType.purchaseBill:
        return 'PURCHASE_BILL';
      case SellerLedgerEntryType.payment:
        return 'PAYMENT';
      case SellerLedgerEntryType.previousBalanceApplied:
        return 'PREVIOUS_BALANCE_APPLIED';
      case SellerLedgerEntryType.settlementAdjustment:
        return 'SETTLEMENT_ADJUSTMENT';
      case SellerLedgerEntryType.extraPaid:
        return 'EXTRA_PAID';
      case SellerLedgerEntryType.lessPaid:
        return 'LESS_PAID';
      case SellerLedgerEntryType.manualAdjustment:
        return 'MANUAL_ADJUSTMENT';
    }
  }
}

class SellerBalanceReference {
  const SellerBalanceReference({
    required this.purchaseId,
    required this.invoiceNumber,
    required this.date,
    required this.originalBillAmount,
    required this.paidAmount,
    required this.balanceAmount,
  });

  final String purchaseId;
  final String invoiceNumber;
  final DateTime date;
  final double originalBillAmount;
  final double paidAmount;
  final double balanceAmount;

  String get actionLabel =>
      balanceAmount >= 0 ? 'Amount to Add' : 'Amount to Reduce';
}

class SellerLedgerEntry {
  const SellerLedgerEntry({
    required this.sellerId,
    required this.sellerName,
    required this.purchaseId,
    required this.invoiceNumber,
    required this.date,
    required this.type,
    required this.amount,
    required this.runningBalance,
    required this.description,
    this.referenceIds = const [],
  });

  final String sellerId;
  final String sellerName;
  final String purchaseId;
  final String invoiceNumber;
  final DateTime date;
  final SellerLedgerEntryType type;
  final double amount;
  final double runningBalance;
  final String description;
  final List<String> referenceIds;
}

class SaleRecord {
  const SaleRecord({
    required this.id,
    required this.invoiceNumber,
    required this.customer,
    required this.items,
    required this.receivedAmount,
    required this.createdAt,
    this.remarks = '',
    this.isDeleted = false,
    this.deletedAt,
    this.updatedAt,
    this.createdBy = 'System',
    this.updatedBy = '',
    this.deletedBy = '',
    this.reminderSentAt,
    this.reminderSentBy = '',
    this.paymentReceivedAt,
    this.paymentReceivedBy = '',
  });

  final String id;
  final String invoiceNumber;
  final Party customer;
  final List<LineItem> items;
  final double receivedAmount;
  final DateTime createdAt;
  final String remarks;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime? updatedAt;
  final String createdBy;
  final String updatedBy;
  final String deletedBy;
  final DateTime? reminderSentAt;
  final String reminderSentBy;
  final DateTime? paymentReceivedAt;
  final String paymentReceivedBy;

  LineItem get item => items.isEmpty
      ? const LineItem(
          materialId: '',
          materialName: 'Material',
          weightKg: 0,
          rate: 0,
        )
      : items.first;

  double get totalAmount => items.fold(0, (sum, item) => sum + item.amount);
  double get balanceAmount => totalAmount - receivedAmount;
  double get totalWeightKg => items.fold(0, (sum, item) => sum + item.weightKg);
  bool get isPaymentPending => balanceAmount > 0.01;
  bool get isPaymentReceived => !isPaymentPending;
  bool get reminderSent => reminderSentAt != null;

  SaleRecord copyWith({
    Party? customer,
    List<LineItem>? items,
    double? receivedAmount,
    DateTime? createdAt,
    String? remarks,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
    String? deletedBy,
    bool clearDeletedBy = false,
    DateTime? reminderSentAt,
    bool clearReminderSentAt = false,
    String? reminderSentBy,
    DateTime? paymentReceivedAt,
    bool clearPaymentReceivedAt = false,
    String? paymentReceivedBy,
  }) {
    return SaleRecord(
      id: id,
      invoiceNumber: invoiceNumber,
      customer: customer ?? this.customer,
      items: items ?? this.items,
      receivedAmount: receivedAmount ?? this.receivedAmount,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      deletedBy: clearDeletedBy ? '' : deletedBy ?? this.deletedBy,
      reminderSentAt: clearReminderSentAt
          ? null
          : reminderSentAt ?? this.reminderSentAt,
      reminderSentBy: reminderSentBy ?? this.reminderSentBy,
      paymentReceivedAt: clearPaymentReceivedAt
          ? null
          : paymentReceivedAt ?? this.paymentReceivedAt,
      paymentReceivedBy: paymentReceivedBy ?? this.paymentReceivedBy,
    );
  }
}

class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.category,
    required this.amount,
    required this.createdAt,
    this.expenseDate,
    this.vendorName = '',
    this.remarks = '',
    this.billUploadPath = '',
    this.photoPath = '',
    this.addedBy = 'System',
    this.updatedAt,
    this.updatedBy = '',
    this.deletedAt,
    this.deletedBy = '',
    this.isDeleted = false,
    this.isApproved = false,
  });

  final String id;
  final String category;
  final double amount;
  final DateTime createdAt;
  final DateTime? expenseDate;
  final String vendorName;
  final String remarks;
  final String billUploadPath;
  final String photoPath;
  final String addedBy;
  final DateTime? updatedAt;
  final String updatedBy;
  final DateTime? deletedAt;
  final String deletedBy;
  final bool isDeleted;
  final bool isApproved;

  DateTime get date => expenseDate ?? createdAt;

  ExpenseRecord copyWith({
    String? category,
    double? amount,
    DateTime? expenseDate,
    String? vendorName,
    String? remarks,
    String? billUploadPath,
    String? photoPath,
    String? addedBy,
    DateTime? updatedAt,
    String? updatedBy,
    DateTime? deletedAt,
    String? deletedBy,
    bool? isDeleted,
    bool? isApproved,
    bool clearDeletedAt = false,
  }) {
    return ExpenseRecord(
      id: id,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      createdAt: createdAt,
      expenseDate: expenseDate ?? this.expenseDate,
      vendorName: vendorName ?? this.vendorName,
      remarks: remarks ?? this.remarks,
      billUploadPath: billUploadPath ?? this.billUploadPath,
      photoPath: photoPath ?? this.photoPath,
      addedBy: addedBy ?? this.addedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      isDeleted: isDeleted ?? this.isDeleted,
      isApproved: isApproved ?? this.isApproved,
    );
  }
}

class CashAllocation {
  const CashAllocation({
    required this.id,
    required this.supervisorName,
    required this.amount,
    required this.createdAt,
    this.allocationDate,
    this.paymentMode = 'Cash',
    this.remarks = '',
    this.createdBy = 'Owner',
    this.updatedAt,
    this.updatedBy = '',
  });

  final String id;
  final String supervisorName;
  final double amount;
  final DateTime createdAt;
  final DateTime? allocationDate;
  final String paymentMode;
  final String remarks;
  final String createdBy;
  final DateTime? updatedAt;
  final String updatedBy;

  DateTime get date => allocationDate ?? createdAt;

  CashAllocation copyWith({
    String? supervisorName,
    double? amount,
    DateTime? allocationDate,
    String? paymentMode,
    String? remarks,
    String? createdBy,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return CashAllocation(
      id: id,
      supervisorName: supervisorName ?? this.supervisorName,
      amount: amount ?? this.amount,
      createdAt: createdAt,
      allocationDate: allocationDate ?? this.allocationDate,
      paymentMode: paymentMode ?? this.paymentMode,
      remarks: remarks ?? this.remarks,
      createdBy: createdBy ?? this.createdBy,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

class OpeningStockRecord {
  const OpeningStockRecord({
    required this.id,
    required this.materialId,
    required this.materialName,
    required this.openingWeightKg,
    required this.date,
    required this.createdBy,
    required this.createdAt,
    this.openingRate = 0,
    this.openingValue = 0,
    this.remarks = '',
    this.updatedBy = '',
    this.updatedAt,
  });

  final String id;
  final String materialId;
  final String materialName;
  final double openingWeightKg;
  final double openingRate;
  final double openingValue;
  final DateTime date;
  final String remarks;
  final String createdBy;
  final DateTime createdAt;
  final String updatedBy;
  final DateTime? updatedAt;

  OpeningStockRecord copyWith({
    String? materialId,
    String? materialName,
    double? openingWeightKg,
    double? openingRate,
    double? openingValue,
    DateTime? date,
    String? remarks,
    String? createdBy,
    DateTime? createdAt,
    String? updatedBy,
    DateTime? updatedAt,
  }) {
    return OpeningStockRecord(
      id: id,
      materialId: materialId ?? this.materialId,
      materialName: materialName ?? this.materialName,
      openingWeightKg: openingWeightKg ?? this.openingWeightKg,
      openingRate: openingRate ?? this.openingRate,
      openingValue: openingValue ?? this.openingValue,
      date: date ?? this.date,
      remarks: remarks ?? this.remarks,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class PhysicalStockRecord {
  const PhysicalStockRecord({
    required this.id,
    required this.materialId,
    required this.materialName,
    required this.quantityKg,
    required this.entryDate,
    required this.createdBy,
    required this.createdAt,
    this.reason = '',
  });

  final String id;
  final String materialId;
  final String materialName;
  final double quantityKg;
  final DateTime entryDate;
  final String reason;
  final String createdBy;
  final DateTime createdAt;

  PhysicalStockRecord copyWith({
    String? materialId,
    String? materialName,
    double? quantityKg,
    DateTime? entryDate,
    String? reason,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return PhysicalStockRecord(
      id: id,
      materialId: materialId ?? this.materialId,
      materialName: materialName ?? this.materialName,
      quantityKg: quantityKg ?? this.quantityKg,
      entryDate: entryDate ?? this.entryDate,
      reason: reason ?? this.reason,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class StockReminderReceiver {
  const StockReminderReceiver({
    required this.id,
    required this.receiverName,
    required this.role,
    required this.whatsAppNumber,
    required this.reminderHour,
    required this.reminderMinute,
    required this.reminderTypes,
    required this.createdAt,
    this.isActive = true,
    this.updatedAt,
  });

  final String id;
  final String receiverName;
  final StockReminderRole role;
  final String whatsAppNumber;
  final bool isActive;
  final int reminderHour;
  final int reminderMinute;
  final List<StockReminderType> reminderTypes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  String get timeKey =>
      '${reminderHour.toString().padLeft(2, '0')}:${reminderMinute.toString().padLeft(2, '0')}';

  bool accepts(StockReminderType type) {
    return reminderTypes.contains(StockReminderType.all) ||
        reminderTypes.contains(type);
  }

  StockReminderReceiver copyWith({
    String? receiverName,
    StockReminderRole? role,
    String? whatsAppNumber,
    bool? isActive,
    int? reminderHour,
    int? reminderMinute,
    List<StockReminderType>? reminderTypes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StockReminderReceiver(
      id: id,
      receiverName: receiverName ?? this.receiverName,
      role: role ?? this.role,
      whatsAppNumber: whatsAppNumber ?? this.whatsAppNumber,
      isActive: isActive ?? this.isActive,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      reminderTypes: reminderTypes ?? this.reminderTypes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ManualReminderLog {
  const ManualReminderLog({
    required this.reminderId,
    required this.receiverName,
    required this.receiverNumber,
    required this.role,
    required this.messageType,
    required this.messageContent,
    required this.status,
    required this.createdAt,
    this.openedAt,
    this.copiedAt,
  });

  final String reminderId;
  final String receiverName;
  final String receiverNumber;
  final StockReminderRole role;
  final StockReminderType messageType;
  final String messageContent;
  final ManualReminderStatus status;
  final DateTime? openedAt;
  final DateTime? copiedAt;
  final DateTime createdAt;

  ManualReminderLog copyWith({
    String? receiverName,
    String? receiverNumber,
    StockReminderRole? role,
    StockReminderType? messageType,
    String? messageContent,
    ManualReminderStatus? status,
    DateTime? openedAt,
    DateTime? copiedAt,
    DateTime? createdAt,
  }) {
    return ManualReminderLog(
      reminderId: reminderId,
      receiverName: receiverName ?? this.receiverName,
      receiverNumber: receiverNumber ?? this.receiverNumber,
      role: role ?? this.role,
      messageType: messageType ?? this.messageType,
      messageContent: messageContent ?? this.messageContent,
      status: status ?? this.status,
      openedAt: openedAt ?? this.openedAt,
      copiedAt: copiedAt ?? this.copiedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.recordType,
    required this.recordId,
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.user,
    required this.role,
    required this.createdAt,
    this.deviceInfo = '',
  });

  final String id;
  final String action;
  final String recordType;
  final String recordId;
  final String field;
  final String oldValue;
  final String newValue;
  final String user;
  final UserRole role;
  final DateTime createdAt;
  final String deviceInfo;
}

class ActivityRecord {
  const ActivityRecord({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    this.userName = 'System',
  });

  final String id;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final String userName;
}

class BusinessMetrics {
  const BusinessMetrics({
    required this.todayPurchase,
    required this.todaySales,
    required this.cashBalance,
    required this.stockValue,
    required this.cashGiven,
    required this.cashUsed,
    required this.salesCollection,
    required this.profitLoss,
    required this.pendingPayments,
    required this.totalExpense,
    required this.scrapPurchaseTotal,
    required this.otherPurchaseTotal,
    required this.inventoryPurchaseTotal,
    required this.adjustmentTotal,
  });

  final double todayPurchase;
  final double todaySales;
  final double cashBalance;
  final double stockValue;
  final double cashGiven;
  final double cashUsed;
  final double salesCollection;
  final double profitLoss;
  final double pendingPayments;
  final double totalExpense;
  final double scrapPurchaseTotal;
  final double otherPurchaseTotal;
  final double inventoryPurchaseTotal;
  final double adjustmentTotal;
}

class SupervisorBalanceSummary {
  const SupervisorBalanceSummary({
    required this.supervisorName,
    required this.cashAllocated,
    required this.expenseTotal,
    required this.scrapPurchaseTotal,
    required this.otherPurchaseTotal,
    required this.inventoryPurchaseTotal,
    required this.adjustmentTotal,
    required this.remainingBalance,
  });

  final String supervisorName;
  final double cashAllocated;
  final double expenseTotal;
  final double scrapPurchaseTotal;
  final double otherPurchaseTotal;
  final double inventoryPurchaseTotal;
  final double adjustmentTotal;
  final double remainingBalance;
}

class SupervisorCashSummary {
  const SupervisorCashSummary({
    required this.supervisorName,
    required this.openingBalance,
    required this.cashGivenByOwner,
    required this.scrapPurchaseUsed,
    required this.otherExpenses,
    required this.salesCollection,
    required this.currentCashBalance,
  });

  final String supervisorName;
  final double openingBalance;
  final double cashGivenByOwner;
  final double scrapPurchaseUsed;
  final double otherExpenses;
  final double salesCollection;
  final double currentCashBalance;
}

class SupervisorCashLedgerEntry {
  const SupervisorCashLedgerEntry({
    required this.date,
    required this.supervisorName,
    required this.activityType,
    required this.openingBalance,
    required this.cashGivenByOwner,
    required this.scrapPurchaseUsed,
    required this.otherExpenses,
    required this.salesCollection,
    required this.currentCashBalance,
    required this.details,
  });

  final DateTime date;
  final String supervisorName;
  final String activityType;
  final double openingBalance;
  final double cashGivenByOwner;
  final double scrapPurchaseUsed;
  final double otherExpenses;
  final double salesCollection;
  final double currentCashBalance;
  final String details;
}

class _SupervisorCashMovement {
  const _SupervisorCashMovement({
    required this.date,
    required this.supervisorName,
    required this.activityType,
    required this.cashGivenByOwner,
    required this.scrapPurchaseUsed,
    required this.otherExpenses,
    required this.salesCollection,
    required this.details,
  });

  final DateTime date;
  final String supervisorName;
  final String activityType;
  final double cashGivenByOwner;
  final double scrapPurchaseUsed;
  final double otherExpenses;
  final double salesCollection;
  final String details;
}

class BusinessState {
  const BusinessState({
    required this.user,
    required this.sellers,
    required this.customers,
    required this.materials,
    required this.purchases,
    required this.sales,
    required this.expenses,
    required this.cashAllocations,
    required this.openingStocks,
    required this.physicalStocks,
    required this.stockReminderReceivers,
    required this.manualReminderLogs,
    required this.auditTrail,
    required this.activities,
  });

  factory BusinessState.empty() {
    return const BusinessState(
      user: AppUser(
        name: 'Radha Rajput',
        mobile: '+919566092123',
        email: 'scrap.emslrmva@gmail.com',
        company: appDisplayName,
        role: UserRole.owner,
      ),
      sellers: [
        Party(
          id: 'seller-mohit-kumar',
          name: 'Mohit Kumar',
          mobile: '',
          area: 'Supervisor',
          kind: PartyKind.seller,
        ),
      ],
      customers: [],
      materials: [
        MaterialStock(
          id: 'coconut-shell',
          name: 'Coconut Shell',
          category: 'Agro Scrap',
          availableKg: 0,
          currentBuyingRate: 15,
          currentSellingRate: 18,
          wastageDeductionPercent: 0,
        ),
        MaterialStock(
          id: 'pet-bottle',
          name: 'PET Bottle',
          category: 'Plastic',
          availableKg: 0,
          currentBuyingRate: 20,
          currentSellingRate: 24,
          wastageDeductionPercent: 10,
        ),
        MaterialStock(
          id: 'cardboard',
          name: 'Cardboard',
          category: 'Paper',
          availableKg: 0,
          currentBuyingRate: 8,
          currentSellingRate: 12,
          wastageDeductionPercent: 5,
        ),
      ],
      purchases: [],
      sales: [],
      expenses: [],
      cashAllocations: [],
      openingStocks: [],
      physicalStocks: [],
      stockReminderReceivers: [],
      manualReminderLogs: [],
      auditTrail: [],
      activities: [],
    );
  }

  final AppUser user;
  final List<Party> sellers;
  final List<Party> customers;
  final List<MaterialStock> materials;
  final List<PurchaseRecord> purchases;
  final List<SaleRecord> sales;
  final List<ExpenseRecord> expenses;
  final List<CashAllocation> cashAllocations;
  final List<OpeningStockRecord> openingStocks;
  final List<PhysicalStockRecord> physicalStocks;
  final List<StockReminderReceiver> stockReminderReceivers;
  final List<ManualReminderLog> manualReminderLogs;
  final List<AuditEntry> auditTrail;
  final List<ActivityRecord> activities;

  List<PurchaseRecord> get activePurchases =>
      purchases.where((item) => !item.isDeleted).toList();
  List<PurchaseRecord> get deletedPurchases =>
      purchases.where((item) => item.isDeleted).toList();
  List<SaleRecord> get activeSales =>
      sales.where((item) => !item.isDeleted).toList();
  List<SaleRecord> get deletedSales =>
      sales.where((item) => item.isDeleted).toList();
  List<ExpenseRecord> get activeExpenses =>
      expenses.where((item) => !item.isDeleted).toList();
  List<ExpenseRecord> get deletedExpenses =>
      expenses.where((item) => item.isDeleted).toList();
  List<MaterialStock> get activeMaterials =>
      materials.where((item) => !item.isDeleted).toList();
  List<MaterialStock> get deletedMaterials =>
      materials.where((item) => item.isDeleted).toList();

  List<SellerBalanceReference> previousBalanceReferencesForSeller(
    String sellerId, {
    String? excludingPurchaseId,
  }) {
    final appliedByOtherPurchases = <String>{
      for (final purchase in activePurchases)
        if (purchase.id != excludingPurchaseId)
          ...purchase.previousBalanceReferenceIds,
    };
    final references = [
      for (final purchase in activePurchases)
        if (purchase.seller.id == sellerId &&
            purchase.id != excludingPurchaseId &&
            purchase.balanceAmount.abs() > 0.01 &&
            !appliedByOtherPurchases.contains(purchase.id))
          SellerBalanceReference(
            purchaseId: purchase.id,
            invoiceNumber: purchase.invoiceNumber,
            date: purchase.createdAt,
            originalBillAmount: purchase.originalBillAmount,
            paidAmount: purchase.paidAmount,
            balanceAmount: purchase.balanceAmount,
          ),
    ];
    references.sort((a, b) {
      final dateOrder = a.date.compareTo(b.date);
      if (dateOrder != 0) {
        return dateOrder;
      }
      return a.invoiceNumber.compareTo(b.invoiceNumber);
    });
    return references;
  }

  double previousBalanceTotalForSeller(
    String sellerId, {
    String? excludingPurchaseId,
  }) {
    return roundMoneyValue(
      previousBalanceReferencesForSeller(
        sellerId,
        excludingPurchaseId: excludingPurchaseId,
      ).fold<double>(0, (sum, item) => sum + item.balanceAmount),
    );
  }

  List<SellerLedgerEntry> get sellerLedgerEntries {
    final sellerIds = {
      for (final seller in sellers) seller.id,
      for (final purchase in activePurchases) purchase.seller.id,
    };
    final entries = <SellerLedgerEntry>[];
    for (final sellerId in sellerIds) {
      entries.addAll(sellerLedgerForSeller(sellerId));
    }
    return entries..sort((a, b) {
      final dateOrder = b.date.compareTo(a.date);
      if (dateOrder != 0) {
        return dateOrder;
      }
      return a.sellerName.compareTo(b.sellerName);
    });
  }

  List<SellerLedgerEntry> sellerLedgerForSeller(
    String sellerId, {
    String? excludingPurchaseId,
  }) {
    final sellerPurchases =
        activePurchases
            .where(
              (purchase) =>
                  purchase.seller.id == sellerId &&
                  purchase.id != excludingPurchaseId,
            )
            .toList()
          ..sort((a, b) {
            final dateOrder = a.createdAt.compareTo(b.createdAt);
            if (dateOrder != 0) {
              return dateOrder;
            }
            return a.invoiceNumber.compareTo(b.invoiceNumber);
          });

    var runningBalance = 0.0;
    final entries = <SellerLedgerEntry>[];
    for (final purchase in sellerPurchases) {
      void addEntry({
        required SellerLedgerEntryType type,
        required double amount,
        required String description,
        bool affectsBalance = true,
        List<String> referenceIds = const [],
      }) {
        if (affectsBalance) {
          runningBalance = roundMoneyValue(runningBalance + amount);
        }
        entries.add(
          SellerLedgerEntry(
            sellerId: purchase.seller.id,
            sellerName: purchase.seller.name,
            purchaseId: purchase.id,
            invoiceNumber: purchase.invoiceNumber,
            date: purchase.createdAt,
            type: type,
            amount: roundMoneyValue(amount),
            runningBalance: runningBalance,
            description: description,
            referenceIds: referenceIds,
          ),
        );
      }

      addEntry(
        type: SellerLedgerEntryType.purchaseBill,
        amount: purchase.originalBillAmount,
        description: 'Original bill ${purchase.invoiceNumber}',
      );
      if (purchase.previousBalanceAppliedAmount.abs() > 0.01) {
        addEntry(
          type: SellerLedgerEntryType.previousBalanceApplied,
          amount: purchase.previousBalanceAppliedAmount,
          description: 'Previous balance linked to ${purchase.invoiceNumber}',
          affectsBalance: false,
          referenceIds: purchase.previousBalanceReferenceIds,
        );
      }
      if (purchase.currentSettlementAdjustmentAmount.abs() > 0.01) {
        addEntry(
          type: SellerLedgerEntryType.settlementAdjustment,
          amount: purchase.currentSettlementAdjustmentAmount,
          description: 'Current bill settlement adjustment',
        );
      }
      if (purchase.paidAmount.abs() > 0.01) {
        addEntry(
          type: SellerLedgerEntryType.payment,
          amount: -purchase.paidAmount,
          description: 'Payment for ${purchase.invoiceNumber}',
        );
      }
      if (purchase.balanceAmount > 0.01) {
        addEntry(
          type: SellerLedgerEntryType.lessPaid,
          amount: purchase.balanceAmount,
          description: 'Balance carried forward',
          affectsBalance: false,
        );
      } else if (purchase.balanceAmount < -0.01) {
        addEntry(
          type: SellerLedgerEntryType.extraPaid,
          amount: purchase.balanceAmount,
          description: 'Advance carried forward',
          affectsBalance: false,
        );
      }
    }
    return entries;
  }

  double sellerNetBalanceFor(String sellerId, {String? excludingPurchaseId}) {
    final entries = sellerLedgerForSeller(
      sellerId,
      excludingPurchaseId: excludingPurchaseId,
    );
    if (entries.isNotEmpty) {
      return roundMoneyValue(entries.last.runningBalance);
    }
    final matching = sellers.where((seller) => seller.id == sellerId);
    return matching.isEmpty ? 0 : roundMoneyValue(matching.first.pendingAmount);
  }

  List<SupervisorBalanceSummary> get supervisorBalances {
    final names = <String>{
      for (final item in cashAllocations) item.supervisorName,
      for (final item in activeExpenses) item.addedBy,
      for (final item in activePurchases) item.createdBy,
    }..removeWhere((item) => item.trim().isEmpty);

    return [for (final name in names) _supervisorBalanceFor(name)]
      ..sort((a, b) => a.supervisorName.compareTo(b.supervisorName));
  }

  List<SupervisorCashSummary> get supervisorCashSummaries {
    return [
      for (final name in _supervisorCashNames())
        _supervisorCashSummaryFor(name),
    ]..sort((a, b) => a.supervisorName.compareTo(b.supervisorName));
  }

  List<SupervisorCashSummary> get visibleSupervisorCashSummaries {
    if (user.role.isOwnerOrAdmin) {
      return supervisorCashSummaries;
    }
    return supervisorCashSummaries
        .where((item) => _samePerson(item.supervisorName, user.name))
        .toList();
  }

  List<CashAllocation> get visibleCashAllocations {
    if (user.role.isOwnerOrAdmin) {
      return cashAllocations;
    }
    return cashAllocations
        .where((item) => _samePerson(item.supervisorName, user.name))
        .toList();
  }

  List<String> get cashAllocationStaffNames {
    final names = <String>{
      for (final item in cashAllocations) item.supervisorName.trim(),
      for (final item in activeExpenses) item.addedBy.trim(),
      for (final item in activePurchases) item.createdBy.trim(),
      for (final item in activeSales) item.createdBy.trim(),
      for (final item in sellers)
        if (_looksLikeStaffParty(item)) item.name.trim(),
      if (user.role == UserRole.supervisor || user.role == UserRole.manager)
        user.name.trim(),
    };
    names.removeWhere(
      (item) =>
          item.isEmpty ||
          item.toLowerCase() == 'system' ||
          item.toLowerCase() == 'owner',
    );
    if (names.isEmpty) {
      names.add('Mohit Kumar');
    }
    return names.toList()..sort((a, b) => a.compareTo(b));
  }

  List<SupervisorCashLedgerEntry> get supervisorCashLedgerEntries {
    final names = _supervisorCashNames();
    final movements = {
      for (final name in names) name: <_SupervisorCashMovement>[],
    };

    String supervisorKey(String value) {
      final cleaned = value.trim();
      return names.firstWhere(
        (name) => _samePerson(name, cleaned),
        orElse: () => cleaned,
      );
    }

    void addMovement(_SupervisorCashMovement movement) {
      final key = supervisorKey(movement.supervisorName);
      if (key.isEmpty) {
        return;
      }
      (movements[key] ??= []).add(movement);
    }

    for (final item in cashAllocations) {
      addMovement(
        _SupervisorCashMovement(
          date: item.date,
          supervisorName: item.supervisorName,
          activityType: 'Cash Given by Owner',
          cashGivenByOwner: item.amount,
          scrapPurchaseUsed: 0,
          otherExpenses: 0,
          salesCollection: 0,
          details: [
            item.paymentMode,
            if (item.remarks.trim().isNotEmpty) item.remarks.trim(),
          ].join(' | '),
        ),
      );
    }
    for (final item in activePurchases) {
      addMovement(
        _SupervisorCashMovement(
          date: item.createdAt,
          supervisorName: item.createdBy,
          activityType: 'Scrap Purchase Used',
          cashGivenByOwner: 0,
          scrapPurchaseUsed: item.totalAmount,
          otherExpenses: 0,
          salesCollection: 0,
          details: '${item.invoiceNumber} | ${item.seller.name}',
        ),
      );
    }
    for (final item in activeExpenses) {
      final scrapExpense = _isScrapPurchaseExpense(item.category);
      addMovement(
        _SupervisorCashMovement(
          date: item.date,
          supervisorName: item.addedBy,
          activityType: scrapExpense ? 'Scrap Purchase Used' : 'Other Expense',
          cashGivenByOwner: 0,
          scrapPurchaseUsed: scrapExpense ? item.amount : 0,
          otherExpenses: scrapExpense ? 0 : item.amount,
          salesCollection: 0,
          details: [
            item.category,
            if (item.vendorName.trim().isNotEmpty) item.vendorName.trim(),
            if (item.remarks.trim().isNotEmpty) item.remarks.trim(),
          ].join(' | '),
        ),
      );
    }
    for (final item in activeSales) {
      addMovement(
        _SupervisorCashMovement(
          date: item.createdAt,
          supervisorName: item.createdBy,
          activityType: 'Sales Collection',
          cashGivenByOwner: 0,
          scrapPurchaseUsed: 0,
          otherExpenses: 0,
          salesCollection: item.receivedAmount,
          details: '${item.invoiceNumber} | ${item.customer.name}',
        ),
      );
    }

    final entries = <SupervisorCashLedgerEntry>[];
    for (final entry in movements.entries) {
      final openingBalance = _openingBalanceFor(entry.key);
      var balance = openingBalance;
      final supervisorMovements = entry.value
        ..sort((a, b) {
          final dateOrder = a.date.compareTo(b.date);
          if (dateOrder != 0) {
            return dateOrder;
          }
          return a.activityType.compareTo(b.activityType);
        });
      for (final movement in supervisorMovements) {
        balance +=
            movement.cashGivenByOwner -
            movement.scrapPurchaseUsed -
            movement.otherExpenses;
        entries.add(
          SupervisorCashLedgerEntry(
            date: movement.date,
            supervisorName: entry.key,
            activityType: movement.activityType,
            openingBalance: openingBalance,
            cashGivenByOwner: movement.cashGivenByOwner,
            scrapPurchaseUsed: movement.scrapPurchaseUsed,
            otherExpenses: movement.otherExpenses,
            salesCollection: movement.salesCollection,
            currentCashBalance: balance,
            details: movement.details,
          ),
        );
      }
    }

    return entries..sort((a, b) {
      final dateOrder = b.date.compareTo(a.date);
      if (dateOrder != 0) {
        return dateOrder;
      }
      return a.supervisorName.compareTo(b.supervisorName);
    });
  }

  List<SupervisorCashLedgerEntry> get visibleSupervisorCashLedgerEntries {
    if (user.role.isOwnerOrAdmin) {
      return supervisorCashLedgerEntries;
    }
    return supervisorCashLedgerEntries
        .where(
          (item) =>
              _samePerson(item.supervisorName, user.name) &&
              item.activityType != 'Sales Collection',
        )
        .toList();
  }

  BusinessMetrics get metrics {
    final now = DateTime.now();
    bool isToday(DateTime date) =>
        date.year == now.year && date.month == now.month && date.day == now.day;

    final todayPurchase = activePurchases
        .where((item) => isToday(item.createdAt))
        .fold<double>(0, (sum, item) => sum + item.totalAmount);
    final todaySales = activeSales
        .where((item) => isToday(item.createdAt))
        .fold<double>(0, (sum, item) => sum + item.totalAmount);
    final cashGiven = cashAllocations.fold<double>(
      0,
      (sum, item) => sum + item.amount,
    );
    final inventoryPurchaseTotal = activePurchases.fold<double>(
      0,
      (sum, item) => sum + item.totalAmount,
    );
    final salesCollection = activeSales.fold<double>(
      0,
      (sum, item) => sum + item.receivedAmount,
    );
    final expensesTotal = activeExpenses.fold<double>(
      0,
      (sum, item) => sum + item.amount,
    );
    final scrapPurchaseTotal = _expenseTotalByCategory('scrap purchase');
    final otherPurchaseTotal = _expenseTotalByCategory('other purchase');
    final adjustmentTotal = _expenseTotalByCategory('adjustment');
    final cashUsed = inventoryPurchaseTotal + expensesTotal;
    final expectedSales = activeSales.fold<double>(
      0,
      (sum, item) => sum + item.totalAmount,
    );
    final stockProfitPotential = activeMaterials.fold<double>(
      0,
      (sum, item) =>
          sum +
          (item.availableKg *
              ((item.currentSellingRate == 0
                      ? item.currentBuyingRate
                      : item.currentSellingRate) -
                  item.currentBuyingRate)),
    );
    final sellerPending = sellers.fold<double>(
      0,
      (sum, item) => sum + sellerNetBalanceFor(item.id),
    );
    final customerPending = customers.fold<double>(
      0,
      (sum, item) => sum + item.pendingAmount,
    );

    return BusinessMetrics(
      todayPurchase: todayPurchase,
      todaySales: todaySales,
      cashGiven: cashGiven,
      cashUsed: cashUsed,
      salesCollection: salesCollection,
      cashBalance: cashGiven - cashUsed,
      stockValue: activeMaterials.fold(0, (sum, item) => sum + item.stockValue),
      profitLoss:
          expectedSales -
          inventoryPurchaseTotal -
          expensesTotal +
          stockProfitPotential,
      pendingPayments: sellerPending + customerPending,
      totalExpense: expensesTotal,
      scrapPurchaseTotal: scrapPurchaseTotal,
      otherPurchaseTotal: otherPurchaseTotal,
      inventoryPurchaseTotal: inventoryPurchaseTotal,
      adjustmentTotal: adjustmentTotal,
    );
  }

  Set<String> _supervisorCashNames() {
    String clean(String value) => value.trim();
    final names = <String>{
      for (final item in cashAllocations) clean(item.supervisorName),
      for (final item in activeExpenses) clean(item.addedBy),
      for (final item in activePurchases) clean(item.createdBy),
      for (final item in activeSales) clean(item.createdBy),
    }..removeWhere((item) => item.isEmpty);
    return names;
  }

  double _expenseTotalByCategory(String category) {
    final needle = category.toLowerCase();
    return activeExpenses
        .where((item) => item.category.toLowerCase().contains(needle))
        .fold<double>(0, (sum, item) => sum + item.amount);
  }

  SupervisorCashSummary _supervisorCashSummaryFor(String name) {
    final allocated = cashAllocations
        .where((item) => _samePerson(item.supervisorName, name))
        .fold<double>(0, (sum, item) => sum + item.amount);
    final personExpenses = activeExpenses.where(
      (item) => _samePerson(item.addedBy, name),
    );
    final scrapExpenseTotal = personExpenses
        .where((item) => _isScrapPurchaseExpense(item.category))
        .fold<double>(0, (sum, item) => sum + item.amount);
    final otherExpenses = personExpenses
        .where((item) => !_isScrapPurchaseExpense(item.category))
        .fold<double>(0, (sum, item) => sum + item.amount);
    final purchaseUsed = activePurchases
        .where((item) => _samePerson(item.createdBy, name))
        .fold<double>(0, (sum, item) => sum + item.totalAmount);
    final salesCollection = activeSales
        .where((item) => _samePerson(item.createdBy, name))
        .fold<double>(0, (sum, item) => sum + item.receivedAmount);
    final openingBalance = _openingBalanceFor(name);
    final scrapPurchaseUsed = purchaseUsed + scrapExpenseTotal;

    return SupervisorCashSummary(
      supervisorName: name,
      openingBalance: openingBalance,
      cashGivenByOwner: allocated,
      scrapPurchaseUsed: scrapPurchaseUsed,
      otherExpenses: otherExpenses,
      salesCollection: salesCollection,
      currentCashBalance:
          openingBalance + allocated - scrapPurchaseUsed - otherExpenses,
    );
  }

  SupervisorBalanceSummary _supervisorBalanceFor(String name) {
    final needle = name.toLowerCase();
    bool samePerson(String value) => value.toLowerCase() == needle;
    final allocated = cashAllocations
        .where((item) => samePerson(item.supervisorName))
        .fold<double>(0, (sum, item) => sum + item.amount);
    final personExpenses = activeExpenses.where(
      (item) => samePerson(item.addedBy),
    );
    final expenseTotal = personExpenses.fold<double>(
      0,
      (sum, item) => sum + item.amount,
    );
    final scrapTotal = personExpenses
        .where((item) => item.category.toLowerCase().contains('scrap purchase'))
        .fold<double>(0, (sum, item) => sum + item.amount);
    final otherTotal = personExpenses
        .where((item) => item.category.toLowerCase().contains('other purchase'))
        .fold<double>(0, (sum, item) => sum + item.amount);
    final adjustmentTotal = personExpenses
        .where((item) => item.category.toLowerCase().contains('adjustment'))
        .fold<double>(0, (sum, item) => sum + item.amount);
    final inventoryPurchaseTotal = activePurchases
        .where((item) => samePerson(item.createdBy))
        .fold<double>(0, (sum, item) => sum + item.totalAmount);

    return SupervisorBalanceSummary(
      supervisorName: name,
      cashAllocated: allocated,
      expenseTotal: expenseTotal,
      scrapPurchaseTotal: scrapTotal,
      otherPurchaseTotal: otherTotal,
      inventoryPurchaseTotal: inventoryPurchaseTotal,
      adjustmentTotal: adjustmentTotal,
      remainingBalance:
          allocated - expenseTotal - inventoryPurchaseTotal - adjustmentTotal,
    );
  }

  bool _samePerson(String left, String right) {
    return left.trim().toLowerCase() == right.trim().toLowerCase();
  }

  bool _looksLikeStaffParty(Party party) {
    final haystack = [
      party.name,
      party.area,
      party.remarks,
    ].join(' ').trim().toLowerCase();
    return haystack.contains('supervisor') ||
        haystack.contains('manager') ||
        party.area.trim().isEmpty;
  }

  bool _isScrapPurchaseExpense(String category) {
    return category.toLowerCase().contains('scrap purchase');
  }

  double _openingBalanceFor(String _) => 0;

  String get reportSummary {
    final metrics = this.metrics;
    final showSales = user.role.isOwnerOrAdmin;
    return [
      'Company: ${user.company}',
      'Owner: ${user.name}',
      'Today Purchase: ${money(metrics.todayPurchase)}',
      if (showSales) 'Today Sales: ${money(metrics.todaySales)}',
      'Cash Given: ${money(metrics.cashGiven)}',
      'Cash Used: ${money(metrics.cashUsed)}',
      'Total Expense: ${money(metrics.totalExpense)}',
      'Scrap Purchase Expense: ${money(metrics.scrapPurchaseTotal)}',
      'Other Purchase Expense: ${money(metrics.otherPurchaseTotal)}',
      'Inventory Purchase: ${money(metrics.inventoryPurchaseTotal)}',
      if (showSales) 'Sales Collection: ${money(metrics.salesCollection)}',
      'Cash Balance: ${money(metrics.cashBalance)}',
      if (showSales) 'Profit/Loss: ${money(metrics.profitLoss)}',
      'Pending Payments: ${money(metrics.pendingPayments)}',
      'Stock Value: ${money(metrics.stockValue)}',
      'Active Purchases: ${activePurchases.length}',
      if (showSales) 'Active Sales: ${activeSales.length}',
      'Deleted Purchases: ${deletedPurchases.length}',
      if (showSales) 'Deleted Sales: ${deletedSales.length}',
      'Sellers: ${sellers.length}',
      'Customers: ${customers.length}',
      'Audit Entries: ${auditTrail.length}',
    ].join('\n');
  }

  BusinessState copyWith({
    AppUser? user,
    List<Party>? sellers,
    List<Party>? customers,
    List<MaterialStock>? materials,
    List<PurchaseRecord>? purchases,
    List<SaleRecord>? sales,
    List<ExpenseRecord>? expenses,
    List<CashAllocation>? cashAllocations,
    List<OpeningStockRecord>? openingStocks,
    List<PhysicalStockRecord>? physicalStocks,
    List<StockReminderReceiver>? stockReminderReceivers,
    List<ManualReminderLog>? manualReminderLogs,
    List<AuditEntry>? auditTrail,
    List<ActivityRecord>? activities,
  }) {
    return BusinessState(
      user: user ?? this.user,
      sellers: sellers ?? this.sellers,
      customers: customers ?? this.customers,
      materials: materials ?? this.materials,
      purchases: purchases ?? this.purchases,
      sales: sales ?? this.sales,
      expenses: expenses ?? this.expenses,
      cashAllocations: cashAllocations ?? this.cashAllocations,
      openingStocks: openingStocks ?? this.openingStocks,
      physicalStocks: physicalStocks ?? this.physicalStocks,
      stockReminderReceivers:
          stockReminderReceivers ?? this.stockReminderReceivers,
      manualReminderLogs: manualReminderLogs ?? this.manualReminderLogs,
      auditTrail: auditTrail ?? this.auditTrail,
      activities: activities ?? this.activities,
    );
  }
}
