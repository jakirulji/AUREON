import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// A user-owned Firebase + Cloudflare Worker configuration. This record must
/// never contain service-account keys, Worker Secrets or access tokens.
class AureonBackendProfile {
  static const shared = AureonBackendProfile(
    id: 'aureon-central',
    name: 'AUREON Central',
    firebaseApiKey: 'AIzaSyB11qyg0gcZME2lzmwz8PHUufYJ1kVHh-4',
    firebaseProjectId: 'aureon-7f612',
    workerBaseUrl: 'https://aureon-api.jakirul220851.workers.dev',
  );

  const AureonBackendProfile({
    required this.id, required this.name, required this.firebaseApiKey,
    required this.firebaseProjectId, required this.workerBaseUrl,
    this.boundUid, this.boundIssuer, this.boundWorkerIdentity,
  });
  final String id, name, firebaseApiKey, firebaseProjectId, workerBaseUrl;
  final String? boundUid, boundIssuer, boundWorkerIdentity;

  String get firebaseIssuer => 'https://securetoken.google.com/$firebaseProjectId';
  String get workerIdentity {
    final uri = Uri.parse(workerBaseUrl);
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path == '/' ? '' : uri.path}';
  }

  bool get isBound => boundUid != null &&
      boundIssuer == firebaseIssuer && boundWorkerIdentity == workerIdentity;

  AureonBackendProfile bindToUid(String uid) {
    final normalized = uid.trim();
    if (normalized.isEmpty) throw ArgumentError('A Firebase UID is required.');
    if (boundUid != null && (boundUid != normalized ||
        boundIssuer != firebaseIssuer || boundWorkerIdentity != workerIdentity)) {
      throw StateError('This backend profile is already bound to a different Master Account identity. Create a separate profile for another account.');
    }
    return AureonBackendProfile(
      id: id, name: name, firebaseApiKey: firebaseApiKey,
      firebaseProjectId: firebaseProjectId, workerBaseUrl: workerBaseUrl,
      boundUid: normalized, boundIssuer: firebaseIssuer,
      boundWorkerIdentity: workerIdentity,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id, 'name': name, 'firebaseApiKey': firebaseApiKey,
    'firebaseProjectId': firebaseProjectId, 'workerBaseUrl': workerBaseUrl,
    'boundUid': boundUid, 'boundIssuer': boundIssuer,
    'boundWorkerIdentity': boundWorkerIdentity,
  };

  factory AureonBackendProfile.fromJson(Map<String, Object?> json) {
    final profile = AureonBackendProfile(
      id: _required(json, 'id'), name: _required(json, 'name'),
      firebaseApiKey: _required(json, 'firebaseApiKey'),
      firebaseProjectId: _required(json, 'firebaseProjectId'),
      workerBaseUrl: _required(json, 'workerBaseUrl'),
      boundUid: json['boundUid'] as String?,
      boundIssuer: json['boundIssuer'] as String?,
      boundWorkerIdentity: json['boundWorkerIdentity'] as String?,
    );
    profile.validate();
    final bindingParts = [profile.boundUid, profile.boundIssuer, profile.boundWorkerIdentity];
    if (bindingParts.any((part) => part != null) && bindingParts.any((part) => part == null)) {
      throw const FormatException('Backend profile identity binding is incomplete.');
    }
    if (profile.boundUid != null && !profile.isBound) {
      throw const FormatException('Backend profile identity binding is inconsistent.');
    }
    return profile;
  }

  void validate() {
    if (id.trim().isEmpty || name.trim().isEmpty || name.trim().length > 48) {
      throw ArgumentError('Give the backend profile a name between 1 and 48 characters.');
    }
    if (firebaseApiKey.trim().isEmpty ||
        !RegExp(r'^[a-z0-9][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(firebaseProjectId)) {
      throw ArgumentError('A valid Firebase API key and project ID are required.');
    }
    final uri = Uri.tryParse(workerBaseUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError('Cloudflare Worker URL must be a valid HTTPS base URL without credentials, query or fragment.');
    }
  }

  static String _required(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Backend profile field $key is required.');
    }
    return value;
  }
}

/// Device-local profile registry; no shared/developer-hosted backend is used.
class AureonBackendProfileStore {
  AureonBackendProfileStore({SharedPreferences? preferences})
      : _providedPreferences = preferences;
  static const _profilesKey = 'aureon.backend_profiles.v1';
  static const _activeKey = 'aureon.backend_profile.active.v1';
  static final _random = Random.secure();
  final SharedPreferences? _providedPreferences;
  Future<SharedPreferences> get _preferences async =>
      _providedPreferences ?? SharedPreferences.getInstance();

  Future<List<AureonBackendProfile>> listProfiles() async {
    final raw = (await _preferences).getString(_profilesKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Saved backend profile registry is invalid.');
    return decoded.map((value) {
      if (value is! Map) throw const FormatException('Saved backend profile entry is invalid.');
      return AureonBackendProfile.fromJson(value.cast<String, Object?>());
    }).toList(growable: false);
  }

  Future<AureonBackendProfile> saveProfile({
    required String name, required String firebaseApiKey,
    required String firebaseProjectId, required String workerBaseUrl,
  }) async {
    final profiles = (await listProfiles()).toList();
    final profile = AureonBackendProfile(
      id: _newId(), name: name.trim(), firebaseApiKey: firebaseApiKey.trim(),
      firebaseProjectId: firebaseProjectId.trim(),
      workerBaseUrl: workerBaseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
    );
    profile.validate();
    profiles.add(profile);
    await _writeProfiles(profiles);
    await activateProfile(profile.id);
    return profile;
  }

  Future<AureonBackendProfile?> activeProfile() async {
    final prefs = await _preferences;
    final id = prefs.getString(_activeKey);
    if (id == null) return null;
    for (final profile in await listProfiles()) {
      if (profile.id == id) return profile;
    }
    throw const FormatException('The active backend profile no longer exists.');
  }

  Future<void> activateProfile(String id) async {
    if (!(await listProfiles()).any((profile) => profile.id == id)) {
      throw StateError('Backend profile does not exist.');
    }
    await (await _preferences).setString(_activeKey, id);
  }

  Future<AureonBackendProfile> bindActiveProfile(String uid) async {
    final active = await activeProfile();
    if (active == null) throw StateError('Add and activate your own backend profile first.');
    final bound = active.bindToUid(uid);
    final profiles = (await listProfiles()).toList();
    final index = profiles.indexWhere((profile) => profile.id == active.id);
    profiles[index] = bound;
    await _writeProfiles(profiles);
    return bound;
  }

  Future<void> _writeProfiles(List<AureonBackendProfile> profiles) async {
    await (await _preferences).setString(_profilesKey,
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()));
  }

  String _newId() => base64Url.encode(
    List<int>.generate(16, (_) => _random.nextInt(256)),
  ).replaceAll('=', '');
}
