import 'package:flutter/material.dart';

import '../store/library.dart';
import 'course_screen.dart';
import 'search_screen.dart';

/// Home screen: the Mega link box plus the course catalogue.
class LibraryScreen extends StatefulWidget {
  final LibraryState library;

  const LibraryScreen({super.key, required this.library});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final TextEditingController _linkController;

  @override
  void initState() {
    super.initState();
    _linkController = TextEditingController(
      text: widget.library.progress.lastLink ?? defaultMegaLink,
    );
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CourseVault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchScreen(library: library),
                ),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _linkController,
                        decoration: const InputDecoration(
                          labelText: 'Mega folder link',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _load(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: library.isLoading ? null : _load,
                      child: const Text('Load'),
                    ),
                  ],
                ),
              ),
              if (library.isLoading)
                const LinearProgressIndicator(),
              if (library.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    library.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(child: _body(library)),
            ],
          );
        },
      ),
    );
  }

  void _load() {
    final url = _linkController.text.trim();
    if (url.isNotEmpty) widget.library.loadLink(url);
  }

  Widget _body(LibraryState library) {
    if (library.isLoading && library.courses.isEmpty) {
      return const Center(child: Text('Loading your library…'));
    }
    if (library.courses.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No courses found.\n\nPaste a Mega folder link above and tap Load. '
            'A folder can hold courses, modules and lessons — videos, notes '
            'and resources are grouped by file name.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: library.courses.length,
      itemBuilder: (context, i) {
        final course = library.courses[i];
        final lessons = course.lessons;
        final done = lessons
            .where((l) => library.progress.isCompleted(l.id))
            .length;
        final progress = library.courseProgress(course);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text(course.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${course.modules.length} modules · ${lessons.length} lessons · $done done',
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CourseScreen(
                    library: library,
                    course: course,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
