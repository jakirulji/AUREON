import 'dart:convert';
import 'dart:math';

import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local durable metadata store. It never performs provider mutations.
/// Cloud sync/backup adapters can implement the same serialized contract later.
class AureonVirtualFolderStore {
  static const storageKey = 'aureon.virtual_folders.v1';

  Future<List<AureonVirtualFolder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Virtual folder catalog is invalid.');
    return decoded.map((value) {
      if (value is! Map) throw const FormatException('Virtual folder entry is invalid.');
      return AureonVirtualFolder.fromJson(value.cast<String, Object?>());
    }).toList();
  }

  Future<void> save(List<AureonVirtualFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(folders.map((folder) => folder.toJson()).toList());
    if (!await prefs.setString(storageKey, encoded)) {
      throw StateError('Could not persist AUREON virtual folders.');
    }
  }

  Future<AureonVirtualFolder> create(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError.value(name, 'name', 'Folder name is required.');
    final folders = await load();
    if (folders.any((folder) => folder.name.toLowerCase() == clean.toLowerCase())) {
      throw StateError('A virtual folder with this name already exists.');
    }
    final folder = AureonVirtualFolder(
      id: _newId(),
      name: clean,
      createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    await save([...folders, folder]);
    return folder;
  }

  Future<void> addItem(String folderId, ProviderFileReference file) async {
    final folders = await load();
    final index = folders.indexWhere((folder) => folder.id == folderId);
    if (index < 0) throw StateError('Virtual folder no longer exists.');
    final updated = [...folders];
    updated[index] = updated[index].add(file);
    await save(updated);
  }

  Future<void> removeItem(String folderId, String stableKey) async {
    final folders = await load();
    final index = folders.indexWhere((folder) => folder.id == folderId);
    if (index < 0) throw StateError('Virtual folder no longer exists.');
    final updated = [...folders];
    updated[index] = updated[index].remove(stableKey);
    await save(updated);
  }

  Future<void> delete(String folderId) async {
    final folders = await load();
    await save(folders.where((folder) => folder.id != folderId).toList());
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
