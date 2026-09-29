import 'package:flutter_test/flutter_test.dart';
import 'package:corda_app/main.dart';

void main() {
  testWidgets('Corda app bootstrap test', (WidgetTester tester) async {
    await tester.pumpWidget(const CordaApp());
    expect(find.text('CORDA'), findsWidgets);
  });
}
