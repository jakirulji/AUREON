import 'package:aureon/src/cloud/aureon_google_drive_page.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements AureonDriveSlotTransport {
  Map<String, Object?> response = {'slots': <Object>[]};
  Map<String, Object?>? lastBody;
  String? lastMethod;

  @override
  Future<Map<String, Object?>> send({
    required String method,
    required Uri uri,
    required String idToken,
    Map<String, Object?>? body,
  }) async {
    expect(uri.scheme, 'https');
    expect(uri.path, '/v1/drive/slots');
    expect(idToken, 'firebase-id-token');
    lastMethod = method;
    lastBody = body;
    return response;
  }
}

void main() {
  test('restores named slots and never returns Google identities from the registry', () async {
    final transport = _FakeTransport()
      ..response = {
        'slots': [
          {'slotId': 'slot_123456789012345678', 'label': 'Personal Drive', 'sortOrder': 0},
        ],
      };
    final client = AureonDriveConnectionSlotClient(
      workerBaseUrl: 'https://example.workers.dev',
      idTokenProvider: () async => 'firebase-id-token',
      transport: transport,
    );
    final slots = await client.load();
    expect(slots.single.label, 'Personal Drive');
    expect(slots.single.slotId, 'slot_123456789012345678');
    expect(transport.lastMethod, 'GET');
    client.close();
  });

  test('sync payload contains only AUREON slot identifiers, user labels and order', () async {
    final transport = _FakeTransport();
    final client = AureonDriveConnectionSlotClient(
      workerBaseUrl: 'https://example.workers.dev',
      idTokenProvider: () async => 'firebase-id-token',
      transport: transport,
    );
    await client.replace([
      const AureonDriveConnectionSlot(
        slotId: 'slot_123456789012345678',
        label: 'Personal Drive',
        sortOrder: 9,
      ),
    ]);
    expect(transport.lastMethod, 'PUT');
    final body = transport.lastBody!;
    expect(body.keys, {'slots'});
    final slot = (body['slots'] as List).single as Map<String, Object?>;
    expect(slot.keys, {'slotId', 'label', 'sortOrder'});
    expect(slot['sortOrder'], 0);
    client.close();
  });

  test('rejects malformed slot IDs, labels and oversized registries', () async {
    final client = AureonDriveConnectionSlotClient(
      workerBaseUrl: 'https://example.workers.dev',
      idTokenProvider: () async => 'firebase-id-token',
      transport: _FakeTransport(),
    );
    await expectLater(client.replace([
      const AureonDriveConnectionSlot(slotId: 'bad', label: 'Personal', sortOrder: 0),
    ]), throwsArgumentError);
    await expectLater(client.replace(List.generate(21, (i) =>
      AureonDriveConnectionSlot(
        slotId: 'slot_${i.toString().padLeft(18, '0')}',
        label: 'Slot $i',
        sortOrder: i,
      ),
    )), throwsArgumentError);
    client.close();
  });
}
