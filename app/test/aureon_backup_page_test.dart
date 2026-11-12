import 'package:aureon/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Settings opens recovery and independent metadata backup tools', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const AureonApp());
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup & Restore').first);
    await tester.pumpAndSettle();
    expect(find.text('Recovery & backups'), findsOneWidget);
    expect(find.text('Generate five recovery keys'), findsOneWidget);

    // The metadata section is below the vault and Cloudflare sections in a
    // lazy ListView. Scroll it into the viewport before asserting its actions.
    await tester.scrollUntilVisible(
      find.text('Create encrypted metadata backup'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Create encrypted metadata backup'), findsOneWidget);
    expect(find.text('Restore metadata backup'), findsOneWidget);
  });
}
