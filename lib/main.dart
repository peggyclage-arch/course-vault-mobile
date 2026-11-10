import 'package:flutter/material.dart';

import 'mega/api.dart';
import 'store/library.dart';
import 'store/progress_store.dart';
import 'ui/library_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final progress = await ProgressStore.load();
  runApp(CourseVaultApp(progress: progress));
}

/// CourseVault — a local-first course library for Android and iPhone.
///
/// Paste a Mega folder link and it builds your catalogue, tracks progress,
/// and resumes where you left off. No accounts, no cloud, no AI.
class CourseVaultApp extends StatefulWidget {
  final ProgressStore progress;

  const CourseVaultApp({super.key, required this.progress});

  @override
  State<CourseVaultApp> createState() => _CourseVaultAppState();
}

class _CourseVaultAppState extends State<CourseVaultApp> {
  late final LibraryState _library;

  @override
  void initState() {
    super.initState();
    _library = LibraryState(api: MegaApi(), progress: widget.progress);
    // Load the last link (or the default one) on startup.
    final link = widget.progress.lastLink ?? defaultMegaLink;
    _library.loadLink(link);
  }

  @override
  void dispose() {
    _library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CourseVault',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: LibraryScreen(library: _library),
    );
  }
}
