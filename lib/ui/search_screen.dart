import 'package:flutter/material.dart';

import '../store/library.dart';
import 'lesson_screen.dart';

/// Search across lesson titles, notes and subtitle text.
class SearchScreen extends StatefulWidget {
  final LibraryState library;

  const SearchScreen({super.key, required this.library});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = widget.library.search(_query);
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search titles, notes, subtitles',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _query.trim().isEmpty
                ? const Center(
                    child: Text('Type to search your library.'),
                  )
                : results.isEmpty
                    ? const Center(child: Text('No lessons match.'))
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final r = results[i];
                          return ListTile(
                            leading: Icon(
                              r.lesson.hasVideo
                                  ? Icons.play_circle_outline
                                  : Icons.description_outlined,
                            ),
                            title: Text(r.lesson.name),
                            subtitle: Text(r.course.name),
                            trailing:
                                const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => LessonScreen(
                                    library: widget.library,
                                    course: r.course,
                                    lesson: r.lesson,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
