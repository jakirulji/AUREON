import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class AureonMediaItem {
  const AureonMediaItem({required this.path, required this.title});
  final String path;
  final String title;
}

class AureonMediaViewerPage extends StatefulWidget {
  const AureonMediaViewerPage({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.queue,
    required this.initialIndex,
    required this.isVideo,
  });
  final String filePath;
  final String fileName;
  final List<AureonMediaItem> queue;
  final int initialIndex;
  final bool isVideo;

  @override
  State<AureonMediaViewerPage> createState() => _AureonMediaViewerPageState();
}

class _AureonMediaViewerPageState extends State<AureonMediaViewerPage> {
  late final Player _player;
  late final VideoController _videoController;
  bool _shuffle = false;
  bool _repeat = false;
  double _pitch = 1;
  bool _controlsVisible = true;
  bool _locked = false;
  BoxFit _videoFit = BoxFit.contain;
  Timer? _controlsTimer;
  Timer? _sleepTimer;
  String? _sleepLabel;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(title: 'AUREON'));
    _videoController = VideoController(_player);
    _open();
  }

  Future<void> _open() async {
    try {
      if (widget.queue.length > 1) {
        await _player.open(Playlist(
          widget.queue.map((item) => Media(item.path, extras: {'title': item.title})).toList(),
          index: widget.initialIndex,
        ));
      } else {
        await _player.open(Media(widget.filePath, extras: {'title': widget.fileName}));
      }
      _scheduleControlsHide();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _sleepTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _time(Duration value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0
        ? '${two(hours)}:${two(value.inMinutes.remainder(60))}:${two(value.inSeconds.remainder(60))}'
        : '${two(value.inMinutes)}:${two(value.inSeconds.remainder(60))}';
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    if (!widget.isVideo || !_controlsVisible || !_player.state.playing || _locked) return;
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (_locked) return;
    setState(() => _controlsVisible = !_controlsVisible);
    _scheduleControlsHide();
  }

  Future<void> _seekBy(int seconds) async {
    final duration = _player.state.duration;
    final current = _player.state.position;
    final next = (current.inMilliseconds + seconds * 1000)
        .clamp(0, duration.inMilliseconds > 0 ? duration.inMilliseconds : 1 << 30);
    await _player.seek(Duration(milliseconds: next.toInt()));
    _scheduleControlsHide();
  }

  Future<void> _pickSubtitle() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub'],
    );
    if (files.isEmpty || files.single.path == null) return;
    final subtitle = files.single;
    await _player.setSubtitleTrack(SubtitleTrack.uri(
      Uri.file(subtitle.path!).toString(),
      title: subtitle.name,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded subtitle: ${subtitle.name}')),
      );
    }
  }

  Future<void> _showSleepTimer() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Sleep timer')),
          for (final value in [15, 30, 45, 60, 90, 120])
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('$value minutes'),
              onTap: () => Navigator.pop(sheetContext, value),
            ),
          ListTile(
            leading: const Icon(Icons.timer_off_outlined),
            title: const Text('Cancel timer'),
            onTap: () => Navigator.pop(sheetContext, 0),
          ),
        ]),
      ),
    );
    if (minutes == null) return;
    _sleepTimer?.cancel();
    if (minutes == 0) {
      setState(() => _sleepLabel = null);
      return;
    }
    setState(() => _sleepLabel = '${minutes}m');
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await _player.pause();
      if (mounted) setState(() => _sleepLabel = null);
    });
  }

  Future<void> _showVideoSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Video settings')),
          ListTile(
            leading: const Icon(Icons.fit_screen_outlined),
            title: const Text('Aspect ratio / fit'),
            subtitle: Text(_videoFit == BoxFit.contain ? 'Fit' :
                _videoFit == BoxFit.cover ? 'Crop to fill' : 'Stretch'),
            onTap: () async {
              final fit = await showModalBottomSheet<BoxFit>(
                context: sheetContext,
                builder: (context) => SafeArea(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(title: const Text('Fit to screen'), onTap: () => Navigator.pop(context, BoxFit.contain)),
                    ListTile(title: const Text('Crop to fill'), onTap: () => Navigator.pop(context, BoxFit.cover)),
                    ListTile(title: const Text('Stretch'), onTap: () => Navigator.pop(context, BoxFit.fill)),
                  ],
                )),
              );
              if (fit != null && mounted) setState(() => _videoFit = fit);
            },
          ),
          ListTile(
            leading: const Icon(Icons.subtitles_outlined),
            title: const Text('Load external subtitle'),
            onTap: () {
              Navigator.pop(sheetContext);
              _pickSubtitle();
            },
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Sleep timer'),
            subtitle: Text(_sleepLabel ?? 'Off'),
            onTap: () {
              Navigator.pop(sheetContext);
              _showSleepTimer();
            },
          ),
          ListTile(
            leading: const Icon(Icons.volume_up_rounded),
            title: const Text('Playback volume'),
            subtitle: Text('${_player.state.volume.round()}%'),
            onTap: () {
              Navigator.pop(sheetContext);
              showModalBottomSheet<void>(
                context: context,
                builder: (context) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                    child: StreamBuilder<double>(
                      stream: _player.stream.volume,
                      initialData: _player.state.volume,
                      builder: (context, snapshot) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Playback volume'),
                          Slider(
                            value: (snapshot.data ?? 100).clamp(0, 100).toDouble(),
                            max: 100,
                            onChanged: _player.setVolume,
                          ),
                          Text('${(snapshot.data ?? 100).round()}%'),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _showTracks({required bool subtitles}) async {
    final tracks = subtitles ? _player.state.tracks.subtitle : _player.state.tracks.audio;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(subtitles ? 'Subtitles' : 'Audio tracks')),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Automatic'),
              onTap: () {
                if (subtitles) {
                  _player.setSubtitleTrack(SubtitleTrack.auto());
                } else {
                  _player.setAudioTrack(AudioTrack.auto());
                }
                Navigator.pop(sheetContext);
              },
            ),
            if (subtitles)
              ListTile(
                leading: const Icon(Icons.subtitles_off_outlined),
                title: const Text('Off'),
                onTap: () {
                  _player.setSubtitleTrack(SubtitleTrack.no());
                  Navigator.pop(sheetContext);
                },
              ),
            for (final track in tracks)
              ListTile(
                leading: Icon(subtitles ? Icons.subtitles_outlined : Icons.audiotrack),
                title: Text(track.toString()),
                onTap: () {
                  if (track is SubtitleTrack) {
                    _player.setSubtitleTrack(track);
                  } else if (track is AudioTrack) {
                    _player.setAudioTrack(track);
                  }
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _videoController,
          controls: NoVideoControls,
          fit: _videoFit,
          fill: const Color(0xFF05070D),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onDoubleTapDown: (details) {
            if (_locked) return;
            final width = MediaQuery.of(context).size.width;
            _seekBy(details.localPosition.dx < width / 2 ? -10 : 10);
          },
          child: const SizedBox.expand(),
        ),
        if (_player.state.buffering)
          const Center(child: CircularProgressIndicator(color: Color(0xFF9A8BFF))),
        if (_controlsVisible && !_locked)
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Colors.transparent, Color(0xCC000000)],
                  stops: [0, .42, 1],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Lock controls',
                          color: Colors.white,
                          onPressed: () => setState(() { _locked = true; _controlsVisible = false; }),
                          icon: const Icon(Icons.lock_open_rounded),
                        ),
                        IconButton(
                          tooltip: 'Video settings',
                          color: Colors.white,
                          onPressed: _showVideoSettings,
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Back 10 seconds',
                        color: Colors.white,
                        iconSize: 34,
                        onPressed: () => _seekBy(-10),
                        icon: const Icon(Icons.replay_10_rounded),
                      ),
                      const SizedBox(width: 28),
                      StreamBuilder<bool>(
                        stream: _player.stream.playing,
                        initialData: _player.state.playing,
                        builder: (context, snapshot) => IconButton.filled(
                          tooltip: snapshot.data == true ? 'Pause' : 'Play',
                          onPressed: _player.playOrPause,
                          iconSize: 38,
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF8067F4),
                            foregroundColor: Colors.white,
                          ),
                          icon: Icon(snapshot.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        ),
                      ),
                      const SizedBox(width: 28),
                      IconButton(
                        tooltip: 'Forward 10 seconds',
                        color: Colors.white,
                        iconSize: 34,
                        onPressed: () => _seekBy(10),
                        icon: const Icon(Icons.forward_10_rounded),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: Column(
                      children: [
                        StreamBuilder<Duration>(
                          stream: _player.stream.position,
                          initialData: _player.state.position,
                          builder: (context, positionSnapshot) {
                            final position = positionSnapshot.data ?? Duration.zero;
                            return StreamBuilder<Duration>(
                              stream: _player.stream.duration,
                              initialData: _player.state.duration,
                              builder: (context, durationSnapshot) {
                                final duration = durationSnapshot.data ?? Duration.zero;
                                final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
                                return Slider(
                                  value: position.inMilliseconds.toDouble().clamp(0, max).toDouble(),
                                  max: max,
                                  onChanged: (value) => _player.seek(Duration(milliseconds: value.round())),
                                );
                              },
                            );
                          },
                        ),
                        Row(
                          children: [
                            StreamBuilder<Duration>(
                              stream: _player.stream.position,
                              initialData: _player.state.position,
                              builder: (context, snapshot) => Text(
                                _time(snapshot.data ?? Duration.zero),
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ),
                            const Spacer(),
                            PopupMenuButton<double>(
                              tooltip: 'Playback speed',
                              initialValue: _player.state.rate,
                              color: const Color(0xFF171C2B),
                              onSelected: (speed) async {
                                await _player.setRate(speed);
                                if (mounted) setState(() {});
                              },
                              itemBuilder: (_) => [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0]
                                  .map((speed) => PopupMenuItem(
                                    value: speed,
                                    child: Text('$speed×', style: const TextStyle(color: Colors.white)),
                                  )).toList(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: Text('${_player.state.rate.toStringAsFixed(2)}×',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            StreamBuilder<Duration>(
                              stream: _player.stream.duration,
                              initialData: _player.state.duration,
                              builder: (context, snapshot) => Text(
                                _time(snapshot.data ?? Duration.zero),
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_locked)
          Positioned(
            right: 14,
            bottom: 18,
            child: FloatingActionButton.small(
              heroTag: 'aureon-video-unlock',
              backgroundColor: const Color(0xCC20243A),
              foregroundColor: Colors.white,
              onPressed: () => setState(() { _locked = false; _controlsVisible = true; }),
              child: const Icon(Icons.lock_open_rounded),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070B14),
        foregroundColor: Colors.white,
        title: Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.isVideo)
            IconButton(
              tooltip: 'Audio track',
              onPressed: () => _showTracks(subtitles: false),
              icon: const Icon(Icons.audiotrack),
            ),
          if (widget.isVideo)
            IconButton(
              tooltip: 'Subtitles',
              onPressed: () => _showTracks(subtitles: true),
              icon: const Icon(Icons.subtitles_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.isVideo)
              Expanded(
                child: Center(
                  child: _error == null
                      ? _buildVideoSurface()
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, style: const TextStyle(color: Colors.white)),
                        ),
                ),
              )
            else ...[
              const Spacer(),
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF25204C), Color(0xFF111D35), Color(0xFF0C1424)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: const Color(0xFF8B7CFF).withValues(alpha: .35)),
                ),
                child: const Icon(Icons.graphic_eq_rounded, size: 100, color: Color(0xFFB8AFFF)),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(widget.fileName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              const Text('AUREON AUDIO', style: TextStyle(color: Color(0xFF9B9DB5), letterSpacing: 2, fontSize: 11)),
              const Spacer(),
            ],
            if (_error != null && widget.isVideo == false)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  StreamBuilder<Duration>(
                    stream: _player.stream.position,
                    initialData: Duration.zero,
                    builder: (context, positionSnapshot) {
                      final position = positionSnapshot.data ?? Duration.zero;
                      return StreamBuilder<Duration>(
                        stream: _player.stream.duration,
                        initialData: Duration.zero,
                        builder: (context, durationSnapshot) {
                          final duration = durationSnapshot.data ?? Duration.zero;
                          final max = duration.inMilliseconds.toDouble().clamp(1, double.infinity);
                          return Column(children: [
                            Slider(
                              value: position.inMilliseconds.toDouble().clamp(0, max).toDouble(),
                              max: max.toDouble(),
                              onChanged: (value) => _player.seek(Duration(milliseconds: value.round())),
                            ),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(_time(position), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              Text(_time(duration), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ]),
                          ]);
                        },
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Shuffle',
                        color: _shuffle ? scheme.primary : Colors.white70,
                        onPressed: () {
                          setState(() => _shuffle = !_shuffle);
                          _player.setShuffle(_shuffle);
                        },
                        icon: const Icon(Icons.shuffle_rounded),
                      ),
                      IconButton(
                        tooltip: 'Previous',
                        color: Colors.white,
                        onPressed: widget.queue.length > 1 ? _player.previous : null,
                        icon: const Icon(Icons.skip_previous_rounded, size: 34),
                      ),
                      StreamBuilder<bool>(
                        stream: _player.stream.playing,
                        initialData: false,
                        builder: (context, snapshot) => IconButton.filled(
                          tooltip: snapshot.data == true ? 'Pause' : 'Play',
                          onPressed: _player.playOrPause,
                          iconSize: 32,
                          icon: Icon(snapshot.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        color: Colors.white,
                        onPressed: widget.queue.length > 1 ? _player.next : null,
                        icon: const Icon(Icons.skip_next_rounded, size: 34),
                      ),
                      IconButton(
                        tooltip: 'Repeat one',
                        color: _repeat ? scheme.primary : Colors.white70,
                        onPressed: () {
                          setState(() => _repeat = !_repeat);
                          _player.setPlaylistMode(_repeat ? PlaylistMode.single : PlaylistMode.none);
                        },
                        icon: const Icon(Icons.repeat_one_rounded),
                      ),
                    ],
                  ),
                  if (!widget.isVideo) ...[
                    Row(children: [
                      const Icon(Icons.volume_down, color: Colors.white70, size: 18),
                      Expanded(
                        child: StreamBuilder<double>(
                          stream: _player.stream.volume,
                          initialData: 100,
                          builder: (context, snapshot) => Slider(
                            value: (snapshot.data ?? 100).clamp(0, 100).toDouble(),
                            max: 100,
                            onChanged: _player.setVolume,
                          ),
                        ),
                      ),
                      const Icon(Icons.volume_up, color: Colors.white70, size: 18),
                    ]),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            builder: (context) => SafeArea(child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const ListTile(title: Text('Playback speed')),
                                for (final speed in [0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
                                  ListTile(title: Text('$speed×'), onTap: () {
                                    _player.setRate(speed);
                                    Navigator.pop(context);
                                  }),
                              ],
                            )),
                          ),
                          icon: const Icon(Icons.speed),
                          label: const Text('Speed'),
                        ),
                        TextButton.icon(
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            builder: (context) => SafeArea(child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const ListTile(title: Text('Pitch control')),
                                Slider(
                                  value: _pitch,
                                  min: 0.75,
                                  max: 1.25,
                                  divisions: 10,
                                  label: _pitch.toStringAsFixed(2),
                                  onChanged: (value) => setState(() => _pitch = value),
                                  onChangeEnd: _player.setPitch,
                                ),
                                const SizedBox(height: 16),
                              ],
                            )),
                          ),
                          icon: const Icon(Icons.tune),
                          label: const Text('Pitch'),
                        ),
                      ],
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerRight,
                      child: PopupMenuButton<double>(
                        tooltip: 'Playback speed',
                        icon: const Icon(Icons.speed, color: Colors.white),
                        onSelected: _player.setRate,
                        itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map(
                          (speed) => PopupMenuItem(value: speed, child: Text('$speed×')),
                        ).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AureonImageViewerPage extends StatefulWidget {
  const AureonImageViewerPage({super.key, required this.images, required this.initialIndex});
  final List<AureonMediaItem> images;
  final int initialIndex;

  @override
  State<AureonImageViewerPage> createState() => _AureonImageViewerPageState();
}

class _AureonImageViewerPageState extends State<AureonImageViewerPage> {
  late final PageController _controller;
  late int _index;
  int _quarterTurns = 0;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.images[_index];
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070D),
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${_index + 1} / ${widget.images.length}',
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Rotate',
            onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
            icon: const Icon(Icons.rotate_right),
          ),
          IconButton(
            tooltip: 'Image details',
            onPressed: () => setState(() => _showDetails = !_showDetails),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Stack(children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          onPageChanged: (index) => setState(() { _index = index; _quarterTurns = 0; }),
          itemBuilder: (context, index) => Center(
            child: InteractiveViewer(
              minScale: 0.7,
              maxScale: 8,
              child: RotatedBox(
                quarterTurns: _quarterTurns,
                child: Image.file(
                  File(widget.images[index].path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                ),
              ),
            ),
          ),
        ),
        if (_showDetails)
          Positioned(
            left: 16, right: 16, bottom: 18,
            child: Card(
              color: const Color(0xEE111A2E),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('File: ${current.title}\nPath: ${current.path}',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
      ]),
    );
  }
}
