// lib/viewmodels/download_vm.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/playlist.dart';
import '../services/yt_dlp_service.dart';
import '../viewmodels/settings_vm.dart';

class DownloadVM extends ChangeNotifier {
  // ---------- Public state consumed by UI ----------
  final TextEditingController urlController = TextEditingController();

  bool _busy = false;
  bool get busy => _busy;

  double _progress = 0.0;
  double get progress => _progress;

  String _status = 'Idle';
  String get status => _status;

  String? _lastOutputPath;
  String? get lastOutputPath => _lastOutputPath;

  // For your playlist workflow (JSON selection + “missing only” download)
  String? _pickedPlaylistJson;
  String? get pickedPlaylistJson => _pickedPlaylistJson;

  Playlist? _loadedPlaylist;
  Playlist? get loadedPlaylist => _loadedPlaylist;

  // ---------- Wiring ----------
  SettingsVM? _settings;
  YtDlpService? _ytService;
  Process? _proc; // keep handle for cancel

  void attach(SettingsVM settings, YtDlpService service) {
    _settings = settings;
    _ytService = service; // currently unused for download (direct Process), but kept for future use
  }

  // ---------- Clipboard ----------
  Future<void> pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      urlController.text = text;
      notifyListeners();
    }
  }

  // ---------- Single video download via yt-dlp ----------
  Future<void> download() async {
    final settings = _settings;
    if (settings == null) {
      _setStatus('Internal error: SettingsVM not attached.');
      return;
    }

    final url = urlController.text.trim();
    if (url.isEmpty) {
      _setStatus('Please paste a YouTube URL.');
      return;
    }

    final targetDir = settings.targetDir;
    if (targetDir == 'No target folder chosen') {
      _setStatus('Please choose a target folder first.');
      return;
    }

    final yt = settings.ytDlpPath;
    if (yt == null || yt.isEmpty) {
      _setStatus('yt-dlp.exe not found. Use “Refresh binaries” or install it.');
      return;
    }

    // Final MP3 path will be printed by yt-dlp via --print after_move:filepath
    final outTpl = p.join(targetDir, '%(title).150s.%(ext)s');

    // VBR: "0" .. "9" from SettingsVM (maps from your dropdown labels)
    final vbr = settings.qualityVbr; // e.g. "0", "2", "4", "7", "9"

    // Build args
    final args = <String>[
      '-f', 'bestaudio/best',
      '--extract-audio',
      '--audio-format', 'mp3',
      '--audio-quality', vbr,
      '-o', outTpl,
      '--restrict-filenames',
      '--newline',
      // print the final moved path so we can set lastOutputPath deterministically
      '--print', 'after_move:filepath',
      url,
    ];

    _busy = true;
    _progress = 0.0;
    _setStatus('Downloading and converting to MP3…');

    try {
      _proc = await Process.start(yt, args, runInShell: true);

      // Progress parsing
      final stdoutLines = _proc!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final stderrLines = _proc!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      String? printedFinalPath;

      final subs = <StreamSubscription>[
        stdoutLines.listen((line) {
          // A plain line that is an absolute/relative path from --print
          if (!_looksLikeYtDlpProgress(line) && _looksLikeAPath(line)) {
            printedFinalPath = line.trim();
            // do not notify here; wait for completion
          }

          final m = RegExp(r'\[download\]\s+(\d+(?:\.\d+)?)%').firstMatch(line);
          if (m != null) {
            final pct = double.tryParse(m.group(1)!);
            if (pct != null) {
              _progress = (pct / 100.0).clamp(0.0, 1.0);
              notifyListeners();
            }
          }
        }),
        stderrLines.listen((line) {
          // keep last message visible to user
          _setStatus(line);
        }),
      ];

      final code = await _proc!.exitCode;
      for (final s in subs) {
        await s.cancel();
      }
      _proc = null;

      if (code == 0) {
        _progress = 1.0;
        if (printedFinalPath != null && printedFinalPath!.isNotEmpty) {
          _lastOutputPath = printedFinalPath;
        }
        _setStatus('Download completed (MP3 ready).');
      } else {
        _setStatus('yt-dlp exited with code $code');
      }
    } catch (e) {
      _setStatus('Download failed: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void cancel() {
    if (_proc != null) {
      // Try graceful, then force
      _proc!.kill(ProcessSignal.sigint);
      Future.delayed(const Duration(milliseconds: 300), () {
        _proc?.kill(ProcessSignal.sigkill);
      });
    }
    _proc = null;
    _busy = false;
    _progress = 0.0;
    _setStatus('Canceled.');
    notifyListeners();
  }

  // ---------- Playlist helpers (JSON → “missing only”) ----------
  Future<void> pickPlaylistJson() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select AudioLearn playlist JSON',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (result == null) return;

    _pickedPlaylistJson = result.files.single.path!;
    _status = 'Loading playlist…';
    notifyListeners();

    try {
      // Your Playlist JSON is exactly what your AudioLearn model expects
      final file = File(_pickedPlaylistJson!);
      final content = await file.readAsString();

      // Reuse your model factory
      _loadedPlaylist = Playlist.fromJson(
        // ignore: avoid_dynamic_calls
        (jsonDecode(content) as Map<String, dynamic>),
      );

      _status = 'Loaded: ${_loadedPlaylist!.title}';
    } catch (e) {
      _status = 'Failed to load JSON: $e';
      _pickedPlaylistJson = null;
      _loadedPlaylist = null;
    }
    notifyListeners();
  }

  /// Skeleton: you can plug your missing-only logic here later.
  /// For now we just validate the presence of JSON/playlist and
  /// surface an informative status.
  Future<void> downloadMissingFromPickedJson() async {
    if (_pickedPlaylistJson == null || _loadedPlaylist == null) {
      _setStatus('Pick a playlist JSON first.');
      notifyListeners();
      return;
    }

    // Here you will do:
    // 1) Inspect _loadedPlaylist.downloadedAudioLst and/or playableAudioLst
    // 2) For each missing video/audio, call yt-dlp similarly to download()
    // 3) Update _progress and _status across items, and persist playlist JSON
    //
    // This VM already contains the single-video pipeline (download()) that
    // you can reuse in a loop.
    _setStatus('Playlist download (missing only) not yet implemented.');
    notifyListeners();
  }

  // ---------- Helpers ----------
  void _setStatus(String s) {
    _status = s;
    // notifyListeners() is called by callers at appropriate cadence
  }

  bool _looksLikeYtDlpProgress(String line) =>
      line.contains('[download]') || line.contains('[ExtractAudio]');

  bool _looksLikeAPath(String line) {
    // Very permissive: we rely on yt-dlp --print to output a path.
    // Windows absolute path (C:\...) or any line ending with .mp3
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.endsWith('.mp3')) return true;
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed);
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }
}
