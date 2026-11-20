import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Callbacks delivered from native iOS `AVPictureInPictureController` lifecycle events.
class SystemPipStopEvent {
  const SystemPipStopEvent({
    required this.restoreUi,
    required this.positionMs,
    required this.wasPlaying,
  });

  /// True when the user tapped the restore button on the PiP window to return to the app.
  final bool restoreUi;

  /// Latest playback position reported by the native PiP player (VOD only; 0 for live).
  final int positionMs;

  /// Whether playback was running right before PiP ended.
  final bool wasPlaying;
}

/// Live playback state update emitted by the native iOS PiP `AVPlayer`.
class SystemPipPlaybackState {
  const SystemPipPlaybackState({
    required this.playing,
    required this.positionMs,
    required this.durationMs,
  });

  final bool playing;
  final int positionMs;
  final int durationMs;
}

/// Bridges Flutter playback state with Apple's native `AVPictureInPictureController`
/// (`ios/Runner/SystemPipPlugin.swift`).
///
/// On non-iOS platforms and headless widget tests all calls are safe no-ops.
class SystemPip {
  SystemPip._();
  static final SystemPip instance = SystemPip._();

  static const MethodChannel _channel = MethodChannel('iptv/system_pip');

  bool _initialized = false;

  /// Fired right as native iOS PiP starts (automatic on app leave or manual button).
  /// The app should pause/release mpv immediately to keep a single IPTV connection slot.
  VoidCallback? onWillStart;

  /// Fired once the floating iOS System PiP window is active.
  VoidCallback? onDidStart;

  /// Fired when PiP ends (user tapped restore or closed the floating window).
  ValueChanged<SystemPipStopEvent>? onDidStop;

  /// Fired if the native AVPlayer could not play the stream format (e.g. MKV).
  ValueChanged<String>? onFailed;

  /// Fired when PiP playback play/pause/position changes (e.g. PiP controls or remote commands).
  ValueChanged<SystemPipPlaybackState>? onPlaybackState;

  @visibleForTesting
  static bool? debugSupportedOverride;

  bool get isSupported {
    final override = debugSupportedOverride;
    if (override != null) return override;
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  /// Converts an Xtream live `.ts` URL to its standard Apple HLS `.m3u8` equivalent
  /// so iOS `AVPlayer` can decode it natively in background System PiP.
  static String pipPlayableUrl(String url, {required bool live}) {
    if (!live) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.path.toLowerCase().endsWith('.ts')) {
      final hlsPath = '${uri.path.substring(0, uri.path.length - 3)}.m3u8';
      return uri.replace(path: hlsPath).toString();
    }
    return url;
  }

  void ensureInitialized() {
    if (_initialized || !isSupported) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'willStart':
        onWillStart?.call();
      case 'didStart':
        onDidStart?.call();
      case 'didStop':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        onDidStop?.call(
          SystemPipStopEvent(
            restoreUi: args['restoreUi'] == true,
            positionMs: (args['positionMs'] as num?)?.toInt() ?? 0,
            wasPlaying: args['wasPlaying'] == true,
          ),
        );
      case 'failed':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        onFailed?.call('${args['reason'] ?? 'Bilinmeyen PiP hatası'}');
      case 'playbackState':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        onPlaybackState?.call(
          SystemPipPlaybackState(
            playing: args['playing'] == true,
            positionMs: (args['positionMs'] as num?)?.toInt() ?? 0,
            durationMs: (args['durationMs'] as num?)?.toInt() ?? 0,
          ),
        );
    }
  }

  /// Arms or updates the native iOS PiP controller with current stream metadata.
  /// Opens ZERO network connections until PiP actually starts.
  Future<void> configure({
    required String url,
    required String title,
    required bool live,
    required bool playing,
    required Duration position,
    required Duration duration,
    required bool autoStart,
    String userAgent = 'VLC/3.0.20 LibVLC/3.0.20',
  }) async {
    if (!isSupported) return;
    ensureInitialized();
    try {
      await _channel.invokeMethod<void>('configure', {
        'url': pipPlayableUrl(url, live: live),
        'originalUrl': url,
        'title': title,
        'live': live,
        'playing': playing,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'autoStart': autoStart,
        'userAgent': userAgent,
      });
    } on MissingPluginException {
      // Safe no-op in tests or unsupported runners.
    } catch (_) {
      // Non-fatal: playback continues normally without PiP.
    }
  }

  /// Immediately updates whether leaving the app automatically starts System PiP.
  Future<void> setAutoStart(bool enabled) async {
    if (!isSupported) return;
    ensureInitialized();
    try {
      await _channel.invokeMethod<void>('setAutoStart', {'enabled': enabled});
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }

  /// Manually requests iOS System PiP right now (e.g. from the player top bar icon).
  Future<bool> start() async {
    if (!isSupported) return false;
    ensureInitialized();
    try {
      final ok = await _channel.invokeMethod<bool>('start');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Updates play/pause state on the active native PiP `AVPlayer` (used by Lock Screen / AirPods).
  Future<void> setPlaying(bool playing) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setPlaying', {'playing': playing});
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }

  /// Seeks the active native PiP `AVPlayer` to an absolute VOD position.
  Future<void> seekTo(Duration position) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('seekTo', {
        'positionMs': position.inMilliseconds < 0 ? 0 : position.inMilliseconds,
      });
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }

  /// Skips the active native PiP `AVPlayer` forward or backward by [offset].
  Future<void> skipBy(Duration offset) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('skipBy', {
        'offsetMs': offset.inMilliseconds,
      });
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }

  /// Switches the active native PiP `AVPlayer` to a new channel or episode in place.
  Future<void> switchStream({
    required String url,
    required String title,
    required bool live,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    String userAgent = 'VLC/3.0.20 LibVLC/3.0.20',
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('switchStream', {
        'url': pipPlayableUrl(url, live: live),
        'originalUrl': url,
        'title': title,
        'live': live,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'userAgent': userAgent,
      });
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }

  /// Stops an active System PiP session if one is currently shown.
  Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }

  /// Disarms PiP completely when playback is closed.
  Future<void> clear() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }
}
