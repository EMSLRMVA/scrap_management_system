import 'business_models.dart';

class StockDateRange {
  const StockDateRange({required this.from, required this.to});

  factory StockDateRange.currentMonthToToday({DateTime? now}) {
    final anchor = _dateOnly(now ?? DateTime.now());
    return StockDateRange(
      from: DateTime(anchor.year, anchor.month),
      to: anchor,
    );
  }

  final DateTime from;
  final DateTime to;

  DateTime get start {
    final normalizedFrom = _dateOnly(from);
    final normalizedTo = _dateOnly(to);
    return normalizedTo.isBefore(normalizedFrom)
        ? normalizedTo
        : normalizedFrom;
  }

  DateTime get end {
    final normalizedFrom = _dateOnly(from);
    final normalizedTo = _dateOnly(to);
    return normalizedTo.isBefore(normalizedFrom)
        ? normalizedFrom
        : normalizedTo;
  }
}

class StockAnalysisResult {
  const StockAnalysisResult({
    required this.material,
    required this.from,
    required this.to,
    required this.monthOpeningQty,
    required this.purchaseQty,
    required this.saleQty,
    required this.physicalStock,
    required this.expectedStock,
    this.openingStock,
    this.physicalStockEntry,
  });

  final MaterialStock material;
  final DateTime from;
  final DateTime to;
  final double monthOpeningQty;
  final double purchaseQty;
  final double saleQty;
  final double physicalStock;
  final double expectedStock;
  final OpeningStockRecord? openingStock;
  final PhysicalStockRecord? physicalStockEntry;

  double get difference => physicalStock - expectedStock;
  double get weightLoss => difference < -0.01 ? difference.abs() : 0;
  double get weightIncrease => difference > 0.01 ? difference : 0;
  bool get isBalanced => weightLoss == 0 && weightIncrease == 0;
}

StockAnalysisResult buildStockAnalysis(
  BusinessState state,
  MaterialStock material, {
  DateTime? from,
  DateTime? to,
  DateTime? now,
}) {
  final defaultRange = StockDateRange.currentMonthToToday(now: now);
  final range = StockDateRange(
    from: from ?? defaultRange.from,
    to: to ?? defaultRange.to,
  );
  final start = range.start;
  final end = range.end;
  final opening = latestMonthOpeningStock(state, material, start);
  final monthOpeningQty = opening?.openingWeightKg ?? 0;
  final purchaseQty = purchaseQtyForRange(state, material, start, end);
  final saleQty = saleQtyForRange(state, material, start, end);
  final physicalEntry = latestPhysicalStockEntry(state, material, end);
  final hasPhysicalEntries = state.physicalStocks.any(
    (entry) =>
        stockMaterialMatches(entry.materialId, entry.materialName, material),
  );
  final physicalStock =
      physicalEntry?.quantityKg ??
      (hasPhysicalEntries ? 0 : material.availableKg);
  final expectedStock = monthOpeningQty + purchaseQty - saleQty;

  return StockAnalysisResult(
    material: material,
    from: start,
    to: end,
    monthOpeningQty: monthOpeningQty,
    purchaseQty: purchaseQty,
    saleQty: saleQty,
    physicalStock: physicalStock,
    expectedStock: expectedStock,
    openingStock: opening,
    physicalStockEntry: physicalEntry,
  );
}

List<StockAnalysisResult> buildStockAnalyses(
  BusinessState state, {
  DateTime? from,
  DateTime? to,
  DateTime? now,
}) {
  return [
    for (final material in state.activeMaterials)
      buildStockAnalysis(state, material, from: from, to: to, now: now),
  ];
}

OpeningStockRecord? latestMonthOpeningStock(
  BusinessState state,
  MaterialStock material,
  DateTime selectedMonth,
) {
  final month = DateTime(selectedMonth.year, selectedMonth.month);
  final records =
      state.openingStocks
          .where(
            (record) =>
                stockMaterialMatches(
                  record.materialId,
                  record.materialName,
                  material,
                ) &&
                record.date.year == month.year &&
                record.date.month == month.month,
          )
          .toList()
        ..sort(_newestOpeningFirst);
  return records.isEmpty ? null : records.first;
}

PhysicalStockRecord? latestPhysicalStockEntry(
  BusinessState state,
  MaterialStock material,
  DateTime rangeEnd,
) {
  final end = _dateOnly(rangeEnd);
  final entries =
      state.physicalStocks
          .where(
            (entry) =>
                stockMaterialMatches(
                  entry.materialId,
                  entry.materialName,
                  material,
                ) &&
                !_dateOnly(entry.entryDate).isAfter(end),
          )
          .toList()
        ..sort(_newestPhysicalFirst);
  return entries.isEmpty ? null : entries.first;
}

double purchaseQtyForRange(
  BusinessState state,
  MaterialStock material,
  DateTime from,
  DateTime to,
) {
  final range = StockDateRange(from: from, to: to);
  return state.activePurchases
      .where((purchase) => _withinInclusiveRange(purchase.createdAt, range))
      .fold<double>(
        0,
        (sum, purchase) => sum + purchaseQtyForRecord(purchase, material),
      );
}

double saleQtyForRange(
  BusinessState state,
  MaterialStock material,
  DateTime from,
  DateTime to,
) {
  final range = StockDateRange(from: from, to: to);
  return state.activeSales
      .where((sale) => _withinInclusiveRange(sale.createdAt, range))
      .fold<double>(0, (sum, sale) => sum + saleQtyForRecord(sale, material));
}

double purchaseQtyForRecord(PurchaseRecord purchase, MaterialStock material) {
  return purchase.items
      .where(
        (item) =>
            stockMaterialMatches(item.materialId, item.materialName, material),
      )
      .fold<double>(0, (sum, item) => sum + item.weightKg);
}

double saleQtyForRecord(SaleRecord sale, MaterialStock material) {
  return sale.items
      .where(
        (item) =>
            stockMaterialMatches(item.materialId, item.materialName, material),
      )
      .fold<double>(0, (sum, item) => sum + item.weightKg);
}

bool stockMaterialMatches(
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

int _newestOpeningFirst(OpeningStockRecord left, OpeningStockRecord right) {
  final leftUpdated = left.updatedAt ?? left.createdAt;
  final rightUpdated = right.updatedAt ?? right.createdAt;
  final updatedOrder = rightUpdated.compareTo(leftUpdated);
  if (updatedOrder != 0) {
    return updatedOrder;
  }
  return right.date.compareTo(left.date);
}

int _newestPhysicalFirst(PhysicalStockRecord left, PhysicalStockRecord right) {
  final dateOrder = right.entryDate.compareTo(left.entryDate);
  if (dateOrder != 0) {
    return dateOrder;
  }
  return right.createdAt.compareTo(left.createdAt);
}

bool _withinInclusiveRange(DateTime value, StockDateRange range) {
  final date = _dateOnly(value);
  return !date.isBefore(range.start) && !date.isAfter(range.end);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
