import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../services/audio_merge_service.dart';
import '../services/share_service.dart';
import '../theme/app_theme.dart';

class MergedPlayerSheet extends StatefulWidget {
  final String filePath;
  final String mixTitle;
  final int totalTracks;

  const MergedPlayerSheet({
    super.key,
    required this.filePath,
    required this.mixTitle,
    required this.totalTracks,
  });

  @override
  State<MergedPlayerSheet> createState() => _MergedPlayerSheetState();
}

class _MergedPlayerSheetState extends State<MergedPlayerSheet> {
  late AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
        });
      }
    });

    _player.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() {
          _duration = dur;
        });
      }
    });

    // Set source
    _player.setSource(DeviceFileSource(widget.filePath));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  void _saveFile() {
    setState(() {
      _isSaved = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.surfaceLight,
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'MP3 saved to: ${widget.filePath}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = File(widget.filePath).uri.pathSegments.last;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppTheme.border, width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle pill
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Success Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: AppTheme.accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mix Ready to Play & Share! 🎉',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${widget.totalTracks} YouTube tracks merged together',
                      style: const TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // File Info Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.audio_file_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total Length: ${AudioMergeService.formatDuration(_duration)}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.accent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Audio Player Controls
          Row(
            children: [
              Text(
                AudioMergeService.formatDuration(_position),
                style: const TextStyle(fontSize: 12, color: Colors.white60, fontFamily: 'monospace'),
              ),
              Expanded(
                child: Slider(
                  value: _position.inMilliseconds.toDouble().clamp(
                        0.0,
                        _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                      ),
                  min: 0.0,
                  max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                  activeColor: AppTheme.accent,
                  inactiveColor: AppTheme.border,
                  onChanged: (val) {
                    _player.seek(Duration(milliseconds: val.round()));
                  },
                ),
              ),
              Text(
                AudioMergeService.formatDuration(_duration),
                style: const TextStyle(fontSize: 12, color: Colors.white60, fontFamily: 'monospace'),
              ),
            ],
          ),

          // Play/Pause button
          Center(
            child: InkWell(
              onTap: _togglePlay,
              borderRadius: BorderRadius.circular(30),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Action Buttons: WhatsApp & Other Apps Share
          Row(
            children: [
              // WhatsApp Share Button
              Expanded(
                child: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.whatsappGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ).let(
                  (style) => ElevatedButton.icon(
                    style: style,
                    onPressed: () => ShareService.shareToWhatsApp(widget.filePath),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text(
                      'WhatsApp',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // System Share Sheet Button
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => ShareService.shareAudioFile(widget.filePath, title: widget.mixTitle),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text(
                    'Share MP3',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Download / Open Folder buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _saveFile,
                  icon: Icon(_isSaved ? Icons.check : Icons.download_rounded, size: 18),
                  label: Text(_isSaved ? 'Saved to Device' : 'Download MP3'),
                ),
              ),
              if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                  onPressed: () => ShareService.openFileLocation(widget.filePath),
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Open Folder'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// Kotlin-like .let extension helper
extension ObjectExt<T> on T {
  R let<R>(R Function(T it) op) => op(this);
}
