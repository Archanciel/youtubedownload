import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/settings_repository.dart';
import 'services/yt_dlp_service.dart';
import 'viewmodels/settings_vm.dart';
import 'viewmodels/download_vm.dart';
import 'views/home_page.dart';

class YtAudioDownloaderApp extends StatelessWidget {
  const YtAudioDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SettingsRepository>(create: (_) => SettingsRepository()),
        Provider<YtDlpService>(create: (_) => YtDlpService()),
        ChangeNotifierProxyProvider2<SettingsRepository, YtDlpService, SettingsVM>(
          create: (_) => SettingsVM(),
          update: (_, repo, service, vm) => vm!..attach(repo, service),
        ),
        ChangeNotifierProxyProvider2<SettingsVM, YtDlpService, DownloadVM>(
          create: (_) => DownloadVM(),
          update: (_, settingsVM, service, vm) => vm!..attach(settingsVM, service),
        ),
      ],
      child: MaterialApp(
        title: 'YouTube Audio Downloader',
        theme: ThemeData(colorSchemeSeed: Colors.blueGrey, useMaterial3: true),
        home: const HomePage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
