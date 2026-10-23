class TrackItem {
  final String id;
  final String url;
  final String videoId;
  final String title;
  final String author;
  Duration totalDuration;
  final String thumbnailUrl;
  
  Duration trimStart;
  Duration trimEnd;
  bool isExpanded;
  String? downloadedPath;
  String? trimmedPath;
  String? audioStreamUrl;
  double downloadProgress;
  bool isDownloading;

  TrackItem({
    required this.id,
    required this.url,
    required this.videoId,
    required this.title,
    required this.author,
    required this.totalDuration,
    required this.thumbnailUrl,
    Duration? trimStart,
    Duration? trimEnd,
    this.isExpanded = false,
    this.downloadedPath,
    this.trimmedPath,
    this.audioStreamUrl,
    this.downloadProgress = 0.0,
    this.isDownloading = false,
  })  : trimStart = trimStart ?? Duration.zero,
        trimEnd = trimEnd ?? (totalDuration > Duration.zero ? totalDuration : const Duration(seconds: 30));

  Duration get clipDuration {
    if (trimEnd <= trimStart) {
      return Duration.zero;
    }
    return trimEnd - trimStart;
  }

  TrackItem copyWith({
    String? id,
    String? url,
    String? videoId,
    String? title,
    String? author,
    Duration? totalDuration,
    String? thumbnailUrl,
    Duration? trimStart,
    Duration? trimEnd,
    bool? isExpanded,
    String? downloadedPath,
    String? trimmedPath,
  }) {
    return TrackItem(
      id: id ?? this.id,
      url: url ?? this.url,
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      author: author ?? this.author,
      totalDuration: totalDuration ?? this.totalDuration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      isExpanded: isExpanded ?? this.isExpanded,
      downloadedPath: downloadedPath ?? this.downloadedPath,
      trimmedPath: trimmedPath ?? this.trimmedPath,
    );
  }
}
