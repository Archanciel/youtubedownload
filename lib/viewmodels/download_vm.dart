import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/yt_dlp_service.dart';
import '../viewmodels/settings_vm.dart';

/// Handles the download action, progress, cancel, and UI state.
class DownloadVM extends ChangeNotifier {
  late SettingsVM _settings;
  late YtDlpService _service;

  final TextEditingController urlController = TextEditingController();

  bool _busy = false;
  bool get busy => _busy;

  double _progress = 0.0;
  double get progress => _progress;

  String _status = 'Idle';
  String get status => _status;

  String? _lastOutputPath;
  String? get lastOutputPath => _lastOutputPath;

  void attach(SettingsVM settings, YtDlpService service) {
    _settings = settings;
    _service = service;
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  void _setProgress(double v) {
    _progress = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void _setStatus(String s) {
    _status = s;
    notifyListeners();
  }

  void _setLastOutput(String? path) {
    _lastOutputPath = path;
    notifyListeners();
  }

  Future<void> pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      urlController.text = text;
      notifyListeners();
    }
  }

  Future<void> download() async {
    final url = urlController.text.trim();
    if (url.isEmpty) {
      _setStatus('Please paste a YouTube URL.');
      return;
    }
    if (_settings.targetDir == 'No target folder chosen') {
      _setStatus('Please choose a target folder first.');
      return;
    }
    if (!_settings.ffmpegAvailable) {
      _setStatus('FFmpeg not found: place ffmpeg.exe next to yt-dlp.exe or add it to PATH.');
      return;
    }
    if (_settings.ytDlpPath == null) {
      _setStatus('yt-dlp not found (c:\\YtDlp, PATH, or working dir).');
      return;
    }

    _setBusy(true);
    _setProgress(0.0);
    _setLastOutput(null);
    _setStatus('Preparing…');

    final outTpl = '${_settings.targetDir}\\%(title).150s.%(ext)s';

    final args = [
      '--yes-playlist',
      '-f', 'bestaudio/best',
      '--extract-audio',
      '--audio-format', 'mp3',
      '--audio-quality', _settings.qualityVbr,
      '-o', outTpl,
      '--restrict-filenames',
      '--newline',
      url,
    ];

    _setStatus('Downloading and converting to MP3… (quality ${_settings.qualityLabel})');

    try {
      final code = await _service.run(
        exe: _settings.ytDlpPath!,
        args: args,
        onProgress: (pct) => _setProgress(pct),
        onStatus: (s) => _setStatus(s),
        onDestination: (path) => _setLastOutput(path),
      );

      if (code == 0) {
        _setProgress(1.0);
        _setStatus('Download completed (MP3 ready).');
      } else {
        _setStatus('yt-dlp exited with code $code');
      }
    } catch (e) {
      _setStatus('yt-dlp failed: $e');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> cancel() async {
    await _service.killIfRunning();
    _setBusy(false);
    _setProgress(0.0);
    _setStatus('Canceled.');
  }
}
