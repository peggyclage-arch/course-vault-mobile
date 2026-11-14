import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import '../mega/catalogue.dart';
import '../mega/download.dart';
import '../store/library.dart';
import '../store/progress_store.dart';
import 'lesson_screen.dart';

/// One course: its modules and lessons, with progress.
///
/// Lessons that have attachments (note, subtitles or files) are shown
/// as an accordion: tap the lesson to open it, tap the expand arrow to
/// open the list of its attached files without leaving the course.
class CourseScreen extends StatelessWidget {
  final LibraryState library;
  final Course course;

  const CourseScreen({
    super.key,
    required this.library,
    required this.course,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(course.name)),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          return ListView.builder(
            itemCount: course.modules.length,
            itemBuilder: (context, i) {
              final module = course.modules[i];
              return _ModuleSection(
                library: library,
                course: course,
                module: module,
              );
            },
          );
        },
      ),
    );
  }
}

class _ModuleSection extends StatefulWidget {
  final LibraryState library;
  final Course course;
  final Module module;

  const _ModuleSection({
    required this.library,
    required this.course,
    required this.module,
  });

  @override
  State<_ModuleSection> createState() => _ModuleSectionState();
}

class _ModuleSectionState extends State<_ModuleSection> {
  /// Lesson ids whose attachment accordion is open.
  final Set<String> _expanded = {};

  /// Resource handles currently downloading (to open).
  final Set<String> _downloading = {};

  void _openLesson(Lesson lesson) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LessonScreen(
          library: widget.library,
          course: widget.course,
          lesson: lesson,
        ),
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

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            module.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ...module.lessons.map((lesson) {
          final done = widget.library.progress.isCompleted(lesson.id);
          final pos = widget.library.progress.position(lesson.id);
          final hasAttachments = lesson.resources.isNotEmpty ||
              lesson.note != null ||
              lesson.subtitles.isNotEmpty;
          final expanded = _expanded.contains(lesson.id);
          return Column(
            children: [
              ListTile(
                leading: Icon(
                  done
                      ? Icons.check_circle
                      : lesson.hasVideo
                          ? Icons.play_circle_outline
                          : Icons.description_outlined,
                  color: done ? Colors.green : null,
                ),
                title: Text(lesson.name),
                subtitle: Text(
                  [
                    if (lesson.hasVideo) 'Video',
                    if (lesson.note != null) 'Notes',
                    if (lesson.subtitles.isNotEmpty) 'Subtitles',
                    if (lesson.resources.isNotEmpty)
                      '${lesson.resources.length} file${lesson.resources.length == 1 ? '' : 's'}',
                    if (pos > 5) 'Resume ${formatDuration(pos)}',
                  ].join(' · '),
                ),
                trailing: hasAttachments
                    ? IconButton(
                        icon: Icon(
                          expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        tooltip: expanded
                            ? 'Hide attached files'
                            : 'Show attached files',
                        onPressed: () {
                          setState(() {
                            if (expanded) {
                              _expanded.remove(lesson.id);
                            } else {
                              _expanded.add(lesson.id);
                            }
                          });
                        },
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => _openLesson(lesson),
              ),
              if (hasAttachments && expanded)
                _AttachmentsAccordion(
                  lesson: lesson,
                  downloading: _downloading,
                  onOpenLesson: () => _openLesson(lesson),
                  onOpenResource: _openResource,
                ),
            ],
          );
        }),
      ],
    );
  }
}

/// The expanded attachment list for one lesson: its note, subtitles
/// and resource files, each tappable to open.
class _AttachmentsAccordion extends StatelessWidget {
  final Lesson lesson;
  final Set<String> downloading;
  final VoidCallback onOpenLesson;
  final Future<void> Function(MegaNode file) onOpenResource;

  const _AttachmentsAccordion({
    required this.lesson,
    required this.downloading,
    required this.onOpenLesson,
    required this.onOpenResource,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(56, 0, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.4,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'Attached files',
              style: theme.textTheme.labelMedium,
            ),
          ),
          if (lesson.note != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined, size: 20),
              title: Text(lesson.note!.name),
              subtitle: const Text('Notes · tap to read in the lesson'),
              onTap: onOpenLesson,
            ),
          ...lesson.subtitles.map(
            (sub) => ListTile(
              dense: true,
              leading: const Icon(Icons.closed_caption, size: 20),
              title: Text(sub.name),
              subtitle: const Text('Subtitles'),
              onTap: onOpenLesson,
            ),
          ),
          ...lesson.resources.map((file) {
            final isDownloading = downloading.contains(file.handle);
            return ListTile(
              dense: true,
              leading: const Icon(Icons.attach_file, size: 20),
              title: Text(file.name),
              subtitle: Text(_formatSize(file.size)),
              trailing: isDownloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new, size: 20),
              onTap: () => onOpenResource(file),
            );
          }),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
