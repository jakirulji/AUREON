import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'aureon_metadata_backup.dart';

class AureonMetadataStore {
  static const storageKey = 'aureon.metadata.snapshot.v1';

  Future<AureonMetadataSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) {
      return AureonMetadataSnapshot(
        snapshotId: 'local-empty',
        generation: 0,
        createdAtEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Stored metadata snapshot is invalid.');
    return AureonMetadataSnapshot.fromJson(decoded.cast<String, Object?>());
  }

  Future<void> save(AureonMetadataSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(storageKey, jsonEncode(snapshot.toJson()))) {
      throw StateError('Could not persist AUREON metadata snapshot.');
    }
  }
}
