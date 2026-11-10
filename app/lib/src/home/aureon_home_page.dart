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

class _AureonHomePageState extends State<AureonHomePage> with WidgetsBindingObserver {
  final DiskSpacePlus _disk = DiskSpacePlus();
  Timer? _timer;
  double? _total;
  double? _free;
  DateTime? _updated;
  String? _error;
  bool _loading = true;

  static const violet = Color(0xFF9B8CFF);
  static const ice = Color(0xFF8EDCFF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh(showLoader: false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(showLoader: false);
  }

  Future<void> _refresh({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() { _loading = true; _error = null; });
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw UnsupportedError('Live device storage metrics are currently enabled on Android.');
      }
      final values = await Future.wait<double?>([_disk.getTotalDiskSpace, _disk.getFreeDiskSpace]);
      final total = values[0];
      final free = values[1];
      if (total == null || free == null || total <= 0 || free < 0) {
        throw StateError('The device did not return valid storage information.');
      }
      if (!mounted) return;
      setState(() {
        _total = total;
        _free = free.clamp(0, total);
        _updated = DateTime.now();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _format(double mb) {
    if (mb >= 1024 * 1024) return '${(mb / (1024 * 1024)).toStringAsFixed(2)} TB';
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDarkMode;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final used = _total != null && _free != null ? (_total! - _free!).clamp(0, _total!).toDouble() : null;
    final ratio = _total != null && used != null ? (used / _total!).clamp(0.0, 1.0).toDouble() : null;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 34),
        children: [
          _header(dark, muted),
          const SizedBox(height: 28),
          const Text('YOUR DIGITAL UNIVERSE', style: TextStyle(color: violet, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 7),
          const Text('Everything, in one place.', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.8)),
          const SizedBox(height: 6),
          Text('A clear view of your digital space.', style: TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 22),
          _hero(dark, muted, used, ratio),
          const SizedBox(height: 26),
          _section('STORAGE INSIGHTS', 'DEVICE'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _metric(Icons.storage_rounded, 'Total capacity', _total == null ? '—' : _format(_total!), dark)),
            const SizedBox(width: 9),
            Expanded(child: _metric(Icons.folder_open_rounded, 'Space used', used == null ? '—' : _format(used), dark)),
            const SizedBox(width: 9),
            Expanded(child: _metric(Icons.savings_outlined, 'Available', _free == null ? '—' : _format(_free!), dark)),
          ]),
          const SizedBox(height: 27),
          _section('YOUR CLOUD', 'UNIFIED STORAGE'),
          const SizedBox(height: 12),
          _cloudCard(dark, muted),
          const SizedBox(height: 18),
          _privacyCard(dark, muted),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.sync_rounded, size: 14, color: muted),
            const SizedBox(width: 7),
            Expanded(child: Text(_updated == null ? 'Waiting for device data' : 'Updated ${TimeOfDay.fromDateTime(_updated!).format(context)}  ·  Auto-refresh 30s',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 10))),
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'Refresh storage',
              onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh_rounded, size: 18)),
          ]),
        ],
      ),
    );
  }

  Widget _header(bool dark, Color muted) => Row(children: [
    Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [violet, Color(0xFF536DDB)]),
        boxShadow: [BoxShadow(color: violet.withOpacity(dark ? .28 : .16), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 28),
    ),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('AUREON', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2.2)),
      Text('YOUR DIGITAL UNIVERSE', style: TextStyle(color: muted, fontSize: 8, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
    ])),
    _action(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, dark ? 'Light theme' : 'Dark theme',
      () => widget.onThemeChanged(!dark), dark),
    const SizedBox(width: 7),
    _action(Icons.refresh_rounded, 'Refresh storage', _loading ? null : _refresh, dark),
  ]);

  Widget _action(IconData icon, String tip, VoidCallback? tap, bool dark) => Material(
    color: dark ? const Color(0xFF1A2540) : Colors.white,
    shape: CircleBorder(side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
    child: IconButton(tooltip: tip, onPressed: tap, icon: Icon(icon, size: 19),
      constraints: const BoxConstraints.tightFor(width: 42, height: 42), padding: EdgeInsets.zero),
  );

  Widget _hero(bool dark, Color muted, double? used, double? ratio) {
    final soft = dark ? const Color(0xFFC7C8E8) : const Color(0xFF52617D);
    final foreground = dark ? Colors.white : const Color(0xFF171D39);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: dark ? const [Color(0xFF29234F), Color(0xFF202D55), Color(0xFF14263F)]
            : const [Color(0xFFE9E5FF), Color(0xFFE2F1FF), Color(0xFFF8FBFF)]),
        border: Border.all(color: dark ? const Color(0xFF514A83) : const Color(0xFFC9C5F0)),
        boxShadow: [BoxShadow(color: violet.withOpacity(.11), blurRadius: 26, offset: const Offset(0, 11))],
      ),
      child: Stack(children: [
        Positioned(right: -38, top: -58, child: Container(width: 170, height: 170,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: violet.withOpacity(.13), width: 25)))),
        Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: dark ? const Color(0xFF40396D) : const Color(0xFFDCD7FF), borderRadius: BorderRadius.circular(30)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.phone_android_rounded, color: violet, size: 14),
                const SizedBox(width: 6),
                Text('DEVICE STORAGE', style: TextStyle(color: dark ? const Color(0xFFE0DAFF) : const Color(0xFF514A83), fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w900)),
              ])),
            const Spacer(),
            const Icon(Icons.circle, color: Color(0xFF55D6A3), size: 7),
            const SizedBox(width: 6),
            Text('LIVE DATA', style: TextStyle(color: soft, fontSize: 9, letterSpacing: .8, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('You are using', style: TextStyle(color: soft, fontSize: 12)),
              const SizedBox(height: 6),
              if (_loading && _total == null)
                const SizedBox(width: 110, child: LinearProgressIndicator(minHeight: 3))
              else
                Text(used == null ? '—' : _format(used), style: TextStyle(color: foreground, fontSize: 31, fontWeight: FontWeight.w900, letterSpacing: -1)),
              const SizedBox(height: 5),
              Text(_total == null ? 'of device capacity' : 'of ${_format(_total!)} total', style: TextStyle(color: soft, fontSize: 12)),
            ])),
            const SizedBox(width: 12),
            SizedBox(width: 108, height: 108, child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(child: CircularProgressIndicator(value: ratio, strokeWidth: 9, strokeCap: StrokeCap.round,
                backgroundColor: dark ? const Color(0xFF424366) : const Color(0xFFD0D5EC),
                valueColor: const AlwaysStoppedAnimation<Color>(violet))),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(ratio == null ? '—' : '${(ratio * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: foreground, fontSize: 22, fontWeight: FontWeight.w900)),
                Text('USED', style: TextStyle(color: soft, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              ]),
            ])),
          ]),
          const SizedBox(height: 22),
          Container(height: 1, color: dark ? Colors.white.withOpacity(.12) : const Color(0xFFBFC8E3)),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF55D6A3), size: 16),
            const SizedBox(width: 7),
            Expanded(child: Text('Available space', style: TextStyle(color: soft, fontSize: 11))),
            Text(_free == null ? '—' : _format(_free!), style: TextStyle(color: foreground, fontSize: 13, fontWeight: FontWeight.w800)),
          ]),
          if (_error != null && _total == null) ...[
            const SizedBox(height: 10),
            Text('Storage data unavailable: $_error', style: TextStyle(color: soft, fontSize: 10)),
          ],
        ])),
      ]),
    );
  }

  Widget _section(String title, String trailing) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(children: [
      Text(title, style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w900)),
      const Spacer(),
      Text(trailing, style: TextStyle(color: muted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .7)),
    ]);
  }

  Widget _metric(IconData icon, String label, String value, bool dark) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.fromLTRB(11, 13, 9, 12),
      decoration: BoxDecoration(color: dark ? const Color(0xFF131D32) : Colors.white,
        borderRadius: BorderRadius.circular(17), border: Border.all(color: scheme.outlineVariant.withOpacity(.75))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: violet, size: 18),
        const SizedBox(height: 12),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -.3))),
        const SizedBox(height: 4),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
      ]),
    );
  }

  Widget _cloudCard(bool dark, Color muted) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(color: dark ? const Color(0xFF131D32) : Colors.white,
      borderRadius: BorderRadius.circular(20), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(.75))),
    child: Column(children: [
      Row(children: [
        Container(width: 43, height: 43, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: [violet, Color(0xFF536DDB)])),
          child: const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 23)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('AUREON Cloud Pool', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('One space for all your clouds', style: TextStyle(color: muted, fontSize: 11)),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(color: dark ? const Color(0xFF40351E) : const Color(0xFFFFF1D5), borderRadius: BorderRadius.circular(30)),
          child: const Text('IN SETUP', style: TextStyle(color: Color(0xFFE8B95E), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .6))),
      ]),
      const SizedBox(height: 15),
      Container(width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: dark ? const Color(0xFF1A2740) : const Color(0xFFF3F5FC), borderRadius: BorderRadius.circular(13)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, color: ice, size: 17),
          const SizedBox(width: 9),
          Expanded(child: Text('Connect your cloud providers to see combined capacity and account-level storage here. Live cloud totals are not available yet.',
            style: TextStyle(color: muted, fontSize: 11, height: 1.45))),
        ])),
    ]),
  );

  Widget _privacyCard(bool dark, Color muted) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
    decoration: BoxDecoration(color: dark ? const Color(0xFF102B2C) : const Color(0xFFEAF8F5),
      borderRadius: BorderRadius.circular(17), border: Border.all(color: dark ? const Color(0xFF24504C) : const Color(0xFFCBE9E0))),
    child: Row(children: [
      const Icon(Icons.shield_moon_rounded, color: Color(0xFF55C9A3), size: 22),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your space. Your control.', style: TextStyle(color: dark ? const Color(0xFFB7F1DE) : const Color(0xFF176A56), fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text('AUREON is designed around secure, unified file management.', style: TextStyle(color: muted, fontSize: 10, height: 1.35)),
      ])),
    ]),
  );
}
