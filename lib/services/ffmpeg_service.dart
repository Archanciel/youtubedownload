import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';

class FfmpegService {
  final String targetDir;

  FfmpegService(this.targetDir);

  Future<String> updateFfmpeg() async {
    const url = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip';
    final tmpZip = File('$targetDir/ffmpeg_temp.zip');

    // 1. Download the ZIP
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw 'Failed to download FFmpeg (HTTP ${resp.statusCode})';
    }
    await tmpZip.writeAsBytes(resp.bodyBytes);

    // 2. Decode the archive
    final bytes = await tmpZip.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 3. Extract only ffmpeg.exe
    String? extracted;
    for (final file in archive) {
      if (file.isFile && file.name.endsWith('ffmpeg.exe')) {
        final outPath = '$targetDir/ffmpeg.exe';
        final outFile = File(outPath)..createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
        extracted = outPath;
        break;
      }
    }

    await tmpZip.delete();

    if (extracted == null) throw 'ffmpeg.exe not found in ZIP archive';
    return extracted;
  }
}
