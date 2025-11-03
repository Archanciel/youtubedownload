/// Describes the human label -> yt-dlp/ffmpeg VBR value mapping.
class AudioQuality {
  final String label; // e.g., "Best (V0)"
  final String vbr;   // "0".."9" for --audio-quality

  const AudioQuality(this.label, this.vbr);

  static const values = <AudioQuality>[
    AudioQuality('Best (V0)', '0'),
    AudioQuality('High (V2)', '2'),
    AudioQuality('Medium (V5)', '5'),
    AudioQuality('Low (V9)', '9'),
  ];

  static AudioQuality byLabel(String label) =>
      values.firstWhere((q) => q.label == label, orElse: () => values.first);

  static List<String> labels() => values.map((q) => q.label).toList();

  static String vbrFor(String label) => byLabel(label).vbr;
}
