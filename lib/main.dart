import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/track_item.dart';
import 'services/audio_merge_service.dart';
import 'services/youtube_service.dart';
import 'theme/app_theme.dart';
import 'widgets/merge_progress_dialog.dart';
import 'widgets/merged_player_sheet.dart';
import 'widgets/track_card.dart';

import 'screens/welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SentraApp());
}

class SentraApp extends StatelessWidget {
  const SentraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sentra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.whiteTheme,
      home: const WelcomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final YouTubeService _ytService = YouTubeService();
  final AudioMergeService _mergeService = AudioMergeService();

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _mixTitleController = TextEditingController(text: 'Sentra_Mix');

  final List<TrackItem> _tracks = [];
  bool _isLoadingTrack = false;
  int _crossfadeSeconds = 0;
  int _bitrateKbps = 192;

  // Sample royalty-free YouTube videos for instant 1-tap testing
  final List<Map<String, String>> _sampleTracks = [
    {
      'title': 'Lofi Chill Study',
      'url': 'https://www.youtube.com/watch?v=jfKfPfyJRdk',
    },
    {
      'title': 'Acoustic Guitar Breeze',
      'url': 'https://www.youtube.com/watch?v=5qap5aO4i9A',
    },
    {
      'title': 'Synthwave Dreams',
      'url': 'https://www.youtube.com/watch?v=4xDzrJKXOOY',
    },
  ];

  @override
  void dispose() {
    _ytService.dispose();
    _urlController.dispose();
    _mixTitleController.dispose();
    super.dispose();
  }

  // Paste from clipboard
  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _urlController.text = data.text!.trim();
      });
    }
  }

  // Add track by URL
  Future<void> _addTrack(String url) async {
    if (url.trim().isEmpty) return;

    setState(() {
      _isLoadingTrack = true;
    });

    try {
      final track = await _ytService.fetchTrackInfo(url.trim());
      setState(() {
        _tracks.add(track);
        _urlController.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.surfaceLight,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Added "${track.title}" to sequence'),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.coral,
            content: Text('Failed to load track: ${e.toString().replaceAll('Exception: ', '')}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrack = false;
        });
      }
    }
  }

  // Reorder tracks
  void _moveTrack(int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex >= _tracks.length) return;
    setState(() {
      final item = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, item);
    });
  }

  // Remove track
  void _removeTrack(int index) {
    setState(() {
      _tracks.removeAt(index);
    });
  }

  // Calculate total merged duration
  Duration get _totalMergedDuration {
    Duration total = Duration.zero;
    for (final t in _tracks) {
      total += t.clipDuration;
    }
    if (_crossfadeSeconds > 0 && _tracks.length > 1) {
      final deduction = Duration(seconds: _crossfadeSeconds * (_tracks.length - 1));
      if (total > deduction) {
        total -= deduction;
      }
    }
    return total;
  }

  // Merge and generate MP3
  Future<void> _mergeAndExport() async {
    if (_tracks.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.amber,
          content: Text('Please add at least 2 YouTube songs to merge.'),
        ),
      );
      return;
    }

    double progress = 0.0;
    String status = 'Initializing download pipeline...';
    StateSetter? dialogSetState;

    // Show progress modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          dialogSetState = setDialogState;
          return MergeProgressDialog(
            progress: progress,
            status: status,
          );
        },
      ),
    );

    try {
      final cacheDir = await _mergeService.getWorkingDir();

      // 1. Download YouTube audio streams
      for (int i = 0; i < _tracks.length; i++) {
        final track = _tracks[i];
        final trackStep = (i / _tracks.length) * 0.4; // 0% to 40%

        dialogSetState?.call(() {
          progress = trackStep;
          status = 'Downloading audio ${i + 1}/${_tracks.length}: "${track.title}"...';
        });

        final rawPath = await _ytService.downloadAudioStream(
          track,
          cacheDir.path,
          onProgress: (p, s) {
            dialogSetState?.call(() {
              progress = trackStep + (p * (0.4 / _tracks.length));
              status = 'Track ${i + 1}/${_tracks.length}: $s';
            });
          },
        );
        track.downloadedPath = rawPath;
      }

      // 2. Trim and Merge tracks with FFmpeg
      final finalMp3Path = await _mergeService.mergeTracks(
        _tracks,
        mixTitle: _mixTitleController.text.trim().isNotEmpty
            ? _mixTitleController.text.trim()
            : 'Sentra_Mix',
        bitrateKbps: _bitrateKbps,
        crossfadeSeconds: _crossfadeSeconds,
        onProgress: (p, s) {
          dialogSetState?.call(() {
            progress = p;
            status = s;
          });
        },
      );

      // Close progress dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Open Player & Share Sheet
      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => MergedPlayerSheet(
            filePath: finalMp3Path,
            mixTitle: _mixTitleController.text.trim(),
            totalTracks: _tracks.length,
          ),
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: AppTheme.coral),
                SizedBox(width: 8),
                Text('Processing Error'),
              ],
            ),
            content: Text(
              e.toString().replaceAll('Exception: ', ''),
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: AppTheme.accent)),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/applogo.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ShaderMask(
              shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
              child: const Text(
                'SENTRA',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_tracks.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _tracks.clear();
                });
              },
              icon: const Icon(Icons.clear_all_rounded, size: 18, color: Colors.white60),
              label: const Text('Clear All', style: TextStyle(color: Colors.white60, fontSize: 13)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // URL Input Card
          _buildInputSection(),

          // Preset sample tracks chips
          _buildSamplePresets(),

          const Divider(color: AppTheme.border, height: 1),

          // Playlist Header & Info
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.queue_music_rounded, size: 18, color: AppTheme.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Sequence Queue (${_tracks.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (_tracks.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      'Total Mix: ${AudioMergeService.formatDuration(_totalMergedDuration)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Tracks List
          Expanded(
            child: _tracks.isEmpty
                ? _buildEmptyState()
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: _tracks.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }
                        final item = _tracks.removeAt(oldIndex);
                        _tracks.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final track = _tracks[index];
                      return TrackCard(
                        key: ValueKey(track.id),
                        index: index,
                        track: track,
                        isFirst: index == 0,
                        isLast: index == _tracks.length - 1,
                        onMoveUp: () => _moveTrack(index, index - 1),
                        onMoveDown: () => _moveTrack(index, index + 1),
                        onDelete: () => _removeTrack(index),
                        onTrackChanged: (updated) {
                          setState(() {
                            _tracks[index] = updated;
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),

      // Bottom Merge Action Bar
      bottomSheet: _buildBottomActionBar(),
    );
  }

  // URL Input Section
  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: AppTheme.background,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              onSubmitted: (val) => _addTrack(val),
              decoration: InputDecoration(
                hintText: 'Paste YouTube song URL...',
                prefixIcon: const Icon(Icons.link_rounded, color: Colors.white54, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded, color: AppTheme.accent, size: 18),
                  tooltip: 'Paste from clipboard',
                  onPressed: _pasteClipboard,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _isLoadingTrack ? null : () => _addTrack(_urlController.text),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
            child: _isLoadingTrack
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    children: [
                      Icon(Icons.add_rounded, size: 20),
                      SizedBox(width: 4),
                      Text('Add'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // Sample Presets Bar
  Widget _buildSamplePresets() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      color: AppTheme.background,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text(
              'Quick Try: ',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
            ..._sampleTracks.map(
              (sample) => Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ActionChip(
                  label: Text(sample['title']!, style: const TextStyle(fontSize: 11)),
                  avatar: const Icon(Icons.play_circle_outline_rounded, size: 14, color: AppTheme.accent),
                  backgroundColor: AppTheme.surface,
                  side: const BorderSide(color: AppTheme.border),
                  onPressed: () => _addTrack(sample['url']!),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Empty State Widget
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/applogo.png',
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.border, width: 2),
                    ),
                    child: const Icon(
                      Icons.playlist_add_rounded,
                      size: 44,
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No Songs in Sequence',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Paste YouTube video URLs above or tap any of the "Quick Try" sample presets to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white60, height: 1.5),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.accent),
                  foregroundColor: AppTheme.accent,
                ),
                onPressed: () {
                  _addTrack(_sampleTracks[0]['url']!);
                  Future.delayed(const Duration(milliseconds: 300), () {
                    _addTrack(_sampleTracks[1]['url']!);
                  });
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('Add 2 Demo Songs to Mix'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Bottom Action Bar
  Widget _buildBottomActionBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(top: BorderSide(color: AppTheme.border, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Options row (Bitrate & Crossfade)
            Row(
              children: [
                // Crossfade selector
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Fade:', style: TextStyle(fontSize: 11, color: Colors.white60)),
                        DropdownButton<int>(
                          value: _crossfadeSeconds,
                          isDense: true,
                          underline: const SizedBox(),
                          dropdownColor: AppTheme.surfaceLight,
                          style: const TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('None')),
                            DropdownMenuItem(value: 1, child: Text('1s')),
                            DropdownMenuItem(value: 2, child: Text('2s')),
                            DropdownMenuItem(value: 3, child: Text('3s')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _crossfadeSeconds = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Bitrate selector
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Quality:', style: TextStyle(fontSize: 11, color: Colors.white60)),
                        DropdownButton<int>(
                          value: _bitrateKbps,
                          isDense: true,
                          underline: const SizedBox(),
                          dropdownColor: AppTheme.surfaceLight,
                          style: const TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 192, child: Text('192 kbps')),
                            DropdownMenuItem(value: 320, child: Text('320 kbps')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _bitrateKbps = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Large Glowing Merge Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _tracks.length >= 2 ? _mergeAndExport : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  disabledBackgroundColor: AppTheme.surfaceLight,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.merge_type_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _tracks.length < 2
                          ? 'Add at least 2 songs to merge'
                          : 'Merge ${_tracks.length} Songs & Export MP3',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
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
    );
  }
}
