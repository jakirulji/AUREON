import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'aureon_recovery_key_service.dart';

typedef AureonFirebaseIdTokenProvider = Future<String?> Function();

abstract interface class AureonVaultHttpTransport {
  Future<Map<String, Object?>> send({
    required String method,
    required Uri uri,
    required String idToken,
    Map<String, Object?>? body,
  });
}

class AureonHttpVaultTransport implements AureonVaultHttpTransport {
  AureonHttpVaultTransport({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  @override
  Future<Map<String, Object?>> send({
    required String method,
    required Uri uri,
    required String idToken,
    Map<String, Object?>? body,
  }) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError('AUREON Cloudflare API must use HTTPS.');
    }
    final request = await _client.openUrl(method, uri).timeout(const Duration(seconds: 20));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $idToken')
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close().timeout(const Duration(seconds: 45));
    final text = await response.transform(utf8.decoder).join();
    Map<String, Object?> decoded = <String, Object?>{};
    if (text.isNotEmpty) {
      final value = jsonDecode(text);
      if (value is! Map) throw const FormatException('Cloudflare API returned invalid JSON.');
      decoded = value.cast<String, Object?>();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded['message'];
      throw AureonCloudflareApiException(
        response.statusCode,
        message is String ? message : 'Cloudflare API request failed.',
      );
    }
    return decoded;
  }

  void close() => _client.close(force: true);
}

class AureonCloudflareApiException implements Exception {
  const AureonCloudflareApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'AUREON Cloudflare API ($statusCode): $message';
}

/// Authenticated HTTPS adapter. It only transports encrypted credential
/// records; provider file bytes and E2E file-content keys never enter this API.
class AureonCloudflareVaultClient {
  AureonCloudflareVaultClient({
    required String baseUrl,
    AureonVaultHttpTransport? transport,
  }) : _baseUri = _validateBaseUrl(baseUrl),
       _transport = transport ?? AureonHttpVaultTransport();

  final Uri _baseUri;
  final AureonVaultHttpTransport _transport;
  static const _sha256 = Sha256();

  static Uri _validateBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError('A valid HTTPS Cloudflare Worker base URL is required.');
    }
    return uri.replace(path: uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path);
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      _baseUri.replace(path: '${_baseUri.path}$path', queryParameters: query);

  Future<String> _token(AureonFirebaseIdTokenProvider provider) async {
    final token = await provider();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Sign in to AUREON and verify your email before cloud vault sync.');
    }
    return token;
  }

  Future<Map<String, Object?>> createCloudflareEnvelope({
    required String vaultId,
    required int generation,
    required List<int> dek,
    required AureonFirebaseIdTokenProvider idTokenProvider,
  }) async {
    if (dek.length != 32) throw ArgumentError('Vault DEK must be 256 bits.');
    final result = await _transport.send(
      method: 'POST',
      uri: _uri('/v1/vault/envelope'),
      idToken: await _token(idTokenProvider),
      body: {
        'vaultId': vaultId,
        'generation': generation,
        'dek': _encodeBase64Url(dek),
      },
    );
    final envelope = result['envelope'];
    if (envelope is! Map) throw const FormatException('Cloudflare did not return a vault envelope.');
    final parsed = envelope.cast<String, Object?>();
    if (parsed['formatVersion'] != 1 ||
        parsed['algorithm'] != 'HKDF-SHA-256/AES-256-GCM' ||
        parsed['rootKeyVersion'] is! int ||
        _decodeBase64Url(parsed['salt'], 32).length != 32 ||
        _decodeBase64Url(parsed['nonce'], 12).length != 12 ||
        _decodeBase64Url(parsed['cipherText'], 48).length != 48) {
      throw const FormatException('Cloudflare returned a malformed recovery envelope.');
    }
    return parsed;
  }

  Future<void> uploadSnapshot({
    required VaultRecoveryBundle bundle,
    required AureonFirebaseIdTokenProvider idTokenProvider,
  }) async {
    if (bundle.cloudflareEnvelope == null) {
      throw StateError('Provision the Cloudflare recovery envelope before uploading the vault snapshot.');
    }
    await _transport.send(
      method: 'PUT',
      uri: _uri('/v1/vault/snapshot'),
      idToken: await _token(idTokenProvider),
      body: bundle.toJson(),
    );
  }

  Future<VaultRecoveryBundle> fetchSnapshot({
    required String vaultId,
    required AureonFirebaseIdTokenProvider idTokenProvider,
  }) async {
    final result = await _transport.send(
      method: 'GET',
      uri: _uri('/v1/vault/snapshot', {'vaultId': vaultId}),
      idToken: await _token(idTokenProvider),
    );
    final raw = result['snapshot'];
    final expectedHash = result['snapshotSha256'];
    if (raw is! Map || expectedHash is! String) {
      throw const FormatException('Cloudflare snapshot response is incomplete.');
    }
    final canonical = utf8.encode(jsonEncode(raw));
    final digest = await _sha256.hash(canonical);
    final actualHash = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (actualHash != expectedHash) {
      throw const FormatException('Cloudflare snapshot integrity verification failed.');
    }
    return VaultRecoveryBundle.fromJson(raw.cast<String, Object?>());
  }

  static String _encodeBase64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List _decodeBase64Url(Object? value, int expectedLength) {
    if (value is! String || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const FormatException('Invalid Cloudflare envelope encoding.');
    }
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (bytes.length != expectedLength) {
      throw const FormatException('Invalid Cloudflare envelope field length.');
    }
    return Uint8List.fromList(bytes);
  }
}
