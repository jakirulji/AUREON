import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/aureon_backend_profile.dart';
import '../auth/aureon_firebase_auth_service.dart';

class AureonDriveConnectionSlot {
  const AureonDriveConnectionSlot({
    required this.slotId,
    required this.label,
    required this.sortOrder,
  });

  final String slotId;
  final String label;
  final int sortOrder;

  Map<String, Object?> toJson() => {
    'slotId': slotId,
    'label': label,
    'sortOrder': sortOrder,
  };

  factory AureonDriveConnectionSlot.fromJson(Map<String, Object?> json) {
    final id = json['slotId'];
    final label = json['label'];
    final order = json['sortOrder'];
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(id) ||
        label is! String || label.trim().isEmpty || label.length > 48 ||
        order is! int || order < 0 || order >= 20) {
      throw const FormatException('The saved Google Drive connection slot is invalid.');
    }
    return AureonDriveConnectionSlot(slotId: id, label: label, sortOrder: order);
  }
}

abstract interface class AureonDriveSlotTransport {
  Future<Map<String, Object?>> send({
    required String method,
    required Uri uri,
    required String idToken,
    Map<String, Object?>? body,
  });
}

class AureonIoDriveSlotTransport implements AureonDriveSlotTransport {
  AureonIoDriveSlotTransport({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  @override
  Future<Map<String, Object?>> send({
    required String method,
    required Uri uri,
    required String idToken,
    Map<String, Object?>? body,
  }) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError('AUREON connection registry must use HTTPS.');
    }
    final request = await _client.openUrl(method, uri).timeout(const Duration(seconds: 20));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $idToken')
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
      if (all.length + chunk.length > 128 * 1024) {
        throw const FormatException('AUREON connection registry response is too large.');
      }
      return all..addAll(chunk);
    });
    final raw = utf8.decode(bytes);
    Map<String, Object?> decoded = <String, Object?>{};
    if (raw.isNotEmpty) {
      final value = jsonDecode(raw);
      if (value is! Map) throw const FormatException('AUREON connection registry returned invalid JSON.');
      decoded = value.cast<String, Object?>();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded['message'];
      throw StateError(message is String ? message : 'AUREON connection registry request failed.');
    }
    return decoded;
  }

  void close() => _client.close(force: true);
}

/// Stores only AUREON-generated slot IDs, user-entered labels and ordering.
/// Google identities, OAuth tokens and all Drive-derived data are excluded.
class AureonDriveConnectionSlotClient {
  AureonDriveConnectionSlotClient({
    required String workerBaseUrl,
    required AureonDriveSlotIdTokenProvider idTokenProvider,
    AureonDriveSlotTransport? transport,
  }) : _baseUri = _validateBaseUrl(workerBaseUrl),
       _idTokenProvider = idTokenProvider,
       _transport = transport ?? AureonIoDriveSlotTransport();

  final Uri _baseUri;
  final AureonDriveSlotIdTokenProvider _idTokenProvider;
  final AureonDriveSlotTransport _transport;

  void close() {
    final transport = _transport;
    if (transport is AureonIoDriveSlotTransport) transport.close();
  }

  static Uri _validateBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError('A valid HTTPS AUREON Worker URL is required.');
    }
    return uri.replace(path: uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path);
  }

  Uri get _slotsUri => _baseUri.replace(path: '${_baseUri.path}/v1/drive/slots');

  Future<String> _token() async {
    final token = await _idTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Sign in to AUREON and verify your email before restoring Drive connection slots.');
    }
    return token;
  }

  Future<List<AureonDriveConnectionSlot>> load() async {
    final response = await _transport.send(
      method: 'GET',
      uri: _slotsUri,
      idToken: await _token(),
    );
    final raw = response['slots'];
    if (raw is! List || raw.length > 20) {
      throw const FormatException('AUREON returned an invalid Drive connection slot list.');
    }
    final slots = raw.map((value) {
      if (value is! Map) throw const FormatException('AUREON returned an invalid connection slot.');
      return AureonDriveConnectionSlot.fromJson(value.cast<String, Object?>());
    }).toList();
    final ids = slots.map((slot) => slot.slotId).toSet();
    final orders = slots.map((slot) => slot.sortOrder).toSet();
    if (ids.length != slots.length || orders.length != slots.length) {
      throw const FormatException('AUREON returned duplicate Drive connection slots.');
    }
    slots.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return slots;
  }

  Future<void> replace(List<AureonDriveConnectionSlot> slots) async {
    if (slots.length > 20) throw ArgumentError('AUREON supports up to 20 Google Drive connection slots.');
    final normalized = <AureonDriveConnectionSlot>[];
    final ids = <String>{};
    for (var index = 0; index < slots.length; index++) {
      final slot = slots[index];
      final label = slot.label.trim();
      if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(slot.slotId) ||
          !ids.add(slot.slotId) || label.isEmpty || label.length > 48) {
        throw ArgumentError('Each Drive connection needs a unique ID and a label of 1–48 characters.');
      }
      normalized.add(AureonDriveConnectionSlot(
        slotId: slot.slotId,
        label: label,
        sortOrder: index,
      ));
    }
    await _transport.send(
      method: 'PUT',
      uri: _slotsUri,
      idToken: await _token(),
      body: {'slots': normalized.map((slot) => slot.toJson()).toList()},
    );
  }

  static String newSlotId() => base64Url.encode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');
}

typedef AureonDriveSlotIdTokenProvider = Future<String?> Function();

class AureonGoogleDrivePage extends StatefulWidget {
  const AureonGoogleDrivePage({super.key, required this.auth});
  final AureonFirebaseAuthService auth;

  @override
  State<AureonGoogleDrivePage> createState() => _AureonGoogleDrivePageState();
}

class _AureonGoogleDrivePageState extends State<AureonGoogleDrivePage> {
  static const _channel = MethodChannel('aureon/google_drive');
  late final AureonDriveConnectionSlotClient _slotsClient;
  List<AureonDriveConnectionSlot> _slots = const [];
  final Map<String, _ConnectedDriveAccount> _connected = {};
  final Map<String, List<Map<String, Object?>>> _files = {};
  final Map<String, String?> _nextPageTokens = {};
  bool _loading = true;
  bool _busy = false;
  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.auth.activeBackendProfile ?? AureonBackendProfile.shared;
    _slotsClient = AureonDriveConnectionSlotClient(
      workerBaseUrl: profile.workerBaseUrl,
      idTokenProvider: () async => widget.auth.getIdToken(forceRefresh: true),
    );
    _refresh();
  }

  @override
  void dispose() {
    _slotsClient.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() { _loading = true; _error = null; });
    try {
      final user = await widget.auth.reloadUser();
      if (!user.emailVerified) {
        throw StateError('Verify your AUREON Master Account email before syncing connection slots.');
      }
      final slots = await _slotsClient.load();
      if (mounted) setState(() { _slots = slots; _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _loading = false; });
    }
  }

  Future<String?> _askLabel({String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(initial.isEmpty ? 'Add Google Drive slot' : 'Rename connection slot'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 48,
            decoration: const InputDecoration(
              labelText: 'Your label',
              hintText: 'Personal Drive',
              helperText: 'This label is the only Google-related setup detail synced to your AUREON account.',
            ),
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

  Future<void> _addSlot() async {
    if (_slots.length >= 20) {
      _message('AUREON supports up to 20 Google Drive connection slots.');
      return;
    }
    final label = await _askLabel();
    if (label == null || label.trim().isEmpty) return;
    final updated = [..._slots, AureonDriveConnectionSlot(
      slotId: AureonDriveConnectionSlotClient.newSlotId(),
      label: label.trim(),
      sortOrder: _slots.length,
    )];
    await _saveSlots(updated);
  }

  Future<void> _renameSlot(AureonDriveConnectionSlot slot) async {
    final label = await _askLabel(initial: slot.label);
    if (label == null || label.trim().isEmpty) return;
    await _saveSlots(_slots.map((item) => item.slotId == slot.slotId
      ? AureonDriveConnectionSlot(slotId: item.slotId, label: label.trim(), sortOrder: item.sortOrder)
      : item).toList());
  }

  Future<void> _deleteSlot(AureonDriveConnectionSlot slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove connection slot?'),
        content: Text('Remove "${slot.label}" from your AUREON Master Account? This does not delete anything from Google Drive or revoke Google permission.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _clearLocalSession(slot.slotId);
    await _saveSlots(_slots.where((item) => item.slotId != slot.slotId).toList());
  }

  Future<void> _saveSlots(List<AureonDriveConnectionSlot> slots) async {
    setState(() { _busy = true; _error = null; });
    try {
      await _slotsClient.replace(slots);
      final refreshed = await _slotsClient.load();
      if (mounted) setState(() => _slots = refreshed);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(AureonDriveConnectionSlot slot) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final identity = await _channel.invokeMapMethod<String, dynamic>(
        'authorizeDrive',
        {'slotId': slot.slotId},
      );
      if (identity == null || identity['email'] is! String) {
        throw const FormatException('Google did not return the selected Drive account identity.');
      }
      final email = (identity['email'] as String).trim();
      final displayName = identity['displayName'] as String? ?? email;
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm Google account'),
          content: Text('Google selected:\n$email\n\nConnect this account to the AUREON slot "${slot.label}"? The email and Drive data remain on this device.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not this account')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Confirm account')),
          ],
        ),
      );
      if (accepted != true) {
        await _clearLocalSession(slot.slotId);
        return;
      }
      if (mounted) {
        setState(() {
          _connected[slot.slotId] = _ConnectedDriveAccount(email: email, displayName: displayName);
          _files.remove(slot.slotId);
          _nextPageTokens.remove(slot.slotId);
        });
      }
      await _loadFiles(slot.slotId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadFiles(String slotId, {String? pageToken}) async {
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'listDriveFiles',
      {
        'slotId': slotId,
        ...?(pageToken == null ? null : {'pageToken': pageToken}),
      },
    );
    if (response == null || response['files'] is! List) {
      throw const FormatException('Google Drive returned an invalid file listing.');
    }
    final batch = (response['files'] as List).whereType<Map>()
      .map((item) => item.cast<String, Object?>()).toList();
    if (!mounted) return;
    setState(() {
      _files[slotId] = [...?_files[slotId], ...batch];
      _nextPageTokens[slotId] = response['nextPageToken'] as String?;
    });
  }

  Future<void> _loadMore(String slotId) async {
    final token = _nextPageTokens[slotId];
    if (token == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _loadFiles(slotId, pageToken: token);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearLocalSession(String slotId) async {
    try {
      await _channel.invokeMethod<bool>('clearDriveSession', {'slotId': slotId});
    } catch (_) {
      // The slot may be restored on a platform that has no Android bridge.
    }
    if (mounted) {
      setState(() {
        _connected.remove(slotId);
        _files.remove(slotId);
        _nextPageTokens.remove(slotId);
      });
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text('Google Drive connections', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text(
        'Your AUREON Master Account restores these named connection slots. Android can reconnect and browse Drive now; Windows support will follow.',
        style: TextStyle(color: Color(0xFF9AA8BD), fontSize: 12),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF102A2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF27645B)),
        ),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.shield_outlined, color: Color(0xFF64E6C2)),
          SizedBox(width: 10),
          Expanded(child: Text(
            'Only your slot ID, label and order sync to the AUREON Worker. Google email, OAuth tokens, file names, IDs, folder data and file contents stay on this device.',
            style: TextStyle(color: Color(0xFFBDEFE3), fontSize: 12),
          )),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Text('${_slots.length} of 20 connection slots', style: const TextStyle(fontWeight: FontWeight.w700))),
        IconButton(onPressed: _loading || _busy ? null : _refresh, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
        FilledButton.icon(onPressed: _loading || _busy ? null : _addSlot,
          icon: const Icon(Icons.add), label: const Text('Add account')),
      ]),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      if (_error != null) Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
      ),
      if (!_loading && _slots.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No connection slots yet. Add one to get started.')),
        ),
      ..._slots.map(_slotCard),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
    ],
  );

  Widget _slotCard(AureonDriveConnectionSlot slot) {
    final account = _connected[slot.slotId];
    final files = _files[slot.slotId] ?? const <Map<String, Object?>>[];
    return Card(
      child: ExpansionTile(
        key: ValueKey(slot.slotId),
        leading: Icon(account == null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
          color: account == null ? null : const Color(0xFF64E6C2)),
        title: Text(slot.label),
        subtitle: Text(account?.email ?? (_isAndroid ? 'Not connected on this device' : 'Google Drive connection is Android-only for now')),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'rename') _renameSlot(slot);
            if (action == 'remove') _deleteSlot(slot);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename slot')),
            PopupMenuItem(value: 'remove', child: Text('Remove slot')),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              FilledButton.tonalIcon(
                onPressed: _busy || !_isAndroid ? null : () => _connect(slot),
                icon: const Icon(Icons.link),
                label: Text(account == null ? 'Connect Google' : 'Reconnect'),
              ),
              const SizedBox(width: 8),
              if (account != null)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _clearLocalSession(slot.slotId),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect on device'),
                ),
            ]),
          ),
          if (account != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                const Icon(Icons.person_outline, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(account.displayName, style: const TextStyle(fontSize: 12))),
                Text('${files.length} files loaded', style: const TextStyle(fontSize: 11, color: Color(0xFF9AA8BD))),
              ]),
            ),
            if (files.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('No files on this page, or Drive is empty.'))
            else
              ...files.map((file) => ListTile(
                dense: true,
                leading: Icon(file['mimeType'] == 'application/vnd.google-apps.folder'
                  ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
                title: Text(file['name'] as String? ?? 'Unnamed file',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${file['mimeType'] ?? 'File'} • ${file['modifiedTime'] ?? ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              )),
            if (_nextPageTokens[slot.slotId] != null)
              TextButton.icon(
                onPressed: _busy ? null : () => _loadMore(slot.slotId),
                icon: const Icon(Icons.expand_more),
                label: const Text('Load more files'),
              ),
          ],
        ],
      ),
    );
  }
}

class _ConnectedDriveAccount {
  const _ConnectedDriveAccount({required this.email, required this.displayName});
  final String email;
  final String displayName;
}
