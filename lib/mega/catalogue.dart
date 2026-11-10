import 'dart:typed_data';

import 'api.dart';
import 'crypto.dart';
import 'link.dart';

/// One node (file or folder) in a Mega folder tree, with its decrypted key.
class MegaNode {
  final String handle;
  final String? parentHandle;
  final bool isDir;
  final String name;
  final int size;

  /// Decrypted key: 16 bytes for folders, 32 bytes (merged) for files.
  final Uint8List? key;

  final List<MegaNode> children = [];

  MegaNode({
    required this.handle,
    required this.parentHandle,
    required this.isDir,
    required this.name,
    required this.size,
    required this.key,
  });
}

/// A lesson: one video and/or document, with its notes, subtitles and
/// resource files grouped by filename stem.
class Lesson {
  /// Stable id: `Course/Module/stem`.
  final String id;
  final String name;
  final int order;
  final MegaNode? video;
  final MegaNode? note;
  final List<MegaNode> subtitles;
  final List<MegaNode> resources;

  /// Plain text of the note / subtitles, filled in after download.
  String noteText = '';
  String subtitleText = '';

  Lesson({
    required this.id,
    required this.name,
    required this.order,
    this.video,
    this.note,
    List<MegaNode>? subtitles,
    List<MegaNode>? resources,
  })  : subtitles = subtitles ?? const [],
        resources = resources ?? const [];

  bool get hasVideo => video != null;
}

class Module {
  final String id;
  final String name;
  final int order;
  final List<Lesson> lessons;

  Module({
    required this.id,
    required this.name,
    required this.order,
    required this.lessons,
  });
}

class Course {
  final String id;
  final String name;
  final int order;
  final String description;
  final List<Module> modules;

  Course({
    required this.id,
    required this.name,
    required this.order,
    this.description = '',
    required this.modules,
  });

  List<Lesson> get lessons => modules.expand((m) => m.lessons).toList();
}

const _videoExts = {'mp4', 'mkv', 'webm', 'mov'};
const _noteExts = {'md', 'txt'};
const _subtitleExts = {'srt', 'vtt'};

String _ext(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

String _stem(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? name : name.substring(0, i);
}

/// `01 - Intro to X` -> (order: 1, title: `Intro to X`).
/// Same rule as the desktop scanner.
({int order, String title}) splitPrefix(String name) {
  final m = RegExp(r'^(\d+)\s*[-_.]\s*(.+)$').firstMatch(name);
  if (m == null) return (order: 9999, title: name);
  return (order: int.parse(m.group(1)!), title: m.group(2)!);
}

int _byPrefix<T>(T a, T b, int Function(T) order, String Function(T) title) =>
    order(a) != order(b)
        ? order(a) - order(b)
        : title(a).compareTo(title(b));

/// Build a decrypted Mega tree from one `f` API response.
///
/// [nodesJson] is the raw `f` array, [rootKey] the 16-byte folder key from
/// the link. Throws [MegaApiException] when nothing decrypts.
MegaNode buildTree(List<dynamic> nodesJson, Uint8List rootKey) {
  final byHandle = <String, Map<String, dynamic>>{};
  for (final raw in nodesJson) {
    final m = raw as Map<String, dynamic>;
    byHandle[m['h'] as String] = m;
  }

  // The root folder is the node whose handle appears as the first part
  // of one of its own key alternatives.
  Map<String, dynamic>? rootRaw;
  for (final raw in nodesJson) {
    final m = raw as Map<String, dynamic>;
    final k = m['k'] as String?;
    if (k == null) continue;
    final isRoot = k.split('/').any(
          (part) => m['h'] == part.split(':')[0],
        );
    if (isRoot) {
      rootRaw = m;
      break;
    }
  }
  rootRaw ??= byHandle.values.firstWhere(
    (m) => m['p'] == null,
    orElse: () => byHandle.values.first,
  );

  // The root folder's own name decrypts with the link key.
  var rootName = rootRaw['h'] as String;
  final rootAttrs = rootRaw['a'] as String?;
  if (rootAttrs != null) {
    final parsed = decryptAttributes(rootKey, rootAttrs);
    if (parsed != null && parsed['n'] is String) {
      rootName = parsed['n'] as String;
    }
  }
  return _buildRootWithName(rootRaw, byHandle, rootKey, rootName);
}

MegaNode _buildRootWithName(
  Map<String, dynamic> rootRaw,
  Map<String, Map<String, dynamic>> byHandle,
  Uint8List rootKey,
  String name,
) {
  final root = MegaNode(
    handle: rootRaw['h'] as String,
    parentHandle: null,
    isDir: true,
    name: name,
    size: 0,
    key: rootKey,
  );
  for (final childRaw in byHandle.values) {
    if (childRaw['p'] == root.handle) {
      root.children.add(_buildChild(childRaw, byHandle, rootKey));
    }
  }
  // Note: _buildChild decrypts every node key with the folder (link) key,
  // not the parent key — see below.
  root.children.sort(
    (a, b) => _byPrefix(
      a,
      b,
      (n) => splitPrefix(n.name).order,
      (n) => splitPrefix(n.name).title,
    ),
  );
  return root;
}

/// Build one node of the tree. Every node key in a public folder is
/// AES-ECB encrypted with the FOLDER (link) key — not with the parent
/// node's key. This mirrors megajs: `File.loadAttributes` builds one AES
/// object from the root folder key and passes it to `loadMetadata` for
/// every node in the `f` response ("HACK: The correct key for shared
/// folder is the one which parts[0] === folder.h but we can just try
/// every single key alternative"). The raw `k` values confirm it: every
/// node in Soufian's folder has `k` prefixed with the root handle.
MegaNode _buildChild(
  Map<String, dynamic> raw,
  Map<String, Map<String, dynamic>> byHandle,
  Uint8List folderKey,
) {
  final handle = raw['h'] as String;
  final isDir = raw['t'] == 1;
  final kField = raw['k'] as String?;
  Uint8List? key;
  String name = handle;
  if (kField != null) {
    for (final alt in kField.split('/')) {
      final kb64 = alt.split(':').last;
      final decoded = b64UrlDecode(kb64);
      if (decoded.length > 32) continue;
      final candidate = aesEcbDecrypt(folderKey, decoded);
      final attrs = raw['a'] as String?;
      if (attrs != null) {
        final parsed = decryptAttributes(candidate, attrs);
        if (parsed != null && parsed['n'] is String) {
          key = candidate;
          name = parsed['n'] as String;
          break;
        }
      } else {
        key ??= candidate;
      }
    }
  }
  key ??= folderKey;
  final node = MegaNode(
    handle: handle,
    parentHandle: raw['p'] as String?,
    isDir: isDir,
    name: name,
    size: (raw['s'] as num?)?.toInt() ?? 0,
    key: key,
  );
  if (isDir) {
    for (final childRaw in byHandle.values) {
      if (childRaw['p'] == handle) {
        node.children.add(_buildChild(childRaw, byHandle, folderKey));
      }
    }
    node.children.sort(
      (a, b) => _byPrefix(
        a,
        b,
        (n) => splitPrefix(n.name).order,
        (n) => splitPrefix(n.name).title,
      ),
    );
  }
  return node;
}

/// Group the files directly inside [dir] into lessons by filename stem.
/// A stem becomes a lesson when it has a video, a note, subtitles, or any
/// resource file. A same-stem subfolder contributes its files as resources.
List<Lesson> _lessonsInDir(MegaNode dir, String moduleId) {
  final files = dir.children.where((c) => !c.isDir).toList();
  final dirsByName = <String, MegaNode>{
    for (final c in dir.children.where((c) => c.isDir)) c.name: c,
  };
  final byStem = <String, _StemFiles>{};
  for (final f in files) {
    final stem = _stem(f.name);
    final slot = byStem.putIfAbsent(stem, () => _StemFiles());
    final ext = _ext(f.name);
    if (_videoExts.contains(ext)) {
      slot.video = f;
    } else if (_noteExts.contains(ext)) {
      slot.note ??= f;
    } else if (_subtitleExts.contains(ext)) {
      slot.subtitles.add(f);
    } else {
      slot.resources.add(f);
    }
  }
  final lessons = <Lesson>[];
  for (final entry in byStem.entries) {
    final stem = entry.key;
    final slot = entry.value;
    if (slot.video == null &&
        slot.note == null &&
        slot.subtitles.isEmpty &&
        slot.resources.isEmpty) {
      continue;
    }
    final resources = List<MegaNode>.of(slot.resources);
    final resDir = dirsByName[stem];
    if (resDir != null) {
      void collect(MegaNode d) {
        for (final c in d.children) {
          if (c.isDir) {
            collect(c);
          } else {
            resources.add(c);
          }
        }
      }

      collect(resDir);
    }
    final parsed = splitPrefix(stem);
    lessons.add(Lesson(
      id: '$moduleId/$stem',
      name: parsed.title,
      order: parsed.order,
      video: slot.video,
      note: slot.note,
      subtitles: slot.subtitles,
      resources: resources,
    ));
  }
  lessons.sort(
    (a, b) => _byPrefix(a, b, (l) => l.order, (l) => l.name),
  );
  return lessons;
}

class _StemFiles {
  MegaNode? video;
  MegaNode? note;
  final List<MegaNode> subtitles = [];
  final List<MegaNode> resources = [];
}

/// Build one course from a directory node: its subdirectories are modules,
/// and files directly inside it become lessons of a synthetic module
/// named after the course (the flat-layout case).
Course? _buildCourse(MegaNode dir) {
  final parsed = splitPrefix(dir.name);
  final modules = <Module>[];
  final direct = _lessonsInDir(dir, '${dir.name}/Lessons');
  if (direct.isNotEmpty) {
    modules.add(Module(
      id: '${dir.name}/Lessons',
      name: dir.name,
      order: 9998,
      lessons: direct,
    ));
  }
  for (final sub in dir.children.where((c) => c.isDir)) {
    final lessons = _lessonsInDir(sub, '${dir.name}/${sub.name}');
    if (lessons.isEmpty) continue;
    final modParsed = splitPrefix(sub.name);
    modules.add(Module(
      id: '${dir.name}/${sub.name}',
      name: modParsed.title,
      order: modParsed.order,
      lessons: lessons,
    ));
  }
  modules.sort(
    (a, b) => _byPrefix(a, b, (m) => m.order, (m) => m.name),
  );
  if (modules.isEmpty) return null;
  return Course(
    id: dir.name,
    name: parsed.title,
    order: parsed.order,
    modules: modules,
  );
}

/// Build the course list for a linked folder ([target], usually the
/// subfolder from the link, else the folder root).
///
/// - If the target itself builds into a course (its subdirectories hold
///   lessons directly, or it holds videos directly), it is one course.
/// - Otherwise each subdirectory that builds into a course becomes one
///   (the target is a library of courses).
/// - A course with no lessons is dropped.
List<Course> buildCatalogue(MegaNode target) {
  final asCourse = _buildCourse(target);
  if (asCourse != null) return [asCourse];
  final courses = <Course>[];
  for (final sub in target.children.where((c) => c.isDir)) {
    final course = _buildCourse(sub);
    if (course != null) courses.add(course);
  }
  courses.sort(
    (a, b) => _byPrefix(a, b, (c) => c.order, (c) => c.name),
  );
  return courses;
}

/// Load a Mega folder link end to end: parse, list, decrypt, catalogue.
/// Returns the courses under the linked (sub)folder.
Future<List<Course>> loadCatalogueFromLink(MegaApi api, String url) async {
  final link = parseMegaLink(url);
  final rootKey = b64UrlDecode(link.key);
  if (rootKey.length != 16) {
    throw const MegaApiException('Invalid Mega folder key in link.');
  }
  final nodesJson = await api.listFolder(link.rootHandle);
  final tree = buildTree(nodesJson, rootKey);
  MegaNode target = tree;
  if (link.subfolderHandle != null) {
    final found = _findByHandle(tree, link.subfolderHandle!);
    if (found == null) {
      throw const MegaApiException(
        'Subfolder from the link was not found in this Mega folder.',
      );
    }
    target = found;
  }
  return buildCatalogue(target);
}

MegaNode? _findByHandle(MegaNode node, String handle) {
  if (node.handle == handle) return node;
  for (final c in node.children) {
    if (c.isDir) {
      final found = _findByHandle(c, handle);
      if (found != null) return found;
    }
  }
  return null;
}
