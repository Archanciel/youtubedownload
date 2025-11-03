// lib/viewmodels/audio_download_vm.dart

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:logger/logger.dart';

// importing youtube_explode_dart as yt enables to name the app Model
// playlist class as Playlist so it does not conflict with
// youtube_explode_dart Playlist class name.
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../constants.dart';
import '../services/settings_data_service.dart';
import '../services/json_data_service.dart';
import '../models/audio.dart';
import '../models/playlist.dart';
import '../utils/dir_util.dart';

// global variables used by the AudioDownloadVM in order
// to avoid multiple downloads of the same playlist
List<String> downloadingPlaylistUrls = [];

/// This VM (View Model) class is part of the MVVM architecture.
/// It was posted on Github on 12-04-2023.
///
/// It is responsible of connecting to Youtube in order to download
/// the audio of the videos referenced in the Youtube playlists.
/// It can also download the audio of a single video.
///
/// It is also responsible of creating and deleting application
/// Playlist's, either Youtube app Playlist's or local app
/// Playlist's.
///
/// Another responsibility of this class is to move or copy
/// audio files from one Playlist to another as well as to
/// rename or delete audio files or update their playing
/// speed.
class AudioDownloadVM extends ChangeNotifier {
  static final Logger logger = Logger();

  List<Playlist> _listOfPlaylist = [];
  List<Playlist> get listOfPlaylist => _listOfPlaylist;

  yt.YoutubeExplode? _youtubeExplode;
  // setter used by test only !
  set youtubeExplode(yt.YoutubeExplode youtubeExplode) =>
      _youtubeExplode = youtubeExplode;

  late String _playlistsRootPath;

  // used when updating the playlists root path using the
  // playlist download view left appbar 'Application Settings ...'
  // menu item.
  set playlistsRootPath(String playlistsRootPath) =>
      _playlistsRootPath = playlistsRootPath;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  int _lastSecondDownloadSpeed = 0;
  int get lastSecondDownloadSpeed => _lastSecondDownloadSpeed;

  late Audio _currentDownloadingAudio;
  Audio get currentDownloadingAudio => _currentDownloadingAudio;

  bool isHighQuality = false;

  bool _stopDownloadPressed = false;
  // ignore: unnecessary_getters_setters
  bool get isDownloadStopping => _stopDownloadPressed;

  // setter used by MockAudioDownloadVM in integration test only !
  set isDownloadStopping(bool isDownloadStopping) =>
      _stopDownloadPressed = isDownloadStopping;

  bool _audioDownloadError = false;
  bool get audioDownloadError => _audioDownloadError;

  final SettingsDataService _settingsDataService;

  /// Passing true for {isTest} has the effect that the windows
  /// test directory is used as playlist root directory. This
  /// directory is located in the test directory of the project.
  ///
  /// Otherwise, the windows or smartphone audio root directory
  /// is used.
  AudioDownloadVM({required SettingsDataService settingsDataService})
    : _settingsDataService = settingsDataService {
    _playlistsRootPath = _settingsDataService.get(
      settingType: SettingType.dataLocation,
      settingSubType: DataLocation.playlistRootPath,
    );

    loadExistingPlaylists();
  }

  /// This method is used by ConvertTextToAudioDialog in order to update the
  /// playlist download view playlist audio list so that the audio added by
  /// the text to speech conversion is immediately visible in its playlist.
  ///
  /// This method is necessary since the AudioDownloadVM.importAudioFilesInPlaylist
  /// method does not call notifyListeners() if the audio files are imported
  /// from text to speech conversion.
  void doNotifyListeners() {
    notifyListeners();
  }

  /// [restoringPlaylistsCommentsAndSettingsJsonFilesFromZip] is true if the
  /// method is called in order to restore the playlists, comments and settings
  /// json files from a zip file. In this case, the playlists root path is
  /// updated if necessary.
  void loadExistingPlaylists({
    List<Playlist> initialListOfPlaylist = const [],
    bool restoringPlaylistsCommentsAndSettingsJsonFilesFromZip = false,
  }) {
    // reinitializing the list of playlist is necessary since
    // loadExistingPlaylists() is also called by PlaylistListVM.
    // updateSettingsAndPlaylistJsonFiles() method.
    _listOfPlaylist = [];

    List<String> playlistPathFileNamesLst = DirUtil.getPlaylistPathFileNamesLst(
      baseDir: _playlistsRootPath,
    );

    bool arePlaylistsRestoredFromAndroidToWindows = false;
    bool arePlaylistsRestoredFromWindowsToAndroid = false;
    String playlistWindowsDownloadRootPath = '';

    try {
      for (String playlistPathFileName in playlistPathFileNamesLst) {
        Playlist currentPlaylist = JsonDataService.loadFromFile(
          jsonPathFileName: playlistPathFileName,
          type: Playlist,
        );

        if (restoringPlaylistsCommentsAndSettingsJsonFilesFromZip) {
          if (!arePlaylistsRestoredFromAndroidToWindows) {
            // If arePlaylistsRestoredFromAndroidToWindows is false,
            // then the playlists root path is the same as the one
            // used on Android. The playlists root path must be
            // updated only if the playlists are restored from Android
            // to Windows.
            arePlaylistsRestoredFromAndroidToWindows =
                _playlistsRootPath.contains('C:\\') &&
                currentPlaylist.downloadPath.contains('/storage/emulated/0');

            arePlaylistsRestoredFromWindowsToAndroid =
                _playlistsRootPath.contains('/storage/emulated/0') &&
                currentPlaylist.downloadPath.contains('C:\\');

            if (arePlaylistsRestoredFromAndroidToWindows) {
              // This test avoids that the playlists root path is
              // determined for each playlist since the playlists
              // root path is the same for all playlists restored
              // from Android.
              List<String> playlistRootPathElementsLst = currentPlaylist
                  .downloadPath
                  .split('/');

              // This name may have been changed by the user on Android
              // using the 'Application Settings ...' menu.
              String androidAppPlaylistDirName =
                  playlistRootPathElementsLst[playlistRootPathElementsLst
                          .length -
                      2];

              _playlistsRootPath =
                  "$kApplicationPathWindowsTest${path.separator}$androidAppPlaylistDirName";
              _settingsDataService.set(
                settingType: SettingType.dataLocation,
                settingSubType: DataLocation.playlistRootPath,
                value: _playlistsRootPath,
              );

              _settingsDataService.saveSettings();

              playlistWindowsDownloadRootPath =
                  "$_playlistsRootPath${path.separator}";
            }
          }

          _updatePlaylistRootPathIfNecessary(
            playlist: currentPlaylist,
            isPlaylistRestoredFromAndroidToWindows:
                arePlaylistsRestoredFromAndroidToWindows,
            isPlaylistRestoredFromWindowsToAndroid:
                arePlaylistsRestoredFromWindowsToAndroid,
            playlistWindowsDownloadRootPath: playlistWindowsDownloadRootPath,
          );
        }

        _listOfPlaylist.add(currentPlaylist);

        // if the playlist is selected, the audio quality checkbox will be
        // checked or not according to the selected playlist quality
        updatePlaylistAudioQuality(playlist: currentPlaylist);
      }
    } catch (e) {
      logger.e('Load error ${e.toString()}');
    }

    // notifyListeners();  not necessary since the unique
    //                     Consumer<AudioDownloadVM> is not concerned
    //                     by the _listOfPlaylist changes
  }

  /// This method is called when the user change a playlist audio quality
  /// as well when the application is launched.
  void updatePlaylistAudioQuality({required Playlist playlist}) {
    if (playlist.isSelected) {
      isHighQuality = playlist.playlistQuality == PlaylistQuality.music;

      // Necessary in order to update the playlist quality
      // checkbox in the playlist download view.
      notifyListeners();
    }
  }

  // This method is only called in the situation of restoring from
  // a zip file.
  void _updatePlaylistRootPathIfNecessary({
    required Playlist playlist,
    required bool isPlaylistRestoredFromAndroidToWindows,
    required bool isPlaylistRestoredFromWindowsToAndroid,
    required String playlistWindowsDownloadRootPath,
  }) {
    if (isPlaylistRestoredFromAndroidToWindows) {
      if (playlist.downloadPath.contains(kPlaylistDownloadRootPath)) {
        playlist.downloadPath = playlist.downloadPath
            .replaceFirst(
              "$kPlaylistDownloadRootPath/",
              playlistWindowsDownloadRootPath,
            )
            .trim(); // trim() is necessary since the path is used in
        //              the JsonDataService.saveToFile constructor and
        //              the path must not contain any trailing spaces
        //              on Windows or Android.
      }
    } else if (isPlaylistRestoredFromWindowsToAndroid) {
      if (playlist.downloadPath.contains(kApplicationPathWindowsTest)) {
        playlist.downloadPath = playlist.downloadPath
            .replaceFirst(kApplicationPathWindowsTest, kApplicationPath)
            .replaceAll('\\', '/')
            .trim(); // trim() is necessary since the path is used in
        //              the JsonDataService.saveToFile constructor and
        //              the path must not contain any trailing spaces
        //              on Windows or Android.
      } else {
        playlist.downloadPath = playlist.downloadPath
            .trim(); // trim() is necessary since the path is used in
        //              the JsonDataService.saveToFile constructor and
        //              the path must not contain any trailing spaces
        //              on Windows or Android.
      }
    }

    JsonDataService.saveToFile(
      model: playlist,
      path: playlist.getPlaylistDownloadFilePathName(),
    );
  }

  Future<Playlist?> addPlaylist({
    String playlistUrl = '',
    String localPlaylistTitle = '',
    required PlaylistQuality playlistQuality,
  }) async {
    return addPlaylistCallableAlsoByMock(
      playlistUrl: playlistUrl,
      localPlaylistTitle: localPlaylistTitle,
      playlistQuality: playlistQuality,
    );
  }

  void deletePlaylist({required Playlist playlistToDelete}) {
    _listOfPlaylist.removeWhere(
      (playlist) => playlist.id == playlistToDelete.id,
    );

    DirUtil.deleteDirAndSubDirsIfExist(rootPath: playlistToDelete.downloadPath);

    notifyListeners();
  }

  /// The MockAudioDownloadVM exists because when
  /// executing integration tests, using YoutubeExplode
  /// to get a Youtube playlist in order to obtain the
  /// playlist title is not possible, the
  /// {mockYoutubePlaylistTitle} is passed to the method if
  /// the method is called by the MockAudioDownloadVM.
  ///
  /// This method has been created in order for the
  /// MockAudioDownloadVM addPlaylist() method to be able
  /// to use the AudioDownloadVM.addPlaylist() logic.
  ///
  /// Additionally, since the method is called by the
  /// AudioDownloadVM, it contains the logic to add a
  /// playlist and so, if this logic is modified, it
  /// will be modified in only one place and will be
  /// applied to the MockAudioDownloadVM as well and so
  /// will be tested by the integration test.
  Future<Playlist?> addPlaylistCallableAlsoByMock({
    String playlistUrl = '',
    String localPlaylistTitle = '',
    required PlaylistQuality playlistQuality,
    String? mockYoutubePlaylistTitle,
  }) async {
    Playlist addedPlaylist;

    // Will contain the Youtube playlist title which will have to be
    // corrected
    String youtubePlaylistTitleToCorrect = '';

    if (localPlaylistTitle.isNotEmpty) {
      // handling creation of a local playlist

      addedPlaylist = Playlist(
        id: localPlaylistTitle, // necessary since the id is used to
        //                         identify the playlist in the list
        //                         of playlist
        title: localPlaylistTitle,
        playlistType: PlaylistType.local,
        playlistQuality: playlistQuality,
      );

      if (playlistQuality == PlaylistQuality.music) {
        addedPlaylist.audioPlaySpeed = 1.0;
      } else {
        addedPlaylist.audioPlaySpeed = _settingsDataService.get(
          settingType: SettingType.playlists,
          settingSubType: Playlists.playSpeed,
        );
      }

      await setPlaylistPath(
        playlistTitle: localPlaylistTitle,
        playlist: addedPlaylist,
      );

      JsonDataService.saveToFile(
        model: addedPlaylist,
        path: addedPlaylist.getPlaylistDownloadFilePathName(),
      );

      // if the local playlist is not added to the list of
      // playlist, then it will not be displayed at the end
      // of the list of playlist in the UI ! This is because
      // ExpandablePlaylistListVM.getUpToDateSelectablePlaylists()
      // obtains the list of playlist from the AudioDownloadVM.
      _listOfPlaylist.add(addedPlaylist);

      logger.i('Local playlist added: $localPlaylistTitle');

      return addedPlaylist;
    } else if (!playlistUrl.contains('list=')) {
      // the case if the url is a video url and the user
      // clicked on the Add button instead of the Download
      // single video audio button or if the String pasted to
      // the url text field is not a valid Youtube playlist url.
      logger.e('invalidPlaylistUrl = $playlistUrl');

      return null;
    } else {
      // handling creation of a Youtube playlist

      // get Youtube playlist
      String? playlistId;
      yt.Playlist youtubePlaylist;

      _youtubeExplode ??= yt.YoutubeExplode();

      playlistId = yt.PlaylistId.parsePlaylistId(playlistUrl);

      if (playlistId == null) {
        // the case if the String pasted to the url text field
        // is not a valid Youtube playlist url.
        logger.e('invalidPlaylistUrl = $playlistUrl');

        return null;
      }

      String playlistTitle;

      if (mockYoutubePlaylistTitle == null) {
        // the method is called by AudioDownloadVM.addPlaylist()
        try {
          youtubePlaylist = await _youtubeExplode!.playlists.get(playlistId);
        } on SocketException catch (e) {
          logger.e('No internet: $e');

          return null;
        } catch (e) {
          logger.e('invalidPlaylistUrl = $playlistUrl');

          return null;
        }

        playlistTitle = youtubePlaylist.title;
      } else {
        // the method is called by MockAudioDownloadVM.addPlaylist()
        playlistTitle = mockYoutubePlaylistTitle;
      }

      if (playlistTitle.contains(',')) {
        // A playlist title containing one or several commas can not
        // be handled by the application due to the fact that when
        // this playlist title will be added in the  playlist ordered
        // title list of the SettingsDataService, since the elements
        // of this list are separated by a comma, the playlist title
        // containing on or more commas will be divided in two or more
        // titles which will then not be findable in the playlist
        // directory. For this reason, adding such a playlist is refused
        // by the method.
        logger.e('invalidYoutubePlaylistTitle = $playlistTitle');

        return null;
      } else if (playlistTitle == '') {
        // The case if the Youtube playlist is private
        logger.e('privatePlaylistAddition = $playlistTitle');

        return null;
      }

      if (playlistTitle.contains('/') ||
          playlistTitle.contains(':') ||
          playlistTitle.contains('\\')) {
        // The case if the Youtube playlist title contains a '/'
        // character. This character is used to separate the
        // directories in a path and so can not be used in a
        // playlist title. For this reason, '/' is replaced by
        // '-' in the playlist title.
        youtubePlaylistTitleToCorrect = playlistTitle;

        playlistTitle = playlistTitle.replaceAll('/', '-');
        playlistTitle = playlistTitle.replaceAll(':', '-');
        playlistTitle = playlistTitle.replaceAll('\\', '-');
      }

      int playlistIndex = _listOfPlaylist.indexWhere(
        (playlist) => playlist.title == playlistTitle,
      );

      if (playlistIndex != -1) {
        // This means that the playlist was not added, but
        // that its url was updated. The case when a new
        // playlist with the same title is created in order
        // to replace the old one which contains too many
        // videos.
        Playlist updatedPlaylist = _updateYoutubePlaylisrUrl(
          playlistIndex: playlistIndex,
          playlistId: playlistId,
          playlistUrl: playlistUrl,
          playlistTitle: playlistTitle,
        );

        // since the updated playlist is returned. Since its title
        // is not new, it will not be added to the orderedTitleLst
        // in the SettingsDataService json file, which would cause
        // a bug when filtering audio's of a playlist
        return updatedPlaylist;
      }

      // Adding the Youtube playlist to the application

      addedPlaylist = await _addYoutubePlaylistIfNotExist(
        playlistUrl: playlistUrl,
        playlistQuality: playlistQuality,
        playlistTitle: playlistTitle,
        playlistId: playlistId,
      );

      JsonDataService.saveToFile(
        model: addedPlaylist,
        path: addedPlaylist.getPlaylistDownloadFilePathName(),
      );
    }

    if (youtubePlaylistTitleToCorrect.isEmpty) {
      logger.e('youtubePlaylistTitleToCorrect is empty');
    } else {
      logger.i('youtubePlaylistTitle correct as ${addedPlaylist.title}');
    }

    return addedPlaylist;
  }

  /// This method handles the case where the user wants to update
  /// the url of a Youtube playlist.
  ///
  /// After having been used a lot by the user, the Youtube playlist
  /// may contain too many videos. Removing manually the already listened
  /// videos from the Youtube playlist takes too much time. Instead, the
  /// too big Youtube playlist is deleted or is renamed and a new Youtube
  /// playlist with the same title is created. The new Youtube playlist is
  /// then added in the application. The method is called by the
  /// AudioDownloadVM.addPlaylistCallableAlsoByMock() method in the case
  /// where the new Youtube playlist has the same title than the deleted
  /// or renamed Youtube playlist. In this case, the existing application
  /// playlist is updated with the new Youtube playlist url and id.
  ///
  /// The updated playlist is returned by the method.
  Playlist _updateYoutubePlaylisrUrl({
    required int playlistIndex,
    required String playlistId,
    required String playlistUrl,
    required String playlistTitle,
  }) {
    Playlist updatedPlaylist = _listOfPlaylist[playlistIndex];
    updatedPlaylist.url = playlistUrl;
    updatedPlaylist.id = playlistId;
    logger.i('updatedPlaylistTitle = $playlistTitle');

    JsonDataService.saveToFile(
      model: updatedPlaylist,
      path: updatedPlaylist.getPlaylistDownloadFilePathName(),
    );

    return updatedPlaylist;
  }

  /// Downloads the audio of the videos referenced in the passed playlist url. If
  /// the audio of a video has already been downloaded, it will not be downloaded
  /// again.
  Future<void> downloadPlaylistAudio({required String playlistUrl}) async {
    // if the playlist is already being downloaded, then
    // the method is not executed. This avoids that the
    // audio of the playlist are downloaded multiple times
    // if the user clicks multiple times on the download
    // playlist text button.
    if (downloadingPlaylistUrls.contains(playlistUrl)) {
      return;
    } else {
      // If another playlist is being downloaded, then the
      // the previously added playlist url is removed from the
      // downloadingPlaylistUrls list. This will enable the user
      // to restart downloading the previously added playlist.
      downloadingPlaylistUrls = [];
      downloadingPlaylistUrls.add(playlistUrl);
    }

    _stopDownloadPressed = false;
    _youtubeExplode ??= yt.YoutubeExplode();

    // get the Youtube playlist
    String? playlistId = yt.PlaylistId.parsePlaylistId(playlistUrl);
    yt.Playlist youtubePlaylist;

    try {
      youtubePlaylist = await _youtubeExplode!.playlists.get(playlistId);
    } on SocketException catch (e) {
      logger.e('No internet: $e');

      // removing the playlist url from the downloadingPlaylistUrls
      // list since the playlist download has failed
      downloadingPlaylistUrls.remove(playlistUrl);

      return;
    } catch (e) {
      logger.e('downloadAudioYoutubeError = ${e.toString()}');

      // removing the playlist url from the downloadingPlaylistUrls
      // list since the playlist download has failed
      downloadingPlaylistUrls.remove(playlistUrl);

      return;
    }

    String playlistTitle = youtubePlaylist.title;

    // Handling the case where the Youtube playlist was deleted or
    // renamed and a new playlist with the same title was created.
    Playlist currentPlaylist;
    int existingPlaylistIndex = _listOfPlaylist.indexWhere(
      (element) => element.url == playlistUrl,
    );

    if (existingPlaylistIndex > -1) {
      currentPlaylist = _listOfPlaylist[existingPlaylistIndex];
    } else {
      currentPlaylist = await _addYoutubePlaylistIfNotExist(
        playlistUrl: playlistUrl,
        playlistQuality: PlaylistQuality.voice,
        playlistTitle: playlistTitle,
        playlistId: playlistId!,
      );
    }

    String downloadedPlaylistFilePathName = currentPlaylist
        .getPlaylistDownloadFilePathName();

    final List<String> downloadedAudioOriginalVideoTitleLst =
        await _getPlaylistDownloadedAudioOriginalVideoTitleLst(
          currentPlaylist: currentPlaylist,
        );

    // AudioPlayer is used to get the audio duration of the
    // downloaded audio files
    final AudioPlayer audioPlayer = AudioPlayer();

    await for (yt.Video youtubeVideo in _youtubeExplode!.playlists.getVideos(
      playlistId,
    )) {
      _audioDownloadError = false;

      DateTime? videoUploadDate = (await _youtubeExplode!.videos.get(
        youtubeVideo.id.value,
      )).uploadDate;

      // if the video upload date is not available, then the
      // video upload date is set so it is not null.
      videoUploadDate ??= DateTime(00, 1, 1);

      // using youtubeVideo.description is not correct since it
      // it is empty !
      final String videoDescription = (await _youtubeExplode!.videos.get(
        youtubeVideo.id.value,
      )).description;

      final String compactVideoDescription = _createCompactVideoDescription(
        videoDescription: videoDescription,
        videoAuthor: youtubeVideo.author,
      );

      final String youtubeVideoChannel = youtubeVideo.author;
      final String youtubeVideoTitle = youtubeVideo.title;

      final bool alreadyDownloaded = downloadedAudioOriginalVideoTitleLst.any(
        (originalVideoTitle) => originalVideoTitle == youtubeVideoTitle,
      );

      if (alreadyDownloaded) {
        // avoids that the last downloaded audio download
        // informations remain displayed until all videos referenced
        // in the playlist have been handled.
        if (_isDownloading) {
          _isDownloading = false;

          notifyListeners();
        }

        continue;
      }

      if (_stopDownloadPressed) {
        break;
      }

      // Download the audio file

      Stopwatch stopwatch = Stopwatch()..start();

      if (!_isDownloading) {
        _isDownloading = true;

        // This avoid that when downloading a next audio file, the displayed
        // download progress starts at 100 % !

        _downloadProgress = 0.0;

        notifyListeners();
      }

      final Audio audio = Audio(
        youtubeVideoChannel: youtubeVideoChannel,
        enclosingPlaylist: currentPlaylist,
        originalVideoTitle: youtubeVideoTitle,
        compactVideoDescription: compactVideoDescription,
        videoUrl: youtubeVideo.url,
        audioDownloadDateTime: DateTime.now(),
        videoUploadDate: videoUploadDate,
        audioDuration: Duration.zero, // will be set by AudioPlayer after
        //                               the download audio file is created
        audioPlaySpeed: _determineNewAudioPlaySpeed(currentPlaylist),
      );

      try {
        await _downloadAudioFile(youtubeVideoId: youtubeVideo.id, audio: audio);
      } catch (e) {
        logger.e(
          '$youtubeVideoTitle downloadAudioYoutubeError = ${e.toString()}',
        );
        continue;
      }

      stopwatch.stop();

      audio.downloadDuration = stopwatch.elapsed;
      audio.audioDuration = await getMp3DurationWithAudioPlayer(
        audioPlayer: audioPlayer,
        filePathName: audio.filePathName,
      );

      currentPlaylist.addDownloadedAudio(audio);

      JsonDataService.saveToFile(
        model: currentPlaylist,
        path: downloadedPlaylistFilePathName,
      );

      // should avoid that the last downloaded audio is
      // re-downloaded
      downloadedAudioOriginalVideoTitleLst.add(audio.validVideoTitle);

      notifyListeners();
    }

    audioPlayer.dispose();

    _isDownloading = false;
    _youtubeExplode!.close();
    _youtubeExplode = null;

    // removing the playlist url from the downloadingPlaylistUrls
    // list since the playlist download has finished
    downloadingPlaylistUrls.remove(playlistUrl);

    notifyListeners();
  }

  /// Since currently only one playlist is selectable, if the playlist
  /// selection status is changed, the playlist json file will be
  /// updated.
  void updatePlaylistSelection({
    required Playlist playlist,
    required bool isPlaylistSelected,
  }) {
    bool isPlaylistSelectionChanged = playlist.isSelected != isPlaylistSelected;

    if (isPlaylistSelectionChanged) {
      playlist.isSelected = isPlaylistSelected;

      // if the playlist is selected, the audio quality checkbox will be
      // checked or not according to the selected playlist quality
      if (isPlaylistSelected) {
        isHighQuality = playlist.playlistQuality == PlaylistQuality.music;
      }

      // saving the playlist since its isSelected property has been updated
      JsonDataService.saveToFile(
        model: playlist,
        path: playlist.getPlaylistDownloadFilePathName(),
      );
    }
  }

  void stopDownload() {
    _stopDownloadPressed = true;
  }

  /// This method handles the case where the Youtube playlist was never
  /// downloaded or the case where the Youtube playlist was deleted or was
  /// renamed and then recreated with the same name, which associates the
  /// application existing playlist to a new url.
  ///
  /// Why would the user delete or rename a Youtube playlist and then recreate
  /// a Youtiube playlist with the same name ? The reason is that the Youtube
  /// playlist may contain too many videos. Removing manually the already
  /// listened videos from the Youtube playlist takes too much time. Instead,
  /// the too big Youtube playlist is deleted or is renamed and a new Youtube
  /// playlist with the same title is created. The new Youtube playlist is then
  /// added to the application, which in this case creates a new playlist and
  /// then integrates to it the data of the replaced playlist.
  Future<Playlist> _addYoutubePlaylistIfNotExist({
    required String playlistUrl,
    required PlaylistQuality playlistQuality,
    required String playlistTitle,
    required String playlistId,
  }) async {
    Playlist addedPlaylist = await _createYoutubePlaylist(
      playlistUrl: playlistUrl,
      playlistQuality: playlistQuality,
      playlistTitle: playlistTitle,
      playlistId: playlistId,
    );

    // checking if current Youtube playlist was deleted and recreated
    // on Youtube.
    //
    // The checking must compare the title of the added (recreated)
    // Youtube playlist with the title of the playlist in the
    // _listOfPlaylist since the added playlist url and id are
    // different from their value in the existing playlist.
    int existingPlaylistIndex = _listOfPlaylist.indexWhere(
      (element) => element.title == addedPlaylist.title,
    );

    if (existingPlaylistIndex != -1) {
      // current Youtube playlist was deleted and recreated on Youtube
      // since it is referenced in the _listOfPlaylist and has the same
      // title than the recreated playlist
      Playlist existingPlaylist = _listOfPlaylist[existingPlaylistIndex];

      addedPlaylist.integrateReplacedPlaylistData(
        replacedPlaylist: existingPlaylist,
      );

      _listOfPlaylist[existingPlaylistIndex] = addedPlaylist;
    }

    return addedPlaylist;
  }

  void setAudioQuality({required bool isAudioDownloadHighQuality}) {
    isHighQuality = isAudioDownloadHighQuality;

    notifyListeners();
  }

  /// Returns the play speed value to set to the created audio instance.
  double _determineNewAudioPlaySpeed(Playlist currentPlaylist) {
    return (currentPlaylist.audioPlaySpeed != 0)
        ? currentPlaylist.audioPlaySpeed
        : _settingsDataService.get(
            settingType: SettingType.playlists,
            settingSubType: Playlists.playSpeed,
          );
  }

  /// This method is redifined in the MockAudioDownloadVM in a version which
  /// returns null. This enable the unit test audio_download_vm_test.dart
  /// to be executed without the need of the AudioPlayer package which is
  /// usable only in integration tests, mot in a unit tests.
  AudioPlayer? instanciateAudioPlayer() {
    return AudioPlayer();
  }

  /// This method is not private since it is redifined in the
  /// MockAudioDownloadVM so that the importAudioFilesInPlaylist()
  /// method can be tested by the unit test.
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

  /// This method is return a list containing
  /// [
  ///   0 - the audio mp3 duration
  ///   1 - the audio mp3 file size in bytes
  /// ]
  Future<List<dynamic>> getAudioMp3DurationAndSize({
    required ArchiveFile audioMp3ArchiveFile,
    required String playlistDownloadPath,
  }) async {
    // AudioPlayer is used to get the audio duration of the
    // imported audio files
    final AudioPlayer? audioPlayer = instanciateAudioPlayer();
    try {
      // Create a temporary file from the ArchiveFile data
      final Directory tempDir = Directory(
        _settingsDataService.get(
          settingType: SettingType.dataLocation,
          settingSubType: DataLocation.playlistRootPath,
        ),
      );

      // Use path.basename to extract filename cross-platform
      final String tempFileName = path.basename(audioMp3ArchiveFile.name);

      // Use path.join for cross-platform path joining
      final File tempFile = File(path.join(tempDir.path, tempFileName));

      // Write the archive file content to the temporary file
      await tempFile.writeAsBytes(audioMp3ArchiveFile.content as List<int>);

      // Get the duration using the temporary file path
      Duration audioMp3Duration = await getMp3DurationWithAudioPlayer(
        audioPlayer: audioPlayer,
        filePathName: tempFile.path,
      );

      int fileSize = await tempFile.length();

      // Clean up the temporary file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      return [audioMp3Duration, fileSize];
    } catch (e) {
      // Handle any errors during file operations
      return [Duration.zero, 0];
    }
  }

  String _createCompactVideoDescription({
    required String videoDescription,
    required String videoAuthor,
  }) {
    // Extraire les 3 premières lignes de la description
    List<String> videoDescriptionLinesLst = videoDescription.split('\n');
    String firstThreeLines = videoDescriptionLinesLst.take(3).join('\n');

    // Extraire les noms propres qui ne se trouvent pas dans les 3 premières lignes
    String linesAfterFirstThreeLines = videoDescriptionLinesLst
        .skip(3)
        .join('\n');
    linesAfterFirstThreeLines = _removeTimestampLines(
      '$linesAfterFirstThreeLines\n',
    );
    final List<String> linesAfterFirstThreeLinesWordsLst =
        linesAfterFirstThreeLines.split(RegExp(r'[ \n]'));

    // Trouver les noms propres consécutifs (au moins deux)
    List<String> consecutiveProperNames = [];

    for (int i = 0; i < linesAfterFirstThreeLinesWordsLst.length - 1; i++) {
      if (linesAfterFirstThreeLinesWordsLst[i].isNotEmpty &&
          _isEnglishOrFrenchUpperCaseLetter(
            linesAfterFirstThreeLinesWordsLst[i][0],
          ) &&
          linesAfterFirstThreeLinesWordsLst[i + 1].isNotEmpty &&
          _isEnglishOrFrenchUpperCaseLetter(
            linesAfterFirstThreeLinesWordsLst[i + 1][0],
          )) {
        consecutiveProperNames.add(
          '${linesAfterFirstThreeLinesWordsLst[i]} ${linesAfterFirstThreeLinesWordsLst[i + 1]}',
        );
        i++; // Pour ne pas prendre en compte les noms propres suivants qui font déjà partie d'une paire consécutive
      }
    }

    // Combiner firstThreeLines et consecutiveProperNames en une seule chaîne
    final String compactVideoDescription;

    if (consecutiveProperNames.isEmpty) {
      compactVideoDescription = '$videoAuthor\n\n$firstThreeLines ...';
    } else {
      compactVideoDescription =
          '$videoAuthor\n\n$firstThreeLines ...\n\n${consecutiveProperNames.join(', ')}';
    }

    return compactVideoDescription;
  }

  bool _isEnglishOrFrenchUpperCaseLetter(String letter) {
    // Expression régulière pour vérifier si la lettre est une lettre
    // majuscule valide en anglais ou en français
    RegExp validLetterRegex = RegExp(r'[A-ZÀ-ÿ]');
    // Expression régulière pour vérifier si le caractère n'est pas
    // un chiffre
    RegExp notDigitRegex = RegExp(r'\D');

    return validLetterRegex.hasMatch(letter) && notDigitRegex.hasMatch(letter);
  }

  String _removeTimestampLines(String text) {
    // Expression régulière pour identifier les lignes de texte de la vidéo formatées comme les timestamps
    RegExp timestampRegex = RegExp(r'^\d{1,2}:\d{2} .+\n', multiLine: true);

    // Supprimer les lignes correspondantes
    return text.replaceAll(timestampRegex, '').trim();
  }

  Future<Playlist> _createYoutubePlaylist({
    required String playlistUrl,
    required PlaylistQuality playlistQuality,
    required String playlistTitle,
    required String playlistId,
  }) async {
    Playlist playlist = Playlist(
      url: playlistUrl,
      id: playlistId,
      title: playlistTitle,
      playlistType: PlaylistType.youtube,
      playlistQuality: playlistQuality,
    );

    if (playlistQuality == PlaylistQuality.music) {
      playlist.audioPlaySpeed = 1.0;
    } else {
      playlist.audioPlaySpeed = _settingsDataService.get(
        settingType: SettingType.playlists,
        settingSubType: Playlists.playSpeed,
      );
    }

    _listOfPlaylist.add(playlist);

    return await setPlaylistPath(
      playlistTitle: playlistTitle,
      playlist: playlist,
    );
  }

  /// Private method defined as public since it is used by the mock
  /// audio download VM.
  Future<Playlist> setPlaylistPath({
    required String playlistTitle,
    required Playlist playlist,
  }) async {
    final String playlistDownloadPath =
        '$_playlistsRootPath${Platform.pathSeparator}$playlistTitle';

    // ensure playlist audio download dir exists
    await DirUtil.createDirIfNotExist(pathStr: playlistDownloadPath);

    playlist.downloadPath = playlistDownloadPath;

    return playlist;
  }

  /// Returns an empty list if the passed playlist was created or
  /// recreated.
  Future<List<String>> _getPlaylistDownloadedAudioOriginalVideoTitleLst({
    required Playlist currentPlaylist,
  }) async {
    List<Audio> playlistDownloadedAudioLst = currentPlaylist.downloadedAudioLst;

    return playlistDownloadedAudioLst
        .map((downloadedAudio) => downloadedAudio.originalVideoTitle)
        .toList();
  }

  /// Downloads the audio file from the Youtube video and saves it to the enclosing
  /// playlist directory. Returns true if the audio file was successfully downloaded,
  /// false otherwise.
  ///
  /// The method is also called when the user selects the 'Redownload deleted Audio'
  /// menu item of audio list item or the audio player view left appbar. In this
  /// case, [redownloading] is set to true and [audio] is _currentDownloadingAudio
  /// which was set in the AudioDownloadVM.redownloadPlaylistFilteredAudio()
  /// method.
  Future<bool> _downloadAudioFile({
    required yt.VideoId youtubeVideoId,
    required Audio audio,
    bool redownloading = false,
  }) async {
    if (!redownloading) {
      // _currentDownloadingAudio must be set to passed audio since
      // contrary to the redownloading situation, it was not
      // previously set
      _currentDownloadingAudio = audio;
    }

    final yt.StreamManifest streamManifest;

    try {
      streamManifest = await _youtubeExplode!.videos.streamsClient.getManifest(
        youtubeVideoId,
      );
    } catch (e) {
      logger.e(
        'downloadAudioYoutubeError = ${e.toString()} for video '
        '${audio.originalVideoTitle}',
      );

      // emptying the playlist url from the downloadingPlaylistUrls
      // list since the playlist download has failed
      downloadingPlaylistUrls = [];

      return false;
    }

    final yt.AudioOnlyStreamInfo audioStreamInfo;

    if (isHighQuality) {
      audioStreamInfo = streamManifest.audioOnly.withHighestBitrate();
      if (!redownloading) {
        // if redownloading, the audio quality is already set
        audio.setAudioToMusicQuality();
      }
    } else {
      audioStreamInfo = streamManifest.audioOnly.reduce(
        (a, b) => a.bitrate.bitsPerSecond < b.bitrate.bitsPerSecond ? a : b,
      );
    }

    final int audioFileSize = audioStreamInfo.size.totalBytes;

    if (!redownloading) {
      // if redownloading, the audio file size is already set
      audio.audioFileSize = audioFileSize;
    }

    await _youtubeDownloadAudioFile(
      audioStreamInfo: audioStreamInfo,
      audioFilePathName: audio.filePathName,
      audioFileSize: audioFileSize,
    );

    return true;
  }

  /// Downloads the audio file from the Youtube video and saves it
  /// to the enclosing playlist directory.
  Future<void> _youtubeDownloadAudioFile({
    required yt.AudioOnlyStreamInfo audioStreamInfo,
    required String audioFilePathName,
    required int audioFileSize,
  }) async {
    final File file = File(audioFilePathName);
    final IOSink audioFileSink = file.openWrite();
    final Stream<List<int>> audioStream = _youtubeExplode!.videos.streamsClient
        .get(audioStreamInfo);
    int totalBytesDownloaded = 0;
    int previousSecondBytesDownloaded = 0;

    // This avoid that when downloading a next audio file, the displayed
    // download progress starts at 100 % !

    _downloadProgress = 0.0;

    notifyListeners();

    Duration updateInterval = const Duration(seconds: 1);
    DateTime lastUpdate = DateTime.now();
    Timer timer = Timer.periodic(updateInterval, (timer) {
      if (DateTime.now().difference(lastUpdate) >= updateInterval) {
        _downloadProgress = totalBytesDownloaded / audioFileSize;
        _lastSecondDownloadSpeed =
            totalBytesDownloaded - previousSecondBytesDownloaded;

        notifyListeners();

        if (!_isDownloading) {
          // Avoids that the playlist download view is rebuilded
          // an infiite number of times when the download was stopped
          // due to a Youtube error.
          timer.cancel();
        }

        previousSecondBytesDownloaded = totalBytesDownloaded;
        lastUpdate = DateTime.now();
      }
    });

    await for (List<int> byteChunk in audioStream) {
      totalBytesDownloaded += byteChunk.length;

      // Check if the deadline has been exceeded before updating the
      // progress
      if (DateTime.now().difference(lastUpdate) >= updateInterval) {
        _downloadProgress = totalBytesDownloaded / audioFileSize;
        _lastSecondDownloadSpeed =
            totalBytesDownloaded - previousSecondBytesDownloaded;

        notifyListeners();

        previousSecondBytesDownloaded = totalBytesDownloaded;
        lastUpdate = DateTime.now();
      }

      audioFileSink.add(byteChunk);
    }

    // Make sure to update the progress one last time to 100% before
    // finishing

    _downloadProgress = 1.0;
    _lastSecondDownloadSpeed = 0;

    notifyListeners();

    // Cancel Timer to avoid unuseful updates
    timer.cancel();

    await audioFileSink.flush();
    await audioFileSink.close();

    _lastSecondDownloadSpeed = 0;
  }

  /// Returns a map containing the chapters names and their HH:mm:ss
  /// time position in the audio.
  Map<String, String> getVideoDescriptionChapters({
    required String videoDescription,
  }) {
    // Extract the "TIME CODE" section from the description.
    String timeCodeSection = videoDescription.split('TIME CODE :').last;

    // Define a pattern to match time codes and chapter names.
    RegExp pattern = RegExp(r'(\d{1,2}:\d{2}(?::\d{2})?)\s+(.+)');

    // Use the pattern to find matches in the time code section.
    Iterable<RegExpMatch> matches = pattern.allMatches(timeCodeSection);

    // Create a map to hold the time codes and chapter names.
    Map<String, String> chapters = <String, String>{};

    for (var match in matches) {
      var timeCode = match.group(1)!;
      var chapterName = match.group(2)!;
      chapters[chapterName] = timeCode;
    }

    return chapters;
  }
}
