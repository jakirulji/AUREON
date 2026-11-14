import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

class AureonArchivePage extends StatefulWidget {
  const AureonArchivePage({super.key, required this.archivePath});
  final String archivePath;

  @override
  State<AureonArchivePage> createState() => _AureonArchivePageState();
}

class _AureonArchivePageState extends State<AureonArchivePage> {
  Archive? _archive;
  bool _loading = true;
  bool _extracting = false;
  String? _error;
  String? _password;

  String get _extension => p.extension(widget.archivePath).toLowerCase();
  bool get _isZip => _extension == '.zip';
  bool get _isTar => _extension == '.tar';

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  Future<void> _loadArchive({String? password}) async {
    setState(() { _loading = true; _error = null; });
    InputFileStream? input;
    try {
      final file = File(widget.archivePath);
      if (!await file.exists()) throw const FileSystemException('Archive file not found.');
      if (await file.length() > 8 * 1024 * 1024 * 1024) {
        throw const FormatException('This archive is larger than the current 8 GB browsing limit.');
      }
      input = InputFileStream(widget.archivePath);
      final Archive decoded;
      if (_isZip) {
        decoded = ZipDecoder().decodeStream(input, password: password, verify: true, throwOnError: true);
      } else if (_isTar) {
        decoded = TarDecoder().decodeStream(input, verify: true, throwOnError: true);
      } else {
        throw FormatException('This build can browse ZIP and TAR archives. ${p.extension(widget.archivePath).toUpperCase()} requires an additional audited decoder.');
      }
      if (!mounted) return;
      setState(() { _archive = decoded; _password = password; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString(); _loading = false; });
    } finally {
      input?.closeSync();
    }
  }

  Future<void> _extract() async {
    final archive = _archive;
    if (archive == null || _extracting) return;
    final parent = p.dirname(widget.archivePath);
    final baseName = p.basenameWithoutExtension(widget.archivePath);
    final destination = Directory(p.join(parent, '${baseName}_extracted'));
    if (await destination.exists()) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Extraction folder already exists'),
          content: const Text('Use the existing folder? Existing files will not be overwritten.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
          ],
        ),
      );
      if (proceed != true) return;
    } else {
      await destination.create(recursive: true);
    }

    setState(() => _extracting = true);
    var extracted = 0;
    try {
      for (final entry in archive) {
        if (entry.isSymbolicLink) continue;
        final normalized = entry.name.replaceAll('\\\\', '/');
        final segments = normalized.split('/');
        if (normalized.startsWith('/') ||
            RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
            segments.any((part) => part == '..')) {
          throw FormatException('Unsafe archive path rejected: ${entry.name}');
        }
        final targetPath = p.normalize(p.join(destination.path, normalized));
        if (targetPath != destination.path && !p.isWithin(destination.path, targetPath)) {
          throw FormatException('Archive entry escapes the extraction folder: ${entry.name}');
        }
        if (entry.isDirectory) {
          await Directory(targetPath).create(recursive: true);
        } else if (entry.isFile) {
          final target = File(targetPath);
          await target.parent.create(recursive: true);
          if (await target.exists()) continue;
          final output = OutputFileStream(target.path);
          try {
            entry.writeContent(output);
            extracted++;
          } finally {
            output.closeSync();
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extracted $extracted files to ${destination.path}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extraction stopped safely: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _askPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Unlock')),
        ],
      ),
    );
    controller.dispose();
    if (password != null && password.isNotEmpty) await _loadArchive(password: password);
  }

  @override
  Widget build(BuildContext context) {
    final archive = _archive;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(widget.archivePath), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (archive != null)
            IconButton(
              tooltip: 'Extract archive',
              onPressed: _extracting ? null : _extract,
              icon: _extracting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.folder_zip_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.archive_outlined, size: 42),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      if (_isZip) ...[
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _askPassword, child: const Text('Try password')),
                      ],
                      TextButton(onPressed: () => _loadArchive(password: _password), child: const Text('Retry')),
                    ]),
                  ),
                )
              : ListView.builder(
                  itemCount: archive?.length ?? 0,
                  itemBuilder: (context, index) {
                    final entry = archive![index];
                    return ListTile(
                      leading: Icon(entry.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
                      title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(entry.isDirectory ? 'Folder' : '${entry.size} bytes'),
                    );
                  },
                ),
    );
  }
}
