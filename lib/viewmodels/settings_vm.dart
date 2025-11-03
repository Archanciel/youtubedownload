import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../data/settings_repository.dart';
import '../domain/audio_quality.dart';
import '../services/yt_dlp_service.dart';
import '../services/ffmpeg_service.dart';

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

  // yt-dlp diagnostics
  String? _ytDlpVersion;
  String? get ytDlpVersion => _ytDlpVersion;

  bool _updatingYtDlp = false;
  bool get updatingYtDlp => _updatingYtDlp;

  String? _lastUpdateLog;
  String? get lastUpdateLog => _lastUpdateLog;

  // --- FFmpeg update state ---
  bool _updatingFfmpeg = false;
  bool get updatingFfmpeg => _updatingFfmpeg;

  String? _ffmpegUpdateDate; // ISO 8601 string persisted
  String? get ffmpegUpdateDate => _ffmpegUpdateDate;

  String? _ffmpegUpdateLog;
  String? get ffmpegUpdateLog => _ffmpegUpdateLog;

  // NEW: store ffprobe path (nullable)
  String? _ffprobePath;
  String? get ffprobePath => _ffprobePath;

  // NEW: cache default play speed (comes from repo)
  final double _defaultPlaySpeed = kAudioDefaultPlaySpeed;
  double get defaultPlaySpeed => _defaultPlaySpeed;

  String _qualityLabelToVbr(String label) {
    // map your UI label (e.g., "Best (V0)") to "0" etc.
    // Or, if you already store "0".."9", just return it.
    // Example:
    switch (label) {
      case 'Best (V0)': return '0';
      case 'High (V2)': return '2';
      case 'Good (V4)': return '4';
      case 'Light (V7)': return '7';
      case 'Very light (V9)': return '9';
      default: return '7';
    }
  }
  
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
    _ffmpegUpdateDate = await _repo.getFfmpegUpdatedAt();
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

  // ---- yt-dlp ----
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

  Future<void> checkYtDlpVersion() async {
    await _updateVersionCached();
    notifyListeners();
  }

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
      await _updateVersionCached();
      _updatingYtDlp = false;
      notifyListeners();
      return code == 0 || code == 1;
    } catch (e) {
      _updatingYtDlp = false;
      _lastUpdateLog = 'Update failed: $e';
      notifyListeners();
      return false;
    }
  }

  // ---- FFmpeg ----
  Future<bool> updateFfmpeg() async {
    // Choose a writable directory to host ffmpeg.exe.
    // Prefer the directory where yt-dlp.exe lives; otherwise fallback to C:\YtDlp.
    var baseDir = r'c:\YtDlp';
    if (_ytDlpPath != null) {
      try {
        baseDir = File(_ytDlpPath!).parent.path;
      } catch (_) {}
    }
    final service = FfmpegService(targetDir: baseDir);

    _updatingFfmpeg = true;
    _ffmpegUpdateLog = null;
    notifyListeners();

    final logBuf = StringBuffer();

    try {
      final path = await service.updateFfmpeg(onLog: (m) {
        logBuf.writeln(m);
        _ffmpegUpdateLog = logBuf.toString().trimRight();
        notifyListeners();
      });

      // Refresh availability and remember update date
      _ffmpegAvailable = await _repo.isFfmpegAvailable();
      _ffmpegUpdateDate = DateFormat('dd/MM/yyyy hh:mm:ss').format(DateTime.now());
      await _repo.setFfmpegUpdatedAt(_ffmpegUpdateDate!);

      _updatingFfmpeg = false;
      _ffmpegUpdateLog = '${logBuf.toString().trimRight()}\nDone → $path';
      notifyListeners();
      return true;
    } catch (e) {
      _updatingFfmpeg = false;
      _ffmpegUpdateLog = '${logBuf.toString().trimRight()}\nFailed: $e';
      notifyListeners();
      return false;
    }
  }
}
