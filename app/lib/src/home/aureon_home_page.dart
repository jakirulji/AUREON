import 'dart:async';
import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:material_ui/material_ui.dart';
import '../files/aureon_operation_history.dart';

class AureonHomePage extends StatefulWidget {
  const AureonHomePage({
    super.key,
    required this.isDarkMode,
    required this.onBrowseCategory,
    required this.onOpenFiles,
    required this.onOpenProfile,
    required this.onOpenCloud,
  });

  final bool isDarkMode;
  final ValueChanged<String> onBrowseCategory;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenCloud;

  @override
  State<AureonHomePage> createState() => _AureonHomePageState();
}

class _AureonHomePageState extends State<AureonHomePage>
    with WidgetsBindingObserver {
  final DiskSpacePlus _disk = DiskSpacePlus();
  Timer? _timer;
  double? _total;
  double? _free;
  bool _loading = true;
  List<AureonOperationRecord> _recentFiles = [];

  static const _violet = Color(0xFF8057F5);
  static const _categories = <_HomeCategory>[
    _HomeCategory('Images', 'images', Color(0xFFE84CB7), Color(0xFFFFD9ED), Color(0xFF51214A)),
    _HomeCategory('Videos', 'videos', Color(0xFF2875DF), Color(0xFFDCEBFF), Color(0xFF1C355C)),
    _HomeCategory('Audio', 'audio', Color(0xFF079B70), Color(0xFFD7F7EB), Color(0xFF173F39)),
    _HomeCategory('Documents', 'documents', Color(0xFF8050DF), Color(0xFFE9DFFF), Color(0xFF33265B)),
    _HomeCategory('Downloads', 'downloads', Color(0xFF0AA878), Color(0xFFD8F7E9), Color(0xFF1B493C)),
    _HomeCategory('APKs', 'apks', Color(0xFF9B5A16), Color(0xFFFFE8C8), Color(0xFF49351F)),
    _HomeCategory('Archives', 'archives', Color(0xFF7650D8), Color(0xFFE9DFFF), Color(0xFF30254F)),
    _HomeCategory('Other', 'other', Color(0xFF2875D8), Color(0xFFDCEBFF), Color(0xFF20395E)),
  ];

  bool get _dark => widget.isDarkMode;
  Color get _ink => _dark ? const Color(0xFFF5F4FF) : const Color(0xFF111832);
  Color get _muted => _dark ? const Color(0xFF9DA9C8) : const Color(0xFF65718E);
  Color get _surface => _dark ? const Color(0xFF111A31) : Colors.white;
  Color get _line => _dark ? const Color(0xFF273454) : const Color(0xFFE3E8F5);

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
    if (state == AppLifecycleState.resumed) {
      _refresh(showLoader: false);
      _loadRecentFiles();
    }
  }

  Future<void> _loadRecentFiles() async {
    try {
      final records = await AureonOperationHistory.load();
      if (!mounted) return;
      final seen = <String>{};
      final recent = records.where((row) =>
        row.kind == 'open' && row.succeeded &&
        seen.add('${row.itemName}|${row.sourceLocation}')).take(3).toList();
      setState(() => _recentFiles = recent);
    } catch (_) {
      if (mounted) setState(() => _recentFiles = []);
    }
  }

  Future<void> _refresh({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _loading = true);
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw UnsupportedError('Live device storage metrics are available on mobile.');
      }
      final values = await Future.wait<double?>([
        _disk.getTotalDiskSpace,
        _disk.getFreeDiskSpace,
      ]);
      final total = values[0];
      final free = values[1];
      if (total == null || free == null || total <= 0 || free < 0) {
        throw StateError('Invalid device storage information.');
      }
      if (!mounted) return;
      setState(() {
        _total = total;
        _free = free.clamp(0, total);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _format(double mb) {
    if (mb >= 1024 * 1024) return '${(mb / (1024 * 1024)).toStringAsFixed(1)} TB';
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final used = _total != null && _free != null
        ? (_total! - _free!).clamp(0, _total!).toDouble() : null;
    final ratio = _total != null && used != null
        ? (used / _total!).clamp(0.0, 1.0).toDouble() : null;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: _violet,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(17, 13, 17, 24),
        children: [
          _header(),
          const SizedBox(height: 17),
          _storageCard(used, ratio),
          const SizedBox(height: 22),
          _sectionHeading('Browse Categories', 'View All', widget.onOpenFiles,
            Icons.grid_view_rounded),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 9,
              mainAxisSpacing: 9,
              childAspectRatio: .82,
            ),
            itemBuilder: (context, index) => _categoryTile(_categories[index]),
          ),
          const SizedBox(height: 22),
          _sectionHeading('Recent Files', 'See All', widget.onOpenFiles,
            Icons.access_time_rounded),
          const SizedBox(height: 10),
          _recentFilesCard(),
          const SizedBox(height: 13),
          _cloudCard(),
          const SizedBox(height: 18),
          Row(children: [
            Icon(Icons.sync_rounded, size: 13, color: _muted),
            const SizedBox(width: 6),
            Expanded(child: Text(
              _updatedLabel(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _muted, fontSize: 9),
            )),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Refresh storage',
              onPressed: _loading ? null : _refresh,
              icon: Icon(Icons.refresh_rounded, size: 17, color: _muted),
            ),
          ]),
        ],
      ),
    );
  }

  String _updatedLabel() {
    if (_total == null) return _loading ? 'Updating device storage…' : 'Device storage data unavailable';
    return 'Live device storage · Auto-refresh every 30 seconds';
  }

  Widget _header() => SizedBox(
    height: 66,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -28, right: -25, top: -24, bottom: -12,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _HeaderWavePainter(dark: _dark),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: Row(children: [
            SizedBox(
              width: 49, height: 49,
              child: CustomPaint(painter: _AureonMarkPainter()),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AUREON', style: TextStyle(color: _ink, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: .5)),
                Text('YOUR DIGITAL UNIVERSE', style: TextStyle(color: _muted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .6)),
              ],
            )),
            _headerAction(Icons.search_rounded, 'Search files', widget.onOpenFiles),
            _headerAction(Icons.notifications_none_rounded, 'Notifications', () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('You are all caught up.')),
              );
            }, dot: true),
            const SizedBox(width: 3),
            GestureDetector(
              onTap: widget.onOpenProfile,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF5579D8),
                child: const Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ],
    ),
  );

  Widget _headerAction(IconData icon, String tip, VoidCallback onTap, {bool dot = false}) =>
    Stack(clipBehavior: Clip.none, children: [
      IconButton(
        onPressed: onTap,
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: _ink, size: 24),
      ),
      if (dot) Positioned(right: 7, top: 7, child: Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(color: Color(0xFFFF455D), shape: BoxShape.circle),
      )),
    ]);

  Widget _sectionHeading(String title, String action, VoidCallback onTap, IconData icon) =>
    Row(children: [
      Icon(icon, color: _ink, size: 19),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800))),
      TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: _violet, padding: const EdgeInsets.symmetric(horizontal: 3)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(action, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 3),
          const Icon(Icons.arrow_forward_rounded, size: 16),
        ]),
      ),
    ]);

  Widget _storageCard(double? used, double? ratio) {
    final cardColors = _dark
      ? const [Color(0xFF20234D), Color(0xFF182B4B), Color(0xFF111E3B)]
      : const [Color(0xFFFFFFFF), Color(0xFFF1F3FF), Color(0xFFE8F2FF)];
    final soft = _dark ? const Color(0xFFC5C9E8) : const Color(0xFF65718E);
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cardColors),
        border: Border.all(color: _dark ? const Color(0xFF414A83) : const Color(0xFFDDE2F5)),
        boxShadow: [BoxShadow(color: _violet.withValues(alpha: _dark ? .15 : .09), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.storage_rounded, color: _ink, size: 18),
          const SizedBox(width: 7),
          Expanded(child: Text('Storage Overview', style: TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800))),
          TextButton(
            onPressed: widget.onOpenCloud,
            style: TextButton.styleFrom(foregroundColor: _violet, padding: EdgeInsets.zero),
            child: const Row(children: [Text('View Details', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)), SizedBox(width: 4), Icon(Icons.arrow_forward_rounded, size: 15)]),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
            width: 94, height: 94,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(child: CircularProgressIndicator(
                value: ratio,
                strokeWidth: 9,
                strokeCap: StrokeCap.round,
                backgroundColor: _dark ? const Color(0xFF343B70) : const Color(0xFFDDE3F8),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4D8DF4)),
              )),
              Icon(Icons.storage_rounded, color: _dark ? const Color(0xFFD3D6FF) : const Color(0xFF202C5A), size: 31),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(used == null ? '—' : _format(used),
              style: TextStyle(color: _ink, fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: -1)),
            Text('Used storage', style: TextStyle(color: soft, fontSize: 11)),
            const SizedBox(height: 3),
            Text(_total == null ? 'of device capacity' : 'of ${_format(_total!)} total',
              style: TextStyle(color: soft, fontSize: 11)),
          ])),
          Container(width: 1, height: 57, color: _line),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_free == null ? '—' : _format(_free!),
              style: TextStyle(color: _ink, fontSize: 19, fontWeight: FontWeight.w800)),
            Text('Available', style: TextStyle(color: soft, fontSize: 11)),
          ])),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            minHeight: 9,
            value: ratio,
            backgroundColor: _dark ? const Color(0xFF303A66) : const Color(0xFFD9E0F4),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF9360F6)),
          ),
        ),
      ]),
    );
  }

  Widget _categoryTile(_HomeCategory category) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: () => widget.onBrowseCategory(category.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
        decoration: BoxDecoration(
          color: _dark
              ? Color.alphaBlend(category.color.withValues(alpha: .12), const Color(0xFF17213B))
              : Color.alphaBlend(category.lightBackground.withValues(alpha: .62), Colors.white),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 39, height: 39,
            child: CustomPaint(painter: _CategoryGlyphPainter(category.key, category.color)),
          ),
          const SizedBox(height: 7),
          Text(category.label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _dark ? Colors.white : const Color(0xFF17203C), fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      ),
    ),
  );

  Widget _recentFilesCard() => Column(children: [
    if (_recentFiles.isEmpty)
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
        child: Row(children: [
          Icon(Icons.history_rounded, color: _muted, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text('Files you open in AUREON will appear here.',
            style: TextStyle(color: _muted, fontSize: 11))),
        ]),
      )
    else
      for (var i = 0; i < _recentFiles.length; i++) ...[
        if (i > 0) const SizedBox(height: 7),
        _recentFileRow(_recentFiles[i]),
      ],
  ]);

  Widget _recentFileRow(AureonOperationRecord record) {
    final name = record.itemName;
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    final path = record.sourceLocation;
    final imageExtensions = const {'jpg','jpeg','png','gif','webp','heic','bmp'};
    final isImage = imageExtensions.contains(ext);
    final file = File(path);
    final exists = path.isNotEmpty && file.existsSync();
    final fileBytes = exists ? _safeFileSize(file) : null;
    final icon = _recentIcon(ext);
    final iconColor = _recentIconColor(ext);
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(record.occurredAtMs).toLocal();
    final details = [
      if (fileBytes != null) _formatBytes(fileBytes),
      _relativeTime(occurredAt),
    ].join(' • ');
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: widget.onOpenFiles,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: _line),
            boxShadow: [
              BoxShadow(
                color: _dark
                  ? const Color(0xFF687BCE).withValues(alpha: .07)
                  : const Color(0xFF6B78B8).withValues(alpha: .07),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 39, height: 39,
                child: isImage && exists
                  ? Image.file(
                      file,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _fileIcon(icon, color: iconColor),
                    )
                  : _fileIcon(icon, color: iconColor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
              Text(details.isEmpty ? path : details, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted, fontSize: 9)),
            ])),
            Icon(Icons.more_vert_rounded, color: _muted, size: 19),
          ]),
        ),
      ),
    );
  }

  int? _safeFileSize(File file) {
    try {
      return file.lengthSync();
    } catch (_) {
      return null;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String _relativeTime(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Color _recentIconColor(String ext) {
    if (ext == 'pdf') return const Color(0xFFE53935);
    if (const {'jpg','jpeg','png','gif','webp','heic','bmp'}.contains(ext)) return const Color(0xFFE84CB7);
    if (const {'mp4','mkv','mov','avi','webm'}.contains(ext)) return const Color(0xFF2875DF);
    if (const {'mp3','m4a','wav','flac','ogg'}.contains(ext)) return const Color(0xFF079B70);
    if (const {'zip','rar','7z','tar','gz'}.contains(ext)) return const Color(0xFFE89A22);
    if (const {'doc','docx','txt','rtf'}.contains(ext)) return const Color(0xFF2875DF);
    if (const {'xls','xlsx','csv'}.contains(ext)) return const Color(0xFF159B69);
    if (const {'ppt','pptx'}.contains(ext)) return const Color(0xFFE66B36);
    if (const {'apk','aab'}.contains(ext)) return const Color(0xFF249B68);
    return _violet;
  }

  Widget _fileIcon(IconData icon, {Color? color}) => Container(
    color: (color ?? _violet).withValues(alpha: _dark ? .18 : .12),
    child: Icon(icon, color: color ?? _violet, size: 23),
  );

  IconData _recentIcon(String ext) {
    if (const {'jpg','jpeg','png','gif','webp','heic','bmp'}.contains(ext)) return Icons.image_rounded;
    if (const {'mp4','mkv','mov','avi','webm'}.contains(ext)) return Icons.movie_rounded;
    if (const {'mp3','m4a','wav','flac','ogg'}.contains(ext)) return Icons.audio_file_rounded;
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (const {'zip','rar','7z','tar','gz'}.contains(ext)) return Icons.archive_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Widget _cloudCard() => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: widget.onOpenCloud,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
            colors: [Color(0xFF38209D), Color(0xFF6545E7), Color(0xFF3859D9)]),
          boxShadow: [BoxShadow(color: _violet.withValues(alpha: .22), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .13), shape: BoxShape.circle),
            child: const Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 27),
          ),
          const SizedBox(width: 11),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Cloud Pool', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
            SizedBox(height: 3),
            Text('Connect your cloud accounts', style: TextStyle(color: Color(0xFFD9D3FF), fontSize: 10)),
          ])),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 23),
        ]),
      ),
    ),
  );
}


class _HomeCategory {
  const _HomeCategory(this.label, this.key, this.color,
      this.lightBackground, this.darkBackground);
  final String label;
  final String key;
  final Color color;
  final Color lightBackground;
  final Color darkBackground;
}

class _HeaderWavePainter extends CustomPainter {
  const _HeaderWavePainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final glow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.72, 0.42),
        radius: 1.05,
        colors: [
          const Color(0xFF8057F5).withValues(alpha: dark ? .28 : .20),
          const Color(0xFF438CFF).withValues(alpha: dark ? .15 : .12),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, glow);

    final wave1 = Path()
      ..moveTo(0, size.height * .68)
      ..cubicTo(size.width * .20, size.height * .10, size.width * .43, size.height * 1.10, size.width * .68, size.height * .48)
      ..cubicTo(size.width * .82, size.height * .12, size.width * .93, size.height * .20, size.width, size.height * .02);
    final wave2 = Path()
      ..moveTo(0, size.height * .88)
      ..cubicTo(size.width * .22, size.height * .36, size.width * .43, size.height * 1.12, size.width * .70, size.height * .68)
      ..cubicTo(size.width * .84, size.height * .42, size.width * .94, size.height * .44, size.width, size.height * .28);
    final p1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF9878FF).withValues(alpha: dark ? .34 : .27);
    final p2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF62A5FF).withValues(alpha: dark ? .28 : .22);
    canvas.drawPath(wave1, p1);
    canvas.drawPath(wave2, p2);
  }

  @override
  bool shouldRepaint(covariant _HeaderWavePainter oldDelegate) => oldDelegate.dark != dark;
}

class _AureonMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shadow = Paint()
      ..color = const Color(0xFF7554EF).withValues(alpha: .20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width * .43, shadow);
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFFB18AFF), Color(0xFF6939E8), Color(0xFF3E64D9)],
      ).createShader(rect);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width * .46, bg);
    final mark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white;
    final path = Path()
      ..moveTo(size.width * .22, size.height * .57)
      ..cubicTo(size.width * .32, size.height * .28, size.width * .43, size.height * .28, size.width * .51, size.height * .50)
      ..cubicTo(size.width * .61, size.height * .77, size.width * .73, size.height * .73, size.width * .80, size.height * .44)
      ..moveTo(size.width * .22, size.height * .57)
      ..cubicTo(size.width * .34, size.height * .80, size.width * .44, size.height * .75, size.width * .52, size.height * .51)
      ..cubicTo(size.width * .61, size.height * .25, size.width * .73, size.height * .27, size.width * .80, size.height * .44);
    canvas.drawPath(path, mark);
  }

  @override
  bool shouldRepaint(covariant _AureonMarkPainter oldDelegate) => false;
}

class _CategoryGlyphPainter extends CustomPainter {
  const _CategoryGlyphPainter(this.kind, this.color);
  final String kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final fill = Paint()..color = color.withValues(alpha: .14);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final solid = Paint()..color = color;
    final r = Rect.fromCenter(center: center, width: s * .62, height: s * .62);

    switch (kind) {
      case 'images':
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), fill);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), stroke);
        canvas.drawCircle(Offset(center.dx + s*.12, center.dy - s*.12), s*.055, solid);
        final p = Path()..moveTo(r.left+s*.06,r.bottom-s*.08)..lineTo(center.dx-s*.02,center.dy+s*.02)..lineTo(center.dx+s*.09,center.dy-s*.02)..lineTo(r.right-s*.05,r.bottom-s*.08);
        canvas.drawPath(p, stroke);
        break;
      case 'videos':
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), fill);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), stroke);
        final play = Path()..moveTo(center.dx-s*.09,center.dy-s*.14)..lineTo(center.dx+s*.17,center.dy)..lineTo(center.dx-s*.09,center.dy+s*.14)..close();
        canvas.drawPath(play, Paint()..color=color..style=PaintingStyle.fill);
        break;
      case 'audio':
        final p = Path()..moveTo(center.dx-s*.27,center.dy-s*.04)..lineTo(center.dx-s*.12,center.dy-s*.04)..lineTo(center.dx+s*.02,center.dy-s*.22)..lineTo(center.dx+s*.02,center.dy+s*.22)..lineTo(center.dx-s*.12,center.dy+s*.04)..lineTo(center.dx-s*.27,center.dy+s*.04)..close();
        canvas.drawPath(p, Paint()..color=color..style=PaintingStyle.fill);
        canvas.drawArc(Rect.fromCircle(center:center,radius:s*.20), -0.9, 1.8, false, stroke);
        canvas.drawArc(Rect.fromCircle(center:center,radius:s*.30), -0.9, 1.8, false, stroke);
        break;
      case 'documents':
        final p = Path()..moveTo(r.left+s*.08,r.top)..lineTo(r.right-s*.17,r.top)..lineTo(r.right,r.top+s*.17)..lineTo(r.right,r.bottom)..lineTo(r.left,r.bottom)..lineTo(r.left,r.top+s*.08)..close();
        canvas.drawPath(p, fill); canvas.drawPath(p, stroke);
        for (var i=0;i<3;i++) { final y=r.top+s*(.25+i*.13); canvas.drawLine(Offset(r.left+s*.12,y),Offset(r.right-s*.12,y),stroke); }
        break;
      case 'downloads':
        canvas.drawLine(Offset(center.dx, r.top),Offset(center.dx,center.dy+s*.10),stroke);
        final arrow=Path()..moveTo(center.dx-s*.14,center.dy)..lineTo(center.dx,center.dy+s*.15)..lineTo(center.dx+s*.14,center.dy);
        canvas.drawPath(arrow,stroke);
        final tray=Path()..moveTo(r.left+s*.04,center.dy+s*.10)..lineTo(r.left+s*.04,r.bottom)..lineTo(r.right-s*.04,r.bottom)..lineTo(r.right-s*.04,center.dy+s*.10);
        canvas.drawPath(tray,stroke);
        break;
      case 'apks':
        final head=Rect.fromCenter(center:Offset(center.dx,center.dy-s*.14),width:s*.38,height:s*.27);
        canvas.drawArc(head,3.14,3.14,false,stroke);
        canvas.drawLine(Offset(center.dx-s*.19,center.dy-s*.14),Offset(center.dx-s*.19,center.dy+s*.22),stroke);
        canvas.drawLine(Offset(center.dx+s*.19,center.dy-s*.14),Offset(center.dx+s*.19,center.dy+s*.22),stroke);
        canvas.drawLine(Offset(center.dx-s*.19,center.dy+s*.22),Offset(center.dx+s*.19,center.dy+s*.22),stroke);
        canvas.drawLine(Offset(center.dx-s*.12,center.dy-s*.30),Offset(center.dx-s*.20,center.dy-s*.39),stroke);
        canvas.drawLine(Offset(center.dx+s*.12,center.dy-s*.30),Offset(center.dx+s*.20,center.dy-s*.39),stroke);
        break;
      case 'archives':
        final box=RRect.fromRectAndRadius(r, const Radius.circular(5));
        canvas.drawRRect(box,fill); canvas.drawRRect(box,stroke);
        canvas.drawLine(Offset(r.left,center.dy-s*.08),Offset(r.right,center.dy-s*.08),stroke);
        canvas.drawLine(Offset(center.dx-s*.11,center.dy+s*.04),Offset(center.dx+s*.11,center.dy+s*.04),stroke);
        break;
      default:
        final folder=Path()..moveTo(r.left,r.top+s*.12)..lineTo(center.dx-s*.06,r.top+s*.12)..lineTo(center.dx+s*.04,r.top+s*.23)..lineTo(r.right,r.top+s*.23)..lineTo(r.right,r.bottom)..lineTo(r.left,r.bottom)..close();
        canvas.drawPath(folder,fill); canvas.drawPath(folder,stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
