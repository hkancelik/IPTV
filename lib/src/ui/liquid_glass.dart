import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'layout.dart';
import 'tokens.dart';

/// Test hook to force native iOS 26 Liquid Glass platform views (`true`) or
/// Flutter fallbacks (`false`). Leave `null` in production.
@visibleForTesting
bool? debugUseNativeLiquidGlass;

int? _cachedIosMajorVersion;

int _iosMajorVersion() {
  if (_cachedIosMajorVersion != null) return _cachedIosMajorVersion!;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || !Platform.isIOS) {
    return _cachedIosMajorVersion = 0;
  }
  final match = RegExp(r'(\d+)\.\d+').firstMatch(Platform.operatingSystemVersion);
  return _cachedIosMajorVersion = match == null ? 0 : (int.tryParse(match.group(1)!) ?? 0);
}

/// Whether this device natively supports Apple's iOS 26+ Liquid Glass UIKit
/// APIs (`UIGlassEffect`, `UIButton.Configuration.glass()`, `UIMenu`, `UITabBarController`).
bool get isNativeLiquidGlassSupported {
  final forced = debugUseNativeLiquidGlass;
  if (forced != null) return forced;
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && _iosMajorVersion() >= 26;
}

/// Maps our Flutter icons to authentic Apple SF Symbols for native iOS 26 buttons.
String? sfSymbolForIcon(IconData icon) {
  if (icon == Icons.chevron_left_rounded) return 'chevron.left';
  if (icon == Icons.chevron_right_rounded) return 'chevron.right';
  if (icon == Icons.more_horiz_rounded) return 'ellipsis';
  if (icon == Icons.tune_rounded) return 'slider.horizontal.3';
  if (icon == Icons.favorite_rounded) return 'heart.fill';
  if (icon == Icons.favorite_border_rounded) return 'heart';
  if (icon == Icons.fullscreen_rounded) return 'arrow.up.left.and.arrow.down.right';
  if (icon == Icons.screen_rotation_rounded) return 'arrow.down.right.and.arrow.up.left';
  if (icon == Icons.aspect_ratio_rounded) return 'aspectratio';
  if (icon == Icons.fit_screen_rounded) return 'rectangle.arrowtriangle.2.outward';
  if (icon == Icons.play_arrow_rounded) return 'play.fill';
  if (icon == Icons.pause_rounded) return 'pause.fill';
  if (icon == Icons.replay_5_rounded) return 'gobackward.5';
  if (icon == Icons.replay_10_rounded) return 'gobackward.10';
  if (icon == Icons.replay_30_rounded) return 'gobackward.30';
  if (icon == Icons.forward_5_rounded) return 'goforward.5';
  if (icon == Icons.forward_10_rounded) return 'goforward.10';
  if (icon == Icons.forward_30_rounded) return 'goforward.30';
  if (icon == Icons.skip_previous_rounded) return 'backward.end.fill';
  if (icon == Icons.skip_next_rounded) return 'forward.end.fill';
  if (icon == Icons.keyboard_arrow_up_rounded) return 'chevron.up';
  if (icon == Icons.keyboard_arrow_down_rounded) return 'chevron.down';
  if (icon == Icons.queue_play_next_rounded) return 'list.bullet';
  if (icon == Icons.audiotrack_rounded) return 'speaker.wave.2';
  if (icon == Icons.subtitles_rounded) return 'captions.bubble';
  if (icon == Icons.speed_rounded) return 'gauge.with.needle';
  if (icon == Icons.schedule_rounded) return 'clock';
  if (icon == Icons.swap_vert_rounded) return 'arrow.up.arrow.down';
  if (icon == Icons.grid_view_rounded) return 'square.grid.2x2';
  if (icon == Icons.home_rounded) return 'house.fill';
  if (icon == Icons.live_tv_rounded) return 'tv.fill';
  if (icon == Icons.movie_rounded) return 'film.fill';
  if (icon == Icons.video_library_rounded) return 'play.square.stack.fill';
  if (icon == Icons.download_rounded) return 'arrow.down.circle';
  if (icon == Icons.download_for_offline_rounded) return 'arrow.down.circle.fill';
  if (icon == Icons.download_done_rounded) return 'checkmark.circle.fill';
  if (icon == Icons.folder_open_rounded) return 'folder';
  if (icon == Icons.delete_outline_rounded) return 'trash';
  if (icon == Icons.bedtime_rounded) return 'moon.fill';
  if (icon == Icons.bedtime_outlined) return 'moon';
  if (icon == Icons.fast_forward_rounded) return 'forward.fill';
  if (icon == Icons.star_rounded) return 'star.fill';
  if (icon == Icons.star_border_rounded) return 'star';
  if (icon == Icons.bookmark_rounded) return 'bookmark.fill';
  if (icon == Icons.bookmark_border_rounded) return 'bookmark';
  if (icon == Icons.collections_bookmark_rounded) return 'books.vertical.fill';
  if (icon == Icons.shuffle_rounded) return 'shuffle';
  return null;
}

/// Visual variant for native `UIButton.Configuration` Liquid Glass controls.
enum NativeGlassStyle {
  glass,
  clearGlass,
  prominentGlass,
  prominentClearGlass,
}

/// Geometric mask for [NativeGlassSurface].
enum NativeGlassShape {
  rect,
  capsule,
  circle,
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_deepEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Hosts Apple's native UIKit `UIVisualEffectView` + `UIGlassEffect` behind [child] on iOS 26+.
///
/// The native backdrop ignores touches so Flutter gestures on [child] (such as
/// precision timeline scrubbing or navigation items) continue undisturbed.
class NativeGlassSurface extends StatefulWidget {
  const NativeGlassSurface({
    super.key,
    required this.child,
    this.clear = false,
    this.shape = NativeGlassShape.rect,
    this.cornerRadius = AppSizes.panelRadius,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.interactive = false,
    this.isDark = true,
  });

  final Widget child;
  final bool clear;
  final NativeGlassShape shape;
  final double cornerRadius;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final bool interactive;
  final bool isDark;

  @override
  State<NativeGlassSurface> createState() => _NativeGlassSurfaceState();
}

class _NativeGlassSurfaceState extends State<NativeGlassSurface> {
  MethodChannel? _channel;
  late Map<String, Object?> _params = _encode();

  Map<String, Object?> _encode() => <String, Object?>{
        'effect': widget.clear ? 'clear' : 'regular',
        'shape': widget.shape.name,
        'cornerRadius': widget.cornerRadius,
        if (widget.tint != null) 'tint': widget.tint!.toARGB32(),
        'interactive': widget.interactive,
        'isDark': widget.isDark,
      };

  @override
  void didUpdateWidget(NativeGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _encode();
    if (!_deepEquals(next, _params)) {
      _params = next;
      _channel?.invokeMethod<void>('update', next);
    }
  }

  @override
  void dispose() {
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: UiKitView(
              viewType: 'iptv/liquid_glass_surface',
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
              creationParams: _params,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: (id) {
                _channel = MethodChannel('iptv/liquid_glass_surface_$id');
              },
            ),
          ),
        ),
        Padding(padding: widget.padding, child: widget.child),
      ],
    );
  }
}

/// Real native iOS 26 interactive Liquid Glass `UIButton` with system stretch,
/// press-and-drag deformation, specular highlights and spring bounce.
///
/// Renders [fallback] on non-iOS-26 platforms and in widget tests.
class NativeGlassButton extends StatefulWidget {
  const NativeGlassButton({
    super.key,
    required this.fallback,
    this.sfSymbol,
    this.label,
    this.tooltip,
    this.style = NativeGlassStyle.glass,
    this.isRound = true,
    this.cornerRadius,
    this.width,
    this.height = 42,
    this.iconSize = 18,
    this.iconWeight = 'semibold',
    this.fontSize = 13.5,
    this.foregroundColor,
    this.tintColor,
    this.isDark = true,
    this.onPressed,
  });

  final Widget fallback;
  final String? sfSymbol;
  final String? label;
  final String? tooltip;
  final NativeGlassStyle style;
  final bool isRound;
  final double? cornerRadius;
  final double? width;
  final double height;
  final double iconSize;
  final String iconWeight;
  final double fontSize;
  final Color? foregroundColor;
  final Color? tintColor;
  final bool isDark;
  final VoidCallback? onPressed;

  @override
  State<NativeGlassButton> createState() => _NativeGlassButtonState();
}

class _NativeGlassButtonState extends State<NativeGlassButton> {
  MethodChannel? _channel;
  late Map<String, Object?> _params = _encode();

  Map<String, Object?> _encode() => <String, Object?>{
        'style': widget.style.name,
        'isRound': widget.isRound,
        if (widget.cornerRadius != null) 'cornerRadius': widget.cornerRadius,
        if (widget.sfSymbol != null) 'sfSymbol': widget.sfSymbol,
        'iconSize': widget.iconSize,
        'iconWeight': widget.iconWeight,
        if (widget.label != null) 'label': widget.label,
        'fontSize': widget.fontSize,
        if (widget.foregroundColor != null) 'foregroundColor': widget.foregroundColor!.toARGB32(),
        if (widget.tintColor != null) 'tintColor': widget.tintColor!.toARGB32(),
        'enabled': widget.onPressed != null,
        'isDark': widget.isDark,
        if (widget.tooltip != null) 'tooltip': widget.tooltip,
      };

  @override
  void didUpdateWidget(NativeGlassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _encode();
    if (!_deepEquals(next, _params)) {
      _params = next;
      _channel?.invokeMethod<void>('update', next);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  void _onCreated(int id) {
    final ch = MethodChannel('iptv/liquid_glass_button_$id');
    _channel = ch;
    ch.setMethodCallHandler((call) async {
      if (call.method == 'pressed' && mounted) {
        widget.onPressed?.call();
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!isNativeLiquidGlassSupported) return widget.fallback;
    final resolvedWidth = widget.width ??
        (widget.isRound
            ? widget.height
            : (widget.label == null ? widget.height : (widget.label!.length * 8.2 + 48).clamp(76.0, 176.0)));
    return SizedBox(
      width: resolvedWidth,
      height: widget.height,
      child: UiKitView(
        viewType: 'iptv/liquid_glass_button',
        creationParams: _params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
      ),
    );
  }
}

/// One action or submenu entry inside a [NativeGlassMenuButton].
@immutable
class GlassMenuItem {
  const GlassMenuItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.sfSymbol,
    this.icon,
    this.selected = false,
    this.enabled = true,
    this.destructive = false,
    this.inline = false,
    this.children = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? sfSymbol;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final bool destructive;
  final bool inline;
  final List<GlassMenuItem> children;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (sfSymbol != null) 'sfSymbol': sfSymbol,
        'selected': selected,
        'enabled': enabled,
        'destructive': destructive,
        'inline': inline,
        if (children.isNotEmpty) 'children': [for (final c in children) c.toMap()],
      };
}

/// Native iOS 26 interactive Liquid Glass menu trigger (`UIButton` + `UIMenu`).
///
/// Pressing, holding, and pulling stretches the Liquid Glass bubble elastically
/// and morphs it directly into Apple's native Liquid Glass floating menu (just
/// like iPhone's native Photos/Video player `•••` menu).
///
/// On non-iOS-26 platforms and in widget tests, renders [fallback] or a glass
/// trigger that opens a structured Kömür bottom sheet menu.
class NativeGlassMenuButton extends StatefulWidget {
  const NativeGlassMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.menuTitle = '',
    this.sfSymbol = 'ellipsis',
    this.fallbackIcon = Icons.more_horiz_rounded,
    this.label,
    this.tooltip = 'Daha fazla',
    this.style = NativeGlassStyle.clearGlass,
    this.isRound = true,
    this.cornerRadius,
    this.width,
    this.height = 42,
    this.iconSize = 18,
    this.iconWeight = 'semibold',
    this.fontSize = 13.5,
    this.foregroundColor = AppColors.ink,
    this.tintColor,
    this.isDark = true,
    this.enabled = true,
    this.onMenuWillShow,
    this.onMenuDidHide,
    this.fallbackBuilder,
  });

  final List<GlassMenuItem> items;
  final ValueChanged<String> onSelected;
  final String menuTitle;
  final String sfSymbol;
  final IconData fallbackIcon;
  final String? label;
  final String tooltip;
  final NativeGlassStyle style;
  final bool isRound;
  final double? cornerRadius;
  final double? width;
  final double height;
  final double iconSize;
  final String iconWeight;
  final double fontSize;
  final Color? foregroundColor;
  final Color? tintColor;
  final bool isDark;
  final bool enabled;
  final VoidCallback? onMenuWillShow;
  final VoidCallback? onMenuDidHide;

  /// Optional custom fallback widget builder for non-iOS-26 platforms.
  final Widget Function(BuildContext context, VoidCallback openMenu)? fallbackBuilder;

  @override
  State<NativeGlassMenuButton> createState() => _NativeGlassMenuButtonState();
}

class _NativeGlassMenuButtonState extends State<NativeGlassMenuButton> {
  MethodChannel? _channel;
  late Map<String, Object?> _params = _encode();

  Map<String, Object?> _encode() => <String, Object?>{
        'style': widget.style.name,
        'isRound': widget.isRound,
        if (widget.cornerRadius != null) 'cornerRadius': widget.cornerRadius,
        'sfSymbol': widget.sfSymbol,
        'iconSize': widget.iconSize,
        'iconWeight': widget.iconWeight,
        if (widget.label != null) 'label': widget.label,
        'fontSize': widget.fontSize,
        if (widget.foregroundColor != null) 'foregroundColor': widget.foregroundColor!.toARGB32(),
        if (widget.tintColor != null) 'tintColor': widget.tintColor!.toARGB32(),
        'enabled': widget.enabled && widget.items.isNotEmpty,
        'isDark': widget.isDark,
        'tooltip': widget.tooltip,
        'menuTitle': widget.menuTitle,
        'items': [for (final item in widget.items) item.toMap()],
      };

  @override
  void didUpdateWidget(NativeGlassMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _encode();
    if (!_deepEquals(next, _params)) {
      _params = next;
      _channel?.invokeMethod<void>('update', next);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  void _onCreated(int id) {
    final ch = MethodChannel('iptv/liquid_glass_menu_$id');
    _channel = ch;
    ch.setMethodCallHandler((call) async {
      if (!mounted) return null;
      switch (call.method) {
        case 'selected':
          final args = call.arguments as Map?;
          final itemId = args?['id'] as String?;
          if (itemId != null && itemId.isNotEmpty) {
            widget.onSelected(itemId);
          }
        case 'menuWillShow':
          widget.onMenuWillShow?.call();
        case 'menuDidHide':
          widget.onMenuDidHide?.call();
      }
      return null;
    });
  }

  Future<void> _openFallbackMenu(BuildContext context, {String? title, List<GlassMenuItem>? entries}) async {
    final list = entries ?? widget.items;
    if (list.isEmpty) return;
    final root = entries == null;
    if (root) widget.onMenuWillShow?.call();
    try {
      final flat = <GlassMenuItem>[];
      for (final item in list) {
        if (item.inline && item.children.isNotEmpty) {
          flat.addAll(item.children);
        } else {
          flat.add(item);
        }
      }
      final picked = await showAppSheet<GlassMenuItem>(
        context: context,
        title: title ?? (widget.menuTitle.isNotEmpty ? widget.menuTitle : widget.tooltip),
        builder: (ctx) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final item in flat)
              Opacity(
                opacity: item.enabled ? 1 : 0.4,
                child: SheetOptionTile(
                  label: item.title,
                  subtitle: item.subtitle,
                  leadingIcon: item.icon,
                  selected: item.selected,
                  trailingText: item.children.isNotEmpty ? '›' : null,
                  onTap: () {
                    if (!item.enabled) return;
                    Navigator.of(ctx).pop(item);
                  },
                ),
              ),
          ],
        ),
      );
      if (picked == null || !context.mounted) return;
      if (picked.children.isNotEmpty) {
        await _openFallbackMenu(context, title: picked.title, entries: picked.children);
      } else {
        widget.onSelected(picked.id);
      }
    } finally {
      if (root) widget.onMenuDidHide?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isNativeLiquidGlassSupported) {
      final resolvedWidth = widget.width ??
          (widget.isRound
              ? widget.height
              : (widget.label == null ? widget.height : (widget.label!.length * 8.2 + 48).clamp(84.0, 176.0)));
      return SizedBox(
        width: resolvedWidth,
        height: widget.height,
        child: UiKitView(
          viewType: 'iptv/liquid_glass_menu',
          creationParams: _params,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onCreated,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
        ),
      );
    }

    if (widget.fallbackBuilder != null) {
      return widget.fallbackBuilder!(context, () => _openFallbackMenu(context));
    }

    final fg = widget.foregroundColor ?? AppColors.ink;
    final bg = widget.style == NativeGlassStyle.clearGlass || widget.style == NativeGlassStyle.prominentClearGlass
        ? AppColors.videoGlass
        : AppColors.surface;
    Widget trigger = Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled && widget.items.isNotEmpty
              ? () {
                  AppHaptics.selection(context);
                  _openFallbackMenu(context);
                }
              : null,
          child: widget.label == null
              ? SizedBox(
                  width: widget.width ?? widget.height,
                  height: widget.height,
                  child: Center(
                    child: Container(
                      width: (widget.height - 4).clamp(32.0, 56.0),
                      height: (widget.height - 4).clamp(32.0, 56.0),
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.glassBorder, width: 1),
                      ),
                      child: Icon(widget.fallbackIcon, size: widget.iconSize, color: fg),
                    ),
                  ),
                )
              : Container(
                  height: widget.height,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(widget.cornerRadius ?? widget.height / 2),
                    border: Border.all(color: AppColors.glassBorder, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.fallbackIcon, size: widget.iconSize - 2, color: fg),
                      const SizedBox(width: 6),
                      Text(widget.label!, style: AppText.label(widget.fontSize, color: fg)),
                    ],
                  ),
                ),
        ),
      ),
    );
    return trigger;
  }
}

/// One tab definition inside [NativeGlassTabBar].
@immutable
class NativeGlassTab {
  const NativeGlassTab({
    required this.id,
    required this.label,
    required this.sfSymbol,
  });

  final String id;
  final String label;
  final String sfSymbol;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'label': label,
        'sfSymbol': sfSymbol,
      };
}

/// Native iOS 26 floating Liquid Glass bottom tab bar backed by Apple's
/// real `UITabBarController` and `UITab` APIs (`iptv/liquid_glass_tab_bar`).
class NativeGlassTabBar extends StatefulWidget {
  const NativeGlassTabBar({
    super.key,
    required this.tabs,
    required this.selectedId,
    required this.onSelected,
    this.onReselect,
    this.tintColor = AppColors.accent,
    this.isDark = true,
  });

  final List<NativeGlassTab> tabs;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onReselect;
  final Color tintColor;
  final bool isDark;

  @override
  State<NativeGlassTabBar> createState() => _NativeGlassTabBarState();
}

class _NativeGlassTabBarState extends State<NativeGlassTabBar> {
  MethodChannel? _channel;
  late Map<String, Object?> _params = _encode();

  Map<String, Object?> _encode() => <String, Object?>{
        'tabs': [for (final t in widget.tabs) t.toMap()],
        'selectedId': widget.selectedId,
        'tintColor': widget.tintColor.toARGB32(),
        'isDark': widget.isDark,
      };

  @override
  void didUpdateWidget(NativeGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _encode();
    if (!_deepEquals(next, _params)) {
      _params = next;
      _channel?.invokeMethod<void>('update', next);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  void _onCreated(int id) {
    final ch = MethodChannel('iptv/liquid_glass_tab_bar_$id');
    _channel = ch;
    ch.setMethodCallHandler((call) async {
      if (!mounted) return null;
      final args = call.arguments as Map?;
      final tabId = args?['id'] as String?;
      if (tabId == null || tabId.isEmpty) return null;
      if (call.method == 'selected') {
        widget.onSelected(tabId);
      } else if (call.method == 'reselected') {
        widget.onReselect?.call(tabId);
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final height = (bottomInset + 84).clamp(92.0, 140.0);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: UiKitView(
        viewType: 'iptv/liquid_glass_tab_bar',
        creationParams: _params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
      ),
    );
  }
}
