import 'package:aureon/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AUREON preview shell renders prototype state', (tester) async {
    await tester.pumpWidget(const AureonApp());
    expect(find.text('AUREON'), findsOneWidget);
    expect(find.text('Storage overview'), findsOneWidget);
    expect(find.textContaining('Sample data only'), findsOneWidget);
  });
}
