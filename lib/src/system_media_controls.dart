import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'title_utils.dart';
import 'ui/format.dart';
import 'xtream.dart';

/// Commands delivered from OS media controllers:
/// - iOS: Lock Screen, Control Center, Dynamic Island, AirPods, CarPlay (`MPRemoteCommandCenter`)
/// - Linux: KDE Plasma Media Controller, Lock Screen, `playerctl`, Dynamic Island (D-Bus MPRIS2)
enum SystemMediaAction {
  play,
  pause,
  playPause,
  stop,
  next,
  previous,
  seek,
  seekBy,
  setVolume,
  setRate,
  audioInterruptionBegan,
  audioInterruptionEnded,
  audioBecomingNoisy,
}

/// Incoming remote media command from the host platform.
class SystemMediaCommand {
  const SystemMediaCommand(
    this.action, {
    this.position,
    this.offset,
    this.volume,
    this.rate,
    this.shouldResume = false,
  });

  final SystemMediaAction action;
  final Duration? position;
  final Duration? offset;
  final double? volume;
  final double? rate;
  final bool shouldResume;
}

/// Snapshot of active media metadata and transport capabilities sent to native OS controls.
class SystemMediaState {
  const SystemMediaState({
    required this.trackId,
    required this.title,
    required this.subtitle,
    required this.album,
    required this.artUrl,
    required this.localUrl,
    required this.live,
    required this.playing,
    required this.positionMs,
    required this.durationMs,
    required this.rate,
    required this.volume,
    required this.canGoNext,
    required this.canGoPrevious,
    required this.canSeek,
    required this.skipSeconds,
    this.userAgent = 'VLC/3.0.20 LibVLC/3.0.20',
  });

  /// Valid D-Bus object path (e.g. `/dev/nailhakan/iptv/track/t_1_0`) uniquely identifying this track.
  final String trackId;
  final String title;
  final String subtitle;
  final String album;
  final String artUrl;

  /// Only populated (`file://...`) when playing an offline local file; empty for network streams
  /// so Xtream credentials in stream URLs are never exposed over session D-Bus.
  final String localUrl;
  final bool live;
  final bool playing;
  final int positionMs;
  final int durationMs;
  final double rate;
  final double volume;
  final bool canGoNext;
  final bool canGoPrevious;
  final bool canSeek;
  final int skipSeconds;
  final String userAgent;

  Map<String, dynamic> toMap({bool seeked = false}) => {
        'trackId': trackId,
        'title': title,
        'subtitle': subtitle,
        'album': album,
        'artUrl': artUrl,
        'localUrl': localUrl,
        'live': live,
        'playing': playing,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'rate': rate,
        'volume': volume,
        'canGoNext': canGoNext,
        'canGoPrevious': canGoPrevious,
        'canSeek': canSeek,
        'skipSeconds': skipSeconds,
        'userAgent': userAgent,
        'seeked': seeked,
      };
}

/// Sanitizes an artwork URL so only `http://`, `https://`, or `file://` URLs are passed to native players.
String sanitizeArtworkUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('file://')) {
    return trimmed;
  }
  return '';
}

/// Finds the currently airing EPG programme at [now], or null if none matches.
Programme? activeEpgProgramme(List<Programme> programmes, {DateTime? now}) {
  if (programmes.isEmpty) return null;
  final t = now ?? DateTime.now();
  for (final p in programmes) {
    if (!p.start.isAfter(t) && p.end.isAfter(t)) {
      return p;
    }
  }
  return null;
}

/// Builds a clean, platform-ready [SystemMediaState] for Live TV, Movies, and Series episodes.
SystemMediaState buildSystemMediaState({
  required String trackId,
  required String rawTitle,
  required Kind kind,
  required bool playing,
  required Duration position,
  required Duration duration,
  required bool canGoNext,
  required bool canGoPrevious,
  String logo = '',
  String? group,
  Item? item,
  List<Programme> programmes = const [],
  String? localPath,
  double rate = 1.0,
  double volumePercent = 100.0,
  int skipSeconds = 10,
  String userAgent = 'VLC/3.0.20 LibVLC/3.0.20',
  DateTime? now,
}) {
  final live = kind == Kind.live;
  final rawGroup = (group?.trim().isNotEmpty == true)
      ? group!.trim()
      : (item?.group.trim().isNotEmpty == true ? item!.group.trim() : '');
  final cleanGroup = rawGroup.isEmpty ? '' : groupLabel(rawGroup);

  final String title;
  final String subtitle;
  final String album;
  int positionMs;
  int durationMs;
  final bool canSeek;

  if (live) {
    title = rawTitle.trim().isEmpty ? 'Canlı TV' : rawTitle.trim();
    final epg = activeEpgProgramme(programmes, now: now);
    final epgTitle = epg?.title.trim() ?? '';
    if (epg != null && epgTitle.isNotEmpty) {
      subtitle = epgTitle;
      album = cleanGroup.isNotEmpty ? cleanGroup : 'Canlı TV';
      final t = now ?? DateTime.now();
      final totalMs = epg.end.difference(epg.start).inMilliseconds;
      final elapsedMs = t.difference(epg.start).inMilliseconds;
      durationMs = totalMs > 0 ? totalMs : 0;
      positionMs = durationMs > 0 ? elapsedMs.clamp(0, durationMs) : 0;
    } else {
      subtitle = cleanGroup.isNotEmpty ? cleanGroup : 'Canlı TV';
      album = 'Canlı TV';
      durationMs = 0;
      positionMs = 0;
    }
    canSeek = false;
  } else if (kind == Kind.series) {
    final ep = episodeLabel(rawTitle);
    final stripped = rawTitle.replaceAll(RegExp(r'\s*S\d+\s*E\d+', caseSensitive: false), '').trim();
    final parsed = parseTitle(stripped.isEmpty ? rawTitle : stripped);
    title = parsed.title.isEmpty ? rawTitle.trim() : parsed.title;
    if (ep != null && ep.isNotEmpty) {
      subtitle = ep;
      album = cleanGroup;
    } else {
      subtitle = cleanGroup.isNotEmpty ? cleanGroup : 'Dizi';
      album = '';
    }
    durationMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 0;
    positionMs = position.inMilliseconds > 0
        ? (durationMs > 0 ? position.inMilliseconds.clamp(0, durationMs) : position.inMilliseconds)
        : 0;
    canSeek = durationMs > 0;
  } else {
    final parsed = parseTitle(rawTitle);
    title = parsed.title.isEmpty ? rawTitle.trim() : parsed.title;
    final parts = <String>[
      if (parsed.year != null && parsed.year!.isNotEmpty) parsed.year!,
      if (cleanGroup.isNotEmpty) cleanGroup,
    ];
    subtitle = parts.isNotEmpty ? parts.join(' · ') : 'Film';
    album = '';
    durationMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 0;
    positionMs = position.inMilliseconds > 0
        ? (durationMs > 0 ? position.inMilliseconds.clamp(0, durationMs) : position.inMilliseconds)
        : 0;
    canSeek = durationMs > 0;
  }

  final effectiveArt = sanitizeArtworkUrl(logo.isNotEmpty ? logo : (item?.logo ?? ''));
  final effectiveLocalUrl =
      (localPath != null && localPath.isNotEmpty) ? Uri.file(localPath).toString() : '';

  return SystemMediaState(
    trackId: trackId,
    title: title,
    subtitle: subtitle,
    album: album,
    artUrl: effectiveArt,
    localUrl: effectiveLocalUrl,
    live: live,
    playing: playing,
    positionMs: positionMs,
    durationMs: durationMs,
    rate: live ? 1.0 : rate.clamp(0.25, 4.0).toDouble(),
    volume: (volumePercent / 100.0).clamp(0.0, 1.0).toDouble(),
    canGoNext: canGoNext,
    canGoPrevious: canGoPrevious,
    canSeek: canSeek,
    skipSeconds: skipSeconds.clamp(5, 60),
    userAgent: userAgent,
  );
}

/// Bridges Flutter playback state with native OS system media controls:
/// - **iOS**: `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` (`ios/Runner/MediaControlsPlugin.swift`)
/// - **Linux**: D-Bus MPRIS2 (`linux/runner/mpris_plugin.cc` + `mpris_server.cc`) for KDE Plasma & Dynamic Island
///
/// On unsupported platforms and headless tests, all calls are safe no-ops.
class SystemMediaControls {
  SystemMediaControls._();
  static final SystemMediaControls instance = SystemMediaControls._();

  static const MethodChannel _channel = MethodChannel('iptv/system_media_controls');

  bool _initialized = false;

  /// Fired whenever the OS media center (Lock Screen, AirPods, KDE Plasma, Dynamic Island)
  /// sends a transport or audio-session command.
  ValueChanged<SystemMediaCommand>? onCommand;

  @visibleForTesting
  static bool? debugSupportedOverride;

  bool get isSupported {
    final override = debugSupportedOverride;
    if (override != null) return override;
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isLinux;
  }

  void ensureInitialized() {
    if (_initialized || !isSupported) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @visibleForTesting
  void debugReset() {
    _initialized = false;
    onCommand = null;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final cmd = switch (call.method) {
      'play' => const SystemMediaCommand(SystemMediaAction.play),
      'pause' => const SystemMediaCommand(SystemMediaAction.pause),
      'playPause' => const SystemMediaCommand(SystemMediaAction.playPause),
      'stop' => const SystemMediaCommand(SystemMediaAction.stop),
      'next' => const SystemMediaCommand(SystemMediaAction.next),
      'previous' => const SystemMediaCommand(SystemMediaAction.previous),
      'seek' => SystemMediaCommand(
          SystemMediaAction.seek,
          position: Duration(milliseconds: ((args['positionMs'] as num?)?.toInt() ?? 0).clamp(0, 1 << 50)),
        ),
      'seekBy' => SystemMediaCommand(
          SystemMediaAction.seekBy,
          offset: Duration(milliseconds: (args['offsetMs'] as num?)?.toInt() ?? 0),
        ),
      'setVolume' => SystemMediaCommand(
          SystemMediaAction.setVolume,
          volume: ((args['volume'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0).toDouble(),
        ),
      'setRate' => SystemMediaCommand(
          SystemMediaAction.setRate,
          rate: ((args['rate'] as num?)?.toDouble() ?? 1.0).clamp(0.25, 4.0).toDouble(),
        ),
      'audioInterruptionBegan' => const SystemMediaCommand(SystemMediaAction.audioInterruptionBegan),
      'audioInterruptionEnded' => SystemMediaCommand(
          SystemMediaAction.audioInterruptionEnded,
          shouldResume: args['shouldResume'] == true,
        ),
      'audioBecomingNoisy' => const SystemMediaCommand(SystemMediaAction.audioBecomingNoisy),
      _ => null,
    };
    if (cmd != null) {
      onCommand?.call(cmd);
    }
  }

  /// Publishes the latest playback metadata, status, position, and capabilities to the OS.
  Future<void> update(SystemMediaState state, {bool seeked = false}) async {
    if (!isSupported) return;
    ensureInitialized();
    try {
      await _channel.invokeMethod<void>('update', state.toMap(seeked: seeked));
    } on MissingPluginException {
      // Safe no-op in tests or unsupported runners.
    } catch (_) {
      // Non-fatal: playback continues even if OS media bridge fails.
    }
  }

  /// Fast-path seek notification (emits MPRIS2 `Seeked` and refreshes iOS Lock Screen elapsed time).
  Future<void> notifySeeked(Duration position) async {
    if (!isSupported) return;
    ensureInitialized();
    try {
      await _channel.invokeMethod<void>('seeked', {
        'positionMs': position.inMilliseconds < 0 ? 0 : position.inMilliseconds,
      });
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }

  /// Clears OS media controls (removes Lock Screen Now Playing card & releases Linux MPRIS2 D-Bus name).
  Future<void> clear() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }
}
