import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ShareService {
  /// Share audio or video file to any app via native OS share sheet
  static Future<void> shareAudioFile(String filePath, {String? title}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    final isVideo = filePath.toLowerCase().endsWith('.mp4');
    final mimeType = isVideo ? 'video/mp4' : 'audio/mpeg';

    final xFile = XFile(
      filePath,
      mimeType: mimeType,
      name: file.uri.pathSegments.last,
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [xFile],
        subject: title ?? (isVideo ? 'Sentra Video Mix' : 'Sentra Merged Audio Mix'),
        text: isVideo
            ? '🎬 Check out this music video created with Sentra! 🔥'
            : '🎵 Listen to this merged song mix created with Sentra! 🔥',
      ),
    );
  }

  /// Direct WhatsApp share trigger
  static Future<void> shareToWhatsApp(String filePath, {String? message}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    final isVideo = filePath.toLowerCase().endsWith('.mp4');
    final mimeType = isVideo ? 'video/mp4' : 'audio/mpeg';

    final xFile = XFile(
      filePath,
      mimeType: mimeType,
      name: file.uri.pathSegments.last,
    );

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          text: message ?? (isVideo ? '🎬 Here is the music video created with Sentra!' : '🎵 Here is the merged audio mix from Sentra!'),
        ),
      );
    } catch (_) {
      // Fallback: Open WhatsApp URL directly
      final encodedMsg = Uri.encodeComponent(
        '${message ?? "Here is the audio mix created with Sentra"}: ${file.uri.pathSegments.last}',
      );
      final waUrl = Uri.parse('whatsapp://send?text=$encodedMsg');
      if (await canLaunchUrl(waUrl)) {
        await launchUrl(waUrl);
      } else {
        final webUrl = Uri.parse('https://api.whatsapp.com/send?text=$encodedMsg');
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    }
  }

  /// Open containing directory or open file in default system application
  static Future<void> openFileLocation(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    if (Platform.isWindows) {
      // Open explorer highlighting the file
      Process.run('explorer.exe', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      Process.run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [file.parent.path]);
    }
  }
}
