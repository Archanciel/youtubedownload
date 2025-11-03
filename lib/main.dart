import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_size/window_size.dart';
import 'app.dart';

void main() {
  _setDesktopWindow();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YtAudioDownloaderApp());
}

Future<void> _setDesktopWindow() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final screens = await getScreenList();
    if (screens.isNotEmpty) {
      final screen = screens.first;
      final rect = screen.visibleFrame;

      const double windowHeight = 1100;
      final double windowWidth = 1100;
      final double posX = rect.right - windowWidth + 10;
      final double posY = (rect.height - windowHeight) / 2;

      setWindowFrame(Rect.fromLTWH(posX, posY, windowWidth, windowHeight));
      setWindowMinSize(const Size(600, 360));
    }
  }
}
