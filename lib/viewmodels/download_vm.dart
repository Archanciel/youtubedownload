import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import '../services/playlist_sync_service.dart';
import '../services/settings_data_service.dart';
import '../models/playlist.dart';

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
  final _runner = ProcessRunner();

  String? _pickedPlaylistJson;
  String? get pickedPlaylistJson => _pickedPlaylistJson;

  Playlist? _loadedPlaylist;
  Playlist? get loadedPlaylist => _loadedPlaylist;

  late SettingsDataService _settingsDataService;
  void attachSettings(SettingsDataService sds) => _settingsDataService = sds;

  // Injected from SettingsVM/UI once binaries are detected
  late String _ytDlpExe;
  String? _ffprobeExe;
  late String _qualityVbr; // e.g. from SettingsVM.qualityVbr
  late double _defaultPlaySpeed; // e.g. from SettingsDataService

  void attach(SettingsVM settings, YtDlpService service) {
    _settings = settings;
    _service = service;
  }

  void attachBinariesAndPrefs({
    required String ytDlpExe,
    String? ffprobeExe,
    required String qualityVbr,
    double? defaultPlaySpeed,
  }) {
    _ytDlpExe = ytDlpExe;
    _ffprobeExe = ffprobeExe;
    _qualityVbr = qualityVbr;
    _defaultPlaySpeed =
        defaultPlaySpeed ??
        (_settingsDataService.get(
              settingType: SettingType.playlists,
              settingSubType: Playlists.playSpeed,
            )
            as double);
  }

  Future<void> pickPlaylistJson() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select AudioLearn playlist JSON',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return;
    _pickedPlaylistJson = result.files.single.path!;
    notifyListeners();

    // Load as your Playlist via JsonDataService (through the service)
    final sync = PlaylistSyncService(
      runner: _runner,
      settings: _settingsDataService,
      ytDlpExe: _ytDlpExe,
      ffprobeExe: _ffprobeExe,
      defaultPlaySpeed: _defaultPlaySpeed,
    );

    _loadedPlaylist = await sync.loadPlaylistFromJson(_pickedPlaylistJson!);
    notifyListeners();
  }

  Future<void> downloadMissingFromPickedJson() async {
    if (_pickedPlaylistJson == null || _loadedPlaylist == null) {
      _status = 'Pick a playlist JSON first.';
      notifyListeners();
      return;
    }
    if (_busy) return;

    _busy = true;
    _progress = 0.0;
    _status = 'Starting…';
    notifyListeners();

    final sync = PlaylistSyncService(
      runner: _runner,
      settings: _settingsDataService,
      ytDlpExe: _ytDlpExe,
      ffprobeExe: _ffprobeExe,
      defaultPlaySpeed: _defaultPlaySpeed,
      saveAfterEachItem: true, // safer
    );

    try {
      await sync.downloadMissingAudios(
        playlistJsonPathFileName: _pickedPlaylistJson!,
        playlist: _loadedPlaylist!,
        // If you want to force UI-selected VBR, pass qualityVbrOverride: _qualityVbr,
        onStatus: (s) {
          _status = s;
          notifyListeners();
        },
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
        onItemIndex: (cur, tot) {
          /* optionally expose per-item index */
        },
      );
      // After completion, update `lastOutputPath` if you like
    } catch (e) {
      _status = 'Failed: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
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
      _setStatus(
        'FFmpeg not found: place ffmpeg.exe next to yt-dlp.exe or add it to PATH.',
      );
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
      '-f',
      'bestaudio/best',
      '--extract-audio',
      '--audio-format',
      'mp3',
      '--audio-quality',
      _settings.qualityVbr,
      '-o',
      outTpl,
      '--restrict-filenames',
      '--newline',
      url,
    ];

    _setStatus(
      'Downloading and converting to MP3… (quality ${_settings.qualityLabel})',
    );

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
