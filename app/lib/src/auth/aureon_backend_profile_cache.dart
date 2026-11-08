import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'aureon_firebase_auth_service.dart';

/// Public bootstrap data for one user's own Firebase and Cloudflare backend.
/// This is configuration, not an authentication credential.
class AureonBackendProfile {
  const AureonBackendProfile({
    required this.discoveryId,
    required this.firebaseApiKey,
    required this.firebaseProjectId,
    required this.firebaseAuthDomain,
    required this.firebaseAppId,
    required this.workerBaseUrl,
    required this.profileVersion,
  });

  final String discoveryId;
  final String firebaseApiKey;
  final String firebaseProjectId;
  final String firebaseAuthDomain;
  final String firebaseAppId;
  final String workerBaseUrl;
  final int profileVersion;

  AureonFirebaseAuthConfig get firebaseConfig => AureonFirebaseAuthConfig(
        apiKey: firebaseApiKey,
        projectId: firebaseProjectId,
        authDomain: firebaseAuthDomain,
        appId: firebaseAppId,
      );

  Map<String, Object?> toJson() => {
        'discoveryId': discoveryId,
        'firebaseApiKey': firebaseApiKey,
        'firebaseProjectId': firebaseProjectId,
        'firebaseAuthDomain': firebaseAuthDomain,
        'firebaseAppId': firebaseAppId,
        'workerBaseUrl': workerBaseUrl,
        'profileVersion': profileVersion,
      };

  factory AureonBackendProfile.fromJson(Map<String, Object?> json) {
    String field(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Backend profile field $key is missing.');
      }
      return value.trim();
    }

    final discoveryId = field('discoveryId');
    if (discoveryId.length < 22 || discoveryId.length > 128) {
      throw const FormatException('Discovery ID has an invalid length.');
    }
    final worker = Uri.tryParse(field('workerBaseUrl'));
    if (worker == null ||
        worker.scheme != 'https' ||
        worker.host.isEmpty ||
        worker.userInfo.isNotEmpty ||
        worker.query.isNotEmpty ||
        worker.fragment.isNotEmpty) {
      throw const FormatException('Cloudflare Worker URL must be a valid HTTPS base URL.');
    }
    final version = json['profileVersion'];
    if (version is! int || version < 1) {
      throw const FormatException('Backend profile version is invalid.');
    }
    return AureonBackendProfile(
      discoveryId: discoveryId,
      firebaseApiKey: field('firebaseApiKey'),
      firebaseProjectId: field('firebaseProjectId'),
      firebaseAuthDomain: field('firebaseAuthDomain'),
      firebaseAppId: field('firebaseAppId'),
      workerBaseUrl: worker.toString().replaceFirst(RegExp(r'/+$'), ''),
      profileVersion: version,
    );
  }
}

/// Persists only public bootstrap configuration. It deliberately survives
/// Master Account sign-out so the next sign-in does not need discovery again.
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
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> write(AureonBackendProfile profile) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_key, jsonEncode(profile.toJson()));
    if (!saved) throw StateError('Could not persist the AUREON backend profile.');
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}
