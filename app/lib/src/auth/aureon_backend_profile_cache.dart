import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'aureon_firebase_auth_service.dart';

class AureonBackendProfile {
  const AureonBackendProfile({required this.discoveryId, required this.firebaseApiKey,
    required this.firebaseProjectId, required this.firebaseAuthDomain, required this.firebaseAppId,
    required this.workerBaseUrl, required this.profileVersion, this.registered = true});
  final String discoveryId, firebaseApiKey, firebaseProjectId, firebaseAuthDomain, firebaseAppId, workerBaseUrl;
  final int profileVersion;
  final bool registered;

  AureonFirebaseAuthConfig get firebaseConfig => AureonFirebaseAuthConfig(
    apiKey: firebaseApiKey, projectId: firebaseProjectId, authDomain: firebaseAuthDomain, appId: firebaseAppId);

  Map<String, Object?> toJson() => {'discoveryId': discoveryId, 'firebaseApiKey': firebaseApiKey,
    'firebaseProjectId': firebaseProjectId, 'firebaseAuthDomain': firebaseAuthDomain,
    'firebaseAppId': firebaseAppId, 'workerBaseUrl': workerBaseUrl, 'profileVersion': profileVersion, 'registered': registered};

  factory AureonBackendProfile.fromJson(Map<String, Object?> json) {
    String field(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) throw FormatException('Backend profile field $key is missing.');
      return value.trim();
    }
    final id = field('discoveryId');
    if (id.length < 22 || id.length > 128 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Discovery ID has an invalid format.');
    }
    final worker = Uri.tryParse(field('workerBaseUrl'));
    if (worker == null || worker.scheme != 'https' || worker.host.isEmpty || worker.userInfo.isNotEmpty ||
        worker.query.isNotEmpty || worker.fragment.isNotEmpty || (worker.path.isNotEmpty && worker.path != '/')) {
      throw const FormatException('Cloudflare Worker URL must be a valid HTTPS base URL.');
    }
    final version = json['profileVersion'];
    final registered = json['registered'] != false;
    if (version is! int || version < 0 || (registered && version < 1)) throw const FormatException('Backend profile version is invalid.');
    return AureonBackendProfile(discoveryId: id, firebaseApiKey: field('firebaseApiKey'),
      firebaseProjectId: field('firebaseProjectId'), firebaseAuthDomain: field('firebaseAuthDomain'),
      firebaseAppId: field('firebaseAppId'), workerBaseUrl: worker.origin, profileVersion: version, registered: registered);
  }
}

/// Stores only public bootstrap configuration and survives local sign-out.
class AureonBackendProfileCache {
  static const _key = 'aureon.backend_profile.v1';
  Future<AureonBackendProfile?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return AureonBackendProfile.fromJson(decoded.cast<String, Object?>());
    } on FormatException { return null; } on TypeError { return null; }
  }
  Future<void> write(AureonBackendProfile profile) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_key, jsonEncode(profile.toJson()))) {
      throw StateError('Could not persist the AUREON backend profile.');
    }
  }
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}

class AureonDiscoveryRegistryException implements Exception {
  const AureonDiscoveryRegistryException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Used only for bootstrap. Normal app requests go directly to the user's Worker.
class AureonDiscoveryRegistryClient {
  AureonDiscoveryRegistryClient({
    String registryUrl = const String.fromEnvironment('AUREON_DISCOVERY_REGISTRY_URL'),
    HttpClient? httpClient, AureonBackendProfileCache? cache,
  }) : _registryUrl = registryUrl, _http = httpClient ?? HttpClient(),
       _cache = cache ?? AureonBackendProfileCache();
  final String _registryUrl;
  final HttpClient _http;
  final AureonBackendProfileCache _cache;

  void close() => _http.close(force: true);

  Uri _endpoint(String path) {
    final base = Uri.tryParse(_registryUrl);
    if (base == null || base.scheme != 'https' || base.host.isEmpty) {
      throw const AureonDiscoveryRegistryException('AUREON Discovery Registry is not configured in this build.');
    }
    return base.resolve(path);
  }

  Future<Map<String, Object?>> _post(String path, {required Map<String, Object?> body, String? idToken}) async {
    final request = await _http.postUrl(_endpoint(path)).timeout(const Duration(seconds: 15));
    request.headers..contentType = ContentType.json..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    if (idToken != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
      if (all.length + chunk.length > 32 * 1024) throw const FormatException('Discovery response exceeded the size limit.');
      return all..addAll(chunk);
    });
    final raw = utf8.decode(bytes);
    final decoded = raw.isEmpty ? <String, Object?>{} : jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Discovery returned invalid JSON.');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded['message'];
      throw AureonDiscoveryRegistryException(message is String ? message : 'Discovery request failed (${response.statusCode}).', response.statusCode);
    }
    return decoded.cast<String, Object?>();
  }

  Future<AureonBackendProfile> discover(String discoveryId) async {
    final id = discoveryId.trim();
    final result = await _post('/v1/profiles/lookup', body: {'discoveryId': id});
    final value = result['profile'];
    if (value is! Map) throw const FormatException('Discovery profile is missing.');
    final profile = AureonBackendProfile.fromJson(value.cast<String, Object?>());
    if (profile.discoveryId != id) throw const FormatException('Discovery returned a mismatched profile.');
    await _cache.write(profile);
    return profile;
  }

  Future<void> verifyBinding({required AureonFirebaseAuthService auth, required AureonBackendProfile profile}) async {
    final token = await auth.getIdToken(forceRefresh: true);
    final result = await _post('/v1/profiles/verify', idToken: token, body: {
      'discoveryId': profile.discoveryId,
      'firebaseProjectId': profile.firebaseProjectId,
    });
    if (result['bound'] != true) throw const AureonDiscoveryRegistryException('Master Account identity could not be verified.');
  }

  Future<AureonBackendProfile> register({required AureonFirebaseAuthService auth, required String discoveryId,
    required String workerBaseUrl, required String firebaseAuthDomain, required String firebaseAppId,
    int? expectedProfileVersion}) async {
    final config = auth.config;
    if (!config.isConfigured) throw StateError('Configure your Firebase project first.');
    final worker = Uri.tryParse(workerBaseUrl);
    if (worker == null || worker.scheme != 'https' || worker.host.isEmpty ||
        worker.userInfo.isNotEmpty || worker.query.isNotEmpty || worker.fragment.isNotEmpty ||
        (worker.path.isNotEmpty && worker.path != '/')) {
      throw const FormatException('Cloudflare Worker URL must be an HTTPS origin.');
    }
    final token = await auth.getIdToken(forceRefresh: true);
    final result = await _post('/v1/profiles', idToken: token, body: {
      'discoveryId': discoveryId, 'firebaseProjectId': config.projectId, 'firebaseApiKey': config.apiKey,
      'firebaseAuthDomain': firebaseAuthDomain, 'firebaseAppId': firebaseAppId, 'workerBaseUrl': worker.origin,
      'expectedProfileVersion': ?expectedProfileVersion,
    });
    final profile = AureonBackendProfile(discoveryId: discoveryId, firebaseApiKey: config.apiKey,
      firebaseProjectId: config.projectId, firebaseAuthDomain: firebaseAuthDomain, firebaseAppId: firebaseAppId,
      workerBaseUrl: worker.origin, profileVersion: result['profileVersion'] as int? ?? 1, registered: true);
    await _cache.write(profile);
    return profile;
  }

  static String generateDiscoveryId() => base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
}
