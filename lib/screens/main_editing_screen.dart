import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../models/track_item.dart';
import '../services/audio_merge_service.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/timeline_slider_shapes.dart';
import 'download_export_screen.dart';

class MainEditingScreen extends StatefulWidget {
  final List<TrackItem> initialTracks;

  const MainEditingScreen({super.key, required this.initialTracks});

  @override
  State<MainEditingScreen> createState() => _MainEditingScreenState();
}

class _MainEditingScreenState extends State<MainEditingScreen> {
  final YouTubeService _ytService = YouTubeService();
  final AudioMergeService _mergeService = AudioMergeService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  late List<TrackItem> _tracks;

  bool _isPlaying = false;
  bool _isAudioBuffering = false;
  bool _isDraggingSlider = false;
  Duration _playbackPosition = Duration.zero;
  Timer? _playbackTimer;
  int _activeTrackIndex = -1;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    _tracks = List.from(widget.initialTracks);
    _initAudioListeners();
    _ensureTracksDownloaded();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    _ytService.dispose();
    super.dispose();
  }

  void _initAudioListeners() {
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      if (state == PlayerState.completed) {
        _onCurrentTrackCompleted();
      }
    });
  }

  Future<void> _ensureTracksDownloaded() async {
    try {
      final cacheDir = await _mergeService.getWorkingDir();
      for (final track in _tracks) {
        if (track.downloadedPath == null || !File(track.downloadedPath!).existsSync()) {
          final path = await _ytService.downloadAudioStream(track, cacheDir.path);
          track.downloadedPath = path;
          if (mounted) setState(() {});
        }
      }
    } catch (_) {}
  }

  Future<String?> _ensureTrackDownloaded(TrackItem track) async {
    if (track.downloadedPath != null && File(track.downloadedPath!).existsSync()) {
      return track.downloadedPath;
    }
    try {
      final cacheDir = await _mergeService.getWorkingDir();
      final path = await _ytService.downloadAudioStream(track, cacheDir.path);
      track.downloadedPath = path;
      return path;
    } catch (_) {
      return null;
    }
  }

  Duration get _totalDuration {
    Duration total = Duration.zero;
    for (final t in _tracks) {
      total += t.clipDuration;
    }
    return total;
  }

  int _getTrackIndexForPosition(Duration pos) {
    Duration acc = Duration.zero;
    for (int i = 0; i < _tracks.length; i++) {
      acc += _tracks[i].clipDuration;
      if (pos < acc) return i;
    }
    return _tracks.isEmpty ? 0 : _tracks.length - 1;
  }

  Duration _getTrackAccumulatedStart(int index) {
    Duration acc = Duration.zero;
    for (int i = 0; i < index && i < _tracks.length; i++) {
      acc += _tracks[i].clipDuration;
    }
    return acc;
  }

  Future<void> _playCurrentSegment({bool forceReload = false}) async {
    if (_tracks.isEmpty) return;

    final trackIdx = _getTrackIndexForPosition(_playbackPosition);
    final track = _tracks[trackIdx];
    final trackAccStart = _getTrackAccumulatedStart(trackIdx);
    final offsetWithinClip = _playbackPosition - trackAccStart;
    final seekPoint = track.trimStart + offsetWithinClip;

    final isAlreadyDownloaded = track.downloadedPath != null && File(track.downloadedPath!).existsSync();
    final isSameTrack = (_activeTrackIndex == trackIdx);

    setState(() {
      _activeTrackIndex = trackIdx;
    });

    // Fast native seek within the active track if already playing
    if (!forceReload && isSameTrack && _isPlaying) {
      try {
        await _audioPlayer.seek(seekPoint);
      } catch (_) {}
      return;
    }

    setState(() {
      _isAudioBuffering = !isAlreadyDownloaded;
    });

    try {
      final localPath = isAlreadyDownloaded
          ? track.downloadedPath!
          : await _ensureTrackDownloaded(track);

      if (localPath != null && mounted && _isPlaying) {
        await _audioPlayer.stop();
        await _audioPlayer.play(
          DeviceFileSource(localPath),
          position: seekPoint,
        );
        if (seekPoint > Duration.zero) {
          await _audioPlayer.seek(seekPoint);
        }
        if (mounted && _isAudioBuffering) {
          setState(() {
            _isAudioBuffering = false;
          });
        }
      } else {
        if (mounted && _isAudioBuffering) {
          setState(() {
            _isAudioBuffering = false;
          });
        }
      }
    } catch (_) {
      if (mounted && _isAudioBuffering) {
        setState(() {
          _isAudioBuffering = false;
        });
      }
    }
  }

  void _onCurrentTrackCompleted() {
    if (!_isPlaying) return;
    final nextIdx = _activeTrackIndex + 1;
    if (nextIdx < _tracks.length) {
      _playbackPosition = _getTrackAccumulatedStart(nextIdx);
      _playCurrentSegment();
    } else {
      _stopPlayback();
      _playbackPosition = Duration.zero;
    }
  }

  void _toggleMasterPlayback() async {
    if (_isPlaying) {
      _stopPlayback();
    } else {
      _startPlayback();
    }
  }

  void _startPlayback() async {
    if (_totalDuration == Duration.zero || _tracks.isEmpty) return;

    if (_playbackPosition >= _totalDuration) {
      _playbackPosition = Duration.zero;
    }

    setState(() {
      _isPlaying = true;
    });

    await _playCurrentSegment(forceReload: true);

    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || !_isPlaying) {
        timer.cancel();
        return;
      }
      if (_isAudioBuffering || _isDraggingSlider) return;

      setState(() {
        _playbackPosition += const Duration(milliseconds: 100);
        if (_playbackPosition >= _totalDuration) {
          _stopPlayback();
          _playbackPosition = Duration.zero;
          return;
        }

        // Check if transition to next track is needed
        final currentIdx = _getTrackIndexForPosition(_playbackPosition);
        if (currentIdx != _activeTrackIndex) {
          _playCurrentSegment();
        }
      });
    });
  }

  void _stopPlayback() {
    setState(() {
      _isPlaying = false;
      _isAudioBuffering = false;
    });
    _playbackTimer?.cancel();
    _audioPlayer.pause();
  }

  void _onSliderChangeStart(double val) {
    setState(() {
      _isDraggingSlider = true;
    });
  }

  void _onSliderChanged(double val) {
    final newPos = Duration(milliseconds: val.round());
    setState(() {
      _playbackPosition = newPos > _totalDuration ? _totalDuration : newPos;
    });
  }

  void _onSliderChangeEnd(double val) async {
    final newPos = Duration(milliseconds: val.round());
    setState(() {
      _playbackPosition = newPos > _totalDuration ? _totalDuration : newPos;
      _isDraggingSlider = false;
    });
    if (_isPlaying) {
      await _playCurrentSegment();
    } else {
      final trackIdx = _getTrackIndexForPosition(_playbackPosition);
      if (mounted) {
        setState(() {
          _activeTrackIndex = trackIdx;
        });
      }
    }
  }

  void _openTrimDialog(TrackItem track, int index) {
    _stopPlayback();
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Trim Song',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, anim1, anim2) => _SongTrimPopup(
        track: track,
        trackIndex: index,
        ytService: _ytService,
        mergeService: _mergeService,
        onSave: (updated) {
          setState(() {
            _tracks[index] = updated;
          });
        },
      ),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    _stopPlayback();
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, item);
      _playbackPosition = Duration.zero;
    });
  }


  void _goToDownloadPage() {
    _stopPlayback();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DownloadExportScreen(
          tracks: _tracks,
          crossfadeSeconds: 0,
          bitrateKbps: 192,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.mainBackground,
      appBar: AppBar(
        title: const Text('Arrange & Trim'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.secondaryBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 14, color: AppTheme.electricBlue),
                const SizedBox(width: 4),
                Text(
                  AudioMergeService.formatDuration(_totalDuration),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryText,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Informational Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: AppTheme.secondaryBackground,
              child: const Row(
                children: [
                  Icon(Icons.touch_app_outlined, size: 18, color: AppTheme.electricBlue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hold & drag cards to reorder. Tap any card to trim song.',
                      style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Horizontal Timeline Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Song Sequence',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryText,
                    ),
                  ),
                  Text(
                    '${_tracks.length} songs',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Compact Horizontal Cards Timeline (without 6 dots default drag handles)
            SizedBox(
              height: 155,
              child: Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: Colors.transparent,
                  shadowColor: Colors.black.withValues(alpha: 0.1),
                ),
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _tracks.length,
                  onReorder: _onReorder,
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final track = _tracks[index];
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(track.id),
                      index: index,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                        child: _TimelineSongCard(
                          index: index,
                          track: track,
                          onTap: () => _openTrimDialog(track, index),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(color: AppTheme.border, height: 1),
            const SizedBox(height: 16),

            // Master Playback Timeline Player Section
            _buildMasterPlaybackTimeline(),
          ],
        ),
      ),

      // Bottom Finish Button
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: AppTheme.mainBackground,
          border: const Border(top: BorderSide(color: AppTheme.border, width: 1.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _goToDownloadPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.electricBlue,
                foregroundColor: Colors.white,
                elevation: 3,
                shadowColor: AppTheme.electricBlue.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Finish',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Master Timeline Player with Play/Pause button on left of timeline slider
  Widget _buildMasterPlaybackTimeline() {
    final hasDuration = _totalDuration.inMilliseconds > 0;
    final maxMilli = hasDuration ? _totalDuration.inMilliseconds.toDouble() : 1.0;
    final currentMilli = _playbackPosition.inMilliseconds.toDouble().clamp(0.0, maxMilli);
    final currentTrackIdx = _getTrackIndexForPosition(_playbackPosition);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.electricBlue.withValues(alpha: 0.05),
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "Play your song" with status indicator (play icon removed)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Play your song',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryText,
                  letterSpacing: -0.3,
                ),
              ),
              // Live status chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isPlaying
                      ? AppTheme.electricBlue.withValues(alpha: 0.1)
                      : AppTheme.secondaryBackground,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isPlaying
                        ? AppTheme.electricBlue.withValues(alpha: 0.3)
                        : AppTheme.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _isPlaying ? AppTheme.electricBlue : AppTheme.secondaryText,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isPlaying ? 'Playing' : 'Paused',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _isPlaying ? AppTheme.electricBlue : AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Main Timeline Row: Play button strictly on the LEFT of the timeline slider
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Play / Pause Circle Button on the left of timeline slider
              GestureDetector(
                onTap: _toggleMasterPlayback,
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
                        color: AppTheme.electricBlue.withValues(alpha: 0.35),
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
                    child: _isAudioBuffering
                        ? const Padding(
                            key: ValueKey('buffering'),
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            key: ValueKey(_isPlaying ? 'pause' : 'play'),
                            color: Colors.white,
                            size: 28,
                          ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Interactive Slider with Integrated Multi-Song Colored Track + Live Timer
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 8,
                        trackShape: MultiSongSliderTrackShape(
                          tracks: _tracks,
                          totalDuration: _totalDuration,
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
                        value: currentMilli,
                        min: 0.0,
                        max: maxMilli,
                        onChangeStart: hasDuration ? _onSliderChangeStart : null,
                        onChanged: hasDuration ? _onSliderChanged : null,
                        onChangeEnd: hasDuration ? _onSliderChangeEnd : null,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Bottom info: Active song pill on left, dynamic live timer on right
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (_tracks.isNotEmpty && currentTrackIdx >= 0 && currentTrackIdx < _tracks.length)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: AppTheme.songPalette[currentTrackIdx % AppTheme.songPalette.length],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Song ${currentTrackIdx + 1} of ${_tracks.length}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.secondaryText,
                                  ),
                                ),
                              ],
                            )
                          else
                            const SizedBox(),

                          Text(
                            '${AudioMergeService.formatDuration(_playbackPosition)} / ${AudioMergeService.formatDuration(_totalDuration)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryText,
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
    );
  }
}

// Compact Horizontal Timeline Card for each Song
class _TimelineSongCard extends StatelessWidget {
  final int index;
  final TrackItem track;
  final VoidCallback onTap;

  const _TimelineSongCard({
    required this.index,
    required this.track,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTrimmed = track.trimStart > Duration.zero || track.trimEnd < track.totalDuration;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, // Clicking anywhere on the card opens the trim popup
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 128,
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isTrimmed ? AppTheme.electricBlue : AppTheme.border,
              width: isTrimmed ? 1.6 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isTrimmed
                    ? AppTheme.electricBlue.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Sequence Badge (no 6 dots)
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.songPalette[index % AppTheme.songPalette.length],
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Thumbnail with Clip Length Overlay
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          Image.network(
                            track.thumbnailUrl,
                            width: double.infinity,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: double.infinity,
                              height: 52,
                              color: AppTheme.secondaryBackground,
                              child: const Icon(Icons.music_note_rounded, size: 18, color: AppTheme.secondaryText),
                            ),
                          ),
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                AudioMergeService.formatDuration(track.clipDuration),
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Title
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryText,
                      ),
                    ),
                    const SizedBox(height: 1),

                    // Channel
                    Text(
                      track.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: AppTheme.secondaryText),
                    ),
                  ],
                ),
              ),

              // Edited Badge in the top-right corner if the song is trimmed
              if (isTrimmed)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3867FF), Color(0xFF853CFF)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3867FF).withValues(alpha: 0.35),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_rounded, size: 8, color: Colors.white),
                        SizedBox(width: 3),
                        Text(
                          'Edited',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Trimming Popup Dialog with Independent Timeline and Manual Input Boxes
class _SongTrimPopup extends StatefulWidget {
  final TrackItem track;
  final int trackIndex;
  final YouTubeService ytService;
  final AudioMergeService mergeService;
  final ValueChanged<TrackItem> onSave;

  const _SongTrimPopup({
    required this.track,
    required this.trackIndex,
    required this.ytService,
    required this.mergeService,
    required this.onSave,
  });

  @override
  State<_SongTrimPopup> createState() => _SongTrimPopupState();
}

class _SongTrimPopupState extends State<_SongTrimPopup> {
  late double _startSec;
  late double _endSec;
  late double _maxSec;
  double _currentPosSec = 0.0;
  bool _isDraggingScrubber = false;

  late TextEditingController _startController;
  late TextEditingController _endController;

  final AudioPlayer _popupAudioPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _popupStateSubscription;
  StreamSubscription<Duration>? _popupPositionSubscription;
  bool _isPopupPlaying = false;
  bool _isBuffering = false;

  @override
  void initState() {
    super.initState();
    _maxSec = widget.track.totalDuration.inSeconds.toDouble();
    if (_maxSec < 1) _maxSec = 60.0;

    _startSec = widget.track.trimStart.inSeconds.toDouble().clamp(0.0, _maxSec - 1);
    _endSec = widget.track.trimEnd.inSeconds.toDouble().clamp(_startSec + 1, _maxSec);
    _currentPosSec = _startSec;

    _startController = TextEditingController(
      text: AudioMergeService.formatDuration(Duration(seconds: _startSec.round())),
    );
    _endController = TextEditingController(
      text: AudioMergeService.formatDuration(Duration(seconds: _endSec.round())),
    );

    _popupStateSubscription = _popupAudioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPopupPlaying = state == PlayerState.playing;
      });
    });

    _popupPositionSubscription = _popupAudioPlayer.onPositionChanged.listen((pos) {
      if (!mounted) return;
      final curSec = pos.inMilliseconds / 1000.0;
      if (!_isDraggingScrubber) {
        setState(() {
          _currentPosSec = curSec.clamp(_startSec, _endSec);
        });
      }
      if (_isPopupPlaying && curSec >= _endSec) {
        _popupAudioPlayer.pause();
        setState(() {
          _isPopupPlaying = false;
          _currentPosSec = _startSec;
        });
      }
    });
  }

  @override
  void dispose() {
    _popupStateSubscription?.cancel();
    _popupPositionSubscription?.cancel();
    _startController.dispose();
    _endController.dispose();
    _popupAudioPlayer.stop();
    _popupAudioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePreviewPlay() async {
    if (_isPopupPlaying) {
      await _popupAudioPlayer.pause();
      setState(() => _isPopupPlaying = false);
    } else {
      if (_currentPosSec >= _endSec - 0.2) {
        _currentPosSec = _startSec;
      }

      final isAlreadyDownloaded = widget.track.downloadedPath != null && File(widget.track.downloadedPath!).existsSync();
      if (!isAlreadyDownloaded) {
        setState(() => _isBuffering = true);
      }
      try {
        if (!isAlreadyDownloaded) {
          final cacheDir = await widget.mergeService.getWorkingDir();
          final path = await widget.ytService.downloadAudioStream(widget.track, cacheDir.path);
          widget.track.downloadedPath = path;
        }

        if (widget.track.downloadedPath != null && mounted) {
          final startPos = Duration(milliseconds: (_currentPosSec * 1000).round());
          await _popupAudioPlayer.stop();
          await _popupAudioPlayer.play(
            DeviceFileSource(widget.track.downloadedPath!),
            position: startPos,
          );
          if (startPos > Duration.zero) {
            await _popupAudioPlayer.seek(startPos);
          }
          if (mounted) {
            setState(() => _isPopupPlaying = true);
          }
        }
      } catch (_) {}
      if (mounted && _isBuffering) {
        setState(() => _isBuffering = false);
      }
    }
  }

  void _onScrubberChangeStart(double val) {
    setState(() {
      _isDraggingScrubber = true;
    });
  }

  void _onScrubberChanged(double val) {
    setState(() {
      _currentPosSec = val.clamp(_startSec, _endSec);
    });
  }

  void _onScrubberChangeEnd(double val) async {
    final clamped = val.clamp(_startSec, _endSec);
    setState(() {
      _currentPosSec = clamped;
      _isDraggingScrubber = false;
    });
    if (_isPopupPlaying) {
      try {
        await _popupAudioPlayer.seek(Duration(milliseconds: (clamped * 1000).round()));
      } catch (_) {}
    }
  }

  void _onSliderChange(RangeValues values) {
    setState(() {
      _startSec = values.start;
      _endSec = values.end;
      if (_currentPosSec < _startSec || _currentPosSec > _endSec) {
        _currentPosSec = _startSec;
      }
      _startController.text = AudioMergeService.formatDuration(Duration(seconds: _startSec.round()));
      _endController.text = AudioMergeService.formatDuration(Duration(seconds: _endSec.round()));
    });
  }

  void _onManualStartChanged(String text) {
    final parsed = AudioMergeService.parseTimeCode(text);
    if (parsed != null) {
      final s = parsed.inSeconds.toDouble();
      if (s < _endSec && s >= 0) {
        setState(() {
          _startSec = s;
          if (_currentPosSec < _startSec) _currentPosSec = _startSec;
        });
      }
    }
  }

  void _onManualEndChanged(String text) {
    final parsed = AudioMergeService.parseTimeCode(text);
    if (parsed != null) {
      final e = parsed.inSeconds.toDouble();
      if (e > _startSec && e <= _maxSec) {
        setState(() {
          _endSec = e;
          if (_currentPosSec > _endSec) _currentPosSec = _startSec;
        });
      }
    }
  }

  void _saveAndClose() {
    _popupAudioPlayer.stop();
    widget.track.trimStart = Duration(seconds: _startSec.round());
    widget.track.trimEnd = Duration(seconds: _endSec.round());
    widget.onSave(widget.track);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final clipDur = Duration(seconds: (_endSec - _startSec).round());
    final songColor = AppTheme.songPalette[widget.trackIndex % AppTheme.songPalette.length];

    return Dialog(
      backgroundColor: AppTheme.mainBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.electricBlue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.content_cut_rounded, size: 18, color: AppTheme.electricBlue),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Trim Song',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryText,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.secondaryText),
                    onPressed: () {
                      _popupAudioPlayer.stop();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Song Info Preview Card (Play button moved below)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        widget.track.thumbnailUrl,
                        width: 56,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 56,
                          height: 42,
                          color: AppTheme.border,
                          child: const Icon(Icons.music_note_rounded, color: AppTheme.secondaryText),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryText),
                          ),
                          Text(
                            'Original: ${AudioMergeService.formatDuration(widget.track.totalDuration)}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              const Divider(color: AppTheme.border, height: 1),
              const SizedBox(height: 16),

              // Song Timeline (Trim Range) Section - Moved ABOVE Play Song section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Song Timeline',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryText),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.electricBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Trimmed: ${AudioMergeService.formatDuration(clipDur)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.electricBlue,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Dual-thumb Range Slider
              RangeSlider(
                values: RangeValues(_startSec, _endSec),
                min: 0.0,
                max: _maxSec,
                divisions: _maxSec.toInt() > 0 ? _maxSec.toInt() : 1,
                activeColor: AppTheme.electricBlue,
                inactiveColor: AppTheme.border,
                onChanged: _onSliderChange,
              ),

              const SizedBox(height: 12),

              // 2 Distinct Time Boxes (Start time & End time)
              Row(
                children: [
                  // Start Time Box
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'START TIME (mm:ss)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _startController,
                            keyboardType: TextInputType.datetime,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryText,
                              fontFamily: 'monospace',
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onSubmitted: _onManualStartChanged,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // End Time Box
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'END TIME (mm:ss)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _endController,
                            keyboardType: TextInputType.datetime,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryText,
                              fontFamily: 'monospace',
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onSubmitted: _onManualEndChanged,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),
              const Text(
                'Note: Start and End time belong to this song only.',
                style: TextStyle(fontSize: 11, color: AppTheme.secondaryText),
              ),

              const SizedBox(height: 16),
              const Divider(color: AppTheme.border, height: 1),
              const SizedBox(height: 16),

              // Play Song Section (Play button on LEFT + Scrubber timeline)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border, width: 1.2),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Play / Pause Circle Button on the LEFT of the timeline
                    GestureDetector(
                      onTap: _togglePreviewPlay,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3867FF), Color(0xFF1E4DE8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.electricBlue.withValues(alpha: 0.3),
                              blurRadius: 8,
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
                          child: _isBuffering
                              ? const Padding(
                                  key: ValueKey('trim_buffering'),
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : Icon(
                                  _isPopupPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  key: ValueKey(_isPopupPlaying ? 'trim_pause' : 'trim_play'),
                                  color: Colors.white,
                                  size: 26,
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Play Timeline Scrubber Slider + Dynamic Timer
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 6,
                              thumbShape: const ModernSliderThumbShape(
                                thumbRadius: 7.5,
                                borderWidth: 2.2,
                              ),
                              activeTrackColor: songColor,
                              inactiveTrackColor: AppTheme.border,
                              overlayColor: songColor.withValues(alpha: 0.12),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            ),
                            child: Slider(
                              value: _currentPosSec.clamp(
                                _startSec,
                                _endSec > _startSec ? _endSec : _startSec + 1.0,
                              ),
                              min: _startSec,
                              max: _endSec > _startSec ? _endSec : _startSec + 1.0,
                              onChangeStart: _onScrubberChangeStart,
                              onChanged: _onScrubberChanged,
                              onChangeEnd: _onScrubberChangeEnd,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  AudioMergeService.formatDuration(Duration(seconds: _currentPosSec.round())),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryText,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  AudioMergeService.formatDuration(Duration(seconds: _endSec.round())),
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
              ),

              const SizedBox(height: 20),

              // Save Changes Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saveAndClose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.electricBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
