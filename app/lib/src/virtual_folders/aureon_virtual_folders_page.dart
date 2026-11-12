import 'package:aureon_contracts/aureon_contracts.dart';
import 'package:material_ui/material_ui.dart';

import 'aureon_virtual_folder_store.dart';
import '../backup/aureon_folder_organizer_page.dart';

class AureonVirtualFoldersPage extends StatefulWidget {
  const AureonVirtualFoldersPage({super.key, this.store});

  final AureonVirtualFolderStore? store;

  @override
  State<AureonVirtualFoldersPage> createState() => _AureonVirtualFoldersPageState();
}

class _AureonVirtualFoldersPageState extends State<AureonVirtualFoldersPage> {
  late final _store = widget.store ?? AureonVirtualFolderStore();
  List<AureonVirtualFolder> _folders = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final folders = await _store.load();
      if (mounted) setState(() { _folders = folders; _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _loading = false; });
    }
  }

  Future<String?> _textDialog(String title, String hint, {String initial = ''}) async {
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

  Future<void> _createFolder() async {
    final name = await _textDialog('New virtual folder', 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    try {
      await _store.create(name);
      await _refresh();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _addReference(AureonVirtualFolder folder) async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController();
        final account = TextEditingController();
        final accountLabel = TextEditingController();
        final item = TextEditingController();
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
            TextField(controller: accountLabel, decoration: const InputDecoration(labelText: 'Account label', hintText: 'Personal Drive')),
            TextField(controller: account, decoration: const InputDecoration(labelText: 'Stable provider account ID')),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'File name')),
            TextField(controller: item, decoration: const InputDecoration(labelText: 'Stable provider file ID')),
            const SizedBox(height: 8),
            const Text('This records a reference only. It does not upload, copy, move or modify the cloud file.', style: TextStyle(fontSize: 12)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, {
              'provider': provider.name,
              'accountLabel': accountLabel.text.trim(),
              'account': account.text.trim(),
              'name': name.text.trim(),
              'item': item.text.trim(),
            }), child: const Text('Add reference')),
          ],
        ));
      },
    );
    if (values == null) return;
    if ([values['accountLabel'], values['account'], values['name'], values['item']].any((value) => value == null || value.isEmpty)) {
      _showError('All fields are required to identify a cloud file safely.');
      return;
    }
    try {
      final provider = ProviderKind.values.firstWhere((value) => value.name == values['provider']);
      await _store.addItem(folder.id, ProviderFileReference(
        provider: provider,
        providerAccountId: values['account']!,
        accountLabel: values['accountLabel']!,
        providerItemId: values['item']!,
        name: values['name']!,
      ));
      await _refresh();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _removeReference(AureonVirtualFolder folder, ProviderFileReference file) async {
    await _store.removeItem(folder.id, file.stableKey);
    await _refresh();
  }

  Future<void> _deleteFolder(AureonVirtualFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete virtual folder?'),
        content: Text('Delete "${folder.name}" from AUREON? Cloud files will remain untouched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete folder')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(folder.id);
    await _refresh();
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  static String _providerName(ProviderKind provider) => switch (provider) {
    ProviderKind.googleDrive => 'Google Drive',
    ProviderKind.oneDrive => 'OneDrive',
    ProviderKind.dropbox => 'Dropbox',
    ProviderKind.s3Compatible => 'S3-compatible',
    ProviderKind.other => 'Other',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Virtual folders', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700))),
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
        OutlinedButton.icon(
          onPressed: _loading ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AureonFolderOrganizerPage())),
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('Folder organizer'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: _loading ? null : _createFolder, icon: const Icon(Icons.create_new_folder_outlined), label: const Text('New folder')),
      ]),
      const SizedBox(height: 6),
      const Text('One AUREON folder can organize references from multiple cloud accounts. Membership never changes the original cloud location.', style: TextStyle(color: Color(0xFF9AA8BD), fontSize: 12)),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF302817), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF66512A))),
        child: const Row(children: [
          Icon(Icons.info_outline, color: Color(0xFFFFD27A)),
          SizedBox(width: 10),
          Expanded(child: Text('Prototype: live cloud account browsing and OAuth are not connected yet. You can create folders and register stable cloud-file references for contract testing.', style: TextStyle(color: Color(0xFFFFE4B0), fontSize: 12))),
        ]),
      ),
      const SizedBox(height: 12),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: _folders.isEmpty && !_loading
        ? const Center(child: Text('No virtual folders yet. Create one to get started.'))
        : ListView.builder(
          itemCount: _folders.length,
          itemBuilder: (context, index) {
            final folder = _folders[index];
            return Card(
              child: ExpansionTile(
                key: ValueKey(folder.id),
                leading: const Icon(Icons.folder_special_outlined, color: Color(0xFF64E6C2)),
                title: Text(folder.name),
                subtitle: Text('${folder.items.length} linked cloud files'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(children: [
                      TextButton.icon(onPressed: () => _addReference(folder), icon: const Icon(Icons.add_link), label: const Text('Add cloud reference')),
                      const Spacer(),
                      IconButton(tooltip: 'Delete virtual folder', onPressed: () => _deleteFolder(folder), icon: const Icon(Icons.delete_outline)),
                    ]),
                  ),
                  if (folder.items.isEmpty)
                    const Padding(padding: EdgeInsets.all(16), child: Text('No linked files yet.'))
                  else
                    ...folder.items.map((file) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${_providerName(file.provider)} • ${file.accountLabel} • ${file.providerAccountId}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(tooltip: 'Remove from virtual folder', onPressed: () => _removeReference(folder, file), icon: const Icon(Icons.link_off)),
                    )),
                ],
              ),
            );
          },
        )),
    ]),
  );
}
