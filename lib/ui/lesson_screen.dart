import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:open_file/open_file.dart';
import 'package:video_player/video_player.dart';

import '../mega/catalogue.dart';
import '../mega/download.dart';
import '../store/library.dart';
import '../store/progress_store.dart';

/// One lesson: video with resume/progress, subtitles, notes, resources.
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

  Lesson get _lesson => widget.lesson;

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

  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
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

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              onToggle: () => setState(() {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              }),
            ),
          ],
        );
      },
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
  final VoidCallback onToggle;

  const _PlayerControls({required this.controller, required this.onToggle});

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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: onToggle,
                  ),
                  Text(
                    '${formatDuration(pos.inMilliseconds / 1000)} / ${formatDuration(dur.inMilliseconds / 1000)}',
                  ),
                  const Spacer(),
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
