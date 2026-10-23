import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/track_item.dart';
import '../services/audio_merge_service.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';
import 'main_editing_screen.dart';

class SongInputScreen extends StatefulWidget {
  const SongInputScreen({super.key});

  @override
  State<SongInputScreen> createState() => _SongInputScreenState();
}

class _SongInputScreenState extends State<SongInputScreen> {
  final YouTubeService _ytService = YouTubeService();
  final AudioMergeService _mergeService = AudioMergeService();
  final TextEditingController _urlController = TextEditingController();
  final List<TrackItem> _tracks = [];

  bool _isAdding = false;

  @override
  void dispose() {
    _ytService.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _urlController.text = data.text!.trim();
      });
      // Automatically add & download the song when pasted from clipboard
      _addSong();
    }
  }

  Future<void> _addSong() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showFaultyLinkDialog(
        url: '',
        message: 'Please paste or enter a valid song link first.',
      );
      return;
    }

    setState(() {
      _isAdding = true;
    });

    try {
      // 1. Fetch metadata quickly (< 1s)
      final track = await _ytService.fetchTrackInfo(url);
      track.isDownloading = true;
      track.downloadProgress = 0.05;

      // 2. Add to sequence immediately so the input box unlocks without delay!
      setState(() {
        _tracks.add(track);
        _urlController.clear();
        _isAdding = false;
      });

      // 3. Start fast background download on the card
      _downloadTrackAudio(track);
    } catch (e, st) {
      debugPrint('Error adding song from url $url: $e\n$st');
      if (mounted) {
        _showFaultyLinkDialog(
          url: url,
          message: 'This song cannot be downloaded. Enter other link or paste this link again.',
        );
      }
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
      }
    }
  }

  Future<void> _downloadTrackAudio(TrackItem track) async {
    try {
      final cacheDir = await _mergeService.getWorkingDir();
      final localPath = await _ytService.downloadAudioStream(
        track,
        cacheDir.path,
        onProgress: (p, status) {
          if (mounted && _tracks.contains(track)) {
            setState(() {
              track.downloadProgress = p;
            });
          }
        },
      );

      if (mounted && _tracks.contains(track)) {
        setState(() {
          track.downloadedPath = localPath;
          track.isDownloading = false;
          track.downloadProgress = 1.0;
        });
      }
    } catch (e, st) {
      debugPrint('Error downloading audio stream for "${track.title}": $e\n$st');
      if (mounted && _tracks.contains(track)) {
        setState(() {
          _tracks.remove(track);
        });
        _showFaultyLinkDialog(
          url: track.url,
          message: 'This song cannot be downloaded. Enter other link or paste this link again.',
        );
      }
    }
  }

  void _showFaultyLinkDialog({required String url, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.mainBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: AppTheme.errorRed, size: 24),
            SizedBox(width: 10),
            Text(
              'Link Error',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryText,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.primaryText,
                height: 1.4,
              ),
            ),
            if (url.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.secondaryText,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.electricBlue,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _removeTrack(int index) {
    setState(() {
      _tracks.removeAt(index);
    });
  }

  void _moveTrack(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, item);
    });
  }

  Widget _buildDragProxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double animValue = Curves.easeInOut.transform(animation.value);
        final double scale = lerpDouble(1.0, 1.03, animValue)!;
        return Transform.scale(
          scale: scale,
          child: Material(
            elevation: 8,
            color: Colors.transparent,
            shadowColor: AppTheme.electricBlue.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.electricBlue, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.electricBlue.withValues(alpha: 0.2),
                    blurRadius: 18,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }

  Duration get _totalDuration {
    Duration total = Duration.zero;
    for (final t in _tracks) {
      total += t.clipDuration;
    }
    return total;
  }

  void _goToEditingPage() {
    if (_tracks.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.errorRed,
          content: Text('Please add at least 2 songs to sequence before completing.'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MainEditingScreen(initialTracks: _tracks),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAnyDownloading = _tracks.any((t) => t.isDownloading);
    final readyCount = _tracks.where((t) => !t.isDownloading && t.downloadedPath != null).length;
    final canComplete = _tracks.length >= 2 && !isAnyDownloading;

    return Scaffold(
      backgroundColor: AppTheme.mainBackground,
      appBar: AppBar(
        title: const Text('Add Songs'),
      ),
      body: Column(
        children: [
          // Single Input Box and Add Button
          _buildSingleInputSection(),

          const Divider(color: AppTheme.border, height: 1),

          // Sequence Queue Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.queue_music_rounded, size: 20, color: AppTheme.electricBlue),
                    const SizedBox(width: 8),
                    Text(
                      'Sequence Queue (${_tracks.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryText,
                      ),
                    ),
                  ],
                ),
                if (_tracks.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      'Total: ${AudioMergeService.formatDuration(_totalDuration)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.electricBlue,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Sequence List
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _tracks.isEmpty
                  ? KeyedSubtree(
                      key: const ValueKey('empty_sequence'),
                      child: _buildEmptySequenceState(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('reorderable_list'),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          canvasColor: Colors.transparent,
                          shadowColor: Colors.black.withValues(alpha: 0.1),
                        ),
                        child: ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          itemCount: _tracks.length,
                          onReorder: _moveTrack,
                          buildDefaultDragHandles: false,
                          proxyDecorator: _buildDragProxyDecorator,
                          itemBuilder: (context, index) {
                            final track = _tracks[index];
                            return ReorderableDelayedDragStartListener(
                              key: ValueKey(track.id),
                              index: index,
                              child: _buildTrackCard(track, index),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),

      // Bottom Complete Button
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
              onPressed: canComplete ? _goToEditingPage : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.electricBlue,
                disabledBackgroundColor: AppTheme.disabledControl,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: isAnyDownloading
                    ? Row(
                        key: const ValueKey('downloading'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Downloading ($readyCount/${_tracks.length} Ready)...',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ],
                      )
                    : Row(
                        key: ValueKey('complete_${canComplete}_${_tracks.length}'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            canComplete
                                ? 'Complete (${_tracks.length} Songs)'
                                : 'Add at least 2 songs to continue',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          if (canComplete) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Single Input Box with Add Button
  Widget _buildSingleInputSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      color: AppTheme.mainBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  onSubmitted: (_) => _isAdding ? null : _addSong(),
                  decoration: InputDecoration(
                    hintText: 'Paste YouTube, Shorts, or song link...',
                    prefixIcon: const Icon(Icons.link_rounded, color: AppTheme.secondaryText, size: 20),
                    suffixIcon: _urlController.text.isEmpty
                        ? IconButton(
                            icon: const Icon(Icons.content_paste_rounded, color: AppTheme.electricBlue, size: 18),
                            tooltip: 'Paste from clipboard',
                            onPressed: _pasteFromClipboard,
                          )
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded, color: AppTheme.secondaryText, size: 18),
                            onPressed: () {
                              setState(() {
                                _urlController.clear();
                              });
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isAdding ? null : _addSong,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.electricBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isAdding
                        ? const SizedBox(
                            key: ValueKey('adding_spinner'),
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Row(
                            key: ValueKey('add_label'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded, size: 20),
                              SizedBox(width: 4),
                              Text('Add', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'YouTube videos, Shorts, and tracks are automatically downloaded on paste/add.',
            style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
          ),
        ],
      ),
    );
  }

  // Track Card in the Sequence List
  Widget _buildTrackCard(TrackItem track, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Sequence number badge
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppTheme.electricBlue,
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
          const SizedBox(width: 10),

          // Thumbnail with duration overlay
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Image.network(
                  track.thumbnailUrl,
                  width: 60,
                  height: 45,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 60,
                    height: 45,
                    color: AppTheme.secondaryBackground,
                    child: const Icon(Icons.music_note_rounded, size: 20, color: AppTheme.secondaryText),
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
                      AudioMergeService.formatDuration(track.totalDuration),
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
          const SizedBox(width: 12),

          // Song Title and Artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText),
                ),
                if (track.isDownloading) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0.0,
                        end: track.downloadProgress > 0 ? track.downloadProgress : 0.0,
                      ),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      builder: (context, animValue, _) => LinearProgressIndicator(
                        value: track.downloadProgress > 0 ? animValue : null,
                        backgroundColor: AppTheme.secondaryBackground,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.electricBlue),
                        minHeight: 3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Download status badge
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: track.isDownloading
                ? Container(
                    key: const ValueKey('track_downloading'),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.electricBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.electricBlue, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.electricBlue),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${(track.downloadProgress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.electricBlue,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  )
                : track.downloadedPath != null
                    ? Container(
                        key: const ValueKey('track_downloaded'),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 10, color: Color(0xFF10B981)),
                            SizedBox(width: 3),
                            Text(
                              'Downloaded',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('track_idle')),
          ),
          const SizedBox(width: 6),

          // Delete action button
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.errorRed),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Remove',
            onPressed: () => _removeTrack(index),
          ),
        ],
      ),
    );
  }

  // Empty State
  Widget _buildEmptySequenceState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.secondaryBackground,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.border, width: 1.5),
              ),
              child: const Icon(
                Icons.playlist_add_rounded,
                size: 34,
                color: AppTheme.secondaryText,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Songs Added Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryText,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Paste a song link in the box above and tap "Add" to verify and add it to your sequence.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.secondaryText,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
