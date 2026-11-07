import 'dart:convert';

abstract interface class AureonTrashHttpTransport {
  Future<Map<String, Object?>> send({
    required String method,
    required Uri uri,
    required String bearerToken,
    Map<String, Object?>? body,
  });
}

class AureonTrashSyncConflict implements Exception {
  const AureonTrashSyncConflict(this.code);
  final String code;
  @override
  String toString() => 'Trash sync conflict: $code';
}

class AureonCloudTrashItem {
  const AureonCloudTrashItem({
    required this.id,
    required this.providerAccountId,
    required this.providerItemId,
    required this.status,
    required this.rowVersion,
    required this.trashedAt,
    this.originalParentProviderItemId,
    this.trashMode = 'provider_native',
    this.trashContainerProviderItemId,
  });

  final String id;
  final String providerAccountId;
  final String providerItemId;
  final String? originalParentProviderItemId;
  final String trashMode;
  final String? trashContainerProviderItemId;
  final String status;
  final int rowVersion;
  final DateTime trashedAt;

  factory AureonCloudTrashItem.fromJson(Map<String, Object?> json) =>
      AureonCloudTrashItem(
        id: json['id']! as String,
        providerAccountId: json['providerAccountId']! as String,
        providerItemId: json['providerItemId']! as String,
        originalParentProviderItemId: json['originalParentProviderItemId'] as String?,
        trashMode: json['trashMode']! as String,
        trashContainerProviderItemId: json['trashContainerProviderItemId'] as String?,
        status: json['status']! as String,
        rowVersion: json['rowVersion']! as int,
        trashedAt: DateTime.parse(json['trashedAt']! as String),
      );
}

class AureonTrashSyncClient {
  AureonTrashSyncClient({
    required Uri apiBase,
    required Future<String?> Function() sessionToken,
    required AureonTrashHttpTransport transport,
  })  : _apiBase = apiBase,
        _sessionToken = sessionToken,
        _transport = transport {
    if (apiBase.scheme != 'https' && apiBase.host != 'localhost' && apiBase.host != '127.0.0.1') {
      throw ArgumentError('AUREON Trash sync requires HTTPS.');
    }
  }

  final Uri _apiBase;
  final Future<String?> Function() _sessionToken;
  final AureonTrashHttpTransport _transport;

  Future<List<AureonCloudTrashItem>> list({int limit = 50, DateTime? before}) async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit');
    final query = <String, String>{'limit': '$limit'};
    if (before != null) query['before'] = before.toUtc().toIso8601String();
    final response = await _request('GET', _uri('/v1/trash/items', query));
    final items = response['items'];
    if (items is! List) throw const FormatException('Trash API returned an invalid page.');
    return items.map((item) => AureonCloudTrashItem.fromJson(
      Map<String, Object?>.from(item as Map),
    )).toList(growable: false);
  }

  /// Call only after the provider adapter confirms that the cloud object is trashed.
  Future<Map<String, Object?>> recordProviderTrash({
    required String operationId,
    required String deviceId,
    required String providerAccountId,
    required String providerItemId,
    required String trashMode,
    required String providerOutcomeReference,
    String? originalParentProviderItemId,
    String? trashContainerProviderItemId,
  }) =>
      _request('POST', _uri('/v1/trash/items'), body: {
        'operationId': operationId,
        'deviceId': deviceId,
        'providerAccountId': providerAccountId,
        'providerItemId': providerItemId,
        'originalParentProviderItemId': originalParentProviderItemId,
        'trashMode': trashMode,
        'trashContainerProviderItemId': trashContainerProviderItemId,
        'providerOutcomeReference': providerOutcomeReference,
      });

  /// Call only after the provider adapter confirms restore or permanent deletion.
  Future<Map<String, Object?>> transition({
    required String trashItemId,
    required String operationId,
    required String deviceId,
    required int expectedRowVersion,
    required String providerOutcomeReference,
    required bool permanentlyDelete,
  }) =>
      _request(
        'POST',
        _uri('/v1/trash/items/$trashItemId/\${permanentlyDelete ? 'purge' : 'restore'}'),
        body: {
          'operationId': operationId,
          'deviceId': deviceId,
          'expectedRowVersion': expectedRowVersion,
          'providerOutcomeReference': providerOutcomeReference,
        },
      );

  Uri _uri(String path, [Map<String, String>? query]) =>
      _apiBase.resolve(path).replace(queryParameters: query);

  Future<Map<String, Object?>> _request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final token = await _sessionToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to AUREON before syncing cloud Trash.');
    }
    return _transport.send(
      method: method,
      uri: uri,
      bearerToken: token,
      body: body,
    );
  }
}
