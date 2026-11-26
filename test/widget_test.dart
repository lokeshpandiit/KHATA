import 'package:flutter_test/flutter_test.dart';

import 'package:khata/main.dart';

void main() {
  testWidgets('KHATA has all three navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const KhataApp());

    expect(find.text('HISAB'), findsWidgets);
    expect(find.text('KHET'), findsOneWidget);
    expect(find.text('DOCUMENTS'), findsOneWidget);
  });
}
