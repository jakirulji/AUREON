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
    _HomeCategory('Images', 'images', Icons.image_rounded, Color(0xFFE84CB7), Color(0xFFFFD9ED), Color(0xFF51214A)),
    _HomeCategory('Videos', 'videos', Icons.movie_creation_rounded, Color(0xFF2875DF), Color(0xFFDCEBFF), Color(0xFF1C355C)),
    _HomeCategory('Audio', 'audio', Icons.music_note_rounded, Color(0xFF079B70), Color(0xFFD7F7EB), Color(0xFF173F39)),
    _HomeCategory('Documents', 'documents', Icons.description_rounded, Color(0xFF8050DF), Color(0xFFE9DFFF), Color(0xFF33265B)),
    _HomeCategory('Downloads', 'downloads', Icons.download_rounded, Color(0xFF0AA878), Color(0xFFD8F7E9), Color(0xFF1B493C)),
    _HomeCategory('APKs', 'apks', Icons.android_rounded, Color(0xFF9B5A16), Color(0xFFFFE8C8), Color(0xFF49351F)),
    _HomeCategory('Archives', 'archives', Icons.inventory_2_rounded, Color(0xFF7650D8), Color(0xFFE9DFFF), Color(0xFF30254F)),
    _HomeCategory('Other', 'other', Icons.folder_rounded, Color(0xFF2875D8), Color(0xFFDCEBFF), Color(0xFF20395E)),
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

  Widget _header() => Stack(clipBehavior: Clip.none, children: [
    Positioned(
      top: -24,
      right: 12,
      child: IgnorePointer(
        child: Container(
          width: 205,
          height: 78,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            gradient: RadialGradient(
              colors: [
                const Color(0xFF7655F5).withValues(alpha: _dark ? .30 : .18),
                const Color(0xFF4B8DFF).withValues(alpha: _dark ? .12 : .10),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7655F5).withValues(alpha: _dark ? .22 : .12),
                blurRadius: 38,
                spreadRadius: 7,
              ),
            ],
          ),
        ),
      ),
    ),
    Row(children: [
    Container(
      width: 47,
      height: 47,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB18AFF), Color(0xFF6939E8), Color(0xFF3E64D9)],
        ),
        boxShadow: [BoxShadow(color: _violet.withValues(alpha: .28), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 32),
    ),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('AUREON', style: TextStyle(color: _ink, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: .5)),
      Text('YOUR DIGITAL UNIVERSE', style: TextStyle(color: _muted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .6)),
    ])),
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
  ]);

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
    borderRadius: BorderRadius.circular(19),
    child: InkWell(
      borderRadius: BorderRadius.circular(19),
      onTap: () => widget.onBrowseCategory(category.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _dark
              ? [
                  Color.alphaBlend(category.color.withValues(alpha: .17), category.darkBackground),
                  category.darkBackground,
                ]
              : [
                  Color.alphaBlend(Colors.white.withValues(alpha: .26), category.lightBackground),
                  category.lightBackground,
                ],
          ),
          border: Border.all(color: category.color.withValues(alpha: _dark ? .30 : .20)),
          boxShadow: [
            BoxShadow(
              color: category.color.withValues(alpha: _dark ? .13 : .10),
              blurRadius: 13,
              spreadRadius: .3,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(category.icon, color: category.color, size: 29),
          const SizedBox(height: 8),
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
  const _HomeCategory(this.label, this.key, this.icon, this.color,
      this.lightBackground, this.darkBackground);
  final String label;
  final String key;
  final IconData icon;
  final Color color;
  final Color lightBackground;
  final Color darkBackground;
}
