import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:open_file/open_file.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../mega/catalogue.dart';
import '../mega/download.dart';
import '../store/library.dart';
import '../store/progress_store.dart';

/// One lesson: video with resume/progress, subtitles, notes, resources.
///
/// Player features:
/// - screen stays awake while the video is playing (wakelock)
/// - playback speed, +/-10s skip, fullscreen / landscape view
/// - Previous / Next lesson buttons under the video
class LessonScreen extends StatefulWidget {
  final LibraryState library;
  final Course course;
  final Lesson lesson;

  const LessonScreen({
    super.key,
    required this.library,
    required this.course,
    required this.lesson,
  });

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  String? _playerError;
  String? _resumedFrom;
  Timer? _saveTimer;
  double _lastSaved = 0;
  bool _completed = false;
  String? _noteText;
  bool _noteLoading = false;
  final Set<String> _downloading = {};
  double _speed = 1.0;
  bool _isFullscreen = false;
  bool _wakelockOn = false;

  Lesson get _lesson => widget.lesson;

  /// Lessons of this course in play order (modules in order).
  List<Lesson> get _orderedLessons => widget.course.lessons;

  int get _lessonIndex =>
      _orderedLessons.indexWhere((l) => l.id == _lesson.id);

  Lesson? get _previousLesson {
    final i = _lessonIndex;
    return i > 0 ? _orderedLessons[i - 1] : null;
  }

  Lesson? get _nextLesson {
    final i = _lessonIndex;
    return i >= 0 && i < _orderedLessons.length - 1
        ? _orderedLessons[i + 1]
        : null;
  }

  @override
  void initState() {
    super.initState();
    _completed = widget.library.progress.isCompleted(_lesson.id);
    _lastSaved = widget.library.progress.position(_lesson.id);
    _noteText = _lesson.noteText.isNotEmpty ? _lesson.noteText : null;
    if (_lesson.hasVideo) _initVideo();
    if (_lesson.note != null && _noteText == null) _loadNote();
  }

  Future<void> _loadNote() async {
    setState(() => _noteLoading = true);
    try {
      final api = widget.library.api;
      final rootHandle = widget.library.rootHandle ?? '';
      final text = await downloadText(api, rootHandle, _lesson.note!);
      if (mounted) {
        setState(() {
          _noteText = text;
          _lesson.noteText = text;
        });
      }
    } catch (_) {
      // Notes are best-effort; the lesson still works without them.
    } finally {
      if (mounted) setState(() => _noteLoading = false);
    }
  }

  Future<void> _initVideo() async {
    final proxy = widget.library.proxy;
    final url = proxy.urlFor(_lesson.video!);
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      closedCaptionFile: _closedCaptions(),
      httpHeaders: const {'Accept': 'video/*'},
    );
    _controller = controller;
    _initFuture = controller.initialize().then((_) async {
      if (!mounted) return;
      final saved = widget.library.progress.position(_lesson.id);
      final duration = controller.value.duration.inMilliseconds / 1000;
      if (saved > 5 && duration > 0 && saved < duration - 5) {
        await controller.seekTo(Duration(milliseconds: (saved * 1000).round()));
        setState(() => _resumedFrom = formatDuration(saved));
      }
      controller.addListener(_onTick);
      _saveTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
      setState(() {});
      await controller.play();
      _setWakelock(true);
    }).catchError((Object e) {
      if (mounted) setState(() => _playerError = e.toString());
    });
    setState(() {});
  }

  Future<ClosedCaptionFile>? _closedCaptions() {
    if (_lesson.subtitles.isEmpty || _lesson.subtitleText.isEmpty) {
      return null;
    }
    final first = _lesson.subtitles.first;
    final name = first.name.toLowerCase();
    if (name.endsWith('.vtt')) {
      return Future.value(WebVTTCaptionFile(_lesson.subtitleText));
    }
    return Future.value(SubRipCaptionFile(_lesson.subtitleText));
  }

  /// Keep the screen awake only while the video is actually playing.
  void _setWakelock(bool on) {
    if (_wakelockOn == on) return;
    _wakelockOn = on;
    if (on) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _setWakelock(c.value.isPlaying);
    final pos = c.value.position.inMilliseconds / 1000;
    final dur = c.value.duration.inMilliseconds / 1000;
    if (dur > 0 && pos / dur >= 0.9 && !_completed) {
      _completed = true;
      widget.library.progress.setCompleted(_lesson.id, true);
      setState(() {});
    }
  }

  Future<void> _savePosition() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position.inMilliseconds / 1000;
    if ((pos - _lastSaved).abs() < 1) return;
    _lastSaved = pos;
    await widget.library.progress.savePosition(_lesson.id, pos);
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _setWakelock(false);
      } else {
        c.play();
        _setWakelock(true);
      }
    });
  }

  void _skip(Duration offset) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final target = c.value.position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > c.value.duration ? c.value.duration : target);
    c.seekTo(clamped);
  }

  void _cycleSpeed() {
    final c = _controller;
    if (c == null) return;
    final i = _speeds.indexOf(_speed);
    final next = _speeds[(i + 1) % _speeds.length];
    setState(() => _speed = next);
    c.setPlaybackSpeed(next);
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (mounted) setState(() => _isFullscreen = false);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (mounted) setState(() => _isFullscreen = true);
    }
  }

  void _goToLesson(Lesson lesson) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LessonScreen(
          library: widget.library,
          course: widget.course,
          lesson: lesson,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    _setWakelock(false);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullscreen) return _fullscreenView();
    return Scaffold(
      appBar: AppBar(
        title: Text(_lesson.name),
        actions: [
          if (_completed)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.check_circle, color: Colors.green),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_lesson.hasVideo) _videoSection(),
            if (_resumedFrom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Chip(
                  label: Text('Resumed from $_resumedFrom'),
                  avatar: const Icon(Icons.history, size: 18),
                ),
              ),
            if (_lesson.note != null) _notesSection(),
            if (_lesson.subtitles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Subtitles: ${_lesson.subtitles.map((s) => s.name).join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_lesson.resources.isNotEmpty) _resourcesSection(),
            if (!_lesson.hasVideo && _lesson.note == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('This lesson has files but no video or notes.'),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Fullscreen / landscape player: video fills the screen, controls
  /// overlay the bottom, exit button at the top.
  Widget _fullscreenView() {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (controller != null && controller.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
              onPressed: _toggleFullscreen,
            ),
          ),
          if (controller != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                child: _PlayerControls(
                  controller: controller,
                  speed: _speed,
                  onToggle: _togglePlayPause,
                  onSkip: _skip,
                  onCycleSpeed: _cycleSpeed,
                  onToggleFullscreen: _toggleFullscreen,
                  isFullscreen: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _videoSection() {
    if (_playerError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Video could not be played: $_playerError',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || _initFuture == null) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (_playerError != null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Video could not be played: $_playerError',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        return Column(
          children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
            _PlayerControls(
              controller: controller,
              speed: _speed,
              onToggle: _togglePlayPause,
              onSkip: _skip,
              onCycleSpeed: _cycleSpeed,
              onToggleFullscreen: _toggleFullscreen,
              isFullscreen: false,
            ),
            _prevNextRow(),
          ],
        );
      },
    );
  }

  /// Previous / Next lesson, under the video.
  Widget _prevNextRow() {
    final prev = _previousLesson;
    final next = _nextLesson;
    final total = _orderedLessons.length;
    final index = _lessonIndex;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.skip_previous),
              label: const Text('Previous'),
              onPressed: prev == null ? null : () => _goToLesson(prev),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              total > 0 ? '${index + 1} / $total' : '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.skip_next),
              label: const Text('Next'),
              onPressed: next == null ? null : () => _goToLesson(next),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_noteLoading)
            const CircularProgressIndicator()
          else if (_noteText != null && _noteText!.isNotEmpty)
            MarkdownBody(data: _noteText!)
          else
            const Text('No notes for this lesson.'),
        ],
      ),
    );
  }

  Widget _resourcesSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Files', style: Theme.of(context).textTheme.titleMedium),
          ..._lesson.resources.map((file) {
            final downloading = _downloading.contains(file.handle);
            return ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(file.name),
              subtitle: Text(_formatSize(file.size)),
              trailing: downloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              onTap: () => _openResource(file),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _openResource(MegaNode file) async {
    setState(() => _downloading.add(file.handle));
    try {
      final api = widget.library.api;
      final rootHandle = widget.library.rootHandle ?? '';
      final local = await downloadToCache(api, rootHandle, file);
      await OpenFile.open(local.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open ${file.name}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(file.handle));
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _PlayerControls extends StatelessWidget {
  final VideoPlayerController controller;
  final double speed;
  final VoidCallback onToggle;
  final void Function(Duration offset) onSkip;
  final VoidCallback onCycleSpeed;
  final VoidCallback onToggleFullscreen;
  final bool isFullscreen;

  const _PlayerControls({
    required this.controller,
    required this.speed,
    required this.onToggle,
    required this.onSkip,
    required this.onCycleSpeed,
    required this.onToggleFullscreen,
    required this.isFullscreen,
  });

  String get _speedLabel {
    final s = speed == speed.truncateToDouble()
        ? speed.toInt().toString()
        : speed.toString();
    return '${s}x';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final pos = value.position;
        final dur = value.duration;
        return Column(
          children: [
            VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: onToggle,
                    tooltip: value.isPlaying ? 'Pause' : 'Play',
                  ),
                  IconButton(
                    icon: const Icon(Icons.replay_10),
                    onPressed: () => onSkip(const Duration(seconds: -10)),
                    tooltip: 'Back 10 seconds',
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10),
                    onPressed: () => onSkip(const Duration(seconds: 10)),
                    tooltip: 'Forward 10 seconds',
                  ),
                  Text(
                    '${formatDuration(pos.inMilliseconds / 1000)} / ${formatDuration(dur.inMilliseconds / 1000)}',
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onCycleSpeed,
                    child: Text(_speedLabel),
                  ),
                  IconButton(
                    icon: Icon(
                      isFullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                    ),
                    onPressed: onToggleFullscreen,
                    tooltip: isFullscreen
                        ? 'Exit fullscreen'
                        : 'Fullscreen (landscape)',
                  ),
                  if (!isFullscreen)
                    TextButton(
                      onPressed: () {
                        controller.seekTo(Duration.zero);
                        controller.play();
                      },
                      child: const Text('Restart'),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
