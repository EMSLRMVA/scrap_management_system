import 'package:flutter_test/flutter_test.dart';
import 'package:scrap_management_system/domain/business_models.dart';
import 'package:scrap_management_system/domain/stock_calculation.dart';

void main() {
  final material = MaterialStock(
    id: 'al-wire',
    name: 'Alluminium wire',
    category: 'Metal',
    availableKg: 0,
    currentBuyingRate: 10,
    createdAt: DateTime(2026, 1),
  );
  const seller = Party(
    id: 'seller',
    name: 'Seller',
    mobile: '',
    kind: PartyKind.seller,
  );
  const customer = Party(
    id: 'customer',
    name: 'Customer',
    mobile: '',
    kind: PartyKind.customer,
  );

  BusinessState stockState({required double physicalStock}) {
    return BusinessState.empty().copyWith(
      materials: [material.copyWith(availableKg: physicalStock)],
      openingStocks: [
        OpeningStockRecord(
          id: 'opening-jan',
          materialId: material.id,
          materialName: material.name,
          openingWeightKg: 100,
          date: DateTime(2026, 1, 1),
          createdBy: 'Owner',
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
      physicalStocks: [
        PhysicalStockRecord(
          id: 'physical-jan',
          materialId: material.id,
          materialName: material.name,
          quantityKg: physicalStock,
          entryDate: DateTime(2026, 1, 15),
          createdBy: 'Owner',
          createdAt: DateTime(2026, 1, 15),
        ),
      ],
      purchases: [
        PurchaseRecord(
          id: 'purchase-jan',
          invoiceNumber: 'PUR-1',
          seller: seller,
          items: [_line(50)],
          paidAmount: 0,
          createdAt: DateTime(2026, 1, 10),
        ),
      ],
      sales: [
        SaleRecord(
          id: 'sale-jan',
          invoiceNumber: 'SALE-1',
          customer: customer,
          items: [_line(30)],
          receivedAmount: 0,
          createdAt: DateTime(2026, 1, 12),
        ),
      ],
    );
  }

  test('calculates requested loss, increase, and balanced examples', () {
    final cases = [
      (physical: 110.0, loss: 10.0, increase: 0.0, balanced: false),
      (physical: 130.0, loss: 0.0, increase: 10.0, balanced: false),
      (physical: 120.0, loss: 0.0, increase: 0.0, balanced: true),
    ];

    for (final item in cases) {
      final result = buildStockAnalysis(
        stockState(physicalStock: item.physical),
        material,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(result.monthOpeningQty, 100);
      expect(result.purchaseQty, 50);
      expect(result.saleQty, 30);
      expect(result.expectedStock, 120);
      expect(result.physicalStock, item.physical);
      expect(result.weightLoss, item.loss);
      expect(result.weightIncrease, item.increase);
      expect(result.isBalanced, item.balanced);
    }
  });

  test(
    'uses selected month opening and selected date range transactions only',
    () {
      final state = stockState(physicalStock: 150).copyWith(
        openingStocks: [
          OpeningStockRecord(
            id: 'opening-feb-newer',
            materialId: material.id,
            materialName: material.name,
            openingWeightKg: 200,
            date: DateTime(2026, 2, 1),
            createdBy: 'Owner',
            createdAt: DateTime(2026, 2, 2),
          ),
          OpeningStockRecord(
            id: 'opening-feb-older',
            materialId: material.id,
            materialName: material.name,
            openingWeightKg: 999,
            date: DateTime(2026, 2, 1),
            createdBy: 'Owner',
            createdAt: DateTime(2026, 2, 1),
          ),
          OpeningStockRecord(
            id: 'opening-jan',
            materialId: material.id,
            materialName: material.name,
            openingWeightKg: 100,
            date: DateTime(2026, 1, 1),
            createdBy: 'Owner',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        physicalStocks: [
          PhysicalStockRecord(
            id: 'physical-feb',
            materialId: material.id,
            materialName: material.name,
            quantityKg: 150,
            entryDate: DateTime(2026, 2, 20),
            createdBy: 'Owner',
            createdAt: DateTime(2026, 2, 20),
          ),
        ],
        purchases: [
          PurchaseRecord(
            id: 'purchase-in-range',
            invoiceNumber: 'PUR-2',
            seller: seller,
            items: [_line(25)],
            paidAmount: 0,
            createdAt: DateTime(2026, 2, 10),
          ),
          PurchaseRecord(
            id: 'purchase-outside-range',
            invoiceNumber: 'PUR-3',
            seller: seller,
            items: [_line(1000)],
            paidAmount: 0,
            createdAt: DateTime(2026, 1, 10),
          ),
        ],
        sales: [
          SaleRecord(
            id: 'sale-in-range',
            invoiceNumber: 'SALE-2',
            customer: customer,
            items: [_line(5)],
            receivedAmount: 0,
            createdAt: DateTime(2026, 2, 12),
          ),
          SaleRecord(
            id: 'sale-outside-range',
            invoiceNumber: 'SALE-3',
            customer: customer,
            items: [_line(1000)],
            receivedAmount: 0,
            createdAt: DateTime(2026, 1, 12),
          ),
        ],
      );

      final result = buildStockAnalysis(
        state,
        material,
        from: DateTime(2026, 2, 1),
        to: DateTime(2026, 2, 28),
      );

      expect(result.monthOpeningQty, 200);
      expect(result.purchaseQty, 25);
      expect(result.saleQty, 5);
      expect(result.expectedStock, 220);
      expect(result.physicalStock, 150);
      expect(result.weightLoss, 70);
    },
  );
}

LineItem _line(double kg) {
  return LineItem(
    materialId: 'al-wire',
    materialName: 'Alluminium wire',
    weightKg: kg,
    rate: 10,
  );
}
