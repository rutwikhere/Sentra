import 'package:flutter_test/flutter_test.dart';
import 'package:sentra/models/track_item.dart';
import 'package:sentra/services/audio_merge_service.dart';

void main() {
  group('AudioMergeService and Time calculations', () {
    test('formatDuration formats mm:ss and hh:mm:ss properly', () {
      expect(AudioMergeService.formatDuration(const Duration(seconds: 45)), '00:45');
      expect(AudioMergeService.formatDuration(const Duration(minutes: 3, seconds: 12)), '03:12');
      expect(AudioMergeService.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
    });

    test('parseTimeCode parses various timecode formats', () {
      expect(AudioMergeService.parseTimeCode('45'), const Duration(seconds: 45));
      expect(AudioMergeService.parseTimeCode('02:30'), const Duration(minutes: 2, seconds: 30));
      expect(AudioMergeService.parseTimeCode('01:15:20'), const Duration(hours: 1, minutes: 15, seconds: 20));
      expect(AudioMergeService.parseTimeCode('invalid'), isNull);
    });

    test('TrackItem clip duration calculation', () {
      final track = TrackItem(
        id: '1',
        url: 'https://youtube.com/watch?v=dQw4w9WgXcQ',
        videoId: 'dQw4w9WgXcQ',
        title: 'Song 1',
        author: 'Artist',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        totalDuration: const Duration(minutes: 3),
        trimStart: const Duration(seconds: 15),
        trimEnd: const Duration(seconds: 45),
      );

      expect(track.clipDuration, const Duration(seconds: 30));
    });
  });
}
