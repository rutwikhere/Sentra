import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../models/track_item.dart';
import '../services/audio_merge_service.dart';
import '../services/share_service.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/timeline_slider_shapes.dart';
import 'welcome_screen.dart';

class DownloadExportScreen extends StatefulWidget {
  final List<TrackItem> tracks;
  final int crossfadeSeconds;
  final int bitrateKbps;

  const DownloadExportScreen({
    super.key,
    required this.tracks,
    required this.crossfadeSeconds,
    required this.bitrateKbps,
  });

  @override
  State<DownloadExportScreen> createState() => _DownloadExportScreenState();
}

class _DownloadExportScreenState extends State<DownloadExportScreen>
    with SingleTickerProviderStateMixin {
  final YouTubeService _ytService = YouTubeService();
  final AudioMergeService _mergeService = AudioMergeService();
  late AudioPlayer _audioPlayer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isProcessing = true;
  double _progress = 0.0;
  String _statusText = 'Starting audio pipeline...';
  String? _errorMessage;
  int _pipelineStep = 1;

  String? _mp3Path;
  String? _videoPath;
  bool _isGeneratingVideo = false;
  String _videoStatusText = 'Encoding video with Sentra artwork...';
  bool _isSavingMp3 = false;
  bool _isSavingVideo = false;

  bool _isPlaying = false;
  bool _isDraggingSlider = false;
  Duration _currentPos = Duration.zero;
  Duration _totalDur = Duration.zero;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _audioPlayer = AudioPlayer();

    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted && !_isDraggingSlider) {
        setState(() {
          _currentPos = pos;
        });
      }
    });

    _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() {
          _totalDur = dur;
        });
      }
    });

    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPos = Duration.zero;
        });
      }
    });

    _startExportPipeline();
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _pulseController.dispose();
    _ytService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Duration get _computedTracksDuration {
    var dur = Duration.zero;
    for (final t in widget.tracks) {
      dur += t.clipDuration;
    }
    return dur;
  }

  Future<void> _startExportPipeline() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _progress = 0.05;
      _pipelineStep = 1;
      _statusText = 'Preparing audio pipeline...';
    });

    try {
      final cacheDir = await _mergeService.getWorkingDir();

      // 1. Download YouTube streams
      for (int i = 0; i < widget.tracks.length; i++) {
        final track = widget.tracks[i];
        final base = (i / widget.tracks.length) * 0.40;

        setState(() {
          _pipelineStep = 1;
          _progress = base;
          _statusText = 'Preparing song ${i + 1}/${widget.tracks.length}: "${track.title}"...';
        });

        if (track.downloadedPath != null &&
            await File(track.downloadedPath!).exists() &&
            await File(track.downloadedPath!).length() > 10240) {
          continue;
        }

        final rawPath = await _ytService.downloadAudioStream(
          track,
          cacheDir.path,
          onProgress: (p, s) {
            if (mounted) {
              setState(() {
                _progress = base + (p * (0.40 / widget.tracks.length));
                _statusText = 'Song ${i + 1}/${widget.tracks.length}: $s';
              });
            }
          },
        );
        track.downloadedPath = rawPath;
      }

      // 2. Trim and Merge tracks with FFmpeg
      final finalPath = await _mergeService.mergeTracks(
        widget.tracks,
        mixTitle: 'Sentra_Mix',
        bitrateKbps: widget.bitrateKbps,
        crossfadeSeconds: widget.crossfadeSeconds,
        onProgress: (p, s) {
          if (mounted) {
            setState(() {
              if (p < 0.75) {
                _pipelineStep = 2; // Trimming
              } else if (p < 0.92) {
                _pipelineStep = 3; // Stitching
              } else {
                _pipelineStep = 4; // Finalizing
              }
              _progress = p;
              _statusText = s;
            });
          }
        },
      );

      setState(() {
        _mp3Path = finalPath;
        _isProcessing = false;
        _progress = 1.0;
        _pipelineStep = 4;
        _statusText = 'Mix Ready!';
      });

      // Prepare audio player
      await _audioPlayer.setSource(DeviceFileSource(finalPath));
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.resume();
    }
  }

  Future<void> _downloadOrSaveMp3() async {
    if (_mp3Path == null || _isSavingMp3) return;

    setState(() => _isSavingMp3 = true);

    try {
      final savedPath = await AudioMergeService.saveFileToPublicDownloads(_mp3Path!);
      setState(() => _isSavingMp3 = false);

      if (mounted) {
        if (savedPath != null) {
          final displayName = File(savedPath).uri.pathSegments.last;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MP3 Saved to Downloads!',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13),
                        ),
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'Share',
                textColor: Colors.white,
                onPressed: () {
                  ShareService.shareAudioFile(savedPath, title: 'Sentra Song Mix');
                },
              ),
            ),
          );
        } else {
          // If direct storage write was blocked or needs app restart, open native system share dialog so user can choose "Save to Device" / "Files"
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.electricBlue,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: const Row(
                children: [
                  Icon(Icons.downloading_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Choose "Save to device" or "Files" to save MP3',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
          await ShareService.shareAudioFile(_mp3Path!, title: 'Sentra Song Mix');
        }
      }
    } catch (_) {
      setState(() => _isSavingMp3 = false);
      if (mounted) {
        await ShareService.shareAudioFile(_mp3Path!, title: 'Sentra Song Mix');
      }
    }
  }

  Future<void> _generateVideo() async {
    if (_mp3Path == null || _isGeneratingVideo) return;

    setState(() {
      _isGeneratingVideo = true;
      _videoStatusText = 'Encoding video with Sentra artwork...';
    });

    try {
      final video = await _mergeService.createVideoWithLogo(
        _mp3Path!,
        mixTitle: 'Sentra_Mix',
        onProgress: (p, s) {
          if (mounted) {
            setState(() {
              _videoStatusText = s;
            });
          }
        },
      );

      setState(() {
        _videoPath = video;
        _isGeneratingVideo = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Row(
              children: [
                Icon(Icons.videocam_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Video created successfully with Sentra artwork!',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isGeneratingVideo = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.errorRed,
            content: Text('Video generation failed: $e'),
          ),
        );
      }
    }
  }

  Future<void> _downloadVideo() async {
    if (_videoPath == null || _isSavingVideo) return;

    setState(() => _isSavingVideo = true);

    try {
      final savedPath = await AudioMergeService.saveFileToPublicDownloads(_videoPath!);
      setState(() => _isSavingVideo = false);

      if (mounted) {
        if (savedPath != null) {
          final displayName = File(savedPath).uri.pathSegments.last;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Video Saved to Downloads!',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13),
                        ),
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'Share',
                textColor: Colors.white,
                onPressed: () {
                  ShareService.shareAudioFile(savedPath, title: 'Sentra Music Video');
                },
              ),
            ),
          );
        } else {
          // If direct storage write was blocked or needs app restart, open native system share dialog so user can choose "Save to Device" / "Files"
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.electricBlue,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: const Row(
                children: [
                  Icon(Icons.downloading_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Choose "Save to device" or "Files" to save Video',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
          await ShareService.shareAudioFile(_videoPath!, title: 'Sentra Music Video');
        }
      }
    } catch (_) {
      setState(() => _isSavingVideo = false);
      if (mounted) {
        await ShareService.shareAudioFile(_videoPath!, title: 'Sentra Music Video');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.mainBackground,
      appBar: AppBar(
        title: const Text('Export Mix'),
        centerTitle: true,
        automaticallyImplyLeading: !_isProcessing,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _isProcessing
            ? _buildProcessingState()
            : _errorMessage != null
                ? _buildErrorState()
                : _buildReadyState(),
      ),
    );
  }

  // Studio Mastering Pipeline View
  Widget _buildProcessingState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Pulsing Sentra Logo
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.electricBlue.withValues(alpha: 0.28),
                      blurRadius: 28,
                      spreadRadius: 4,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(52),
                  child: Image.asset(
                    'assets/applogo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: const BoxDecoration(
                        gradient: AppTheme.sentraGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.multitrack_audio_rounded, size: 50, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Mastering Your Mix',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryText,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),

            Text(
              'Stitching ${widget.tracks.length} songs into a seamless studio mix',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 28),

            // 4-Stage Visual Studio Pipeline Tracker
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.secondaryBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border, width: 1.2),
              ),
              child: Column(
                children: [
                  _buildPipelineStepRow(
                    stepNumber: 1,
                    title: 'Downloading High-Bitrate Audio',
                    isActive: _pipelineStep == 1,
                    isDone: _pipelineStep > 1,
                    icon: Icons.cloud_download_rounded,
                  ),
                  const Divider(color: AppTheme.border, height: 18),
                  _buildPipelineStepRow(
                    stepNumber: 2,
                    title: 'Precision Trimming & Normalization',
                    isActive: _pipelineStep == 2,
                    isDone: _pipelineStep > 2,
                    icon: Icons.content_cut_rounded,
                  ),
                  const Divider(color: AppTheme.border, height: 18),
                  _buildPipelineStepRow(
                    stepNumber: 3,
                    title: 'Crossfade & Audio Stitching',
                    isActive: _pipelineStep == 3,
                    isDone: _pipelineStep > 3,
                    icon: Icons.tune_rounded,
                  ),
                  const Divider(color: AppTheme.border, height: 18),
                  _buildPipelineStepRow(
                    stepNumber: 4,
                    title: 'Final Master Export (${widget.bitrateKbps} kbps)',
                    isActive: _pipelineStep == 4,
                    isDone: _progress >= 1.0,
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // Modern Gradient Progress Bar with Glow
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Container(
                    height: 9,
                    width: double.infinity,
                    color: const Color(0xFFEDF1F8),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.02, end: _progress.clamp(0.02, 1.0)),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedProgress, _) => FractionallySizedBox(
                      widthFactor: animatedProgress,
                      child: Container(
                        height: 9,
                        decoration: const BoxDecoration(
                          gradient: AppTheme.sentraGradient,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                ),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.electricBlue,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPipelineStepRow({
    required int stepNumber,
    required String title,
    required bool isActive,
    required bool isDone,
    required IconData icon,
  }) {
    Color iconColor;
    Widget statusIndicator;

    if (isDone) {
      iconColor = const Color(0xFF10B981);
      statusIndicator = const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18);
    } else if (isActive) {
      iconColor = AppTheme.electricBlue;
      statusIndicator = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.electricBlue),
      );
    } else {
      iconColor = const Color(0xFF94A3B8);
      statusIndicator = Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFCBD5E1),
          shape: BoxShape.circle,
        ),
      );
    }

    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? AppTheme.primaryText : AppTheme.secondaryText,
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(
            key: ValueKey('step_${stepNumber}_${isDone ? "done" : isActive ? "active" : "pending"}'),
            child: statusIndicator,
          ),
        ),
      ],
    );
  }

  // Error State View
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, size: 40, color: AppTheme.errorRed),
            ),
            const SizedBox(height: 18),
            const Text(
              'Mix Generation Error',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primaryText),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An error occurred during audio processing.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText, height: 1.4),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryText,
                    side: const BorderSide(color: AppTheme.border, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Back to Editor', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _startExportPipeline,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.electricBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Master Ready State View (Clean, Minimal, Modern)
  Widget _buildReadyState() {
    final fileName = _mp3Path != null ? File(_mp3Path!).uri.pathSegments.last : 'Sentra_Mix.mp3';
    final effectiveTotal = _totalDur > Duration.zero ? _totalDur : _computedTracksDuration;
    final totalMs = effectiveTotal.inMilliseconds > 0 ? effectiveTotal.inMilliseconds.toDouble() : 1.0;
    final currentMs = _currentPos.inMilliseconds.toDouble().clamp(0.0, totalMs);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Clean Minimal Hero Banner Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: AppTheme.sentraGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.electricBlue.withValues(alpha: 0.28),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/applogo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mix Created! 🎉',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryText,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Your merged mix is ready to play and export',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. Studio Player Card (Play button on LEFT of timeline slider)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Track Title Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.electricBlue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.music_note_rounded, size: 16, color: AppTheme.electricBlue),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Interactive Scrubber with Play Button strictly on the LEFT of the timeline
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Play / Pause Circle Button on LEFT
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3867FF), Color(0xFF1E4DE8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.electricBlue.withValues(alpha: 0.32),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(scale: anim, child: child),
                          ),
                          child: Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            key: ValueKey(_isPlaying ? 'pause' : 'play'),
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Timeline Scrubber Slider + Dynamic Live Timer
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 8,
                              trackShape: MultiSongSliderTrackShape(
                                tracks: widget.tracks,
                                totalDuration: effectiveTotal,
                                palette: AppTheme.songPalette,
                              ),
                              thumbShape: const ModernSliderThumbShape(
                                thumbRadius: 8.5,
                                borderWidth: 2.5,
                              ),
                              overlayColor: AppTheme.electricBlue.withValues(alpha: 0.12),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                            ),
                            child: Slider(
                              value: currentMs,
                              min: 0.0,
                              max: totalMs,
                              onChangeStart: (_) {
                                setState(() => _isDraggingSlider = true);
                              },
                              onChanged: (val) {
                                setState(() {
                                  _currentPos = Duration(milliseconds: val.round());
                                });
                              },
                              onChangeEnd: (val) async {
                                final target = Duration(milliseconds: val.round());
                                await _audioPlayer.seek(target);
                                setState(() {
                                  _isDraggingSlider = false;
                                  _currentPos = target;
                                });
                              },
                            ),
                          ),

                          const SizedBox(height: 2),

                          // Dynamic Live Timer
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  AudioMergeService.formatDuration(_currentPos),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.electricBlue,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  '${AudioMergeService.formatDuration(_currentPos)} / ${AudioMergeService.formatDuration(effectiveTotal)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.secondaryText,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // 3. Primary Actions: Save to Downloads & Share Options
          // Download MP3 Main Action Button
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSavingMp3 ? null : _downloadOrSaveMp3,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.electricBlue,
                foregroundColor: Colors.white,
                elevation: 3,
                shadowColor: AppTheme.electricBlue.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isSavingMp3
                    ? const SizedBox(
                        key: ValueKey('saving_mp3_spinner'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_rounded, key: ValueKey('download_mp3_icon'), size: 22),
              ),
              label: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _isSavingMp3 ? 'Saving to Downloads...' : 'Save MP3 to Downloads',
                  key: ValueKey(_isSavingMp3 ? 'saving_text' : 'save_text'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Dual Share Buttons: Share MP3 & WhatsApp Direct Share
          Row(
            children: [
              // Share MP3 Button
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_mp3Path != null) {
                        ShareService.shareAudioFile(_mp3Path!, title: 'Sentra Song Mix');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.vividViolet,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: AppTheme.vividViolet.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 19),
                    label: const Text('Share MP3', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // WhatsApp Direct Share Button
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_mp3Path != null) {
                        ShareService.shareToWhatsApp(_mp3Path!);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.whatsappGreen,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: AppTheme.whatsappGreen.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 17),
                    label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 20),

          // 4. Video Export Section (With Sentra Artwork)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.secondaryBackground,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.electricBlue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.video_library_rounded, size: 18, color: AppTheme.electricBlue),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Video Export with Sentra Artwork',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Create an MP4 video with official Sentra visual art to share on WhatsApp Status, Instagram, or YouTube.',
                  style: TextStyle(fontSize: 12, color: AppTheme.secondaryText, height: 1.3),
                ),
                const SizedBox(height: 14),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _videoPath == null
                      ? SizedBox(
                          key: const ValueKey('video_generate_btn'),
                          width: double.infinity,
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: _isGeneratingVideo ? null : _generateVideo,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.electricBlue,
                              side: const BorderSide(color: AppTheme.electricBlue, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _isGeneratingVideo
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.electricBlue),
                                  )
                                : const Icon(Icons.movie_creation_outlined, size: 18),
                            label: Text(
                              _isGeneratingVideo ? _videoStatusText : 'Generate Music Video',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                        )
                      : Column(
                          key: const ValueKey('video_ready_actions'),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Video Ready: ${File(_videoPath!).uri.pathSegments.last}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF047857),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 44,
                                    child: ElevatedButton.icon(
                                      onPressed: _isSavingVideo ? null : _downloadVideo,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.electricBlue,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      icon: _isSavingVideo
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Icon(Icons.download_rounded, size: 18),
                                      label: const Text('Save Video', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppTheme.vividViolet,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.all(12),
                                  ),
                                  onPressed: () => ShareService.shareAudioFile(_videoPath!, title: 'Sentra Music Video'),
                                  icon: const Icon(Icons.share_rounded, size: 18),
                                  tooltip: 'Share Video',
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 5. Return Home / Create New Mix Button
          TextButton.icon(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: AppTheme.secondaryText),
            label: const Text(
              'Create Another Mix',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
