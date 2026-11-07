import 'dart:convert';
import 'package:aureon_local_files/aureon_local_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _FileSort { name, largest, newest, type }
class AureonFilesPage extends StatefulWidget {
  const AureonFilesPage({super.key});
  @override
  State<AureonFilesPage> createState() => _AureonFilesPageState();
}
class _Folder {
  const _Folder(this.name, this.id);
  final String name;
  final String id;
}
class _AureonFilesPageState extends State<AureonFilesPage> {
  static const _savedRootKey = 'aureon.saved_local_root';
  final _files = AureonLocalFiles();
  final _searchController = TextEditingController();
  AureonLocalRoot? _root;
  final List<_Folder> _levels = [];
  List<AureonLocalEntry> _entries = [];
  bool _loading = false;
  bool _showHidden = false;
  String? _error;
  _FileSort _sort = _FileSort.name;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _restoreRoot();
  }
  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  Future<void> _restoreRoot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_savedRootKey);
      if (saved == null) return;
      final decoded = jsonDecode(saved);
      if (decoded is! Map) throw const FormatException('Saved folder bookmark is invalid.');
      final root = AureonLocalRoot.fromMap(decoded.cast<Object?, Object?>());
      if (!mounted) return;
      setState(() { _root = root; _levels..clear()..add(_Folder(root.displayName, root.rootDocumentId)); });
      await _load();
    } catch (error) { _fail('Could not restore the previous folder. Choose it again. $error'); }
  }

  Future<void> _choose() async {
    setState(() { _loading = true; _error = null; });
    try {
      final root = await _files.pickRoot();
      if (!mounted) return;
      if (root == null) { setState(() => _loading = false); return; }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savedRootKey, jsonEncode({
        'rootId': root.rootId, 'displayName': root.displayName, 'rootDocumentId': root.rootDocumentId,
      }));
      if (!mounted) return;
      setState(() {
        _root = root;
        _levels..clear()..add(_Folder(root.displayName, root.rootDocumentId));
        _entries = [];
        _searchController.clear();
      });
      await _load();
    } on PlatformException catch (error) { _fail(error.message ?? error.code); }
    catch (error) { _fail(error.toString()); }
  }

  Future<void> _load() async {
    final root = _root;
    if (root == null || _levels.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _files.listChildren(root: root, parentId: _levels.last.id);
      if (!mounted) return;
      setState(() { _entries = rows; _loading = false; });
    } on PlatformException catch (error) {
      _fail(switch (error.code) {
        'permission_denied' => 'Folder permission was revoked. Re-select the folder to restore access.',
        'invalid_root' => 'The selected drive or folder is unavailable. Reconnect the drive or choose another folder.',
        'not_a_directory' => 'This folder no longer exists. Return to the parent folder or choose another folder.',
        _ => error.message ?? error.code,
      });
    } catch (error) { _fail(error.toString()); }
  }

  Future<void> _createFolder() async {
    final root = _root;
    if (root == null || _levels.isEmpty) return;
    final name = await _nameDialog('New folder', 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    try {
      await _files.createFolder(root: root, parentId: _levels.last.id, name: name.trim());
      await _load();
    } on PlatformException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? error.code)));
    }
  }

  Future<void> _rename(AureonLocalEntry entry) async {
    final root = _root;
    if (root == null) return;
    final name = await _nameDialog('Rename', 'New name', initial: entry.name);
    if (name == null || name.trim().isEmpty || name.trim() == entry.name) return;
    try {
      await _files.renameEntry(root: root, entryId: entry.id, newName: name.trim());
      await _load();
    } on PlatformException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? error.code)));
    }
  }

  Future<String?> _nameDialog(String title, String label, {String initial = ''}) async {
    var draft = initial;
    return showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(title),
      content: TextFormField(initialValue: initial, autofocus: true,
        decoration: InputDecoration(labelText: label), onChanged: (value) => draft = value,
        onFieldSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(draft), child: const Text('Save')),
      ],
    ));
  }

  Future<void> _openFile(AureonLocalEntry entry) async {
    final root = _root;
    if (root == null || entry.isDirectory) return;
    try {
      await _files.openFile(root: root, fileId: entry.id);
    } on PlatformException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? 'Unable to open this file.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _open(AureonLocalEntry entry) async {
    if (!entry.isDirectory) return;
    setState(() { _levels.add(_Folder(entry.name, entry.id)); _entries = []; _searchController.clear(); });
    await _load();
  }
  Future<void> _up() async {
    if (_levels.length < 2) return;
    setState(() { _levels.removeLast(); _entries = []; _searchController.clear(); });
    await _load();
  }
  void _fail(String message) {
    if (!mounted) return;
    setState(() { _error = message; _loading = false; });
  }
  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
  List<AureonLocalEntry> get _visibleEntries {
    final q = _searchController.text.trim().toLowerCase();
    final rows = _entries.where((e) => (_showHidden || !e.isHidden) &&
      (q.isEmpty || e.name.toLowerCase().contains(q))).toList();
    rows.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      switch (_sort) {
        case _FileSort.name: return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _FileSort.largest: return (b.sizeBytes ?? -1).compareTo(a.sizeBytes ?? -1);
        case _FileSort.newest: return (b.modifiedEpochMs ?? -1).compareTo(a.modifiedEpochMs ?? -1);
        case _FileSort.type:
          final c = _ext(a.name).compareTo(_ext(b.name));
          return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
    return rows;
  }
  String _size(int? n) {
    if (n == null) return '—';
    if (n < 1024) return '$n B';
    if (n < 1048576) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1073741824) return '${(n / 1048576).toStringAsFixed(1)} MB';
    return '${(n / 1073741824).toStringAsFixed(2)} GB';
  }
  String _modified(int? ms) {
    if (ms == null || ms <= 0) return 'Modified time unavailable';
    final date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final local = MaterialLocalizations.of(context);
    return 'Modified ${local.formatShortDate(date)} ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleEntries;
    return Padding(padding: const EdgeInsets.all(22), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Files', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700))),
          OutlinedButton.icon(onPressed: _loading ? null : _choose,
            icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Choose folder')),
        ]),
        const SizedBox(height: 8),
        const Text('Local folder operations are explicit. AUREON never overwrites or deletes files automatically.',
          style: TextStyle(color: Color(0xFF9AA8BD), fontSize: 12)),
        if (_root != null) ...[
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: _loading ? null : _createFolder,
            icon: const Icon(Icons.create_new_folder_outlined), label: const Text('New folder'))),
          Row(children: [
            IconButton(onPressed: _levels.length > 1 && !_loading ? _up : null,
              icon: const Icon(Icons.arrow_upward), tooltip: 'Parent folder'),
            Expanded(child: Text(_levels.map((x) => x.name).join(' / '), maxLines: 1, overflow: TextOverflow.ellipsis)),
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
          ]),
          TextField(controller: _searchController, decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search), hintText: 'Search this folder',
            suffixIcon: _searchController.text.isEmpty ? null : IconButton(
              tooltip: 'Clear search', onPressed: _searchController.clear, icon: const Icon(Icons.close)),
            isDense: true, border: const OutlineInputBorder())),
          const SizedBox(height: 8),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
            const Text('Sort by', style: TextStyle(color: Color(0xFF9AA8BD))),
            DropdownButton<_FileSort>(value: _sort, onChanged: (v) => setState(() => _sort = v ?? _sort),
              items: const [
                DropdownMenuItem(value: _FileSort.name, child: Text('Name')),
                DropdownMenuItem(value: _FileSort.largest, child: Text('Largest')),
                DropdownMenuItem(value: _FileSort.newest, child: Text('Newest')),
                DropdownMenuItem(value: _FileSort.type, child: Text('File type')),
              ]),
            FilterChip(selected: _showHidden, label: const Text('Show hidden'),
              onSelected: (v) => setState(() => _showHidden = v)),
            Text('${visible.length} items', style: const TextStyle(color: Color(0xFF9AA8BD), fontSize: 12)),
          ]),
        ],
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null) Padding(padding: const EdgeInsets.all(10), child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFC477)), const SizedBox(width: 8),
          Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFFFC477)))),
          TextButton(onPressed: _loading ? null : _choose, child: const Text('Re-select')),
        ])),
        if (_root == null && !_loading)
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.folder_open_outlined, size: 52, color: Color(0xFF8295B1)),
            const SizedBox(height: 12), const Text('No folder selected'), const SizedBox(height: 12),
            FilledButton.icon(onPressed: _choose, icon: const Icon(Icons.folder_open), label: const Text('Choose folder')),
          ])))
        else
          Expanded(child: visible.isEmpty && !_loading
            ? Center(child: Text(_searchController.text.isNotEmpty ? 'No files match your search.'
              : _entries.isEmpty ? 'This folder is empty.' : 'No visible items. Try Show hidden.'))
            : ListView.separated(itemCount: visible.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final e = visible[index];
                final sub = e.isDirectory ? 'Folder • ${_modified(e.modifiedEpochMs)}'
                  : '${_size(e.sizeBytes)} • ${_modified(e.modifiedEpochMs)}${e.isHidden ? ' • Hidden' : ''}';
                return Material(color: Colors.transparent, child: ListTile(
                  leading: Icon(e.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
                  title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Item actions',
                    onSelected: (action) { if (action == 'rename') _rename(e); },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename'))],
                  ),
                  onTap: e.isDirectory ? () => _open(e) : () => _openFile(e),
                ));
              })),
      ],
    ));
  }
}
