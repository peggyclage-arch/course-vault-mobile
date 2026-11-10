import 'package:flutter/foundation.dart';

import '../mega/api.dart';
import '../mega/catalogue.dart';
import '../mega/download.dart';
import '../mega/link.dart';
import '../mega/proxy.dart';
import 'progress_store.dart';

/// The default Mega folder link, pre-filled in the app (Soufian's link).
const defaultMegaLink =
    'https://mega.nz/folder/ytZkzaSC#l_VpZ-zplh5xYEm8RN7c2g/folder/qsoFTCBb';

/// App state: the loaded library, the streaming proxy, and progress.
class LibraryState extends ChangeNotifier {
  final MegaApi api;
  final ProgressStore progress;

  LibraryState({required this.api, required this.progress});

  VideoProxy? _proxy;
  String? _rootHandle;

  /// Handle of the currently loaded Mega folder (for downloads).
  String? get rootHandle => _rootHandle;

  List<Course> courses = [];
  bool isLoading = false;
  String? error;
  String? currentLink;

  /// Search index: lesson id -> searchable text (titles + note/subtitle
  /// text, downloaded eagerly at load — those files are tiny).
  final Map<String, String> _searchText = {};

  VideoProxy get proxy {
    _proxy ??= VideoProxy(api, _rootHandle ?? '');
    return _proxy!;
  }

  /// Load a Mega folder link and build the catalogue.
  Future<void> loadLink(String url) async {
    isLoading = true;
    error = null;
    currentLink = url;
    notifyListeners();
    try {
      final link = parseMegaLink(url);
      _rootHandle = link.rootHandle;
      _proxy = VideoProxy(api, link.rootHandle);
      await _proxy!.start();
      courses = await loadCatalogueFromLink(api, url);
      await progress.saveLink(url);
      // Index small text files for search (notes + subtitles).
      _searchText.clear();
      for (final course in courses) {
        for (final lesson in course.lessons) {
          final parts = <String>[
            course.name,
            lesson.name,
          ];
          if (lesson.note != null) {
            try {
              lesson.noteText = await downloadText(
                api,
                link.rootHandle,
                lesson.note!,
              );
              parts.add(lesson.noteText);
            } catch (_) {}
          }
          for (final sub in lesson.subtitles) {
            try {
              final text = await downloadText(api, link.rootHandle, sub);
              lesson.subtitleText += '$text\n';
              parts.add(text);
            } catch (_) {}
          }
          _searchText[lesson.id] = parts.join('\n');
        }
      }
    } on MegaApiException catch (e) {
      error = e.message;
      courses = [];
    } on FormatException catch (e) {
      error = e.message;
      courses = [];
    } catch (e) {
      error = 'Could not load that link: $e';
      courses = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Lessons matching [query] across titles, notes and subtitle text.
  List<({Course course, Lesson lesson})> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <({Course course, Lesson lesson})>[];
    for (final course in courses) {
      for (final lesson in course.lessons) {
        final hay = (_searchText[lesson.id] ?? '').toLowerCase();
        if (hay.contains(q)) out.add((course: course, lesson: lesson));
      }
    }
    return out;
  }

  /// Fraction of a course's lessons completed (0..1).
  double courseProgress(Course course) {
    final lessons = course.lessons;
    if (lessons.isEmpty) return 0;
    final done =
        lessons.where((l) => progress.isCompleted(l.id)).length;
    return done / lessons.length;
  }

  Lesson? findLesson(String lessonId) {
    for (final course in courses) {
      for (final lesson in course.lessons) {
        if (lesson.id == lessonId) return lesson;
      }
    }
    return null;
  }

  Course? findCourseOf(String lessonId) {
    for (final course in courses) {
      if (course.lessons.any((l) => l.id == lessonId)) return course;
    }
    return null;
  }

  @override
  void dispose() {
    _proxy?.stop();
    super.dispose();
  }
}
