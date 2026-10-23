import 'package:flutter/material.dart';
import '../models/track_item.dart';
import '../services/audio_merge_service.dart';
import '../theme/app_theme.dart';

class TrimEditor extends StatefulWidget {
  final TrackItem track;
  final ValueChanged<TrackItem> onChanged;

  const TrimEditor({
    super.key,
    required this.track,
    required this.onChanged,
  });

  @override
  State<TrimEditor> createState() => _TrimEditorState();
}

class _TrimEditorState extends State<TrimEditor> {
  late double _startSec;
  late double _endSec;
  late double _maxSec;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  @override
  void didUpdateWidget(covariant TrimEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.trimStart != widget.track.trimStart ||
        oldWidget.track.trimEnd != widget.track.trimEnd ||
        oldWidget.track.totalDuration != widget.track.totalDuration) {
      _initValues();
    }
  }

  void _initValues() {
    _maxSec = widget.track.totalDuration.inSeconds.toDouble();
    if (_maxSec < 1) _maxSec = 60.0;

    _startSec = widget.track.trimStart.inSeconds.toDouble().clamp(0.0, _maxSec - 1);
    _endSec = widget.track.trimEnd.inSeconds.toDouble().clamp(_startSec + 1, _maxSec);
  }

  void _updateTrim(double newStart, double newEnd) {
    if (newStart >= newEnd) return;
    setState(() {
      _startSec = newStart.clamp(0.0, _maxSec - 1);
      _endSec = newEnd.clamp(_startSec + 1, _maxSec);
    });

    widget.track.trimStart = Duration(seconds: _startSec.round());
    widget.track.trimEnd = Duration(seconds: _endSec.round());
    widget.onChanged(widget.track);
  }

  void _adjustStart(int deltaSeconds) {
    final next = (_startSec + deltaSeconds).clamp(0.0, _endSec - 1);
    _updateTrim(next, _endSec);
  }

  void _adjustEnd(int deltaSeconds) {
    final next = (_endSec + deltaSeconds).clamp(_startSec + 1, _maxSec);
    _updateTrim(_startSec, next);
  }

  void _applyPreset(String preset) {
    switch (preset) {
      case 'Full':
        _updateTrim(0.0, _maxSec);
        break;
      case 'First 30s':
        _updateTrim(0.0, (_maxSec < 30 ? _maxSec : 30.0));
        break;
      case 'First 60s':
        _updateTrim(0.0, (_maxSec < 60 ? _maxSec : 60.0));
        break;
      case 'Chorus (Middle)':
        final mid = _maxSec / 2;
        final start = (mid - 20).clamp(0.0, _maxSec - 10);
        final end = (mid + 20).clamp(start + 10, _maxSec);
        _updateTrim(start, end);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final startDur = Duration(seconds: _startSec.round());
    final endDur = Duration(seconds: _endSec.round());
    final clipDur = Duration(seconds: (_endSec - _startSec).round());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with clip duration info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.content_cut_rounded, size: 16, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  const Text(
                    'Song Trimming',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Clip: ${AudioMergeService.formatDuration(clipDur)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Visual Range Slider
          RangeSlider(
            values: RangeValues(_startSec, _endSec),
            min: 0.0,
            max: _maxSec,
            divisions: _maxSec.toInt() > 0 ? _maxSec.toInt() : 1,
            labels: RangeLabels(
              AudioMergeService.formatDuration(startDur),
              AudioMergeService.formatDuration(endDur),
            ),
            activeColor: AppTheme.accent,
            inactiveColor: AppTheme.border,
            onChanged: (RangeValues values) {
              _updateTrim(values.start, values.end);
            },
          ),

          // Precise Time Control Counters
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Start controls
              _buildTimeControl(
                label: 'START',
                timeText: AudioMergeService.formatDuration(startDur),
                onMinus: () => _adjustStart(-1),
                onPlus: () => _adjustStart(1),
              ),
              // End controls
              _buildTimeControl(
                label: 'END',
                timeText: AudioMergeService.formatDuration(endDur),
                onMinus: () => _adjustEnd(-1),
                onPlus: () => _adjustEnd(1),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Quick Presets
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text(
                  'Presets: ',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                _buildPresetChip('Full'),
                _buildPresetChip('First 30s'),
                _buildPresetChip('First 60s'),
                _buildPresetChip('Chorus (Middle)'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeControl({
    required String label,
    required String timeText,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white38,
            ),
          ),
          InkWell(
            onTap: onMinus,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.remove, size: 14, color: Colors.white70),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              timeText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
            ),
          ),
          InkWell(
            onTap: onPlus,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.add, size: 14, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: () => _applyPreset(label),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
