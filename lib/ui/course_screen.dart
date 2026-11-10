import 'package:flutter/material.dart';

import '../mega/catalogue.dart';
import '../store/library.dart';
import '../store/progress_store.dart';
import 'lesson_screen.dart';

/// One course: its modules and lessons, with progress.
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

class _ModuleSection extends StatelessWidget {
  final LibraryState library;
  final Course course;
  final Module module;

  const _ModuleSection({
    required this.library,
    required this.course,
    required this.module,
  });

  @override
  Widget build(BuildContext context) {
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
          final done = library.progress.isCompleted(lesson.id);
          final pos = library.progress.position(lesson.id);
          return ListTile(
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
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LessonScreen(
                    library: library,
                    course: course,
                    lesson: lesson,
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}
