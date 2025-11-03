// ignore_for_file: avoid_print

import 'dart:io';
import 'package:logger/logger.dart';

import '../constants.dart';

enum CopyOrMoveFileResult {
  copiedOrMoved,
  targetFileAlreadyExists,
  sourceFileNotExist,
  audioNotKeptInSourcePlaylist,
}

class DirUtil {
  static final Logger logger = Logger();

  /// Returns the path of the application directory. If the application directory
  /// does not exist, it is created. The returned path depends on the platform.
  static String getApplicationPath({
    bool isTest = false,
  }) {
    String applicationPath = '';

    if (Platform.isWindows) {
      if (isTest) {
        applicationPath = kApplicationPathWindowsTest;
      } else {
        applicationPath = kApplicationPathWindows;
      }
    } else {
      if (isTest) {
        applicationPath = kApplicationPathAndroidTest;
      } else {
        applicationPath = kApplicationPath;
      }
    }

    // On Android or mobile emulator,/ avoids that the application
    // can not be run after it was installed on the smartphone
    Directory dir = Directory(applicationPath);

    if (!dir.existsSync()) {
      try {
        dir.createSync();
      } catch (e) {
        // Handle the exception, e.g., directory not created
        logger.i('Directory could not be created: $e');
      }
    }

    return applicationPath;
  }

  static String getPlaylistDownloadRootPath({
    bool isTest = false,
  }) {
    String playlistDownloadRootPath = '';

    if (Platform.isWindows) {
      if (isTest) {
        playlistDownloadRootPath = kPlaylistDownloadRootPathWindowsTest;
      } else {
        playlistDownloadRootPath = kPlaylistDownloadRootPathWindows;
      }
    } else {
      if (isTest) {
        playlistDownloadRootPath = kPlaylistDownloadRootPathAndroidTest;
      } else {
        playlistDownloadRootPath = kPlaylistDownloadRootPath;
      }
    }

    // On Android or mobile emulator,/ avoids that the application
    // can not be run after it was installed on the smartphone
    Directory dir = Directory(playlistDownloadRootPath);

    if (!dir.existsSync()) {
      try {
        // now create the playlist dir
        dir.createSync();
      } catch (e) {
        // Handle the exception, e.g., directory not created
        logger.i('Directory could not be created: $e');
      }
    }

    return playlistDownloadRootPath;
  }

  static Future<void> createDirIfNotExist({
    required String pathStr,
  }) async {
    final Directory directory = Directory(pathStr);
    bool directoryExists = await directory.exists();

    if (!directoryExists) {
      await directory.create(recursive: true);
    }
  }

  /// Delete the directory {pathStr}, the files it contains and
  /// its subdirectories.
  static void deleteDirAndSubDirsIfExist({
    required String rootPath,
  }) {
    final Directory directory = Directory(rootPath);

    if (directory.existsSync()) {
      try {
        directory.deleteSync(recursive: true);
      } catch (e) {
        logger.i("Error occurred while deleting directory: $e");
      }
    } else {
      logger.i("Directory does not exist.");
    }
  }

  static List<String> getPlaylistPathFileNamesLst({
    required String baseDir,
  }) {
    final playlistsDir = Directory(baseDir);
    final List<String> jsonPathFileNamesLst = [];

    // Check if the directory exists
    if (!playlistsDir.existsSync()) {
      logger.i('Error: Directory $baseDir does not exist.');
      return jsonPathFileNamesLst;
    }

    // Get all subdirectories in the playlists directory
    for (final entity in playlistsDir.listSync()) {
      if (entity is Directory) {
        // For each subdirectory, look for JSON files
        for (final file in entity.listSync()) {
          if (file is File &&
              file.path.endsWith('.json') &&
              !file.path.endsWith('settings.json')) {
            jsonPathFileNamesLst.add(file.path);
          }
        }
      }
    }

    return jsonPathFileNamesLst;
  }

  /// Function to save a string to a text file
  static void saveStringToFile({
    required String pathFileName,
    required String content,
  }) {
    File file = File(pathFileName);

    // Write the content to the file
    file.writeAsStringSync(content);
  }

  /// Function to read a string from a text file
  static String readStringFromFile({
    required String pathFileName,
  }) {
    File file = File(pathFileName);

    // Read the content of the file
    return file.readAsStringSync();
  }
}
