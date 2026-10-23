import 'package:flutter_test/flutter_test.dart';
import 'package:sentra/services/youtube_service.dart';

void main() {
  group('YouTube Shorts & Video ID parsing tests', () {
    final ytService = YouTubeService();

    test('Parses standard YouTube Shorts URL', () {
      const url = 'https://www.youtube.com/shorts/507sO6oZgY8';
      expect(ytService.extractVideoId(url), '507sO6oZgY8');
    });

    test('Parses YouTube Shorts with tracking parameters', () {
      const url = 'https://youtube.com/shorts/dQw4w9WgXcQ?feature=share&si=abc123';
      expect(ytService.extractVideoId(url), 'dQw4w9WgXcQ');
    });

    test('Parses mobile YouTube Shorts link', () {
      const url = 'https://m.youtube.com/shorts/jfKfPfyJRdk';
      expect(ytService.extractVideoId(url), 'jfKfPfyJRdk');
    });

    test('Parses youtu.be shortlinks', () {
      const url = 'https://youtu.be/5qap5aO4i9A?si=xyz';
      expect(ytService.extractVideoId(url), '5qap5aO4i9A');
    });

    test('Parses standard watch URL', () {
      const url = 'https://www.youtube.com/watch?v=4xDzrJKXOOY';
      expect(ytService.extractVideoId(url), '4xDzrJKXOOY');
    });
  });
}
