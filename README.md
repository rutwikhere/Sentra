# 🎵 Sentra

> **Seamless YouTube Song Sequencer, Precision Audio Trimmer & Mix Studio** built with Flutter.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows-brightgreen)](#)

**Sentra** is an open-source mobile and desktop application that allows creators and music enthusiasts to paste YouTube links and Shorts, arrange them in a custom sequence, trim each track with millisecond precision, preview the mix with an interactive multi-song timeline player, and stitch them into a seamless studio master `.mp3` or `.mp4` music video.

---

## ✨ Features

- 🔗 **Universal YouTube Stream Extraction**: Paste any standard YouTube link, mobile link, youtu.be shortlink, or YouTube Shorts URL. Sentra automatically extracts high-bitrate audio, thumbnail artwork, artist, and duration.
- ⚡ **Automated Pre-Download**: Tracks automatically download in the background as you build your queue, complete with smooth animated progress indicators.
- 🔀 **Drag-and-Drop Sequence Arranging**: Easily reorder songs in your mix with intuitive reorderable cards and smooth reorder feedback.
- ✂️ **Precision Song Trimming**:
  - Independent timeline scrubber per song.
  - Formatted `mm:ss` timestamp input boxes for manual timecode entry.
  - Interactive play/pause preview strictly isolated to the song's trim boundaries.
  - Instant clip duration recalculation.
- 🎚️ **Master Mix Timeline Player**:
  - Custom multi-color slider track where each song is rendered with a distinct color segment matching its sequence badge.
  - Dedicated play/pause toggle situated directly on the left of the slider.
  - Dynamic live timer displaying `${current_position} / ${total_mix_duration}`.
- ⚙️ **High-Performance Audio Pipeline**:
  - Powered by **FFmpeg Kit** for precision trimming, audio normalization, and concatenation.
  - 4-stage visual mastering pipeline with animated progress tracking.
- 📲 **Native Device Downloads & Sharing**:
  - **Direct Storage Downloads**: Native Android `MediaStore` integration saves MP3s directly to the device's public `Music/Sentra` or `Download` directories with media indexing.
  - **Direct WhatsApp Sharing**: One-tap direct share to WhatsApp chats and status.
  - **Universal System Share**: Share mixes via Telegram, Discord, Drive, Email, or Bluetooth.
- 🎬 **Video Export with Sentra Visual Art**:
  - Generates full HD MP4 music videos combining your merged audio with official Sentra artwork, ready for Instagram Reels, YouTube Shorts, or WhatsApp Status.

---

## 🏗️ Architecture & Project Structure

```
lib/
├── main.dart                      # Application entry point & theme setup
├── models/
│   └── track_item.dart            # Track metadata, trim boundaries & download state
├── screens/
│   ├── welcome_screen.dart        # Hero landing screen with breathing logo & entrance animations
│   ├── song_input_screen.dart     # Queue builder with clipboard paste & background downloads
│   ├── main_editing_screen.dart   # Sequence reordering, trim dialog & master timeline player
│   └── download_export_screen.dart# 4-stage mastering pipeline, native export & video generator
├── services/
│   ├── audio_merge_service.dart   # FFmpeg trimming, concatenation & duration formatting
│   ├── youtube_service.dart       # YouTubeExplode stream extraction & Shorts parsing
│   └── share_service.dart         # Native share sheet & WhatsApp direct intent
├── theme/
│   └── app_theme.dart             # White theme, Electric Blue accents & Material 3 transitions
└── widgets/
    └── timeline_slider_shapes.dart# Custom MultiSongSliderTrackShape & ModernSliderThumbShape
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.24+ recommended)
- Android Studio / VS Code with Flutter extension
- Connected Android device or Windows Desktop

### Installation & Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/rutwikhere/Sentra.git
   cd Sentra
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run unit & widget tests:**
   ```bash
   flutter test
   ```

4. **Launch on your device:**
   ```bash
   flutter run
   ```

5. **Build release APK (Android):**
   ```bash
   flutter build apk --release
   ```

---

## 🧪 Testing

Sentra includes unit and widget test suites covering:
- Timecode formatting and parsing (`mm:ss`, `hh:mm:ss`).
- Clip duration and accumulation calculations.
- YouTube and YouTube Shorts URL parsing (including query parameter stripping and youtu.be shortlinks).
- Welcome screen and UI smoke tests.

Run tests at any time using:
```bash
flutter test
```

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).
