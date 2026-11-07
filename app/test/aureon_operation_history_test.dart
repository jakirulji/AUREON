import 'package:aureon/src/files/aureon_operation_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists successful and failed operations', () async {
    await AureonOperationHistory.record(kind: 'copy', itemName: 'notes.txt',
      sourceLocation: 'Documents', destinationLocation: 'Documents / notes-copy.txt', succeeded: true);
    await AureonOperationHistory.record(kind: 'trash', itemName: 'draft.pdf',
      sourceLocation: 'Documents', destinationLocation: 'AUREON Trash',
      succeeded: false, errorCode: 'provider_unsupported');
    final rows = await AureonOperationHistory.load();
    expect(rows, hasLength(2));
    expect(rows.first.kind, 'trash');
    expect(rows.first.succeeded, isFalse);
    expect(rows.first.errorCode, 'provider_unsupported');
    expect(rows.last.kind, 'copy');
  });

  test('keeps only the latest 250 operations', () async {
    for (var i = 0; i < 255; i++) {
      await AureonOperationHistory.record(kind: 'open', itemName: 'file-$i',
        sourceLocation: 'Documents', succeeded: true);
    }
    final rows = await AureonOperationHistory.load();
    expect(rows, hasLength(250));
    expect(rows.first.itemName, 'file-254');
    expect(rows.last.itemName, 'file-5');
  });

  test('clear removes history without touching folder bookmarks', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aureon.saved_local_root', 'bookmark');
    await AureonOperationHistory.record(kind: 'rename', itemName: 'a.txt',
      sourceLocation: 'Documents', destinationLocation: 'Documents / b.txt', succeeded: true);
    await AureonOperationHistory.clear();
    expect(await AureonOperationHistory.load(), isEmpty);
    expect(prefs.getString('aureon.saved_local_root'), 'bookmark');
  });
}
