import 'dart:io';

import 'package:flutter/material.dart';
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
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
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
                      ? Video(controller: _videoController)
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
                          (speed) => PopupMenuItem(value: speed, child: Text('${speed}×')),
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
