import 'package:flutter/material.dart';
import '../models/track_item.dart';
import '../services/audio_merge_service.dart';
import '../theme/app_theme.dart';
import 'trim_editor.dart';

class TrackCard extends StatelessWidget {
  final int index;
  final TrackItem track;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final ValueChanged<TrackItem> onTrackChanged;

  const TrackCard({
    super.key,
    required this.index,
    required this.track,
    required this.isFirst,
    required this.isLast,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onTrackChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isTrimmed = track.trimStart > Duration.zero || track.trimEnd < track.totalDuration;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: track.isExpanded ? AppTheme.primary.withValues(alpha: 0.5) : AppTheme.border,
          width: track.isExpanded ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sequence order badge
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Thumbnail with Duration overlay
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      Image.network(
                        track.thumbnailUrl,
                        width: 72,
                        height: 54,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 72,
                          height: 54,
                          color: AppTheme.surface,
                          child: const Icon(Icons.music_video_rounded, color: Colors.white38),
                        ),
                      ),
                      Positioned(
                        bottom: 3,
                        right: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            AudioMergeService.formatDuration(track.totalDuration),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Song Title, Channel, & Trim Summary
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.person_rounded, size: 12, color: Colors.white38),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              track.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Trim Status Badge
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isTrimmed
                                    ? AppTheme.accent.withValues(alpha: 0.15)
                                    : AppTheme.secondaryBackground,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isTrimmed ? AppTheme.accent : AppTheme.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.content_cut_rounded,
                                    size: 11,
                                    color: isTrimmed ? AppTheme.accent : AppTheme.secondaryText,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      isTrimmed
                                          ? '${AudioMergeService.formatDuration(track.trimStart)} - ${AudioMergeService.formatDuration(track.trimEnd)}'
                                          : 'Full (${AudioMergeService.formatDuration(track.totalDuration)})',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: isTrimmed ? FontWeight.bold : FontWeight.normal,
                                        color: isTrimmed ? AppTheme.primaryText : AppTheme.secondaryText,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Quick actions (Reorder & Delete)
                Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isFirst)
                          InkWell(
                            onTap: onMoveUp,
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.white60),
                            ),
                          ),
                        if (!isLast)
                          InkWell(
                            onTap: onMoveDown,
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.white60),
                            ),
                          ),
                        InkWell(
                          onTap: onDelete,
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded, size: 16, color: AppTheme.coral),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Trim toggle button
                    InkWell(
                      onTap: () {
                        track.isExpanded = !track.isExpanded;
                        onTrackChanged(track);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: track.isExpanded ? AppTheme.primary : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              track.isExpanded ? Icons.expand_less_rounded : Icons.tune_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              track.isExpanded ? 'Hide' : 'Trim',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Collapsible Trim Editor
          if (track.isExpanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: TrimEditor(
                track: track,
                onChanged: onTrackChanged,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
