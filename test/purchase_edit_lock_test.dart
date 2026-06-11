import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrap_management_system/domain/business_models.dart';
import 'package:scrap_management_system/presentation/business_controller.dart';

void main() {
  const seller = Party(
    id: 'seller',
    name: 'Seller',
    mobile: '',
    kind: PartyKind.seller,
  );

  PurchaseRecord purchaseCreated(Duration age) {
    return PurchaseRecord(
      id: 'purchase',
      invoiceNumber: 'PUR-1',
      seller: seller,
      items: const [
        LineItem(
          materialId: 'mat',
          materialName: 'Material',
          weightKg: 10,
          rate: 5,
        ),
      ],
      paidAmount: 0,
      createdAt: DateTime.now().subtract(age),
      createdBy: 'Supervisor',
    );
  }

  test(
    'supervisor purchase edit expires after one hour without affecting delete permission',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(businessProvider.notifier);
      notifier.setAuthenticatedUser(
        name: 'Supervisor',
        email: 'supervisor@example.com',
        role: UserRole.supervisor,
      );

      expect(
        notifier.canEditPurchase(purchaseCreated(const Duration(minutes: 59))),
        isTrue,
      );
      expect(
        notifier.canEditPurchase(purchaseCreated(const Duration(minutes: 61))),
        isFalse,
      );
      expect(
        notifier.purchaseEditExpiredMessage(
          purchaseCreated(const Duration(minutes: 61)),
        ),
        'Editing time expired. Purchase entry can be edited only within 1 hour.',
      );
      expect(
        notifier.canModifyPurchase(purchaseCreated(const Duration(days: 2))),
        isTrue,
      );
    },
  );

  test('owner can edit old purchase entries', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(businessProvider.notifier);
    notifier.setAuthenticatedUser(
      name: 'Owner',
      email: 'owner@example.com',
      role: UserRole.owner,
    );

    expect(
      notifier.canEditPurchase(purchaseCreated(const Duration(days: 10))),
      isTrue,
    );
  });
}
