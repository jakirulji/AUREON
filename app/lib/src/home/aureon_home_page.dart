import 'dart:async';
import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/material.dart';

class AureonHomePage extends StatefulWidget {
  const AureonHomePage({super.key, required this.isDarkMode, required this.onThemeChanged});

  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<AureonHomePage> createState() => _AureonHomePageState();
}

class _AureonHomePageState extends State<AureonHomePage>
    with WidgetsBindingObserver {
  final DiskSpacePlus _disk = DiskSpacePlus();
  Timer? _refreshTimer;
  double? _totalMb;
  double? _freeMb;
  DateTime? _updatedAt;
  String? _error;
  bool _loading = true;

  static const _accent = Color(0xFF8B7CFF);
  static const _accentBlue = Color(0xFF65D5FF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStorage();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshStorage(showLoader: false),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStorage(showLoader: false);
    }
  }

  Future<void> _refreshStorage({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw UnsupportedError('Live device storage metrics are currently enabled on Android.');
      }
      final values = await Future.wait<double?>([
        _disk.getTotalDiskSpace,
        _disk.getFreeDiskSpace,
      ]);
      final total = values[0];
      final free = values[1];
      if (total == null || free == null || total <= 0 || free < 0) {
        throw StateError('The device did not return valid storage information.');
      }
      if (!mounted) return;
      setState(() {
        _totalMb = total;
        _freeMb = free.clamp(0, total);
        _updatedAt = DateTime.now();
        _error = null;
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

  String _formatMb(double mb) {
    if (mb >= 1024 * 1024) return '${(mb / (1024 * 1024)).toStringAsFixed(2)} TB';
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  String get _updatedLabel {
    final value = _updatedAt;
    if (value == null) return 'Waiting for device data';
    final local = TimeOfDay.fromDateTime(value);
    return 'Updated ${local.format(context)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final panel = scheme.surface;
    final panelBorder = scheme.outlineVariant;
    final total = _totalMb;
    final free = _freeMb;
    final used = total != null && free != null ? (total - free).clamp(0, total).toDouble() : null;
    final ratio = total != null && used != null && total > 0
        ? (used / total).clamp(0.0, 1.0).toDouble()
        : null;

    return RefreshIndicator(
      onRefresh: _refreshStorage,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Digital Universe',
                      style: TextStyle(color: muted, fontSize: 12, letterSpacing: .4)),
                    SizedBox(height: 5),
                    Text('Storage overview',
                      style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              IconButton(
                tooltip: widget.isDarkMode ? 'Switch to light theme' : 'Switch to dark theme',
                onPressed: () => widget.onThemeChanged(!widget.isDarkMode),
                icon: Icon(widget.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              ),
              IconButton(
                tooltip: 'Refresh storage information',
                onPressed: _loading ? null : () => _refreshStorage(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(19),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.isDarkMode
                    ? [const Color(0xFF24204A), const Color(0xFF172B4A), const Color(0xFF111A2E)]
                    : [const Color(0xFFE8E5FF), const Color(0xFFE7F3FF), Colors.white],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: widget.isDarkMode ? const Color(0xFF514A83) : const Color(0xFFC9C5F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phone_android_rounded, color: _accent, size: 19),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('DEVICE STORAGE',
                        style: TextStyle(fontSize: 11, letterSpacing: 1.3,
                          fontWeight: FontWeight.w700, color: widget.isDarkMode ? const Color(0xFFD0C9FF) : const Color(0xFF514A83))),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: widget.isDarkMode ? const Color(0xFF332D62) : const Color(0xFFE2DEFF),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Row(children: [
                        Icon(Icons.circle, color: _accent, size: 7),
                        SizedBox(width: 6),
                        Text('LIVE', style: TextStyle(color: _accent, fontSize: 10,
                          fontWeight: FontWeight.w800, letterSpacing: .8)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_loading && total == null)
                  const LinearProgressIndicator(minHeight: 3)
                else if (ratio != null) ...[
                  Text(_formatMb(used!),
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800,
                      letterSpacing: -.8)),
                  const SizedBox(height: 3),
                  Text('used of ${_formatMb(total!)}',
                    style: TextStyle(color: widget.isDarkMode ? const Color(0xFFC2CDE0) : const Color(0xFF526579), fontSize: 13)),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 10,
                      backgroundColor: widget.isDarkMode ? const Color(0xFF3A3B63) : const Color(0xFFD8DDF2),
                      valueColor: const AlwaysStoppedAnimation<Color>(_accent),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text('${(ratio * 100).toStringAsFixed(1)}% used',
                        style: const TextStyle(color: _accent, fontWeight: FontWeight.w700, fontSize: 12)),
                      const Spacer(),
                      Text('${_formatMb(free!)} available',
                        style: TextStyle(color: widget.isDarkMode ? const Color(0xFFD6D2F2) : const Color(0xFF526579), fontSize: 12)),
                    ],
                  ),
                ] else ...[
                  const Text('Storage information unavailable',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  const SizedBox(height: 7),
                  Text(_error ?? 'Waiting for Android storage information.',
                    style: TextStyle(color: widget.isDarkMode ? const Color(0xFFB7C7D8) : const Color(0xFF526579), fontSize: 12)),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _loading ? null : () => _refreshStorage(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ),
                ],
                const SizedBox(height: 13),
                Row(children: [
                  Icon(Icons.sync, size: 14, color: muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_updatedLabel, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 11))),
                  const SizedBox(width: 8),
                  Text('Refresh · 30s',
                    style: TextStyle(color: muted, fontSize: 10)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _metricCard(
                icon: Icons.storage_rounded,
                label: 'Total capacity',
                value: total == null ? '—' : _formatMb(total),
              )),
              const SizedBox(width: 10),
              Expanded(child: _metricCard(
                icon: Icons.delete_sweep_outlined,
                label: 'Used space',
                value: used == null ? '—' : _formatMb(used),
              )),
              const SizedBox(width: 10),
              Expanded(child: _metricCard(
                icon: Icons.check_circle_outline_rounded,
                label: 'Available',
                value: free == null ? '—' : _formatMb(free),
              )),
            ],
          ),
          const SizedBox(height: 22),
          Text('CLOUD STORAGE',
            style: TextStyle(fontSize: 11, letterSpacing: 1.3,
              color: muted, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: panelBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_outlined, color: _accent, size: 25),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AUREON cloud pool',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      SizedBox(height: 5),
                      Text('Live provider capacity will appear here when cloud-account OAuth and provider storage APIs are connected. No cloud totals are fabricated.',
                        style: TextStyle(color: muted, fontSize: 12, height: 1.45)),
                      SizedBox(height: 9),
                      Text('PROVIDER CONNECTION PENDING',
                        style: TextStyle(color: Color(0xFFFFD27A), fontSize: 10,
                          letterSpacing: .7, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: panelBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: _accent, size: 19),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Device storage is read directly from the phone. Pull down to refresh; the dashboard also refreshes every 30 seconds and when the app returns to the foreground.',
                    style: TextStyle(color: muted, fontSize: 11, height: 1.4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(11, 13, 8, 13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _accent, size: 18),
        const SizedBox(height: 11),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ),
  );
}
