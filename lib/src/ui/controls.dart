import 'dart:async';

import 'package:flutter/material.dart';

import '../tv_text_field.dart';
import 'focus_ring.dart';
import 'format.dart';
import 'tokens.dart';

/// 1248 → "1.248".
String groupCount(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Round on/off switch: 52×30, or 40×24 when [small].
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged, this.small = false, this.focusable = true});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool small;

  /// false: the surrounding row takes the focus (settings rows).
  final bool focusable;

  @override
  Widget build(BuildContext context) {
    final w = small ? 40.0 : 52.0, h = small ? 24.0 : 30.0, knob = h - 6;
    final track = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: w,
      height: h,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: value ? AppColors.accent : AppColors.dashed, borderRadius: BorderRadius.circular(h / 2)),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: knob,
          height: knob,
          decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, boxShadow: AppShadows.chip),
        ),
      ),
    );
    Widget result = FocusRing(
      radius: h / 2,
      lift: false,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: track,
    );
    if (!focusable) result = ExcludeFocus(child: result);
    return Semantics(toggled: value, child: result);
  }
}

/// A row of mutually exclusive choices on a soft ground.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries)
            Semantics(
              inMutuallyExclusiveGroup: true,
              child: FocusRing(
                selected: e.key == value,
                radius: AppSizes.smallRadius,
                lift: false,
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? AppColors.surface : AppColors.transparent,
                    borderRadius: BorderRadius.circular(AppSizes.smallRadius),
                    boxShadow: e.key == value ? AppShadows.chip : null,
                  ),
                  child: Text(e.value, style: AppText.label(13, color: e.key == value ? AppColors.ink : AppColors.ink2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pill-shaped search box built on [RemoteTextField].
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.hint, this.onChanged, this.controller, this.onPage = true, this.width});

  final String hint;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;

  /// true: white with a chip shadow (on the page ground); false: surfaceAlt (inside a panel).
  final bool onPage;
  final double? width;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.onPage ? 44.0 : 40.0;
    final field = Container(
      width: widget.width,
      height: h,
      padding: const EdgeInsets.only(left: 6, right: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: widget.onPage ? AppColors.surface : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(h / 2),
        boxShadow: widget.onPage ? AppShadows.chip : null,
      ),
      child: RemoteTextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppText.meta(widget.onPage ? 15 : 14),
          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.ink2),
          prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        // Always present (transparent when unfocused): changing the tree here would rebuild the text field.
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: _focused ? AppColors.ink : AppColors.transparent, width: AppSizes.ring),
          borderRadius: BorderRadius.circular(h / 2),
        ),
        child: DefaultTextStyle.merge(style: AppText.label(widget.onPage ? 15 : 14), child: field),
      ),
    );
  }
}

/// "09:05" in a white pill, refreshed once a minute.
class ClockPill extends StatefulWidget {
  const ClockPill({super.key, this.now});

  final DateTime Function()? now; // for tests

  @override
  State<ClockPill> createState() => _ClockPillState();
}

class _ClockPillState extends State<ClockPill> {
  Timer? _timer;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final n = _now();
    _timer = Timer(Duration(seconds: 60 - n.second), () {
      if (!mounted) return;
      setState(() {});
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), boxShadow: AppShadows.chip),
    child: Text(hhmm(_now()), style: AppText.title(15).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
  );
}

/// Category / settings section item with an optional count.
class SideItem extends StatelessWidget {
  const SideItem({
    super.key,
    required this.label,
    this.count,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.tooltip,
    this.height = 42,
  });

  final String label;
  final String? count; // already formatted ("1.248")
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;
  final String? tooltip;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.accentInk : AppColors.ink;
    return FocusRing(
      selected: selected,
      radius: AppSizes.smallRadius,
      lift: false,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapUp: onSecondaryTapUp,
      tooltip: tooltip,
      hoverColor: selected ? null : AppColors.surfaceAlt,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: selected ? AppColors.accentSoft : null, borderRadius: BorderRadius.circular(AppSizes.smallRadius)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: selected ? AppText.title(14, color: fg) : AppText.meta(14, color: fg),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text(count!, style: AppText.meta(13, color: selected ? AppColors.accentInk : AppColors.ink2)),
            ],
          ],
        ),
      ),
    );
  }
}
