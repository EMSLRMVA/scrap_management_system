import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrap_management_system/core/app_branding.dart';
import 'package:scrap_management_system/presentation/enterprise_app.dart';

void main() {
  Future<void> pumpAppShell(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EnterpriseShell())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('renders enterprise dashboard and bottom navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAppShell(tester);

    expect(find.text('Owner Dashboard'), findsOneWidget);
    expect(find.textContaining(appDisplayName), findsOneWidget);
    expect(find.text('Today Purchase'), findsOneWidget);
    expect(find.text('Expected Closing Stock'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Purchase'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
  });

  testWidgets('opens purchase module from bottom navigation', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAppShell(tester);

    await tester.tap(find.text('Purchase').last);
    await tester.pumpAndSettle();

    expect(find.text('Supplier bills and pending balances'), findsOneWidget);
    expect(find.text('No purchases saved'), findsOneWidget);
  });
}
