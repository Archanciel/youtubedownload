import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Thin service wrapping yt-dlp process handling and cancellation.
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

  /// Starts yt-dlp with the given args.
  /// Calls the provided callbacks on progress/status/destination.
  Future<int> run({
    required String exe,
    required List<String> args,
    void Function(double pct)? onProgress,
    void Function(String status)? onStatus,
    void Function(String path)? onDestination,
  }) async {
    _proc = await Process.start(exe, args, runInShell: true);

    final subs = <StreamSubscription>[];

    final stdoutLines = _proc!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final stderrLines = _proc!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    subs.add(stdoutLines.listen((line) {
      // Progress like: [download]  37.4% ...
      final m =
          RegExp(r'\[download\]\s+(\d+(?:\.\d+)?)%').firstMatch(line);
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
}
