import 'dart:io';

import 'package:aureon_local_files/aureon_local_files.dart';
import 'package:cryptography/cryptography.dart';
import 'package:material_ui/material_ui.dart';

class AureonStorageToolsPage extends StatefulWidget {
  const AureonStorageToolsPage({super.key, required this.root, required this.files});
  final AureonLocalRoot root;
  final AureonLocalFiles files;

  @override
  State<AureonStorageToolsPage> createState() => _AureonStorageToolsPageState();
}

class _AureonStorageToolsPageState extends State<AureonStorageToolsPage> {
  bool _running = false;
  String _task = '';
  int _visitedFiles = 0;
  int _visitedFolders = 0;
  int _totalBytes = 0;
  Map<String, int> _categoryBytes = {};
  List<List<AureonLocalEntry>> _duplicateGroups = [];
  String? _error;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _category(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'no extension';
    if ({'jpg','jpeg','png','gif','webp','heic','bmp','tif','tiff'}.contains(ext)) return 'Images';
    if ({'mp4','mkv','mov','avi','webm','3gp','m4v'}.contains(ext)) return 'Videos';
    if ({'mp3','m4a','aac','wav','flac','ogg','opus','wma'}.contains(ext)) return 'Audio';
    if ({'pdf','doc','docx','xls','xlsx','ppt','pptx','txt','rtf','csv','md'}.contains(ext)) return 'Documents';
    if ({'zip','rar','7z','tar','gz','bz2','xz','zst'}.contains(ext)) return 'Archives';
    if ({'apk','apks','xapk','aab'}.contains(ext)) return 'Apps';
    return 'Other';
  }

  Future<List<AureonLocalEntry>> _walkFiles() async {
    final queue = <({String id, int depth})>[
      (id: widget.root.rootDocumentId, depth: 0),
    ];
    final visited = <String>{widget.root.rootDocumentId};
    final files = <AureonLocalEntry>[];
    var cursor = 0;
    while (cursor < queue.length && visited.length < 20000) {
      final current = queue[cursor++];
      if (current.depth > 48) continue;
      List<AureonLocalEntry> children;
      try {
        children = await widget.files.listChildren(root: widget.root, parentId: current.id);
      } catch (_) {
        continue;
      }
      for (final entry in children) {
        if (entry.name == '.AUREON Trash (AUREON)') continue;
        if (entry.isDirectory) {
          if (visited.add(entry.id)) queue.add((id: entry.id, depth: current.depth + 1));
        } else if ((entry.sizeBytes ?? 0) > 0) {
          files.add(entry);
        }
      }
      if (mounted && files.length % 100 == 0) {
        setState(() { _visitedFiles = files.length; _visitedFolders = visited.length; });
      }
    }
    return files;
  }

  Future<void> _analyzeStorage() async {
    if (_running) return;
    setState(() { _running = true; _task = 'Scanning storage'; _error = null; _visitedFiles = 0; _visitedFolders = 0; });
    try {
      final files = await _walkFiles();
      final totals = <String, int>{};
      var bytes = 0;
      for (final file in files) {
        final size = file.sizeBytes ?? 0;
        bytes += size;
        final category = _category(file.name);
        totals[category] = (totals[category] ?? 0) + size;
      }
      if (mounted) setState(() {
        _visitedFiles = files.length;
        _totalBytes = bytes;
        _categoryBytes = totals;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _findDuplicates() async {
    if (_running) return;
    setState(() { _running = true; _task = 'Finding duplicate files'; _error = null; _visitedFiles = 0; _visitedFolders = 0; });
    try {
      final files = await _walkFiles();
      final bySize = <int, List<AureonLocalEntry>>{};
      for (final file in files) {
        final size = file.sizeBytes ?? 0;
        if (size > 0) (bySize[size] ??= []).add(file);
      }
      final candidates = bySize.values.where((group) => group.length > 1).expand((group) => group).toList();
      final hashes = <String, List<AureonLocalEntry>>{};
      var checked = 0;
      for (final file in candidates) {
        try {
          final digest = await const Sha256().hashStream(File(file.id).openRead());
          final key = '${file.sizeBytes}:${digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
          (hashes[key] ??= []).add(file);
        } catch (_) {
          // An inaccessible file is skipped; it is never modified.
        }
        checked++;
        if (mounted && checked % 10 == 0) setState(() => _visitedFiles = checked);
      }
      final groups = hashes.values.where((group) => group.length > 1).toList()
        ..sort((a, b) => (b.first.sizeBytes ?? 0).compareTo(a.first.sizeBytes ?? 0));
      if (mounted) setState(() { _duplicateGroups = groups; _visitedFiles = checked; });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _categoryBytes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final duplicateBytes = _duplicateGroups.fold<int>(0, (sum, group) =>
      sum + group.skip(1).fold<int>(0, (groupSum, entry) => groupSum + (entry.sizeBytes ?? 0)));
    return Scaffold(
      appBar: AppBar(title: const Text('Storage tools')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('Analyze storage usage by file category and locate exact duplicate files using SHA-256. AUREON never deletes anything automatically.',
            style: TextStyle(fontSize: 13, height: 1.45)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _running ? null : _analyzeStorage,
              icon: const Icon(Icons.pie_chart_outline), label: const Text('Analyze storage')),
            OutlinedButton.icon(onPressed: _running ? null : _findDuplicates,
              icon: const Icon(Icons.copy_all_outlined), label: const Text('Find duplicates')),
          ]),
          if (_running) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text('$_task · $_visitedFiles files · $_visitedFolders folders'),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_categoryBytes.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Storage analysis', style: Theme.of(context).textTheme.titleLarge),
            Text('${_visitedFiles} files · ${_formatBytes(_totalBytes)} total scanned'),
            for (final item in sorted)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.key),
                subtitle: LinearProgressIndicator(value: _totalBytes == 0 ? 0 : item.value / _totalBytes),
                trailing: Text(_formatBytes(item.value)),
              ),
          ],
          if (_duplicateGroups.isNotEmpty) ...[
            const Divider(height: 28),
            Text('Exact duplicates', style: Theme.of(context).textTheme.titleLarge),
            Text('${_duplicateGroups.length} duplicate groups · ${_formatBytes(duplicateBytes)} redundant copies (not deleted)'),
            for (final group in _duplicateGroups)
              Card(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${group.length} identical copies · ${_formatBytes(group.first.sizeBytes ?? 0)} each',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  for (final entry in group)
                    Padding(padding: const EdgeInsets.only(top: 6),
                      child: SelectableText(entry.id, style: const TextStyle(fontSize: 11))),
                ]),
              )),
          ],
        ],
      ),
    );
  }
}
