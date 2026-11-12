import 'package:material_ui/material_ui.dart';

import 'aureon_storage_api.g.dart';

class AureonTransfersPage extends StatefulWidget {
  const AureonTransfersPage({super.key});

  @override
  State<AureonTransfersPage> createState() => _AureonTransfersPageState();
}

class _AureonTransfersPageState extends State<AureonTransfersPage> {
  final _api = AureonStorageHostApi();
  List<TransferSnapshot> _transfers = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final transfers = await _api.listTransfers();
      if (!mounted) return;
      setState(() {
        _transfers = transfers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Transfers'),
      actions: [
        IconButton(
          tooltip: 'Refresh transfer queue',
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: _loading
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 220),
                Center(child: CircularProgressIndicator()),
              ],
            )
          : _error != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Icon(Icons.sync_problem_outlined, size: 42),
                    const SizedBox(height: 12),
                    const Text('Native transfer queue is unavailable',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text('The Android Room/Pigeon bridge is available only where the native module is registered. Provider upload/download workers are not connected yet.'),
                    const SizedBox(height: 8),
                    Text(_error!, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ),
                  ],
                )
              : _transfers.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: const [
                        SizedBox(height: 90),
                        Icon(Icons.cloud_sync_outlined, size: 48),
                        SizedBox(height: 16),
                        Center(child: Text('No saved transfer checkpoints')) ,
                        SizedBox(height: 8),
                        Center(child: Text('Queued and in-progress Android operations will appear here. Cloud-provider transfer execution is still under development.', textAlign: TextAlign.center)),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _transfers.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _transferCard(_transfers[index]),
                    ),
    ),
  );

  Widget _transferCard(TransferSnapshot transfer) {
    final acknowledged = transfer.acknowledgedBytes ?? 0;
    final total = transfer.totalBytes;
    final fraction = total == null || total <= 0
        ? null
        : (acknowledged / total).clamp(0.0, 1.0).toDouble();
    final status = transfer.status ?? 'unknown';
    final verified = transfer.remoteVerified == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.sync_outlined),
            const SizedBox(width: 10),
            Expanded(child: Text(transfer.operationId ?? 'Unknown operation',
              style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(status, style: Theme.of(context).textTheme.labelMedium),
          ]),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(total == null
              ? '${_formatBytes(acknowledged)} acknowledged'
              : '${_formatBytes(acknowledged)} / ${_formatBytes(total)}',
              style: Theme.of(context).textTheme.bodySmall)),
            Icon(verified ? Icons.verified_outlined : Icons.pending_outlined, size: 17),
            const SizedBox(width: 5),
            Text(verified ? 'Remote verified' : 'Not verified',
              style: Theme.of(context).textTheme.bodySmall),
          ]),
        ]),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
