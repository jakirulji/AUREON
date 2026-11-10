import 'dart:async';
import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/material.dart';
import '../files/aureon_operation_history.dart';

class AureonHomePage extends StatefulWidget {
  const AureonHomePage({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
    required this.onBrowseCategory,
  });
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;
  final ValueChanged<String> onBrowseCategory;

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
  List<AureonOperationRecord> _recentFiles = [];

  static const violet = Color(0xFF9B8CFF);
  static const _categories = <_HomeCategory>[
    _HomeCategory('Images', 'images', Icons.image_rounded, Color(0xFFD5A7FF), Color(0xFF302541)),
    _HomeCategory('Videos', 'videos', Icons.movie_creation_rounded, Color(0xFF91BFFF), Color(0xFF202F4B)),
    _HomeCategory('Audio', 'audio', Icons.graphic_eq_rounded, Color(0xFF9DE0DC), Color(0xFF203B40)),
    _HomeCategory('Documents', 'documents', Icons.description_rounded, Color(0xFFAFC8FF), Color(0xFF25334B)),
    _HomeCategory('Downloads', 'downloads', Icons.downloading_rounded, Color(0xFFA5D9BD), Color(0xFF233B37)),
    _HomeCategory('APKs', 'apks', Icons.android_rounded, Color(0xFFE8C38C), Color(0xFF403526)),
    _HomeCategory('Archives', 'archives', Icons.inventory_2_rounded, Color(0xFFC1B6FF), Color(0xFF302C4C)),
    _HomeCategory('Other', 'other', Icons.insert_drive_file_rounded, Color(0xFF9EB7D8), Color(0xFF263448)),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _loadRecentFiles();
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

  Future<void> _loadRecentFiles() async {
    try {
      final records = await AureonOperationHistory.load();
      if (!mounted) return;
      final seen = <String>{};
      final recent = records.where((row) => row.kind == 'open' && row.succeeded &&
        seen.add('${row.itemName}| ${row.sourceLocation}')).take(4).toList();
      setState(() => _recentFiles = recent);
    } catch (_) {
      if (mounted) setState(() => _recentFiles = []);
    }
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          _header(dark, muted),
          const SizedBox(height: 22),
          Text('YOUR DIGITAL UNIVERSE', style: TextStyle(color: violet, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 5),
          const Text('Everything, in one place.', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -.7)),
          const SizedBox(height: 4),
          Text('Your files, beautifully organized.', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 18),
          _storageCard(dark, muted, used, ratio),
          const SizedBox(height: 23),
          Row(children: [
            const Expanded(child: Text('BROWSE CATEGORIES', style: TextStyle(fontSize: 10, letterSpacing: 1.45, fontWeight: FontWeight.w900))),
            Text('LOCAL FILES', style: TextStyle(color: muted, fontSize: 9, letterSpacing: .8, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 11),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: .91,
            ),
            itemBuilder: (context, index) {
              final category = _categories[index];
              return _categoryTile(category, dark);
            },
          ),
          const SizedBox(height: 21),
          _recentFilesCard(dark, muted),
          const SizedBox(height: 13),
          _cloudCard(dark, muted),
          const SizedBox(height: 12),
          _privacyCard(dark, muted),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.sync_rounded, size: 13, color: muted),
            const SizedBox(width: 6),
            Expanded(child: Text(
              _updated == null ? (_error == null ? 'Waiting for device data' : 'Device storage data unavailable') :
                'Updated ${TimeOfDay.fromDateTime(_updated!).format(context)} · Auto-refresh 30s',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 9),
            )),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Refresh storage',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 17),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _header(bool dark, Color muted) => Row(children: [
    Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [violet, Color(0xFF536DDB)]),
        boxShadow: [BoxShadow(color: violet.withValues(alpha: dark ? .30 : .17), blurRadius: 17, offset: const Offset(0, 5))],
      ),
      child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 27),
    ),
    const SizedBox(width: 11),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('AUREON', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2.1)),
      Text('YOUR DIGITAL UNIVERSE', style: TextStyle(color: muted, fontSize: 8, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
    ])),
    _action(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, dark ? 'Light theme' : 'Dark theme',
      () => widget.onThemeChanged(!dark), dark),
    const SizedBox(width: 7),
    _action(Icons.refresh_rounded, 'Refresh storage', _loading ? null : _refresh, dark),
  ]);

  Widget _action(IconData icon, String tip, VoidCallback? tap, bool dark) => Material(
    color: dark ? const Color(0xFF1A2540) : Colors.white,
    shape: CircleBorder(side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
    child: IconButton(tooltip: tip, onPressed: tap, icon: Icon(icon, size: 18),
      constraints: const BoxConstraints.tightFor(width: 40, height: 40), padding: EdgeInsets.zero),
  );

  Widget _storageCard(bool dark, Color muted, double? used, double? ratio) {
    final foreground = dark ? Colors.white : const Color(0xFF171D39);
    final soft = dark ? const Color(0xFFC7C8E8) : const Color(0xFF52617D);
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: dark ? const [Color(0xFF29234F), Color(0xFF202D55), Color(0xFF14263F)]
            : const [Color(0xFFE9E5FF), Color(0xFFE2F1FF), Color(0xFFF8FBFF)]),
        border: Border.all(color: dark ? const Color(0xFF514A83) : const Color(0xFFC9C5F0)),
        boxShadow: [BoxShadow(color: violet.withValues(alpha: .10), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.phone_android_rounded, color: violet, size: 15),
          const SizedBox(width: 7),
          Text('DEVICE STORAGE', style: TextStyle(color: soft, fontSize: 9, letterSpacing: 1.15, fontWeight: FontWeight.w900)),
          const Spacer(),
          const Icon(Icons.circle, color: Color(0xFF55D6A3), size: 6),
          const SizedBox(width: 5),
          Text('LIVE', style: TextStyle(color: soft, fontSize: 9, letterSpacing: .8, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Used storage', style: TextStyle(color: soft, fontSize: 11)),
            const SizedBox(height: 3),
            if (_loading && _total == null)
              const SizedBox(width: 90, child: LinearProgressIndicator(minHeight: 3))
            else
              Text(used == null ? '—' : _format(used), style: TextStyle(color: foreground, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.8)),
            const SizedBox(height: 3),
            Text(_total == null ? 'of device capacity' : 'of ${_format(_total!)} total', style: TextStyle(color: soft, fontSize: 10)),
          ])),
          SizedBox(width: 72, height: 72, child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(child: CircularProgressIndicator(value: ratio, strokeWidth: 7, strokeCap: StrokeCap.round,
              backgroundColor: dark ? const Color(0xFF424366) : const Color(0xFFD0D5EC),
              valueColor: const AlwaysStoppedAnimation<Color>(violet))),
            Text(ratio == null ? '—' : '${(ratio * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: foreground, fontSize: 17, fontWeight: FontWeight.w900)),
          ])),
        ]),
        const SizedBox(height: 13),
        Container(height: 1, color: dark ? Colors.white.withValues(alpha: .12) : const Color(0xFFBFC8E3)),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.check_circle_rounded, color: const Color(0xFF55D6A3), size: 14),
          const SizedBox(width: 6),
          Expanded(child: Text('Available space', style: TextStyle(color: soft, fontSize: 10))),
          Text(_free == null ? '—' : _format(_free!), style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
        if (_error != null && _total == null) ...[
          const SizedBox(height: 7),
          Text('Storage details unavailable on this device.', style: TextStyle(color: soft, fontSize: 10)),
        ],
      ]),
    );
  }

  Widget _categoryTile(_HomeCategory category, bool dark) {
    final tile = dark ? const Color(0xFF131D32) : Colors.white;
    return Material(
      color: tile,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => widget.onBrowseCategory(category.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .75)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 43, height: 43,
              decoration: BoxDecoration(
                color: category.background.withValues(alpha: dark ? .95 : .62),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: category.foreground.withValues(alpha: dark ? .10 : .07), blurRadius: 12)],
              ),
              child: Icon(category.icon, color: category.foreground, size: 23),
            ),
            const SizedBox(height: 7),
            Text(category.label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  Widget _recentFilesCard(bool dark, Color muted) {
    final surface = dark ? const Color(0xFF131D32) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .75))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('RECENT FILES', style: TextStyle(fontSize: 10, letterSpacing: 1.35, fontWeight: FontWeight.w900))),
          Text('OPENED', style: TextStyle(color: muted, fontSize: 8, letterSpacing: .8, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        if (_recentFiles.isEmpty)
          Row(children: [
            Icon(Icons.history_rounded, color: muted, size: 19),
            const SizedBox(width: 9),
            Expanded(child: Text('Files you open in AUREON will appear here.', style: TextStyle(color: muted, fontSize: 10))),
          ])
        else
          for (var i = 0; i < _recentFiles.length; i++) ...[
            if (i > 0) Divider(height: 13, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .55)),
            Row(children: [
              Container(width: 35, height: 35, decoration: BoxDecoration(
                color: dark ? const Color(0xFF292443) : const Color(0xFFECE8FF), borderRadius: BorderRadius.circular(11)),
                child: Icon(_recentIcon(_recentFiles[i].itemName), color: violet, size: 18)),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_recentFiles[i].itemName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                Text(_recentFiles[i].sourceLocation, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 9)),
              ])),
              Icon(Icons.more_horiz_rounded, color: muted, size: 18),
            ]),
          ],
      ]),
    );
  }

  IconData _recentIcon(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (const {'jpg','jpeg','png','gif','webp','heic'}.contains(ext)) return Icons.image_rounded;
    if (const {'mp4','mkv','mov','avi','webm'}.contains(ext)) return Icons.movie_rounded;
    if (const {'mp3','m4a','wav','flac','ogg'}.contains(ext)) return Icons.audio_file_rounded;
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (const {'zip','rar','7z','tar','gz'}.contains(ext)) return Icons.archive_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Widget _cloudCard(bool dark, Color muted) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: dark ? const Color(0xFF131D32) : Colors.white,
      borderRadius: BorderRadius.circular(19), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .75))),
    child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(colors: [violet, Color(0xFF536DDB)])),
        child: const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 22)),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('AUREON Cloud Pool', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text('Unified storage · setup required', style: TextStyle(color: muted, fontSize: 10)),
      ])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: dark ? const Color(0xFF40351E) : const Color(0xFFFFF1D5), borderRadius: BorderRadius.circular(30)),
        child: const Text('IN SETUP', style: TextStyle(color: Color(0xFFE8B95E), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: .5))),
    ]),
  );

  Widget _privacyCard(bool dark, Color muted) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: dark ? const Color(0xFF102B2C) : const Color(0xFFEAF8F5),
      borderRadius: BorderRadius.circular(16), border: Border.all(color: dark ? const Color(0xFF24504C) : const Color(0xFFCBE9E0))),
    child: Row(children: [
      const Icon(Icons.shield_moon_rounded, color: Color(0xFF55C9A3), size: 21),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your space. Your control.', style: TextStyle(color: dark ? const Color(0xFFB7F1DE) : const Color(0xFF176A56), fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('Secure, unified file management.', style: TextStyle(color: muted, fontSize: 9)),
      ])),
    ]),
  );
}

class _HomeCategory {
  const _HomeCategory(this.label, this.key, this.icon, this.foreground, this.background);
  final String label;
  final String key;
  final IconData icon;
  final Color foreground;
  final Color background;
}
