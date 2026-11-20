import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges touch player gestures with native iOS hardware brightness and system output volume
/// (`ios/Runner/DeviceControlsPlugin.swift`).
///
/// On non-iOS platforms (and in headless tests without overrides), brightness calls are safe no-ops
/// and volume calls report `false` so the player cleanly falls back to mpv software volume.
class PlayerDeviceControls {
  PlayerDeviceControls._();
  static final PlayerDeviceControls instance = PlayerDeviceControls._();

  static const MethodChannel _channel = MethodChannel('iptv/device_controls');

  @visibleForTesting
  static bool? debugBrightnessSupportedOverride;

  @visibleForTesting
  static bool? debugSystemVolumeSupportedOverride;

  bool get isBrightnessSupported {
    final override = debugBrightnessSupportedOverride;
    if (override != null) return override;
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  bool get isSystemVolumeSupported {
    final override = debugSystemVolumeSupportedOverride;
    if (override != null) return override;
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  Future<double> getBrightness({double fallback = 0.5}) async {
    if (!isBrightnessSupported) return fallback.clamp(0.0, 1.0).toDouble();
    try {
      final raw = await _channel.invokeMethod<num>('getBrightness');
      if (raw != null && raw.isFinite) {
        return raw.toDouble().clamp(0.0, 1.0).toDouble();
      }
    } on MissingPluginException {
      // Safe fallback in tests or unsupported hosts.
    } catch (_) {}
    return fallback.clamp(0.0, 1.0).toDouble();
  }

  Future<void> setBrightness(double value) async {
    if (!isBrightnessSupported) return;
    final clamped = value.clamp(0.0, 1.0).toDouble();
    try {
      await _channel.invokeMethod<void>('setBrightness', {'value': clamped});
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }

  Future<double> getVolume({required double fallbackPlayerVolume}) async {
    final fallback = (fallbackPlayerVolume / 100.0).clamp(0.0, 1.0).toDouble();
    if (!isSystemVolumeSupported) return fallback;
    try {
      final raw = await _channel.invokeMethod<num>('getVolume');
      if (raw != null && raw.isFinite) {
        return raw.toDouble().clamp(0.0, 1.0).toDouble();
      }
    } on MissingPluginException {
      // Safe fallback.
    } catch (_) {}
    return fallback;
  }

  /// Attempts to set native iOS system output volume.
  ///
  /// Returns `true` when the system volume slider was updated natively, or `false` when the caller
  /// should fall back to adjusting mpv software volume (e.g. non-iOS or iOS Simulator).
  Future<bool> setVolume(double value) async {
    if (!isSystemVolumeSupported) return false;
    final clamped = value.clamp(0.0, 1.0).toDouble();
    try {
      final ok = await _channel.invokeMethod<bool>('setVolume', {'value': clamped});
      return ok == true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Releases the off-screen iOS `MPVolumeView` shortly after a volume swipe ends so hardware
  /// volume buttons resume showing the standard iOS HUD.
  Future<void> endVolumeGesture() async {
    if (!isSystemVolumeSupported) return;
    try {
      await _channel.invokeMethod<void>('endVolumeGesture');
    } on MissingPluginException {
      // Safe no-op.
    } catch (_) {}
  }
}
