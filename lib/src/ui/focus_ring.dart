import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Focus, hover and press handling for every clickable item. Draws a 3 px ink ring 4 px outside the item (or
/// inside it for full-width rows) plus a lifted shadow, without changing the layout. Never wrap a FocusRing in
/// a ClipRRect: the ring is painted outside its bounds, clip the picture inside instead.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    this.child,
    this.builder,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.onFocusChange,
    this.onHoverChange,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.radius = AppSizes.cardRadius,
    this.inside = false,
    this.lift = true,
    this.hoverColor,
    this.tooltip,
    this.semanticLabel,
    this.selected,
  }) : assert(child != null || builder != null);

  final Widget? child;
  final Widget Function(BuildContext context, bool focused, bool hovered)? builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;
  final ValueChanged<bool>? onFocusChange;
  final ValueChanged<bool>? onHoverChange;
  final FocusNode? focusNode;
  final bool autofocus;

  /// false: neither focusable nor clickable.
  final bool enabled;
  final double radius;

  /// true: the ring is drawn inside and the ground turns surfaceAlt (full-width rows).
  final bool inside;

  /// true: the focused item gets AppShadows.lift.
  final bool lift;
  final Color? hoverColor;
  final String? tooltip;
  final String? semanticLabel;

  /// Reported to semantics (tabs, segmented choices, list items).
  final bool? selected;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  void _activate() {
    if (widget.enabled) widget.onTap?.call();
  }

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _activate()),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => _activate()),
  };

  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  };

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final content = w.builder?.call(context, _focused, _hovered) ?? w.child!;
    final ground = w.inside && (_focused || _hovered)
        ? AppColors.surfaceAlt
        : (_hovered && w.hoverColor != null ? w.hoverColor : null);
    Widget result = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(w.radius),
        boxShadow: _focused && w.lift && !w.inside ? AppShadows.lift : const [],
      ),
      child: content,
    );
    result = CustomPaint(foregroundPainter: _RingPainter(on: _focused, radius: w.radius, inside: w.inside), child: result);
    result = AnimatedScale(scale: _pressed ? 0.98 : 1, duration: const Duration(milliseconds: 120), child: result);
    final clickable = w.enabled && (w.onTap != null || w.onLongPress != null || w.onSecondaryTapUp != null);
    result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: w.enabled ? w.onTap : null,
      onLongPress: w.enabled ? w.onLongPress : null,
      onSecondaryTapUp: w.enabled ? w.onSecondaryTapUp : null,
      onTapDown: clickable ? (_) => setState(() => _pressed = true) : null,
      onTapUp: clickable ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: clickable ? () => setState(() => _pressed = false) : null,
      child: result,
    );
    result = FocusableActionDetector(
      focusNode: w.focusNode,
      autofocus: w.autofocus,
      enabled: w.enabled,
      actions: _actions,
      shortcuts: _shortcuts,
      mouseCursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onShowFocusHighlight: (_) {},
      onFocusChange: (f) {
        setState(() => _focused = f);
        w.onFocusChange?.call(f);
      },
      onShowHoverHighlight: (h) {
        setState(() => _hovered = h);
        w.onHoverChange?.call(h);
      },
      child: Semantics(button: w.onTap != null, enabled: w.enabled, selected: w.selected, label: w.semanticLabel, child: result),
    );
    if (w.tooltip != null) result = Tooltip(message: w.tooltip!, waitDuration: const Duration(milliseconds: 500), child: result);
    return result;
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.on, required this.radius, required this.inside});

  final bool on;
  final double radius;
  final bool inside;

  @override
  void paint(Canvas canvas, Size size) {
    if (!on) return;
    const half = AppSizes.ring / 2;
    final grow = inside ? -half : AppSizes.ringGap + half;
    final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).inflate(grow);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppSizes.ring
        ..color = AppColors.ink,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.on != on || old.radius != radius || old.inside != inside;
}
