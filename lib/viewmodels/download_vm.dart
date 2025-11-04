// lib/viewmodels/download_vm.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/audio.dart';
import '../models/playlist.dart';
import '../services/yt_dlp_service.dart';
import '../services/json_data_service.dart';
import '../viewmodels/settings_vm.dart';

// --- Private helper types (file-local) --------------------------------------

class _FlatEntry {
  final String id;
  final String title;
  const _FlatEntry({required this.id, required this.title});
}

class _VideoMeta {
  final String id;
  final String title;
  final String? uploader;
  final String? description;
  final DateTime? uploadDate;
  const _VideoMeta({
    required this.id,
    required this.title,
    this.uploader,
    this.description,
    this.uploadDate,
  });
}

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
    _ytService =
        service; // currently unused for download (direct Process), but kept for future use
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
    final outTpl = path.join(targetDir, '%(title).150s.%(ext)s');

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
      '--print', 'filename', // guaranteed final filename
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

      final subs = <StreamSubscription>[
        stdoutLines.listen((line) {
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

    final settings = _settings;
    if (settings == null) {
      _setStatus('Internal error: SettingsVM not attached.');
      notifyListeners();
      return;
    }

    final yt = settings.ytDlpPath;
    if (yt == null || yt.isEmpty) {
      _setStatus('yt-dlp.exe not found. Use “Refresh binaries” or install it.');
      notifyListeners();
      return;
    }

    final playlistUrl = _loadedPlaylist!.url;
    if (playlistUrl.isEmpty || !playlistUrl.contains('list=')) {
      _setStatus('Invalid playlist URL in JSON.');
      notifyListeners();
      return;
    }

    // Ensure destination directory exists (from the JSON)
    final destDir = _loadedPlaylist!.downloadPath.trim();
    if (destDir.isEmpty) {
      _setStatus('Playlist JSON has empty downloadPath.');
      notifyListeners();
      return;
    }

    // 1) List entries quickly (ids + titles) without resolving streams
    _busy = true;
    _progress = 0.0;
    _setStatus('Reading playlist entries…');
    notifyListeners();

    late final List<_FlatEntry> entries;
    try {
      entries = await _listFlatPlaylistEntries(yt, playlistUrl);
    } catch (e) {
      _busy = false;
      _setStatus('Failed to list playlist: $e');
      notifyListeners();
      return;
    }

    // 2) Build set of already downloaded video IDs from your JSON
    final existingIds = <String>{};
    for (final a in _loadedPlaylist!.downloadedAudioLst) {
      final id = _extractVideoIdFromUrl(a.videoUrl);
      if (id != null) existingIds.add(id);
    }

    // 3) Compute missing items
    final missing = entries.where((e) => !existingIds.contains(e.id)).toList();
    if (missing.isEmpty) {
      _busy = false;
      _progress = 1.0;
      _setStatus('No missing audios. Playlist is up to date.');
      notifyListeners();
      return;
    }

    // Progress: item index + per-item progress
    final total = missing.length;
    final vbr = settings.qualityVbr; // "0".."9"
    final defaultPlaySpeed = settings.defaultPlaySpeed; // double

    // AudioPlayer is used to get the audio duration of the
    // downloaded audio files
    final AudioPlayer audioPlayer = AudioPlayer();

    // 4) Process missing items one by one
    for (int i = 0; i < total; i++) {
      final item = missing[i];
      final videoUrl = 'https://www.youtube.com/watch?v=${item.id}';
      final humanIdx = i + 1;

      // Overall progress = completed items + current item progress
      double perItemProgress = 0.0;
      void updateOverall(double currentPct) {
        perItemProgress = currentPct.clamp(0.0, 1.0);
        _progress = ((i) + perItemProgress) / total;
        notifyListeners();
      }

      _setStatus('[$humanIdx/$total] Fetching metadata…');
      notifyListeners();

      // ---- 4a) metadata
      late final _VideoMeta meta;
      try {
        meta = await _readVideoMeta(yt, videoUrl);
      } catch (e) {
        _setStatus('[$humanIdx/$total] Metadata failed: $e — skipping');
        continue;
      }

      // ---- 4b) Create the Audio FIRST so it defines the final file path
      // Pick the play speed exactly like your app logic
      final double playSpeed =
          defaultPlaySpeed; // from SettingsVM, already computed above

      final audio = Audio(
        youtubeVideoChannel: meta.uploader ?? '',
        enclosingPlaylist: _loadedPlaylist!,
        originalVideoTitle: meta.title,
        compactVideoDescription: _compactDescription(
          meta.description ?? '',
          meta.uploader ?? '',
        ),
        videoUrl: videoUrl,
        audioDownloadDateTime: DateTime.now(),
        videoUploadDate: meta.uploadDate ?? DateTime(1, 1, 1),
        audioDuration:
            Duration.zero, // will be set after download (ffprobe or player)
        audioPlaySpeed: playSpeed,
      );

      // This is your canonical absolute MP3 path (Windows or Android),
      // provided by your model. Ensure its directory exists.
      final String targetMp3Path = audio.filePathName;

      // ---- 4c) Download with yt-dlp to the EXACT target path
      _setStatus('[$humanIdx/$total] Downloading “${audio.validVideoTitle}”…');

      // IMPORTANT: no template, no --print; give the absolute file path.
      final args = <String>[
        '-f', 'bestaudio/best',
        '--extract-audio',
        '--audio-format', 'mp3',
        '--audio-quality', vbr, // "0".."9"
        '-o', targetMp3Path, // <<<<< write exactly where Audio expects
        '--newline',
        '--no-overwrites', // optional safety
        videoUrl,
      ];

      final sw = Stopwatch()..start();
      try {
        final result = await _runYtDlpWithProgress(
          ytExe: yt,
          args: args,
          onPercent: (pct) => updateOverall(pct),
          onStderr: (line) => _setStatus('[$humanIdx/$total] $line'),
          // We do NOT need onFinalPath anymore.
          // We know exactly where the file is: targetMp3Path.
        );

        if (result != 0) {
          _setStatus(
            '[$humanIdx/$total] yt-dlp exited with code $result — skipping',
          );
          continue;
        }
      } catch (e) {
        _setStatus('[$humanIdx/$total] Download failed: $e — skipping');
        continue;
      } finally {
        sw.stop();
      }

      // ---- 4d) Post download: set duration and size, then append to playlist

      // Fallback: estimate duration based on audio player speed settings
      audio.audioDuration = await getMp3DurationWithAudioPlayer(
        audioPlayer: audioPlayer,
        filePathName: audio.filePathName,
      );

      audio.downloadDuration = sw.elapsed;
      audio.fileSize = await File(targetMp3Path).length();

      _loadedPlaylist!.addDownloadedAudio(audio);

      // ---- 4e) Persist JSON to the file the user picked
      try {
        JsonDataService.saveToFile(
          model: _loadedPlaylist!,
          path: _pickedPlaylistJson!, // same playlist JSON selected by the user
        );
      } catch (e) {
        _setStatus('[$humanIdx/$total] JSON save warning: $e');
      }

      // UI footer and progress polish
      _lastOutputPath = targetMp3Path;
      updateOverall(1.0);
      _setStatus('[$humanIdx/$total] Added: ${audio.validVideoTitle}');
    }

    audioPlayer.dispose();

    _busy = false;
    _progress = 1.0;
    _setStatus('Playlist download completed.');
    notifyListeners();
  }

  // ---- helpers -------------------------------------------------------------
  Future<Duration> getMp3DurationWithAudioPlayer({
    required AudioPlayer? audioPlayer,
    required String filePathName,
  }) async {
    Duration? duration;

    // Load audio file into audio player
    await audioPlayer!.setSource(DeviceFileSource(filePathName));

    // Get duration
    duration = await audioPlayer.getDuration();

    return duration ?? Duration.zero;
  }

  Future<List<_FlatEntry>> _listFlatPlaylistEntries(
    String yt,
    String playlistUrl,
  ) async {
    final args = <String>[
      '--dump-single-json', // JSON only (playlist object with entries[])
      '--flat-playlist', // “url” entries (fast, no per-video probe)
      '--no-progress',
      '--no-warnings',
      '--encoding', 'utf-8', // ask yt-dlp to re-encode text to UTF-8
      playlistUrl,
    ];

    final proc = await Process.start(
      yt,
      args,
      runInShell: false, // ✅ prevents cmd.exe interpreting &
      environment: {'PYTHONIOENCODING': 'utf-8'},
    );

    // Buffer raw bytes; do not decode per-line.
    final outBytes = <int>[];
    final errBytes = <int>[];
    final outSub = proc.stdout.listen(outBytes.addAll);
    final errSub = proc.stderr.listen(errBytes.addAll);
    final code = await proc.exitCode;
    await outSub.cancel();
    await errSub.cancel();

    final out = _bestEffortDecode(outBytes);
    if (code != 0) {
      final err = _bestEffortDecode(errBytes);
      throw 'yt-dlp failed ($code): ${err.isEmpty ? out : err}';
    }

    // Remove UTF-8 BOM if present.
    final jsonText = out.startsWith('\uFEFF') ? out.substring(1) : out;

    final root = jsonDecode(jsonText) as Map<String, dynamic>;
    final entries = (root['entries'] as List<dynamic>? ?? const [])
        .map((e) => e as Map<String, dynamic>)
        .where((e) => e['id'] != null)
        .map(
          (e) => _FlatEntry(
            id: (e['id'] as String).trim(),
            title: (e['title'] as String? ?? '').trim(),
          ),
        )
        .toList();

    return entries;
  }

  Future<_VideoMeta> _readVideoMeta(String yt, String url) async {
    final args = <String>[
      '-J', // dump JSON for this URL
      '--no-progress',
      '--no-warnings',
      '--encoding', 'utf-8',
      url,
    ];

    final proc = await Process.start(
      yt,
      args,
      runInShell: false, // ✅ prevents cmd.exe interpreting &
      environment: {'PYTHONIOENCODING': 'utf-8'},
    );

    final outBytes = <int>[];
    final errBytes = <int>[];
    final outSub = proc.stdout.listen(outBytes.addAll);
    final errSub = proc.stderr.listen(errBytes.addAll);
    final code = await proc.exitCode;
    await outSub.cancel();
    await errSub.cancel();

    final out = _bestEffortDecode(outBytes);
    if (code != 0) {
      final err = _bestEffortDecode(errBytes);
      throw 'yt-dlp -J failed ($code): ${err.isEmpty ? out : err}';
    }

    final jsonText = out.startsWith('\uFEFF') ? out.substring(1) : out;
    final m = jsonDecode(jsonText) as Map<String, dynamic>;

    return _VideoMeta(
      id: (m['id'] as String?) ?? _extractVideoIdFromUrl(url) ?? url,
      title: (m['title'] as String? ?? '').trim(),
      uploader: (m['uploader'] as String? ?? m['channel'] as String?),
      description: m['description'] as String?,
      uploadDate: _parseUploadDate(
        (m['upload_date'] as String?) ?? (m['modified_date'] as String?),
      ),
    );
  }

  DateTime? _parseUploadDate(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    // Common cases first:
    // 1) "YYYYMMDD" (e.g. "20251101")
    final m8 = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s);
    if (m8 != null) {
      final y = int.parse(m8.group(1)!);
      final mo = int.parse(m8.group(2)!);
      final d = int.parse(m8.group(3)!);
      try {
        return DateTime(y, mo, d);
      } catch (_) {
        /* fall through */
      }
    }

    // 2) ISO 8601 "YYYY-MM-DD" (sometimes appears)
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      try {
        return DateTime.parse(s);
      } catch (_) {
        /* fall through */
      }
    }

    // 3) "YYYYMMDDHHmmss" (rare for some extractors) → use date part
    final m14 = RegExp(r'^(\d{4})(\d{2})(\d{2})\d{6}$').firstMatch(s);
    if (m14 != null) {
      final y = int.parse(m14.group(1)!);
      final mo = int.parse(m14.group(2)!);
      final d = int.parse(m14.group(3)!);
      try {
        return DateTime(y, mo, d);
      } catch (_) {
        /* fall through */
      }
    }

    // 4) Fallback: let DateTime.parse try (covers full ISO strings)
    try {
      return DateTime.parse(s);
    } catch (_) {}

    // Unknown/unsupported format
    return null;
  }

  String _bestEffortDecode(List<int> bytes) {
    // Strip UTF-8 BOM if present before decode attempt
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      try {
        return systemEncoding.decode(bytes); // CP-1252 on many Windows setups
      } catch (_) {
        return const Latin1Codec().decode(bytes, allowInvalid: true);
      }
    }
  }

  Future<int> _runYtDlpWithProgress({
    required String ytExe,
    required List<String> args,
    required void Function(double pct) onPercent,
    required void Function(String line) onStderr,
    void Function(String path)? onFinalPath,
    void Function(int bytes)? onExpectedSizeBytes,
  }) async {
    _proc = await Process.start(ytExe, args, runInShell: true);

    final stdoutLines = _proc!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final stderrLines = _proc!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final c1 = stdoutLines.listen((line) {
      // 2) Progress from stdout
      final m = RegExp(r'\[download\]\s+(\d+(?:\.\d+)?)%').firstMatch(line);
      if (m != null) {
        final pct = double.tryParse(m.group(1)!);
        if (pct != null) onPercent(pct / 100.0);
      }

      // 3) Expected size (rarely printed to stdout, but keep it)
      final s = RegExp(
        r'Total file size:\s*([\d\.]+)\s*([KMG]?i?B)',
      ).firstMatch(line);
      if (s != null) {
        final num = double.tryParse(s.group(1)!);
        final unit = s.group(2)!;
        if (num != null) onExpectedSizeBytes?.call(_toBytes(num, unit));
      }
    });

    final c2 = stderrLines.listen((line) {
      onStderr(line);

      // 4) Also try to capture final path from stderr messages:
      //    [ExtractAudio] Destination: C:\...\file.mp3
      //    [Merger] Merging formats into "C:\...\file.mp3"
      final m1 = RegExp(
        r'\[ExtractAudio\]\s+Destination:\s(.+\.mp3)\s*$',
      ).firstMatch(line);
      if (m1 != null) {
        onFinalPath?.call(m1.group(1)!.trim().replaceAll('"', ''));
        return;
      }
      final m2 = RegExp(
        r'\[Merger\]\s+Merging formats into\s+"?(.+\.mp3)"?\s*$',
      ).firstMatch(line);
      if (m2 != null) {
        onFinalPath?.call(m2.group(1)!.trim().replaceAll('"', ''));
        return;
      }
    });

    final code = await _proc!.exitCode;
    await c1.cancel();
    await c2.cancel();
    _proc = null;
    return code;
  }

  int _toBytes(double n, String unit) {
    switch (unit) {
      case 'KiB':
        return (n * 1024).round();
      case 'MiB':
        return (n * 1024 * 1024).round();
      case 'GiB':
        return (n * 1024 * 1024 * 1024).round();
      case 'KB':
        return (n * 1000).round();
      case 'MB':
        return (n * 1000 * 1000).round();
      case 'GB':
        return (n * 1000 * 1000 * 1000).round();
      default:
        return n.round();
    }
  }

  String? _extractVideoIdFromUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return null;
    final v = u.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    // also handle youtu.be/<id>
    final segs = u.pathSegments;
    if (u.host.contains('youtu.be') && segs.isNotEmpty) return segs.last;
    return null;
  }

  String _compactDescription(String description, String author) {
    final lines = description.split('\n');
    final first3 = lines.take(3).join('\n');
    return (first3.trim().isEmpty) ? author : '$author\n\n$first3 ...';
  }

  // ---------- Helpers ----------
  void _setStatus(String s) {
    _status = s;
    // notifyListeners() is called by callers at appropriate cadence
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }
}
