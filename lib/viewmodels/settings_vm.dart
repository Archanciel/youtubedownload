import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../data/settings_repository.dart';
import '../domain/audio_quality.dart';
import '../services/yt_dlp_service.dart';

/// Holds app-wide settings/state: target directory, audio quality, paths.
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
    notifyListeners();
  }

  Future<void> setQualityLabel(String label) async {
    _qualityLabel = label;
    await _repo.setQualityLabel(label);
    notifyListeners();
  }
}
