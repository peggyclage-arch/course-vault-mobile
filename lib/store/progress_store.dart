import 'package:shared_preferences/shared_preferences.dart';

/// Per-lesson playback positions and completion, stored on the phone.
/// Lesson ids are stable paths like `Course/Module/stem`.
class ProgressStore {
  static const _posPrefix = 'pos:';
  static const _donePrefix = 'done:';
  static const _linkKey = 'mega_link';

  final SharedPreferences _prefs;

  ProgressStore(this._prefs);

  static Future<ProgressStore> load() async {
    return ProgressStore(await SharedPreferences.getInstance());
  }

  double position(String lessonId) =>
      _prefs.getDouble('$_posPrefix$lessonId') ?? 0;

  Future<void> savePosition(String lessonId, double seconds) async {
    await _prefs.setDouble('$_posPrefix$lessonId', seconds);
  }

  bool isCompleted(String lessonId) =>
      _prefs.getBool('$_donePrefix$lessonId') ?? false;

  Future<void> setCompleted(String lessonId, bool value) async {
    await _prefs.setBool('$_donePrefix$lessonId', value);
  }

  String? get lastLink => _prefs.getString(_linkKey);

  Future<void> saveLink(String link) async {
    await _prefs.setString(_linkKey, link);
  }
}

/// Format seconds as `m:ss` or `h:mm:ss`.
String formatDuration(double seconds) {
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}
