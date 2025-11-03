import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/audio.dart';
import '../models/playlist.dart';
import '../services/json_data_service.dart';
import '../services/settings_data_service.dart';

typedef LineHandler = void Function(String line);

class ProcessRunner {
  Future<(int code, String out, String err)> run(
    String exe,
    List<String> args, {
    String? workingDir,
    LineHandler? onStdoutLine,
    LineHandler? onStderrLine,
  }) async {
    final proc = await Process.start(
      exe,
      args,
      runInShell: true,
      workingDirectory: workingDir,
    );

    final outBuf = StringBuffer();
    final errBuf = StringBuffer();

    final outSub = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) {
      outBuf.writeln(l);
      onStdoutLine?.call(l);
    });

    final errSub = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) {
      errBuf.writeln(l);
      onStderrLine?.call(l);
    });

    final code = await proc.exitCode;
    await outSub.cancel();
    await errSub.cancel();

    return (code, outBuf.toString(), errBuf.toString());
  }
}

class PlaylistSyncService {
  final ProcessRunner runner;
  final SettingsDataService settings;

  /// Absolute path to yt-dlp.exe (or on PATH).
  final String ytDlpExe;

  /// ffprobe executable name/path. If absent, duration falls back to yt-dlp output.
  final String? ffprobeExe;

  /// When playlist.audioPlaySpeed == 0, use this default.
  final double defaultPlaySpeed;

  /// If true, save playlist JSON after each item (safer), else save once at end (faster).
  final bool saveAfterEachItem;

  PlaylistSyncService({
    required this.runner,
    required this.settings,
    required this.ytDlpExe,
    this.ffprobeExe,
    required this.defaultPlaySpeed,
    this.saveAfterEachItem = true,
  });

  // ---------------- PUBLIC API ----------------

  /// Loads a Playlist from JSON using your JsonDataService.
  /// Ensures downloadPath exists.
  Future<Playlist> loadPlaylistFromJson(String jsonPathFileName) async {
    final loaded = JsonDataService.loadFromFile(
      jsonPathFileName: jsonPathFileName,
      type: Playlist,
    ) as Playlist?;

    if (loaded == null) {
      throw StateError('Playlist JSON not found or invalid: $jsonPathFileName');
    }

    if (loaded.downloadPath.isEmpty) {
      // Fallback: create a folder beside JSON named after title
      final dir = p.dirname(jsonPathFileName);
      final folder = (loaded.title.isEmpty ? 'Playlist' : loaded.title);
      loaded.downloadPath = p.join(dir, folder);
    }

    await Directory(loaded.downloadPath).create(recursive: true);
    return loaded;
  }

  /// Persists playlist JSON using your JsonDataService.
  Future<void> savePlaylistToJson(Playlist playlist) async {
    final path = playlist.getPlaylistDownloadFilePathName();
    JsonDataService.saveToFile(model: playlist, path: path);
  }

  /// Downloads only missing audios of [playlist.url], creates `Audio` objects
  /// with your exact rules, appends them to the lists and saves JSON.
  ///
  /// [qualityVbrOverride] lets you force a VBR (e.g., "0", "4", "7", "9").
  /// If null, the value is chosen from PlaylistQuality (music => "0", voice => "7").
  Future<void> downloadMissingAudios({
    required String playlistJsonPathFileName,
    required Playlist playlist,
    String? qualityVbrOverride,
    void Function(String msg)? onStatus,
    void Function(double pct)? onProgress,
    void Function(int cur, int tot)? onItemIndex,
  }) async {
    onStatus?.call('Listing playlist entries…');
    final entries = await _listPlaylistEntries(playlist.url);

    // Your logic dedupes by originalVideoTitle in the JSON.
    final alreadyByTitle = playlist.downloadedAudioLst
        .map((a) => a.originalVideoTitle.trim())
        .toSet();

    final missing = <_Entry>[];
    for (final e in entries) {
      final t = e.title.trim();
      if (t.isEmpty) continue;
      if (!alreadyByTitle.contains(t)) missing.add(e);
    }

    if (missing.isEmpty) {
      onStatus?.call('No missing items. Playlist is up to date.');
      onProgress?.call(1.0);
      return;
    }

    final useVbr = qualityVbrOverride ??
        (playlist.playlistQuality == PlaylistQuality.music ? '0' : '9');

    onStatus?.call('Downloading ${missing.length} audio(s)…');
    int idx = 0;

    for (final e in missing) {
      idx++;
      onItemIndex?.call(idx, missing.length);
      onProgress?.call((idx - 1) / missing.length);

      // Enrich metadata for accurate fields
      final meta = await _getVideoMetadata(e.webpageUrl);

      final now = DateTime.now();
      final uploadDate = _parseUploadDate(meta.uploadDate) ?? DateTime(0, 1, 1);

      final originalTitle = (meta.title.isNotEmpty ? meta.title : e.title);
      final validTitle = Audio.createValidVideoTitle(originalTitle);

      final fileName =
          '${Audio.buildDownloadDatePrefix(now)}$validTitle ${Audio.buildUploadDateSuffix(uploadDate)}.mp3';
      final outFullPath = p.join(playlist.downloadPath, fileName);

      await Directory(playlist.downloadPath).create(recursive: true);

      final playSpeed =
          (playlist.audioPlaySpeed != 0) ? playlist.audioPlaySpeed : defaultPlaySpeed;

      final compactDesc = _makeCompactDescription(
        fullDescription: meta.description,
        author: meta.uploader,
      );

      // Build Audio with your constructor (filename is already derived the same way)
      final audio = Audio(
        youtubeVideoChannel: meta.uploader,
        enclosingPlaylist: playlist,
        originalVideoTitle: originalTitle,
        compactVideoDescription: compactDesc,
        videoUrl: meta.webpageUrl,
        audioDownloadDateTime: now,
        videoUploadDate: uploadDate,
        audioDuration: Duration.zero,
        audioPlaySpeed: playSpeed,
      );

      // Music quality flag & speed
      if (playlist.playlistQuality == PlaylistQuality.music) {
        audio.setAudioToMusicQuality(); // sets speed = 1.0 and flag
      }

      // Keep filenames strictly identical to your logic
      audio.audioFileName = fileName;

      onStatus?.call('Downloading “$originalTitle” → MP3 (VBR $useVbr)…');

      final elapsed = await _ytDlpDownloadToMp3(
        url: meta.webpageUrl,
        outFullPath: outFullPath,
        qualityVbr: useVbr,
        onLog: (s) => onStatus?.call(s),
      );

      // Size
      final f = File(outFullPath);
      if (!await f.exists()) {
        onStatus?.call('Failed: output file not found (skipped).');
        continue;
      }
      final size = await f.length();
      audio.audioFileSize = size;

      // Duration (prefer ffprobe; fallback to yt-dlp duration field)
      Duration duration = Duration.zero;
      if (ffprobeExe != null && ffprobeExe!.isNotEmpty) {
        duration = await _probeDurationWithFfprobe(outFullPath);
      }
      if (duration == Duration.zero) {
        // fallback to metadata if ffprobe not available or failed
        final seconds = double.tryParse(meta.durationSec ?? '');
        if (seconds != null && seconds > 0) {
          duration = Duration(milliseconds: (seconds * 1000).round());
        }
      }
      audio.audioDuration = duration;

      // Download duration + computed speed (use your setters)
      audio.downloadDuration = elapsed;
      audio.fileSize = size;

      // Append to lists and persist
      playlist.addDownloadedAudio(audio);

      if (saveAfterEachItem) {
        JsonDataService.saveToFile(
          model: playlist,
          path: playlist.getPlaylistDownloadFilePathName(),
        );
      }

      onStatus?.call('Saved: ${audio.audioFileName}');
      onProgress?.call(idx / missing.length);
    }

    if (!saveAfterEachItem) {
      await savePlaylistToJson(playlist);
    }

    onStatus?.call('Playlist download finished.');
    onProgress?.call(1.0);
  }

  // ---------------- Internals ----------------

  Duration _lastElapsed = Duration.zero;

  Future<Duration> _ytDlpDownloadToMp3({
    required String url,
    required String outFullPath,
    required String qualityVbr,
    required void Function(String msg) onLog,
  }) async {
    // Pass exact full path as output; we don’t rely on templates.
    final args = <String>[
      '-f', 'bestaudio/best',
      '--extract-audio',
      '--audio-format', 'mp3',
      '--audio-quality', qualityVbr, // '0'..'9'
      '-o', outFullPath,
      '--newline',
      url,
    ];

    final sw = Stopwatch()..start();
    final (code, out, err) = await runner.run(
      ytDlpExe,
      args,
      onStdoutLine: (l) {
        if (l.contains('[download]')) onLog(l);
        if (l.contains('[ExtractAudio]') || l.contains('[ffmpeg]')) onLog(l);
      },
      onStderrLine: (l) => onLog(l),
    );
    sw.stop();
    _lastElapsed = sw.elapsed;

    if (code == 0) return _lastElapsed;

    // Accept “has already been downloaded” (shouldn’t happen with fixed name, but harmless).
    if (out.contains('has already been downloaded')) return _lastElapsed;

    onLog('yt-dlp failed (code $code): $err');
    return _lastElapsed;
  }

  Future<Duration> _probeDurationWithFfprobe(String filePath) async {
    try {
      final (code, out, _) = await runner.run(ffprobeExe!, [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        filePath,
      ]);
      if (code == 0) {
        final s = double.tryParse(out.trim());
        if (s != null && s > 0) {
          return Duration(milliseconds: (s * 1000).round());
        }
      }
    } catch (_) {}
    return Duration.zero;
  }

  Future<List<_Entry>> _listPlaylistEntries(String playlistUrl) async {
    // Flat listing: id, title, webpage_url (fast)
    final (code, out, err) = await runner.run(ytDlpExe, [
      '--flat-playlist',
      '--print', '%(id)s\t%(title)s\t%(webpage_url)s',
      playlistUrl,
    ]);
    if (code != 0) {
      throw Exception('yt-dlp listing failed: $err');
    }
    final entries = <_Entry>[];
    for (final line in out.split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      entries.add(_Entry(id: parts[0], title: parts[1], webpageUrl: parts[2]));
    }
    return entries;
  }

  Future<_Meta> _getVideoMetadata(String url) async {
    // Ask yt-dlp for a few fields; duration is helpful if ffprobe is missing.
    final (code, out, err) = await runner.run(ytDlpExe, [
      '--print', '%(title)s',
      '--print', '%(uploader)s',
      '--print', '%(upload_date)s',
      '--print', '%(duration)s',     // seconds, may be empty
      '--print', '%(description)s',
      '--print', '%(webpage_url)s',
      url,
    ]);

    if (code != 0) {
      return _Meta(
        title: '',
        uploader: '',
        uploadDate: '',
        durationSec: '',
        description: '',
        webpageUrl: url,
      );
    }

    final lines = out.split('\n');
    String take(int i) => (i >= 0 && i < lines.length) ? lines[i].trimRight() : '';

    // description may be multi-line; we conservatively stitch everything between idx 4..(n-2)
    // Layout:
    //   0 title
    //   1 uploader
    //   2 upload_date
    //   3 duration_sec
    //   4..n-2 description (maybe multi-line)
    //   n-1 webpage_url
    if (lines.length < 5) {
      return _Meta(
        title: take(0),
        uploader: take(1),
        uploadDate: take(2),
        durationSec: take(3),
        description: '',
        webpageUrl: take(lines.length - 1),
      );
    }

    final web = lines.last.trimRight();
    final descLines = lines.sublist(4, lines.length - 1);
    final desc = descLines.join('\n');

    return _Meta(
      title: take(0),
      uploader: take(1),
      uploadDate: take(2),
      durationSec: take(3),
      description: desc,
      webpageUrl: web.isEmpty ? url : web,
    );
  }

  DateTime? _parseUploadDate(String yyyymmdd) {
    if (yyyymmdd.length != 8) return null;
    final y = int.tryParse(yyyymmdd.substring(0, 4));
    final m = int.tryParse(yyyymmdd.substring(4, 6));
    final d = int.tryParse(yyyymmdd.substring(6, 8));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  String _makeCompactDescription({
    required String fullDescription,
    required String author,
  }) {
    // Port of your logic: first 3 lines + proper-name pairs (very close to your implementation)
    final lines = fullDescription.split('\n');
    final first3 = lines.take(3).join('\n');
    final rest = lines.length > 3 ? lines.sublist(3).join('\n') : '';

    // Remove timestamp lines like "12:34 Something"
    final cleaned = rest.replaceAll(
      RegExp(r'^\d{1,2}:\d{2} .+\n', multiLine: true),
      '',
    );

    final words = cleaned.split(RegExp(r'[ \n]'));
    final properPairs = <String>[];
    for (int i = 0; i + 1 < words.length; i++) {
      final a = words[i];
      final b = words[i + 1];
      bool isCap(String s) =>
          s.isNotEmpty &&
          RegExp(r'[A-ZÀ-ÿ]').hasMatch(s[0]) &&
          RegExp(r'\D').hasMatch(s[0]);
      if (isCap(a) && isCap(b)) {
        properPairs.add('$a $b');
        i++;
      }
    }

    if (properPairs.isEmpty) {
      return '$author\n\n$first3 ...';
    }
    return '$author\n\n$first3 ...\n\n${properPairs.join(', ')}';
  }
}

class _Entry {
  final String id;
  final String title;
  final String webpageUrl;
  _Entry({required this.id, required this.title, required this.webpageUrl});
}

class _Meta {
  final String title;
  final String uploader;
  final String uploadDate;   // yyyymmdd or ''
  final String? durationSec; // seconds or ''
  final String description;
  final String webpageUrl;
  _Meta({
    required this.title,
    required this.uploader,
    required this.uploadDate,
    required this.durationSec,
    required this.description,
    required this.webpageUrl,
  });
}
