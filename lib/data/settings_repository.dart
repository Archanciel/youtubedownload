import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

class SettingsRepository {
  Future<String?> getLastTargetDir() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = prefs.getString(PrefKeys.lastTargetDir);
    if (dir != null && Directory(dir).existsSync()) return dir;
    return null;
  }

  Future<void> setLastTargetDir(String dir) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.lastTargetDir, dir);
  }

  Future<String> getQualityLabel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefKeys.audioQualityLabel) ??
        Defaults.defaultQualityLabel;
  }

  Future<void> setQualityLabel(String label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.audioQualityLabel, label);
  }

  String? findYtDlpExe({String hardcoded = Defaults.hardcodedYtDlp}) {
    if (File(hardcoded).existsSync()) return hardcoded;

    final envPath = Platform.environment['PATH'] ?? '';
    for (final part in envPath.split(Platform.isWindows ? ';' : ':')) {
      final exe = p.join(part.trim(),
          Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp');
      if (File(exe).existsSync()) return exe;
    }

    final local = p.join(Directory.current.path,
        Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp');
    if (File(local).existsSync()) return local;

    return null;
  }

  Future<bool> isFfmpegAvailable() async {
    try {
      final res = await Process.run(
          Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg', ['-version']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // --- New: persist last FFmpeg update date (ISO string) ---

  Future<void> setFfmpegUpdatedAt(String iso) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.ffmpegUpdatedAt, iso);
  }

  Future<String?> getFfmpegUpdatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefKeys.ffmpegUpdatedAt);
  }
}
