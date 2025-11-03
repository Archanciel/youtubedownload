import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/audio_quality.dart';
import '../viewmodels/settings_vm.dart';
import '../viewmodels/download_vm.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsVM>();
    final dl = context.watch<DownloadVM>();

    final canDownload =
        !dl.busy &&
        settings.targetDir != 'No target folder chosen' &&
        dl.urlController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('YouTube Audio Downloader (Windows)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // URL + Paste
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: dl.urlController,
                    decoration: const InputDecoration(
                      labelText: 'YouTube URL (video or playlist)',
                      hintText:
                          'https://www.youtube.com/watch?v=...  or playlist URL',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {}, // no need to notify here
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Paste from clipboard',
                  onPressed: dl.busy ? null : dl.pasteFromClipboard,
                  icon: const Icon(Icons.paste),
                ),
              ],
            ),

            const SizedBox(height: 12),
            // JSON picker row
            Row(
              children: [
                Expanded(
                  child: Text(
                    dl.pickedPlaylistJson ?? '(no playlist JSON selected)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: dl.busy ? null : dl.pickPlaylistJson,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Select Playlist JSON'),
                ),
              ],
            ),

            if (dl.loadedPlaylist != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Playlist: ${dl.loadedPlaylist!.title} • Downloaded: ${dl.loadedPlaylist!.downloadedAudioLst.length}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],

            const SizedBox(height: 8),

            FilledButton.icon(
              onPressed: (dl.busy || dl.loadedPlaylist == null)
                  ? null
                  : dl.downloadMissingFromPickedJson,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Download playlist (missing only)'),
            ),

            const SizedBox(height: 12),

            // Folder picker
            Row(
              children: [
                Expanded(
                  child: Text(
                    settings.targetDir,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: dl.busy ? null : settings.pickDirectory,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose Folder'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Quality selector
            Row(
              children: [
                const Text('MP3 quality:'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: settings.qualityLabel,
                  items: AudioQuality.labels()
                      .map(
                        (label) =>
                            DropdownMenuItem(value: label, child: Text(label)),
                      )
                      .toList(),
                  onChanged: dl.busy
                      ? null
                      : (val) {
                          if (val != null) settings.setQualityLabel(val);
                        },
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Diagnostics: yt-dlp path + version + FFmpeg + Update button
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                settings.ytDlpPath ?? '(yt-dlp not found yet)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                Text('yt-dlp version: ${settings.ytDlpVersion ?? 'unknown'}'),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed:
                      (dl.busy ||
                          settings.updatingYtDlp ||
                          settings.ytDlpPath == null)
                      ? null
                      : () async {
                          final okYt = await settings.updateYtDlp();
                          if (!context.mounted) return;
                          final snack = SnackBar(
                            content: Text(
                              okYt
                                  ? 'yt-dlp update finished.'
                                  : 'yt-dlp update failed.',
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(snack);
                        },
                  icon: settings.updatingYtDlp
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update),
                  label: const Text('Update yt-dlp'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'FFmpeg updated on: ${settings.ffmpegUpdateDate ?? 'unknown'}',
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: (dl.busy || settings.updatingFfmpeg)
                      ? null
                      : () async {
                          final okFF = await settings.updateFfmpeg();
                          if (!context.mounted) return;
                          final snack = SnackBar(
                            content: Text(
                              okFF
                                  ? 'FFmpeg update finished.'
                                  : 'FFmpeg update failed.',
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(snack);
                        },
                  icon: settings.updatingFfmpeg
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update),
                  label: const Text('Update FFmpeg'),
                ),
              ],
            ),
            if (settings.lastUpdateLog != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  settings.lastUpdateLog!,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
            if (settings.ffmpegUpdateLog != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  settings.ffmpegUpdateLog!,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Actions
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: canDownload ? dl.download : null,
                  icon: const Icon(Icons.download),
                  label: const Text('Download audio'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: dl.busy ? dl.cancel : null,
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: dl.busy
                      ? null
                      : () async {
                          await settings.refreshBinaryAvailability();
                          final snack = SnackBar(
                            content: Text('Tools information refreshed.'),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(snack);
                          }
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh binaries'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Progress + status
            if (dl.busy || dl.progress > 0) ...[
              LinearProgressIndicator(value: dl.progress.clamp(0.0, 1.0)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  dl.busy
                      ? 'Progress: ${(dl.progress * 100).toStringAsFixed(1)} %'
                      : dl.status,
                ),
              ),
            ] else
              Align(alignment: Alignment.centerLeft, child: Text(dl.status)),

            const SizedBox(height: 8),

            // Final path + open folder
            if (dl.lastOutputPath != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Saved to: ${dl.lastOutputPath!}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    try {
                      final dir = File(dl.lastOutputPath!).parent.path;
                      if (Platform.isWindows) {
                        Process.run('explorer', [dir]);
                      } else if (Platform.isMacOS) {
                        Process.run('open', [dir]);
                      } else if (Platform.isLinux) {
                        Process.run('xdg-open', [dir]);
                      }
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.folder),
                  label: const Text('Open folder'),
                ),
              ),
            ],

            const Spacer(),
            const Divider(),
            const Text(
              'MVVM: SettingsVM + DownloadVM • Service: YtDlpService • Repo: SharedPreferences\n'
              'Self-update: yt-dlp -U (shows log & version). No YouTube API key required.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
