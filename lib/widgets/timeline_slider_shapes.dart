import 'package:flutter/material.dart';
import '../models/track_item.dart';

// Modern Jewel Slider Thumb with Drop Shadow and Electric Blue Ring
class ModernSliderThumbShape extends SliderComponentShape {
  final double thumbRadius;
  final Color thumbColor;
  final Color borderColor;
  final double borderWidth;

  const ModernSliderThumbShape({
    this.thumbRadius = 8.5,
    this.thumbColor = Colors.white,
    this.borderColor = const Color(0xFF3867FF),
    this.borderWidth = 2.5,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    canvas.drawCircle(center + const Offset(0, 1.8), thumbRadius, shadowPaint);

    // Thumb Body (White)
    final fillPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, thumbRadius, fillPaint);

    // Primary Border Ring (Electric Blue)
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, thumbRadius - (borderWidth / 2), borderPaint);

    // Center Jewel Accent Dot
    final dotPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 2.2, dotPaint);
  }
}

// Integrated Multi-Song Colored Timeline Track Shape
class MultiSongSliderTrackShape extends RoundedRectSliderTrackShape {
  final List<TrackItem> tracks;
  final Duration totalDuration;
  final List<Color> palette;

  MultiSongSliderTrackShape({
    required this.tracks,
    required this.totalDuration,
    required this.palette,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final Canvas canvas = context.canvas;
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    if (trackRect.isEmpty || trackRect.width <= 0) return;

    final radius = Radius.circular(trackRect.height / 2);
    final rrect = RRect.fromRectAndRadius(trackRect, radius);

    // Subtle base track groove
    final baseBgPaint = Paint()..color = const Color(0xFFF1F4F9);
    canvas.drawRRect(rrect, baseBgPaint);

    if (tracks.isEmpty || totalDuration.inMilliseconds <= 0) {
      return;
    }

    // Clip all colored song segments inside the rounded track rect
    canvas.save();
    canvas.clipRRect(rrect);

    Duration accStart = Duration.zero;
    final totalMs = totalDuration.inMilliseconds.toDouble();

    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      final startMs = accStart.inMilliseconds.toDouble();
      final endMs = startMs + t.clipDuration.inMilliseconds.toDouble();
      accStart += t.clipDuration;

      final segLeft = trackRect.left + (startMs / totalMs) * trackRect.width;
      final segRight = trackRect.left + (endMs / totalMs) * trackRect.width;
      if (segRight <= segLeft) continue;

      final color = palette[i % palette.length];

      if (thumbCenter.dx >= segRight) {
        // Fully played segment: vibrant illuminated color
        final segPaint = Paint()..color = color;
        canvas.drawRect(Rect.fromLTRB(segLeft, trackRect.top, segRight, trackRect.bottom), segPaint);
      } else if (thumbCenter.dx <= segLeft) {
        // Upcoming unplayed segment: clean muted tint (30% opacity)
        final segPaint = Paint()..color = color.withValues(alpha: 0.30);
        canvas.drawRect(Rect.fromLTRB(segLeft, trackRect.top, segRight, trackRect.bottom), segPaint);
      } else {
        // Active segment currently playing:
        // Played portion (before thumb): vibrant illuminated color
        final playedPaint = Paint()..color = color;
        canvas.drawRect(Rect.fromLTRB(segLeft, trackRect.top, thumbCenter.dx, trackRect.bottom), playedPaint);

        // Upcoming portion (after thumb): clean muted tint (30% opacity)
        final unplayedPaint = Paint()..color = color.withValues(alpha: 0.30);
        canvas.drawRect(Rect.fromLTRB(thumbCenter.dx, trackRect.top, segRight, trackRect.bottom), unplayedPaint);

        // Subtle indicator bar at playhead
        final playheadPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(thumbCenter.dx, trackRect.top),
          Offset(thumbCenter.dx, trackRect.bottom),
          playheadPaint,
        );
      }
    }

    // Draw thin segment divider lines between songs
    accStart = Duration.zero;
    final dividerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < tracks.length - 1; i++) {
      accStart += tracks[i].clipDuration;
      final divX = trackRect.left + (accStart.inMilliseconds / totalMs) * trackRect.width;
      if (divX > trackRect.left && divX < trackRect.right) {
        canvas.drawLine(
          Offset(divX, trackRect.top),
          Offset(divX, trackRect.bottom),
          dividerPaint,
        );
      }
    }

    canvas.restore();
  }
}
