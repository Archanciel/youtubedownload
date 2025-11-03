import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';

/// Downloads and updates ffmpeg.exe in a writable directory on Windows.
/// Default source: gyan.dev "release essentials" build (stable).
class FfmpegService {
  /// Where ffmpeg.exe should finally live, e.g. "C:\\YtDlp"
  final String targetDir;

  /// Optional override for the download URL (stable release).
  final String zipUrl;

  FfmpegService({
    required this.targetDir,
    this.zipUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip',
  });

  /// Downloads ZIP, extracts ffmpeg.exe, overwrites targetDir\\ffmpeg.exe.
  /// Returns the absolute path to the updated ffmpeg.exe.
  ///
  /// Throws a String on failure with a human-readable message.
  Future<String> updateFfmpeg({void Function(String msg)? onLog}) async {
    onLog?.call('Downloading latest FFmpeg ZIP…');
    final tmpZip = File('$targetDir\\ffmpeg_temp.zip');
    try {
      final resp = await http.get(Uri.parse(zipUrl));
      if (resp.statusCode != 200) {
        throw 'Failed to download FFmpeg (HTTP ${resp.statusCode}).';
      }
      await tmpZip.create(recursive: true);
      await tmpZip.writeAsBytes(resp.bodyBytes);

      onLog?.call('Unpacking ZIP…');
      final archive = ZipDecoder().decodeBytes(await tmpZip.readAsBytes());

      String? extractedPath;
      for (final file in archive) {
        if (!file.isFile) continue;
        // Most builds contain ffmpeg.exe under "ffmpeg-*/bin/ffmpeg.exe"
        if (file.name.toLowerCase().endsWith('bin/ffmpeg.exe') ||
            file.name.toLowerCase().endsWith('bin\\ffmpeg.exe') ||
            file.name.toLowerCase().endsWith('ffmpeg.exe')) {
          final outPath = '$targetDir\\ffmpeg.exe';
          final outFile = File(outPath)..createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
          extractedPath = outPath;
          break;
        }
      }

      if (extractedPath == null) {
        throw 'ffmpeg.exe not found in ZIP archive.';
      }

      onLog?.call('FFmpeg updated: $extractedPath');
      return extractedPath;
    } on SocketException {
      throw 'Network error while downloading FFmpeg.';
    } on FileSystemException catch (e) {
      throw 'File system error: ${e.message}';
    } finally {
      // Best-effort cleanup
      try { if (await tmpZip.exists()) await tmpZip.delete(); } catch (_) {}
    }
  }
}
