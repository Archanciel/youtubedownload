// lib/viewmodels/download_vm.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../models/playlist.dart';
import '../services/playlist_sync_service.dart'; // the service I provided
import '../services/settings_data_service.dart';
import '../utils/dir_util.dart';
import '../viewmodels/settings_vm.dart';
import '../services/yt_dlp_service.dart';

class DownloadVM extends ChangeNotifier {
  // Existing fields you already had...
  bool _busy = false;
  double _progress = 0.0;
  String _status = 'Idle';
  String? _lastOutputPath;

  bool get busy => _busy;
  double get progress => _progress;
  String get status => _status;
  String? get lastOutputPath => _lastOutputPath;

  // ——— New fields for playlist flow ———
  SettingsVM? _settingsVM;
  YtDlpService? _ytService;

  late PlaylistSyncService _sync; // constructed in attach
  late ProcessRunner _runner; // used by the service
  String? _pickedPlaylistJson;
  Playlist? _loadedPlaylist;

  String? get pickedPlaylistJson => _pickedPlaylistJson;
  Playlist? get loadedPlaylist => _loadedPlaylist;

  /// Called by Provider's update() in your YtAudioDownloaderApp.
  Future<void> attach(SettingsVM settingsVM, YtDlpService ytService) async {
    _settingsVM = settingsVM;
    _ytService = ytService;

    // A minimal runner implementation (you can also adapt YtDlpService to implement ProcessRunner)
    _runner = ProcessRunner();

    // Gather values from SettingsVM; make sure SettingsVM exposes these
    final ytPath = settingsVM.ytDlpPath; // e.g. C:\YtDlp\yt-dlp.exe
    final ffprobe = settingsVM.ffprobePath; // nullable; e.g. 'ffprobe'
    final defaultPS = settingsVM
        .defaultPlaySpeed; // from settings repo (e.g. Playlists.playSpeed)
    final qualityVbr = settingsVM.qualityVbr;
    // "0".."9" you selected in UI (we can pass later)
    final SettingsDataService settingsDataService = SettingsDataService(
      sharedPreferences: await SharedPreferences.getInstance(),
      isTest: false,
    );

    await settingsDataService.loadSettingsFromFile(
      settingsJsonPathFileName:
          '${DirUtil.getApplicationPath(isTest: false)}${Platform.pathSeparator}$kSettingsFileName',
    );

    // Build the sync service (idempotent; safe if called multiple times)
    _sync = PlaylistSyncService(
      runner: _runner,
      settings: settingsDataService, // or expose a getter to your underlying SettingsDataService
      ytDlpExe: ytPath ?? r'C:\YtDlp\yt-dlp.exe',
      ffprobeExe: (ffprobe != null && ffprobe.isNotEmpty) ? ffprobe : null,
      defaultPlaySpeed: defaultPS,
      saveAfterEachItem: true,
    );

    // If you want to react immediately when user changes quality in UI,
    // you can keep `qualityVbr` in this VM as well; or just pass an override
    // when calling downloadMissingFromPickedJson().

    notifyListeners();
  }

  // ——— UI actions ———

  Future<void> pickPlaylistJson() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select AudioLearn playlist JSON',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return;

    _pickedPlaylistJson = result.files.single.path!;
    _status = 'Loading playlist…';
    notifyListeners();

    try {
      _loadedPlaylist = await _sync.loadPlaylistFromJson(_pickedPlaylistJson!);
      _status = 'Loaded: ${_loadedPlaylist!.title}';
    } catch (e) {
      _status = 'Failed to load JSON: $e';
      _pickedPlaylistJson = null;
      _loadedPlaylist = null;
    }
    notifyListeners();
  }

  Future<void> downloadMissingFromPickedJson({
    String? qualityVbrOverride,
  }) async {
    if (_pickedPlaylistJson == null || _loadedPlaylist == null) {
      _status = 'Pick a playlist JSON first.';
      notifyListeners();
      return;
    }
    if (_busy) return;

    _busy = true;
    _progress = 0.0;
    _status = 'Starting playlist download…';
    notifyListeners();

    try {
      await _sync.downloadMissingAudios(
        playlistJsonPathFileName: _pickedPlaylistJson!,
        playlist: _loadedPlaylist!,
        qualityVbrOverride: qualityVbrOverride ?? _settingsVM?.qualityVbr,
        onStatus: (msg) {
          _status = msg;
          notifyListeners();
        },
        onProgress: (pct) {
          _progress = pct;
          notifyListeners();
        },
        onItemIndex: (cur, tot) {
          /* optionally expose per-item index */
        },
      );

      // Update a convenient path for “Open folder” style buttons
      if (_loadedPlaylist!.playableAudioLst.isNotEmpty) {
        _lastOutputPath = p.join(
          _loadedPlaylist!.downloadPath,
          _loadedPlaylist!.playableAudioLst.first.audioFileName,
        );
      }
    } catch (e) {
      _status = 'Failed: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
