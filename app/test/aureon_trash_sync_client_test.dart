import 'package:flutter_test/flutter_test.dart';
import 'package:aureon/src/files/aureon_trash_sync_client.dart';

class _FakeTransport implements AureonTrashHttpTransport {
  Map<String, Object?> response = {'items': <Object?>[]};
  String? method;
  Uri? uri;
  String? token;
  Map<String, Object?>? body;

  @override
  Future<Map<String, Object?>> send({
    required String method,
    required Uri uri,
    required String bearerToken,
    Map<String, Object?>? body,
  }) async {
    this.method = method;
    this.uri = uri;
    token = bearerToken;
    this.body = body;
    return response;
  }
}

void main() {
  test('lists provider-backed Trash with authenticated session and cursor', () async {
    final transport = _FakeTransport()
      ..response = {
        'items': [
          {
            'id': 'trash-1',
            'providerAccountId': 'account-1',
            'providerItemId': 'drive-file-1',
            'originalParentProviderItemId': 'folder-1',
            'trashMode': 'provider_native',
            'trashContainerProviderItemId': null,
            'status': 'trashed',
            'trashedAt': '2026-11-07T12:00:00Z',
            'restoredAt': null,
            'permanentlyDeletedAt': null,
            'rowVersion': 1,
          }
        ],
        'nextCursor': null,
      };
    final client = AureonTrashSyncClient(
      apiBase: Uri.parse('https://api.example.invalid'),
      sessionToken: () async => 'short-lived-session',
      transport: transport,
    );

    final items = await client.list(limit: 20);

    expect(items, hasLength(1));
    expect(items.single.providerItemId, 'drive-file-1');
    expect(transport.method, 'GET');
    expect(transport.token, 'short-lived-session');
    expect(transport.uri!.path, '/v1/trash/items');
    expect(transport.uri!.queryParameters['limit'], '20');
  });

  test('records provider Trash only after caller supplies provider outcome reference', () async {
    final transport = _FakeTransport();
    final client = AureonTrashSyncClient(
      apiBase: Uri.parse('https://api.example.invalid'),
      sessionToken: () async => 'session',
      transport: transport,
    );

    await client.recordProviderTrash(
      operationId: 'operation-1',
      deviceId: 'device-1',
      providerAccountId: 'account-1',
      providerItemId: 'file-1',
      trashMode: 'provider_native',
      providerOutcomeReference: 'provider-etag-1',
      originalParentProviderItemId: 'parent-1',
    );

    expect(transport.method, 'POST');
    expect(transport.uri!.path, '/v1/trash/items');
    expect(transport.body!['providerOutcomeReference'], 'provider-etag-1');
    expect(transport.body!['providerItemId'], 'file-1');
  });

  test('rejects non-HTTPS remote API base', () {
    expect(
      () => AureonTrashSyncClient(
        apiBase: Uri.parse('http://api.example.invalid'),
        sessionToken: () async => 'session',
        transport: _FakeTransport(),
      ),
      throwsArgumentError,
    );
  });

  test('does not call transport without an AUREON session', () async {
    final transport = _FakeTransport();
    final client = AureonTrashSyncClient(
      apiBase: Uri.parse('https://api.example.invalid'),
      sessionToken: () async => null,
      transport: transport,
    );

    await expectLater(client.list(), throwsStateError);
    expect(transport.method, isNull);
  });
}
