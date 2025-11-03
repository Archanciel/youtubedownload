import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../data/settings_repository.dart';
import '../domain/audio_quality.dart';
import '../services/yt_dlp_service.dart';

/// Holds app-wide settings/state: target directory, audio quality, binaries.
class SettingsVM extends ChangeNotifier {
  late SettingsRepository _repo;
  late YtDlpService _service;

  String? _targetDir;
  String get targetDir => _targetDir ?? 'No target folder chosen';

  String _qualityLabel = Defaults.defaultQualityLabel;
  String get qualityLabel => _qualityLabel;
  String get qualityVbr => AudioQuality.vbrFor(_qualityLabel);

  String? _ytDlpPath;
  String? get ytDlpPath => _ytDlpPath;

  bool _ffmpegAvailable = false;
  bool get ffmpegAvailable => _ffmpegAvailable;

  // --- New: yt-dlp version + update state
  String? _ytDlpVersion;
  String? get ytDlpVersion => _ytDlpVersion;

  bool _updatingYtDlp = false;
  bool get updatingYtDlp => _updatingYtDlp;

  String? _lastUpdateLog;
  String? get lastUpdateLog => _lastUpdateLog;

  void attach(SettingsRepository repo, YtDlpService service) {
    _repo = repo;
    _service = service;
    _init();
  }

  Future<void> _init() async {
    _targetDir = await _repo.getLastTargetDir();
    _qualityLabel = await _repo.getQualityLabel();
    _ytDlpPath = _repo.findYtDlpExe();
    _ffmpegAvailable = await _repo.isFfmpegAvailable();
    await _updateVersionCached();
    notifyListeners();
  }

  Future<void> pickDirectory() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose target folder',
      initialDirectory: _targetDir,
    );
    if (dir != null) {
      _targetDir = dir;
      await _repo.setLastTargetDir(dir);
      notifyListeners();
    }
  }

  Future<void> refreshBinaryAvailability() async {
    _ytDlpPath = _repo.findYtDlpExe();
    _ffmpegAvailable = await _repo.isFfmpegAvailable();
    await _updateVersionCached();
    notifyListeners();
  }

  Future<void> setQualityLabel(String label) async {
    _qualityLabel = label;
    await _repo.setQualityLabel(label);
    notifyListeners();
  }

  // --- New: version & update ---

  Future<void> _updateVersionCached() async {
    if (_ytDlpPath == null) {
      _ytDlpVersion = null;
      return;
    }
    try {
      _ytDlpVersion = await _service.getVersion(_ytDlpPath!);
    } catch (_) {
      _ytDlpVersion = null;
    }
  }

  /// Checks yt-dlp version and updates the property.
  Future<void> checkYtDlpVersion() async {
    await _updateVersionCached();
    notifyListeners();
  }

  /// Runs yt-dlp self-update (-U), then refreshes version info.
  /// Returns true if the update succeeded (or already up to date).
  Future<bool> updateYtDlp() async {
    if (_ytDlpPath == null) {
      _lastUpdateLog = 'yt-dlp not found (c:\\YtDlp, PATH, or working dir).';
      notifyListeners();
      return false;
    }

    _updatingYtDlp = true;
    _lastUpdateLog = null;
    notifyListeners();

    try {
      final (code, log) = await _service.selfUpdate(_ytDlpPath!);
      _lastUpdateLog = log.trim();

      // Common cases:
      // - If in a protected directory, self-update may fail (access denied).
      // - If already up to date, output contains such note.
      // We don't try to parse exact strings; we just display the log.

      await _updateVersionCached();
      _updatingYtDlp = false;
      notifyListeners();

      // Consider code==0 a success. code==1 is often "already up to date",
      // but treat it as success for UX.
      return code == 0 || code == 1;
    } catch (e) {
      _updatingYtDlp = false;
      _lastUpdateLog = 'Update failed: $e';
      notifyListeners();
      return false;
    }
  }
}
