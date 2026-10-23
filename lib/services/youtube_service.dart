import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track_item.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Parse and validate YouTube URL or Video ID, with full support for YouTube Shorts
  String? extractVideoId(String input) {
    String clean = input.trim();
    if (clean.isEmpty) return null;

    // Remove any leading or trailing quotes/brackets from copy-pasting
    clean = clean.replaceAll(RegExp(r'^["<\[(]+|[">\])]+$'), '');

    // 1. Direct 11-char Video ID (e.g. dQw4w9WgXcQ)
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean)) {
      return clean;
    }

    // 2. YouTube Shorts (e.g. youtube.com/shorts/VIDEO_ID, m.youtube.com/shorts/VIDEO_ID, etc.)
    final shortsMatch = RegExp(
      r'(?:youtube\.com|youtu\.be)\/shorts\/([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    ).firstMatch(clean);
    if (shortsMatch != null) {
      return shortsMatch.group(1);
    }

    // 3. Shortened youtu.be links (e.g. youtu.be/VIDEO_ID?si=...)
    final youtuBeMatch = RegExp(
      r'youtu\.be\/([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    ).firstMatch(clean);
    if (youtuBeMatch != null) {
      return youtuBeMatch.group(1);
    }

    // 4. Standard watch links (e.g. youtube.com/watch?v=VIDEO_ID or &v=VIDEO_ID)
    final watchMatch = RegExp(
      r'[?&]v=([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    ).firstMatch(clean);
    if (watchMatch != null) {
      return watchMatch.group(1);
    }

    // 5. Embedded / Live / Video links (e.g. /embed/VIDEO_ID, /live/VIDEO_ID)
    final embedMatch = RegExp(
      r'(?:embed|live|v)\/([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    ).firstMatch(clean);
    if (embedMatch != null) {
      return embedMatch.group(1);
    }

    // 6. Built-in VideoId parser from youtube_explode_dart
    try {
      return VideoId.parseVideoId(clean);
    } catch (_) {}

    return null;
  }

  /// Fetch YouTube Video or Shorts metadata and create a TrackItem
  /// Uses a resilient strategy: tries direct video metadata first; if rate-limited or blocked,
  /// falls back instantly to YouTube's public oEmbed API.
  Future<TrackItem> fetchTrackInfo(String inputUrl) async {
    final videoId = extractVideoId(inputUrl);
    if (videoId == null || videoId.isEmpty) {
      throw Exception('Invalid YouTube URL or Video ID');
    }

    String title = 'YouTube Song';
    String author = 'YouTube Creator';
    String thumbnail = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    Duration duration = const Duration(minutes: 3);
    bool metadataFound = false;

    // Strategy 1: Attempt standard video metadata fetch with short timeout
    try {
      final video = await _yt.videos.get(videoId).timeout(const Duration(milliseconds: 1600));
      if (video.title.isNotEmpty) title = video.title;
      if (video.author.isNotEmpty) author = video.author;
      if (video.duration != null && video.duration! > Duration.zero) {
        duration = video.duration!;
      }
      if (video.thumbnails.highResUrl.isNotEmpty) {
        thumbnail = video.thumbnails.highResUrl;
      } else if (video.thumbnails.standardResUrl.isNotEmpty) {
        thumbnail = video.thumbnails.standardResUrl;
      }
      metadataFound = true;
    } catch (e) {
      debugPrint('Standard video info fetch skipped ($e), using resilient oEmbed fallback...');
    }

    // Strategy 2: Resilient oEmbed fallback (handles rate limits, shorts, regional blocks)
    if (!metadataFound) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      try {
        final uri = Uri.parse(
          'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json',
        );
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final data = json.decode(body) as Map<String, dynamic>;
          if (data['title'] != null && (data['title'] as String).isNotEmpty) {
            title = data['title'] as String;
          }
          if (data['author_name'] != null && (data['author_name'] as String).isNotEmpty) {
            author = data['author_name'] as String;
          }
          if (data['thumbnail_url'] != null && (data['thumbnail_url'] as String).isNotEmpty) {
            thumbnail = data['thumbnail_url'] as String;
          }
          metadataFound = true;
        }
      } catch (e) {
        debugPrint('oEmbed fallback error: $e');
      } finally {
        client.close();
      }
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();

    return TrackItem(
      id: id,
      url: 'https://www.youtube.com/watch?v=$videoId',
      videoId: videoId,
      title: title,
      author: author,
      totalDuration: duration,
      thumbnailUrl: thumbnail,
      trimStart: Duration.zero,
      trimEnd: duration,
    );
  }

  /// Get direct playable audio stream URL for streaming preview
  Future<String> getAudioStreamUrl(String videoId) async {
    final manifest = await _yt.videos.streamsClient.getManifest(
      videoId,
      requireWatchPage: false,
      ytClients: [
        YoutubeApiClient.android,
        YoutubeApiClient.ios,
        YoutubeApiClient.tv,
      ],
    );

    if (manifest.muxed.isNotEmpty) {
      final muxed = manifest.muxed.firstWhere(
        (s) => s.tag == 18,
        orElse: () => manifest.muxed.first,
      );
      return muxed.url.toString();
    }

    final mp4Streams = manifest.audioOnly
        .where((s) => s.container.name.toLowerCase() == 'mp4')
        .toList();
    if (mp4Streams.isNotEmpty) {
      mp4Streams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      return mp4Streams.first.url.toString();
    }
    return manifest.audioOnly.withHighestBitrate().url.toString();
  }

  /// Download the audio stream for a track at ultra-fast speeds
  /// Bypasses the 1MB YouTube throttle on longer tracks by leveraging rate-bypassed streams
  Future<String> downloadAudioStream(
    TrackItem track,
    String outputDir, {
    void Function(double progress, String status)? onProgress,
  }) async {
    // 1. Fast Cache Check: If already downloaded, return instantly in 0ms
    for (final testExt in ['mp4', 'm4a', 'webm']) {
      final existing = File('$outputDir/audio_${track.videoId}.$testExt');
      if (await existing.exists() && await existing.length() > 10240) {
        onProgress?.call(1.0, 'Ready');
        return existing.path;
      }
    }

    onProgress?.call(0.08, 'Connecting to audio stream...');

    // 2. Fetch manifest bypassing watch page rate-limits
    final manifest = await _yt.videos.streamsClient.getManifest(
      track.videoId,
      requireWatchPage: false,
      ytClients: [
        YoutubeApiClient.android,
        YoutubeApiClient.ios,
        YoutubeApiClient.tv,
      ],
    );

    // Prefer format 18 (360p pre-muxed MP4 with AAC audio) because YouTube assigns it
    // ratebypass=yes, allowing full downloads of long songs (5m, 10m, 30m) without 403 cutoff!
    final StreamInfo selectedStream;
    if (manifest.muxed.isNotEmpty) {
      selectedStream = manifest.muxed.firstWhere(
        (s) => s.tag == 18,
        orElse: () => manifest.muxed.first,
      );
    } else {
      final mp4Streams = manifest.audioOnly
          .where((s) => s.container.name.toLowerCase() == 'mp4')
          .toList();
      if (mp4Streams.isNotEmpty) {
        mp4Streams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        selectedStream = mp4Streams.first;
      } else {
        selectedStream = manifest.audioOnly.withHighestBitrate();
      }
    }

    // 3. Refine accurate duration if it was estimated during metadata fetch
    final totalBytes = selectedStream.size.totalBytes;
    final bps = selectedStream.bitrate.bitsPerSecond;
    if (bps > 0 && totalBytes > 0) {
      final accurateSec = (totalBytes * 8 / bps).round();
      if (accurateSec > 0 && (track.totalDuration == const Duration(minutes: 3) || track.totalDuration == Duration.zero)) {
        final accurateDuration = Duration(seconds: accurateSec);
        track.totalDuration = accurateDuration;
        track.trimEnd = accurateDuration;
      }
    }

    final ext = selectedStream.container.name.isNotEmpty 
        ? selectedStream.container.name 
        : 'mp4';
    final targetPath = '$outputDir/audio_${track.videoId}.$ext';
    final targetFile = File(targetPath);

    if (await targetFile.exists()) {
      try {
        await targetFile.delete();
      } catch (_) {}
    }

    onProgress?.call(0.15, 'Downloading fast audio...');

    // 4. Stream audio directly through authorized StreamsClient
    final stream = _yt.videos.streamsClient.get(selectedStream);
    final fileSink = targetFile.openWrite();
    int downloadedBytes = 0;
    int lastPercent = -1;
    DateTime lastTime = DateTime.now();

    try {
      await for (final chunk in stream) {
        downloadedBytes += chunk.length;
        fileSink.add(chunk);

        if (totalBytes > 0) {
          final percent = (downloadedBytes * 100 ~/ totalBytes);
          final now = DateTime.now();
          if ((percent != lastPercent && percent >= lastPercent + 2) ||
              (now.difference(lastTime).inMilliseconds > 120) ||
              percent == 100) {
            lastPercent = percent;
            lastTime = now;
            final progress = (downloadedBytes / totalBytes).clamp(0.0, 1.0);
            onProgress?.call(progress, 'Downloading: $percent%');
          }
        }
      }
    } finally {
      await fileSink.flush();
      await fileSink.close();
    }

    if (!await targetFile.exists() || await targetFile.length() < 1024) {
      throw Exception('Downloaded audio file is invalid or empty');
    }

    onProgress?.call(1.0, 'Ready');
    return targetPath;
  }

  void dispose() {
    _yt.close();
  }
}
