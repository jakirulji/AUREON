import 'package:aureon/main.dart';
import 'package:aureon/src/files/aureon_files_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 const channel=MethodChannel('aureon/local_files');
 tearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null));
 testWidgets('Files page browses a user-selected folder', (tester) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
   if(call.method=='pickRoot') {
    return {'rootId':'content://tree/root','rootDocumentId':'root-doc','displayName':'Documents'};
   }
   if(call.method=='listChildren') {
    return [
     {'id':'folder-1','name':'Projects','isDirectory':true},
     {'id':'file-1','name':'notes.txt','isDirectory':false,'sizeBytes':42}
    ];
   }
   return null;
  });
  await tester.pumpWidget(const MaterialApp(home:AureonFilesPage()));
  await tester.tap(find.byType(OutlinedButton));await tester.pumpAndSettle();
  expect(find.text('Documents'),findsOneWidget);
  expect(find.text('Projects'),findsOneWidget);
  expect(find.text('notes.txt'),findsOneWidget);
 });
 testWidgets('AUREON dashboard still renders',(tester) async{
  await tester.pumpWidget(const AureonApp());
  expect(find.text('AUREON'),findsOneWidget);
  expect(find.text('Storage overview'),findsOneWidget);
 });
}
