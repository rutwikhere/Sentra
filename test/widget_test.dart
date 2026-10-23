import 'package:flutter_test/flutter_test.dart';
import 'package:sentra/main.dart';

void main() {
  testWidgets('Sentra welcome screen smoke test', (WidgetTester tester) async {
    // Build Sentra app and trigger a frame
    await tester.pumpWidget(const SentraApp());

    // Verify title and create button
    expect(find.text('SENTRA'), findsOneWidget);
    expect(find.text('Create new song'), findsOneWidget);
  });
}
