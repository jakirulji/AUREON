import 'package:aureon/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Cloud navigation opens persistent virtual folders', (tester) async {
    await tester.view.setPhysicalSize(const Size(900, 900));
    await tester.view.setDevicePixelRatio(1);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AureonApp());
    await tester.tap(find.text('Cloud').first);
    await tester.pumpAndSettle();
    expect(find.text('Virtual folders'), findsOneWidget);
    expect(find.textContaining('live cloud account browsing'), findsOneWidget);

    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Research');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Research'), findsOneWidget);
  });
}
