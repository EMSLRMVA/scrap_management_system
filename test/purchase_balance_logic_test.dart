import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrap_management_system/domain/business_models.dart';
import 'package:scrap_management_system/presentation/business_controller.dart';

void main() {
  late ProviderContainer container;
  late BusinessController notifier;
  late Party seller;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(businessProvider.notifier);
    seller = container.read(businessProvider).sellers.first;
  });

  tearDown(() => container.dispose());

  List<LineItem> billItems() {
    return const [
      LineItem(materialId: 'a', materialName: 'A', weightKg: 300, rate: 10),
      LineItem(materialId: 'b', materialName: 'B', weightKg: 150, rate: 10),
    ];
  }

  test('opening and saving unchanged edit keeps the saved original bill', () {
    final purchase = notifier.addPurchase(
      seller: seller,
      items: billItems(),
      paidAmount: 0,
    );

    final edited = notifier.editPurchase(
      original: purchase,
      seller: purchase.seller,
      items: purchase.items,
      paidAmount: purchase.paidAmount,
      originalBillAmount: purchase.originalBillAmount,
    );

    expect(edited.originalBillAmount, 4500);
    expect(edited.finalBillAmount, 4500);
    expect(edited.balanceAmount, 4500);
  });

  test('previous extra paid reduces next bill only when applied', () {
    final previous = notifier.addPurchase(
      seller: seller,
      items: billItems(),
      paidAmount: 4502,
    );
    final currentSeller = notifier.state.sellers.firstWhere(
      (item) => item.id == seller.id,
    );

    final current = notifier.addPurchase(
      seller: currentSeller,
      items: billItems(),
      paidAmount: 4498,
      previousBalanceAppliedAmount: -2,
      previousBalanceReferenceIds: [previous.id],
    );

    expect(previous.balanceAmount, -2);
    expect(current.finalBillAmount, 4498);
    expect(current.balanceAmount, 0);
    expect(notifier.state.sellerNetBalanceFor(seller.id), 0);
  });

  test('previous less paid increases next bill only when applied', () {
    final previous = notifier.addPurchase(
      seller: seller,
      items: billItems(),
      paidAmount: 4498,
    );
    final currentSeller = notifier.state.sellers.firstWhere(
      (item) => item.id == seller.id,
    );

    final current = notifier.addPurchase(
      seller: currentSeller,
      items: billItems(),
      paidAmount: 4502,
      previousBalanceAppliedAmount: 2,
      previousBalanceReferenceIds: [previous.id],
    );

    expect(previous.balanceAmount, 2);
    expect(current.finalBillAmount, 4502);
    expect(current.balanceAmount, 0);
    expect(notifier.state.sellerNetBalanceFor(seller.id), 0);
  });

  test('previous balance kept for later remains in seller ledger', () {
    notifier.addPurchase(seller: seller, items: billItems(), paidAmount: 4498);
    final currentSeller = notifier.state.sellers.firstWhere(
      (item) => item.id == seller.id,
    );

    final current = notifier.addPurchase(
      seller: currentSeller,
      items: billItems(),
      paidAmount: 0,
    );

    expect(current.finalBillAmount, 4500);
    expect(notifier.state.sellerNetBalanceFor(seller.id), 4502);
  });

  test(
    'component adjustment is proportional and totals exactly match final',
    () {
      final purchase = notifier.addPurchase(
        seller: seller,
        items: billItems(),
        paidAmount: 4498,
        previousBalanceAppliedAmount: -2,
        previousBalanceReferenceIds: const ['old'],
      );

      expect(purchase.items[0].componentPreviousBalanceAdjustmentAmount, -1.33);
      expect(purchase.items[1].componentPreviousBalanceAdjustmentAmount, -0.67);
      expect(purchase.items[0].componentFinalAmount, 2998.67);
      expect(purchase.items[1].componentFinalAmount, 1499.33);
      expect(
        purchase.items.fold<double>(0, (sum, item) => sum + item.amount),
        purchase.finalBillAmount,
      );
    },
  );

  test('current bill settlement clears small underpayment', () {
    final purchase = notifier.addPurchase(
      seller: seller,
      items: billItems(),
      paidAmount: 4499,
      currentSettlementAdjustmentAmount: -1,
      settlementStatus: 'settled_current_difference',
    );

    expect(purchase.finalBillAmount, 4499);
    expect(purchase.balanceAmount, 0);
    expect(notifier.state.sellerNetBalanceFor(seller.id), 0);
  });

  test('applied previous reference is not offered again', () {
    final previous = notifier.addPurchase(
      seller: seller,
      items: billItems(),
      paidAmount: 4498,
    );
    final currentSeller = notifier.state.sellers.firstWhere(
      (item) => item.id == seller.id,
    );
    notifier.addPurchase(
      seller: currentSeller,
      items: billItems(),
      paidAmount: 0,
      previousBalanceAppliedAmount: 2,
      previousBalanceReferenceIds: [previous.id],
    );

    final references = notifier.state.previousBalanceReferencesForSeller(
      seller.id,
    );

    expect(
      references.map((item) => item.purchaseId),
      isNot(contains(previous.id)),
    );
  });
}
