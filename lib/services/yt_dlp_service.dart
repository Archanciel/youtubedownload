import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Thin service wrapping yt-dlp process handling, progress parsing, and cancellation.
class YtDlpService {
  Process? _proc;

  bool get isRunning => _proc != null;

  Future<void> killIfRunning() async {
    final p = _proc;
    _proc = null;
    if (p == null) return;

    try {
      // Try graceful
      p.kill(ProcessSignal.sigint);
      await Future.delayed(const Duration(milliseconds: 250));

      // Force kill (Windows-friendly)
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', p.pid.toString(), '/T', '/F']);
      } else {
        p.kill(ProcessSignal.sigkill);
      }
    } catch (_) {
      // ignore
    }
  }

  /// Generic runner with progress/status/destination callbacks (for downloads).
  Future<int> run({
    required String exe,
    required List<String> args,
    void Function(double pct)? onProgress,
    void Function(String status)? onStatus,
    void Function(String path)? onDestination,
  }) async {
    _proc = await Process.start(exe, args, runInShell: true);

    final subs = <StreamSubscription>[];

    final stdoutLines =
        _proc!.stdout.transform(utf8.decoder).transform(const LineSplitter());
    final stderrLines =
        _proc!.stderr.transform(utf8.decoder).transform(const LineSplitter());

    subs.add(stdoutLines.listen((line) {
      // Progress like: [download]  37.4% ...
      final m = RegExp(r'\[download\]\s+(\d+(?:\.\d+)?)%').firstMatch(line);
      if (m != null && onProgress != null) {
        final pct = double.tryParse(m.group(1)!);
        if (pct != null) onProgress(pct / 100.0);
      }

      // Destination capture
      final destMatch = RegExp(r'Destination:\s(.+)$').firstMatch(line);
      if (destMatch != null && onDestination != null) {
        onDestination(destMatch.group(1)!);
      }

      // Post-processing stage
      if ((line.contains('[ExtractAudio]') || line.contains('[ffmpeg]')) &&
          onStatus != null) {
        onStatus('Converting to MP3…');
      }

      if (line.contains('has already been downloaded')) {
        if (onProgress != null) onProgress(1.0);
        if (onStatus != null) {
          onStatus('File already present; verifying/processing…');
        }
      }
    }));

    subs.add(stderrLines.listen((line) {
      if (onStatus != null) onStatus(line);
    }));

    final code = await _proc!.exitCode;

    for (final s in subs) {
      await s.cancel();
    }
    _proc = null;

    return code;
  }

  /// Returns the output of `yt-dlp --version` (e.g., "2025.10.12").
  /// Throws if the process fails.
  Future<String> getVersion(String exe) async {
    final res = await Process.run(exe, ['--version'], runInShell: true);
    if (res.exitCode == 0) {
      return (res.stdout as String).trim();
    }
    throw 'Failed to read yt-dlp version (exit ${res.exitCode}).';
  }

  /// Runs `yt-dlp -U` self-update. Returns the *full* console log (stdout+stderr)
  /// so the caller can display a meaningful message to the user.
  ///
  /// Exit code 0 means success, 1 often means "already up to date",
  /// but we rely on parsing the output text to decide what to display.
  Future<(int code, String log)> selfUpdate(String exe) async {
    final proc = await Process.start(exe, ['-U'], runInShell: true);

    final buffer = StringBuffer();
    final subs = <StreamSubscription>[];

    subs.add(proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => buffer.writeln(line)));

    subs.add(proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => buffer.writeln(line)));

    final code = await proc.exitCode;
    for (final s in subs) {
      await s.cancel();
    }
    return (code, buffer.toString());
  }
}
