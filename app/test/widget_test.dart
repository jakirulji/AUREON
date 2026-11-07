import 'dart:convert';

import 'package:aureon/main.dart';
import 'package:aureon/src/files/aureon_files_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('aureon/local_files');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('Files page browses a user-selected folder and saves bookmark', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickRoot') {
        return {
          'rootId': 'content://tree/root',
          'rootDocumentId': 'root-doc',
          'displayName': 'Documents',
        };
      }
      if (call.method == 'listChildren') {
        return [
          {'id': 'folder-1', 'name': 'Projects', 'isDirectory': true},
          {'id': 'file-1', 'name': 'notes.txt', 'isDirectory': false, 'sizeBytes': 42},
        ];
      }
      if (call.method == 'openFile') return true;
      if (call.method == 'createFolder') return 'folder-new';
      if (call.method == 'renameEntry') return 'renamed-id';
      return null;
    });

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AureonFilesPage())));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    final saved = jsonDecode(preferences.getString('aureon.saved_local_root')!);
    expect(saved['rootId'], 'content://tree/root');
    expect(saved['rootDocumentId'], 'root-doc');
  });

  testWidgets('Files page restores the previous folder bookmark', (tester) async {
    SharedPreferences.setMockInitialValues({
      'aureon.saved_local_root': jsonEncode({
        'rootId': 'content://tree/root',
        'rootDocumentId': 'root-doc',
        'displayName': 'Documents',
      }),
    });
    var listedParent = '';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listChildren') {
        listedParent = (call.arguments as Map)['parentId'] as String;
        return [
          {'id': 'file-1', 'name': 'restored.txt', 'isDirectory': false, 'sizeBytes': 12},
        ];
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AureonFilesPage())));
    await tester.pumpAndSettle();

    expect(listedParent, 'root-doc');
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('restored.txt'), findsOneWidget);
  });

  testWidgets('Files page filters and reveals hidden entries', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickRoot') {
        return {'rootId': 'root', 'rootDocumentId': 'root-doc', 'displayName': 'Home'};
      }
      if (call.method == 'listChildren') {
        return [
        {'id': 'z', 'name': 'zeta.txt', 'isDirectory': false, 'sizeBytes': 20, 'modifiedEpochMs': 1000},
        {'id': 'a', 'name': 'alpha.txt', 'isDirectory': false, 'sizeBytes': 80, 'modifiedEpochMs': 2000},
        {'id': 'h', 'name': '.secret', 'isDirectory': false, 'isHidden': true, 'sizeBytes': 1},
        ];
      }
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AureonFilesPage())));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.text('alpha.txt'), findsOneWidget);
    expect(find.text('zeta.txt'), findsOneWidget);
    expect(find.text('.secret'), findsNothing);
    await tester.tap(find.text('Show hidden'));
    await tester.pumpAndSettle();
    expect(find.text('.secret'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zeta');
    await tester.pumpAndSettle();
    expect(find.text('zeta.txt'), findsOneWidget);
    expect(find.text('alpha.txt'), findsNothing);
  });

  testWidgets('Files page creates a folder using the selected parent', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pickRoot') {
        return {'rootId': 'root', 'rootDocumentId': 'root-doc', 'displayName': 'Home'};
      }
      if (call.method == 'listChildren') return <Map<String, Object?>>[];
      if (call.method == 'createFolder') return 'new-folder-id';
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AureonFilesPage())));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Work');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final create = calls.firstWhere((call) => call.method == 'createFolder');
    expect(create.arguments, {'rootId': 'root', 'parentId': 'root-doc', 'name': 'Work'});
  });

  testWidgets('AUREON dashboard still renders', (tester) async {
    await tester.pumpWidget(const AureonApp());
    expect(find.text('AUREON'), findsOneWidget);
    expect(find.text('Storage overview'), findsOneWidget);
  });
}
