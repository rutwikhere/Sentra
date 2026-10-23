import 'package:flutter/material.dart';
import 'track_item.dart';

enum SlotStatus { empty, checking, verified, error }

class SongSlot {
  int index;
  final TextEditingController controller;
  SlotStatus status;
  TrackItem? track;
  String? errorMessage;

  SongSlot({
    required this.index,
    TextEditingController? controller,
    this.status = SlotStatus.empty,
    this.track,
    this.errorMessage,
  }) : controller = controller ?? TextEditingController();

  static const List<String> ordinals = [
    'first',
    'second',
    'third',
    'fourth',
    'fifth',
    'sixth',
    'seventh',
    'eighth',
    'ninth',
    'tenth',
    'eleventh',
    'twelfth',
    'thirteenth',
    'fourteenth',
    'fifteenth',
    'sixteenth',
    'seventeenth',
    'eighteenth',
    'nineteenth',
    'twentieth',
  ];

  String get ordinalName {
    if (index >= 0 && index < ordinals.length) {
      return ordinals[index];
    }
    return '${index + 1}th';
  }

  void dispose() {
    controller.dispose();
  }
}
