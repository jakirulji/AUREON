import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:material_ui/material_ui.dart';

import 'aureon_metadata_backup.dart';
import 'aureon_metadata_store.dart';

class AureonFolderOrganizerPage extends StatefulWidget {
  const AureonFolderOrganizerPage({super.key});

  @override
  State<AureonFolderOrganizerPage> createState() => _AureonFolderOrganizerPageState();
}

class _AureonFolderOrganizerPageState extends State<AureonFolderOrganizerPage> {
  final _store = AureonMetadataStore();
  AureonMetadataSnapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final snapshot = await _store.load();
      if (mounted) setState(() { _snapshot = snapshot; _loading = false; });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _message('Could not load AUREON folders: $error');
      }
    }
  }

  Future<String?> _askText(String title, String hint, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Save')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createFolder({String? parentId}) async {
    final name = await _askText(parentId == null ? 'New AUREON folder' : 'New subfolder', 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    try {
      await _store.createFolder(name, parentId: parentId);
      await _refresh();
    } catch (error) { _message(error); }
  }

  Future<void> _renameFolder(AureonMetadataFolder folder) async {
    final name = await _askText('Rename folder', 'Folder name', initial: folder.name);
    if (name == null || name.trim().isEmpty) return;
    try {
      await _store.renameFolder(folder.id, name);
      await _refresh();
    } catch (error) { _message(error); }
  }

  Future<void> _deleteFolder(AureonMetadataFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete AUREON folder?'),
        content: Text('Delete "${folder.name}" and its AUREON organization records? Provider cloud files will not be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _store.deleteFolder(folder.id);
      await _refresh();
    } catch (error) { _message(error); }
  }

  Future<void> _addFile(AureonMetadataFolder folder) async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        final accountLabel = TextEditingController();
        final accountId = TextEditingController();
        final fileName = TextEditingController();
        final itemId = TextEditingController();
        var provider = ProviderKind.googleDrive;
        return StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
          title: Text('Add cloud file to ${folder.name}'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<ProviderKind>(
              initialValue: provider,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: ProviderKind.values.map((value) => DropdownMenuItem(value: value, child: Text(_providerName(value)))).toList(),
              onChanged: (value) => setDialogState(() => provider = value ?? provider),
            ),
            TextField(controller: accountLabel, decoration: const InputDecoration(labelText: 'Account label')),
            TextField(controller: accountId, decoration: const InputDecoration(labelText: 'Stable provider account ID')),
            TextField(controller: fileName, decoration: const InputDecoration(labelText: 'File name')),
            TextField(controller: itemId, decoration: const InputDecoration(labelText: 'Stable provider file ID')),
            const SizedBox(height: 8),
            const Text('This creates an AUREON reference only. It does not move, copy, upload or delete the provider file.', style: TextStyle(fontSize: 12)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, {
              'provider': provider.name,
              'accountLabel': accountLabel.text.trim(),
              'accountId': accountId.text.trim(),
              'fileName': fileName.text.trim(),
              'itemId': itemId.text.trim(),
            }), child: const Text('Add reference')),
          ],
        ));
      },
    );
    if (values == null) return;
    if ([values['accountLabel'], values['accountId'], values['fileName'], values['itemId']]
        .any((value) => value == null || value.isEmpty)) {
      _message('All provider identity fields are required.');
      return;
    }
    try {
      final provider = ProviderKind.values.firstWhere((value) => value.name == values['provider']);
      await _store.addFileToFolder(folder.id, ProviderFileReference(
        provider: provider,
        providerAccountId: values['accountId']!,
        accountLabel: values['accountLabel']!,
        providerItemId: values['itemId']!,
        name: values['fileName']!,
      ));
      await _refresh();
    } catch (error) { _message(error); }
  }

  Future<void> _toggleFavorite(AureonMetadataFolder folder, AureonMetadataFileEntry file) async {
    await _store.toggleFavorite(folder.id, file.reference.stableKey);
    await _refresh();
  }

  Future<void> _addTag(AureonMetadataFolder folder, AureonMetadataFileEntry file) async {
    final tag = await _askText('Add tag', 'Tag name');
    if (tag == null || tag.trim().isEmpty) return;
    await _store.addTagToFile(folder.id, file.reference.stableKey, tag);
    await _refresh();
  }

  Future<void> _moveFile(AureonMetadataFolder folder, AureonMetadataFileEntry file, int delta) async {
    final target = file.order + delta;
    if (target < 0 || target >= folder.files.length) return;
    await _store.reorderFile(folder.id, file.reference.stableKey, target);
    await _refresh();
  }

  void _message(Object error) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  static String _providerName(ProviderKind provider) => switch (provider) {
    ProviderKind.googleDrive => 'Google Drive',
    ProviderKind.oneDrive => 'OneDrive',
    ProviderKind.dropbox => 'Dropbox',
    ProviderKind.s3Compatible => 'S3-compatible',
    ProviderKind.other => 'Other',
  };

  Widget _folderTile(AureonMetadataFolder folder, List<AureonMetadataFolder> siblings) {
    final sortedFolders = [...folder.folders]..sort((a, b) => a.order.compareTo(b.order));
    final sortedFiles = [...folder.files]..sort((a, b) => a.order.compareTo(b.order));
    final index = siblings.indexWhere((item) => item.id == folder.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: ValueKey(folder.id),
        leading: const Icon(Icons.folder_outlined, color: Color(0xFF64E6C2)),
        title: Text(folder.name),
        subtitle: Text('${sortedFolders.length} subfolders • ${sortedFiles.length} files'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(spacing: 4, runSpacing: 4, children: [
              TextButton.icon(onPressed: () => _createFolder(parentId: folder.id), icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Subfolder')),
              TextButton.icon(onPressed: () => _addFile(folder), icon: const Icon(Icons.add_link), label: const Text('Add file reference')),
              IconButton(tooltip: 'Rename', onPressed: () => _renameFolder(folder), icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: 'Delete AUREON folder', onPressed: () => _deleteFolder(folder), icon: const Icon(Icons.delete_outline)),
              IconButton(tooltip: 'Move up', onPressed: index > 0 ? () async { await _store.reorderFolder(folder.id, index - 1); await _refresh(); } : null, icon: const Icon(Icons.arrow_upward)),
              IconButton(tooltip: 'Move down', onPressed: index < siblings.length - 1 ? () async { await _store.reorderFolder(folder.id, index + 1); await _refresh(); } : null, icon: const Icon(Icons.arrow_downward)),
            ]),
          ),
          if (sortedFiles.isEmpty && sortedFolders.isEmpty)
            const Padding(padding: EdgeInsets.all(14), child: Text('This AUREON folder is empty.')),
          ...sortedFiles.map((file) => ListTile(
            dense: true,
            leading: Icon(file.favorite ? Icons.star : Icons.insert_drive_file_outlined,
              color: file.favorite ? const Color(0xFFFFC477) : const Color(0xFF9AA8BD)),
            title: Text(file.customLabel ?? file.reference.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${_providerName(file.reference.provider)} • ${file.reference.accountLabel} • ${file.tags.join(', ')}${file.pendingProviderReconciliation ? ' • Pending re-link' : ''}',
              maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Wrap(spacing: 0, children: [
              IconButton(tooltip: 'Favorite', onPressed: () => _toggleFavorite(folder, file), icon: Icon(file.favorite ? Icons.star : Icons.star_border)),
              IconButton(tooltip: 'Add tag', onPressed: () => _addTag(folder, file), icon: const Icon(Icons.sell_outlined)),
              IconButton(tooltip: 'Move up', onPressed: file.order > 0 ? () => _moveFile(folder, file, -1) : null, icon: const Icon(Icons.arrow_upward)),
              IconButton(tooltip: 'Move down', onPressed: file.order < sortedFiles.length - 1 ? () => _moveFile(folder, file, 1) : null, icon: const Icon(Icons.arrow_downward)),
              IconButton(tooltip: 'Remove from AUREON folder', onPressed: () async { await _store.removeFileFromFolder(folder.id, file.reference.stableKey); await _refresh(); }, icon: const Icon(Icons.link_off)),
            ]),
          )),
          ...sortedFolders.map((child) => _folderTile(child, sortedFolders)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roots = [...?_snapshot?.rootFolders]..sort((a, b) => a.order.compareTo(b.order));
    return Scaffold(
      appBar: AppBar(title: const Text('AUREON Folder Organizer')),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(18), children: [
            const Text('Organize files across accounts without changing their original cloud locations.', style: TextStyle(color: Color(0xFF9AA8BD))),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () => _createFolder(), icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Create root folder')),
            const SizedBox(height: 12),
            if (roots.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No AUREON folders yet. Create a root folder to start.')))
            else
              ...roots.map((folder) => _folderTile(folder, roots)),
          ]),
    );
  }
}
