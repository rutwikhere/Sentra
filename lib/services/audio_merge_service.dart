import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track_item.dart';

class AudioMergeService {
  /// Format a Duration to mm:ss or hh:mm:ss for display
  static String formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Parse mm:ss or ss string into Duration
  static Duration? parseTimeCode(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return null;

    final parts = clean.split(':');
    if (parts.length == 1) {
      final secs = int.tryParse(parts[0]);
      if (secs != null && secs >= 0) {
        return Duration(seconds: secs);
      }
    } else if (parts.length == 2) {
      final mins = int.tryParse(parts[0]);
      final secs = int.tryParse(parts[1]);
      if (mins != null && secs != null && mins >= 0 && secs >= 0 && secs < 60) {
        return Duration(minutes: mins, seconds: secs);
      }
    } else if (parts.length == 3) {
      final hrs = int.tryParse(parts[0]);
      final mins = int.tryParse(parts[1]);
      final secs = int.tryParse(parts[2]);
      if (hrs != null && mins != null && secs != null && hrs >= 0 && mins >= 0 && secs >= 0) {
        return Duration(hours: hrs, minutes: mins, seconds: secs);
      }
    }
    return null;
  }

  /// Format a Duration to precise seconds string for FFmpeg (e.g., 34.500)
  static String durationToFFmpegSeconds(Duration d) {
    final totalSeconds = d.inMilliseconds / 1000.0;
    return totalSeconds.toStringAsFixed(3);
  }

  /// Get working directory for caching audio files
  Future<Directory> getWorkingDir() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final sentraDir = Directory('${baseDir.path}/sentra_cache');
    if (!await sentraDir.exists()) {
      await sentraDir.create(recursive: true);
    }
    return sentraDir;
  }

  /// Get user-accessible export directory (Downloads or Documents)
  Future<Directory> getExportDir() async {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }
    dir ??= await getApplicationDocumentsDirectory();
    return dir;
  }

  /// Ensure logo asset is written to a local physical file for FFmpeg to use
  Future<String> getPhysicalLogoPath() async {
    final cacheDir = await getWorkingDir();
    final logoFile = File('${cacheDir.path}/sentra_video_logo.png');
    if (!await logoFile.exists() || await logoFile.length() == 0) {
      try {
        final byteData = await rootBundle.load('assets/applogo.png');
        final bytes = byteData.buffer.asUint8List();
        await logoFile.writeAsBytes(bytes);
      } catch (_) {
        // Fallback to checking assets/icon/app_icon.png
        final byteData = await rootBundle.load('assets/icon/app_icon.png');
        final bytes = byteData.buffer.asUint8List();
        await logoFile.writeAsBytes(bytes);
      }
    }
    return logoFile.path;
  }

  /// Safely save a file to the user's public device Downloads directory
  static Future<String?> saveFileToPublicDownloads(String sourcePath, {String? customName}) async {
    final srcFile = File(sourcePath);
    if (!await srcFile.exists()) return null;

    final fileName = customName ?? srcFile.uri.pathSegments.last;

    // 1. Android MediaStore via MethodChannel (Works seamlessly across Android 10, 11, 12, 13, 14, 15)
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.example.sentra/media_saver');
        final isVideo = fileName.toLowerCase().endsWith('.mp4');
        final result = await platform.invokeMethod<String>('saveToDownloads', {
          'sourcePath': sourcePath,
          'fileName': fileName,
          'mimeType': isVideo ? 'video/mp4' : 'audio/mpeg',
        });
        if (result != null && result.isNotEmpty) {
          return result;
        }
      } catch (_) {}
    }

    // 2. Direct copy to /storage/emulated/0/Download if accessible (legacy Android / rooted)
    if (Platform.isAndroid) {
      try {
        final publicDownloadDir = Directory('/storage/emulated/0/Download');
        if (await publicDownloadDir.exists()) {
          final targetFile = File('${publicDownloadDir.path}/$fileName');
          await srcFile.copy(targetFile.path);
          if (await targetFile.exists() && await targetFile.length() > 0) {
            return targetFile.path;
          }
        }
      } catch (_) {}
    }

    // 3. Desktop / iOS path_provider getDownloadsDirectory
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null && await dir.exists()) {
        final targetFile = File('${dir.path}/$fileName');
        await srcFile.copy(targetFile.path);
        if (await targetFile.exists() && await targetFile.length() > 0) {
          return targetFile.path;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Trim a single track to its specified start and end timestamps
  Future<String> trimTrack(
    TrackItem track, {
    void Function(String status)? onStatus,
  }) async {
    if (track.downloadedPath == null || !File(track.downloadedPath!).existsSync()) {
      throw Exception('Track "${track.title}" has not been downloaded yet.');
    }

    final cacheDir = await getWorkingDir();
    final outputPath = '${cacheDir.path}/trimmed_${track.id}.mp3';
    final outputFile = File(outputPath);

    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    final startSec = durationToFFmpegSeconds(track.trimStart);
    final durationSec = durationToFFmpegSeconds(track.clipDuration);

    onStatus?.call('Trimming "${track.title}" (${formatDuration(track.trimStart)} - ${formatDuration(track.trimEnd)})...');

    final safeInput = track.downloadedPath!.replaceAll(r'\', '/');
    final safeOutput = outputPath.replaceAll(r'\', '/');

    // High quality 192kbps MP3 normalization with precise seek after input
    final command =
        '-i "$safeInput" -ss $startSec -t $durationSec -vn -c:a libmp3lame -ar 44100 -ac 2 -b:a 192k -y "$safeOutput"';

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode) && await outputFile.exists()) {
      track.trimmedPath = outputPath;
      return outputPath;
    } else {
      final logs = await session.getAllLogsAsString();
      throw Exception('Failed to trim audio for "${track.title}": $logs');
    }
  }

  /// Merge multiple trimmed tracks in sequential order into a single MP3
  Future<String> mergeTracks(
    List<TrackItem> tracks, {
    String mixTitle = 'Sentra_Mix',
    int bitrateKbps = 192,
    int crossfadeSeconds = 0,
    void Function(double progress, String status)? onProgress,
  }) async {
    if (tracks.isEmpty) {
      throw Exception('No tracks provided to merge.');
    }

    final cacheDir = await getWorkingDir();
    final exportDir = await getExportDir();

    // 1. Verify and trim each track if not already trimmed
    final trimmedFiles = <String>[];
    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final stepProgress = (i / tracks.length) * 0.4 + 0.4; // 40% to 80%
      onProgress?.call(stepProgress, 'Trimming track ${i + 1} of ${tracks.length}: "${track.title}"...');

      final trimmedPath = await trimTrack(track);
      trimmedFiles.add(trimmedPath);
    }

    // 2. Prepare final merged output path
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitizedTitle = mixTitle.replaceAll(RegExp(r'[^\w\s-]+'), '').replaceAll(' ', '_');
    final finalFileName = '${sanitizedTitle}_$timestamp.mp3';
    final finalOutputPath = '${exportDir.path}/$finalFileName';
    final safeFinalOutput = finalOutputPath.replaceAll(r'\', '/');

    onProgress?.call(0.85, 'Stitching ${tracks.length} tracks into seamless MP3...');

    // 3. Try crossfade if requested and > 1 track
    bool crossfadeSucceeded = false;
    if (crossfadeSeconds > 0 && trimmedFiles.length > 1) {
      try {
        final inputs = StringBuffer();
        final filterComplex = StringBuffer();

        for (int i = 0; i < trimmedFiles.length; i++) {
          final safePath = trimmedFiles[i].replaceAll(r'\', '/');
          inputs.write('-i "$safePath" ');
        }

        if (trimmedFiles.length == 2) {
          filterComplex.write('[0:a][1:a]acrossfade=d=$crossfadeSeconds:c1=tri:c2=tri[outa]');
        } else {
          filterComplex.write('[0:a][1:a]acrossfade=d=$crossfadeSeconds:c1=tri:c2=tri[cf1];');
          for (int i = 2; i < trimmedFiles.length; i++) {
            final isLast = i == trimmedFiles.length - 1;
            final inLabel = 'cf${i - 1}';
            final outLabel = isLast ? 'outa' : 'cf$i';
            filterComplex.write('[$inLabel][$i:a]acrossfade=d=$crossfadeSeconds:c1=tri:c2=tri[$outLabel]${isLast ? '' : ';'}');
          }
        }

        final ffmpegCommand =
            '${inputs.toString()}-filter_complex "${filterComplex.toString()}" -map "[outa]" -c:a libmp3lame -b:a ${bitrateKbps}k -ar 44100 -ac 2 -y "$safeFinalOutput"';

        final session = await FFmpegKit.execute(ffmpegCommand);
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode) && await File(finalOutputPath).exists()) {
          crossfadeSucceeded = true;
        }
      } catch (_) {
        crossfadeSucceeded = false;
      }
    }

    // 4. Concat list concatenation (default or fallback)
    if (!crossfadeSucceeded) {
      final concatListFile = File('${cacheDir.path}/concat_list_$timestamp.txt');
      final listContent = StringBuffer();
      for (final filePath in trimmedFiles) {
        final safePath = filePath.replaceAll(r'\', '/');
        listContent.writeln("file '$safePath'");
      }
      await concatListFile.writeAsString(listContent.toString());

      final safeListPath = concatListFile.path.replaceAll(r'\', '/');
      final ffmpegCommand =
          '-f concat -safe 0 -i "$safeListPath" -vn -c:a libmp3lame -b:a ${bitrateKbps}k -ar 44100 -ac 2 -y "$safeFinalOutput"';

      final session = await FFmpegKit.execute(ffmpegCommand);
      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode) || !await File(finalOutputPath).exists()) {
        final logs = await session.getAllLogsAsString();
        throw Exception('FFmpeg merging failed: $logs');
      }
    }

    onProgress?.call(1.0, 'Mix created successfully!');
    return finalOutputPath;
  }

  /// Create a video with Sentra logo displaying while audio plays
  Future<String> createVideoWithLogo(
    String audioPath, {
    String mixTitle = 'Sentra_Mix',
    void Function(double progress, String status)? onProgress,
  }) async {
    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      throw Exception('Audio file not found: $audioPath');
    }

    onProgress?.call(0.1, 'Preparing Sentra logo & video encoder...');
    final logoPath = await getPhysicalLogoPath();
    final exportDir = await getExportDir();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitizedTitle = mixTitle.replaceAll(RegExp(r'[^\w\s-]+'), '').replaceAll(' ', '_');
    final videoFileName = '${sanitizedTitle}_Video_$timestamp.mp4';
    final videoOutputPath = '${exportDir.path}/$videoFileName';

    onProgress?.call(0.3, 'Encoding video with Sentra logo visual...');

    // Creates an MP4 with 1080x1080 square format, crisp logo on clean white background, audio synced
    final safeLogoPath = logoPath.replaceAll(r'\', '/');
    final safeAudioPath = audioPath.replaceAll(r'\', '/');
    final safeVideoPath = videoOutputPath.replaceAll(r'\', '/');

    // Scale and pad logo onto 720x720 white background
    final ffmpegCommand =
        '-loop 1 -i "$safeLogoPath" -i "$safeAudioPath" -vf "scale=500:500:force_original_aspect_ratio=decrease,pad=720:720:(ow-iw)/2:(oh-ih)/2:color=white,format=yuv420p" -c:v libx264 -preset ultrafast -tune stillimage -c:a aac -b:a 192k -shortest -y "$safeVideoPath"';

    final session = await FFmpegKit.execute(ffmpegCommand);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode) && await File(videoOutputPath).exists()) {
      onProgress?.call(1.0, 'Video generated successfully!');
      return videoOutputPath;
    } else {
      // Fallback command without complex filter if libx264 or filters had issue
      final fallbackCommand =
          '-loop 1 -i "$safeLogoPath" -i "$safeAudioPath" -c:v mpeg4 -q:v 2 -c:a aac -b:a 192k -shortest -y "$safeVideoPath"';
      final sessionFallback = await FFmpegKit.execute(fallbackCommand);
      final returnCodeFallback = await sessionFallback.getReturnCode();
      if (ReturnCode.isSuccess(returnCodeFallback) && await File(videoOutputPath).exists()) {
        onProgress?.call(1.0, 'Video generated successfully!');
        return videoOutputPath;
      }
      final logs = await session.getAllLogsAsString();
      throw Exception('Failed to generate video with logo: $logs');
    }
  }

  /// Clean up temporary cache directory
  Future<void> clearCache() async {
    try {
      final cacheDir = await getWorkingDir();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
