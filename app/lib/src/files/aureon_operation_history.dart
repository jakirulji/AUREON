import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AureonOperationRecord {
  const AureonOperationRecord({
    required this.id,
    required this.kind,
    required this.itemName,
    required this.sourceLocation,
    required this.destinationLocation,
    required this.succeeded,
    required this.occurredAtMs,
    this.errorCode,
  });

  final String id;
  final String kind;
  final String itemName;
  final String sourceLocation;
  final String? destinationLocation;
  final bool succeeded;
  final int occurredAtMs;
  final String? errorCode;

  factory AureonOperationRecord.fromJson(Map<String, dynamic> json) => AureonOperationRecord(
    id: json['id'] as String,
    kind: json['kind'] as String,
    itemName: json['itemName'] as String,
    sourceLocation: json['sourceLocation'] as String,
    destinationLocation: json['destinationLocation'] as String?,
    succeeded: json['succeeded'] as bool,
    occurredAtMs: json['occurredAtMs'] as int,
    errorCode: json['errorCode'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id, 'kind': kind, 'itemName': itemName,
    'sourceLocation': sourceLocation, 'destinationLocation': destinationLocation,
    'succeeded': succeeded, 'occurredAtMs': occurredAtMs, 'errorCode': errorCode,
  };
}

class AureonOperationHistory {
  static const storageKey = 'aureon.file_operation_history.v1';
  static const maxRecords = 250;
  static Future<void> _writeQueue = Future<void>.value();

  static Future<void> record({
    required String kind,
    required String itemName,
    required String sourceLocation,
    String? destinationLocation,
    required bool succeeded,
    String? errorCode,
  }) {
    final operation = _writeQueue.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      final rows = _decode(preferences.getString(storageKey));
      final now = DateTime.now().millisecondsSinceEpoch;
      rows.insert(0, AureonOperationRecord(
        id: '$now-${rows.length}-$kind',
        kind: kind,
        itemName: itemName,
        sourceLocation: sourceLocation,
        destinationLocation: destinationLocation,
        succeeded: succeeded,
        occurredAtMs: now,
        errorCode: errorCode,
      ));
      if (rows.length > maxRecords) rows.removeRange(maxRecords, rows.length);
      await preferences.setString(storageKey, jsonEncode(rows.map((row) => row.toJson()).toList()));
    });
    _writeQueue = operation.catchError((Object _) {});
    return _writeQueue;
  }

  static Future<void> flush() => _writeQueue;

  static Future<List<AureonOperationRecord>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(storageKey));
  }

  static Future<void> clear() {
    _writeQueue = _writeQueue.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(storageKey);
    });
    return _writeQueue;
  }

  static List<AureonOperationRecord> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((row) =>
        AureonOperationRecord.fromJson(Map<String, dynamic>.from(row))).toList();
    } catch (_) {
      return [];
    }
  }
}

class AureonOperationHistoryPage extends StatefulWidget {
  const AureonOperationHistoryPage({super.key});

  @override
  State<AureonOperationHistoryPage> createState() => _AureonOperationHistoryPageState();
}

class _AureonOperationHistoryPageState extends State<AureonOperationHistoryPage> {
  List<AureonOperationRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final records = await AureonOperationHistory.load();
      if (mounted) setState(() { _records = records; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _records = []; _loading = false; });
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Clear operation history?'),
      content: const Text('This removes the saved operation log from this device. It does not change any files.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Clear history')),
      ],
    ));
    if (confirmed != true) return;
    await AureonOperationHistory.clear();
    await _load();
  }

  String _label(String kind) => switch (kind) {
    'copy' => 'Copy',
    'move' => 'Move',
    'rename' => 'Rename',
    'trash' => 'Move to Trash',
    'restore' => 'Restore',
    'permanent_delete' => 'Permanent delete',
    'create_folder' => 'Create folder',
    'open' => 'Open',
    _ => kind,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Operation history'),
      actions: [
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'Clear history', onPressed: _records.isEmpty ? null : _clear, icon: const Icon(Icons.delete_sweep_outlined)),
      ],
    ),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : _records.isEmpty
        ? const Center(child: Text('No file operations recorded yet.'))
        : Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Stored on this device • Last 250 operations • History does not provide Undo',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9AA8BD))),
              ),
            ),
            Expanded(child: ListView.separated(
              itemCount: _records.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _records[index];
                final date = DateTime.fromMillisecondsSinceEpoch(row.occurredAtMs).toLocal();
                final local = MaterialLocalizations.of(context);
                final time = '${local.formatShortDate(date)} ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
                final destination = row.destinationLocation;
                final detail = destination == null || destination.isEmpty
                  ? row.sourceLocation
                  : '${row.sourceLocation}  →  $destination';
                return ListTile(
                  leading: Icon(row.succeeded ? Icons.check_circle_outline : Icons.error_outline,
                    color: row.succeeded ? const Color(0xFF66CDAA) : const Color(0xFFFF8A80)),
                  title: Text('${_label(row.kind)} • ${row.itemName}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('$detail\n$time • ${row.succeeded ? 'Success' : 'Failed'}${row.errorCode == null ? '' : ' • ${row.errorCode}'}',
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                );
              },
            )),
          ]),
  );
}
