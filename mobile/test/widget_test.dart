import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bbmp_pending_poles/app/app.dart';


void main() {
  testWidgets('Luminex App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PoletraceApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2500));
    expect(tester.takeException(), isNull);
  });
}



