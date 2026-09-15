import 'package:flutter_test/flutter_test.dart';
import 'package:bbmp_pending_poles/main.dart';

void main() {
  testWidgets('BBMP Pending Poles App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BbmpPendingPolesApp());
    expect(find.text('BBMP PENDING POLES'), findsOneWidget);
  });
}
