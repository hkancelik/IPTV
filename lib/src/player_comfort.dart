import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

/// Temporary playback speed multiplier applied while press-and-holding on VOD playback.
const double holdBoostRate = 2.0;

/// Allowed subtitle sync delay bounds in milliseconds (±30 s).
const int minSubDelayMs = -30000;
const int maxSubDelayMs = 30000;

/// Allowed audio sync delay bounds in milliseconds (±10 s).
const int minAudioDelayMs = -10000;
const int maxAudioDelayMs = 10000;

/// Standard sleep timer duration presets in minutes.
const List<int> sleepTimerPresetsMinutes = <int>[15, 30, 45, 60, 90];

int clampSubDelayMs(int ms) => ms.clamp(minSubDelayMs, maxSubDelayMs);
int clampAudioDelayMs(int ms) => ms.clamp(minAudioDelayMs, maxAudioDelayMs);

/// Formats a millisecond offset for mpv `sub-delay` / `audio-delay` string properties (in seconds).
String mpvDelaySeconds(int ms) => (ms / 1000.0).toStringAsFixed(3);

/// Formats a millisecond audio/subtitle delay offset cleanly for Turkish UI & OSD badges.
///
/// Examples:
/// - `0` → `0 ms`
/// - `50` → `+50 ms`
/// - `-200` → `−200 ms`
/// - `1000` → `+1.0 sn`
/// - `-1250` → `−1.25 sn`
String formatDelayMs(int ms) {
  if (ms == 0) return '0 ms';
  final sign = ms < 0 ? '−' : '+';
  final abs = ms.abs();
  if (abs < 1000) return '$sign$abs ms';
  final secs = abs / 1000.0;
  final decimals = (abs % 100 == 0) ? 1 : 2;
  return '$sign${secs.toStringAsFixed(decimals)} sn';
}

/// Active mode of the player's sleep timer.
enum SleepTimerMode {
  off,
  countdown,
  endOfCurrent,
}

/// Immutable snapshot of the player's sleep timer state.
@immutable
class SleepTimerState {
  const SleepTimerState.off()
      : mode = SleepTimerMode.off,
        remaining = null;

  const SleepTimerState.countdown(Duration this.remaining) : mode = SleepTimerMode.countdown;

  const SleepTimerState.endOfCurrent()
      : mode = SleepTimerMode.endOfCurrent,
        remaining = null;

  final SleepTimerMode mode;
  final Duration? remaining;

  bool get isActive => mode != SleepTimerMode.off;

  /// Compact live readout for top-bar pills and action chips (e.g. `29:45`, `1:15:00`, `Bölüm sonu`).
  String shortLabel({bool isSeries = false}) {
    switch (mode) {
      case SleepTimerMode.off:
        return 'Kapalı';
      case SleepTimerMode.endOfCurrent:
        return isSeries ? 'Bölüm sonu' : 'İçerik sonu';
      case SleepTimerMode.countdown:
        final rem = remaining ?? Duration.zero;
        final safe = rem.isNegative ? Duration.zero : rem;
        final h = safe.inHours;
        final m = safe.inMinutes % 60;
        final s = safe.inSeconds % 60;
        String two(int n) => n.toString().padLeft(2, '0');
        return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
    }
  }

  /// Stable minute-granularity label for native iOS `UIMenu` subtitles (avoids rebuilding UIMenu every second).
  String menuSubtitle({bool isSeries = false}) {
    switch (mode) {
      case SleepTimerMode.off:
        return 'Kapalı';
      case SleepTimerMode.endOfCurrent:
        return isSeries ? 'Bu bölüm bitince' : 'Bu içerik bitince';
      case SleepTimerMode.countdown:
        final rem = remaining ?? Duration.zero;
        if (rem <= Duration.zero) return '< 1 dk kaldı';
        final mins = (rem.inSeconds + 59) ~/ 60;
        if (mins <= 1 && rem.inSeconds < 60) return '< 1 dk kaldı';
        if (mins >= 60) {
          final h = mins ~/ 60;
          final m = mins % 60;
          return m == 0 ? '$h sa kaldı' : '$h sa $m dk kaldı';
        }
        return '$mins dk kaldı';
    }
  }

  /// Detailed live status text shown inside the Sleep Timer picker sheet/dialog.
  String detailLabel({bool isSeries = false}) {
    switch (mode) {
      case SleepTimerMode.off:
        return 'Kapalı';
      case SleepTimerMode.endOfCurrent:
        return isSeries ? 'Bu bölüm bitince durdurulacak' : 'Bu içerik bitince durdurulacak';
      case SleepTimerMode.countdown:
        return '${shortLabel(isSeries: isSeries)} sonra durdurulacak';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepTimerState &&
          other.mode == mode &&
          other.remaining?.inSeconds == remaining?.inSeconds;

  @override
  int get hashCode => Object.hash(mode, remaining?.inSeconds);
}

/// Which touch action a vertical drag on the phone video surface owns.
enum PhoneVerticalGesture {
  none,
  brightness,
  volume,
  minimize,
}

/// Classifies where a vertical touch drag started on the phone video surface.
///
/// - **Landscape**: left 45% → brightness (if supported), right 45% → volume, middle 10% dead strip;
///   outer top/bottom/side edges are reserved for iOS Control Center, Home Indicator, and system swipes.
/// - **Portrait (16:9)**: left 30% → brightness (if supported), right 30% → volume, center 40% → swipe down
///   to minimize to Mini Player (so brightness/volume gestures never collide with minimize!).
PhoneVerticalGesture classifyPhoneVerticalGesture({
  required Offset localPosition,
  required Size size,
  required bool landscape,
  bool brightnessEnabled = true,
  bool controlsVisible = false,
  bool live = false,
}) {
  if (size.width <= 0 || size.height <= 0) return PhoneVerticalGesture.none;
  final dx = localPosition.dx;
  final dy = localPosition.dy;

  final topMargin = landscape ? 32.0 : 10.0;
  final bottomMargin = (controlsVisible && !live)
      ? (landscape ? 56.0 : 44.0)
      : (landscape ? 28.0 : 10.0);
  if (dy < topMargin || dy > size.height - bottomMargin) {
    return PhoneVerticalGesture.none;
  }

  if (landscape) {
    if (dx < 16.0 || dx > size.width - 16.0) return PhoneVerticalGesture.none;
    if (dx < size.width * 0.45) {
      return brightnessEnabled ? PhoneVerticalGesture.brightness : PhoneVerticalGesture.none;
    }
    if (dx > size.width * 0.55) {
      return PhoneVerticalGesture.volume;
    }
    return PhoneVerticalGesture.none;
  }

  if (dx < size.width * 0.30) {
    return brightnessEnabled ? PhoneVerticalGesture.brightness : PhoneVerticalGesture.minimize;
  }
  if (dx > size.width * 0.70) {
    return PhoneVerticalGesture.volume;
  }
  return PhoneVerticalGesture.minimize;
}

/// Applies a vertical drag delta (`dy < 0` moves upward = increases value) into `[0.0, 1.0]`.
double applyVerticalDragDelta({
  required double currentValue,
  required double deltaDy,
  required double viewportHeight,
}) {
  final travel = math.max(150.0, viewportHeight * 0.65);
  return (currentValue - deltaDy / travel).clamp(0.0, 1.0).toDouble();
}
