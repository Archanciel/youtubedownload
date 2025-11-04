class PrefKeys {
  static const lastTargetDir = 'last_target_dir';
  static const audioQualityLabel = 'audio_quality_label';
  static const ffmpegUpdatedAt = 'ffmpeg_updated_at'; // <— add this
}

class Defaults {
  static const hardcodedYtDlp = r'c:\YtDlp\yt-dlp.exe';
  static const defaultQualityLabel = 'Best (V0)';
}

const String kApplicationVersion = '1.0.0';
const String kImposedPlaylistsSubDirName = 'playlists';

// Used for Android app version
const String kApplicationPath = "/storage/emulated/0/Documents/audiolearn";
const String kPlaylistDownloadRootPath =
    "/storage/emulated/0/Documents/audiolearn/$kImposedPlaylistsSubDirName";
const String kApplicationPicturePath =
    "/storage/emulated/0/Documents/audiolearn/pictures";

// Used for testing on Android
const String kApplicationPathAndroidTest =
    "/storage/emulated/0/Documents/test/audiolearn";
const String kPlaylistDownloadRootPathAndroidTest =
    "/storage/emulated/0/Documents/test/audiolearn/$kImposedPlaylistsSubDirName";
const String kApplicationPicturePathAndroidTest =
    "/storage/emulated/0/Documents/test/audiolearn/pictures";

// Used for Windows app version
const String kApplicationPathWindows = "C:\\audiolearn";
const String kPlaylistDownloadRootPathWindows =
    "C:\\audiolearn\\$kImposedPlaylistsSubDirName";
const String kApplicationPicturePathWindows = "C:\\audiolearn\\pictures";

// Used for testing and debugging on Windows
const String kApplicationPathWindowsTest =
    "C:\\development\\flutter\\audiolearn\\test\\data\\audio";
const String kPlaylistDownloadRootPathWindowsTest =
    "C:\\development\\flutter\\audiolearn\\test\\data\\audio\\$kImposedPlaylistsSubDirName";
const String kApplicationPicturePathWindowsTest =
    "C:\\development\\flutter\\audiolearn\\test\\data\\audio\\pictures";

const String kDownloadAppTestSavedDataDir =
    "C:\\development\\flutter\\audiolearn\\test\\data\\saved";

const String kSettingsFileName = 'settings.json';
const String kOrderedPlaylistTitlesFileName = 'savedOrderedPlaylistTitles.txt';

// true makes sense if audio are played in
// Smart AudioBook app
const bool kAudioFileNamePrefixIncludeTime = true;

const double kAudioDefaultPlaySpeed = 1.0;
const double kAudioDefaultPlayVolume = 0.5;

const double kMp3ZipFileSizeLimitInMb = 525.0; // 525 required by Android

// Number of seconds to consider that the audio was fully listened:
// If its current position is greater or equal to its total duration
// minus fullyListenedBufferSeconds seconds, then the audio is considered
// as being fully listened.
const int kFullyListenedBufferSeconds = 10;
