import 'package:flutter/material.dart';

import '../downloads.dart';
import 'basics.dart';
import 'focus_ring.dart';
import 'layout.dart';
import 'liquid_glass.dart';
import 'tokens.dart';

const navLabels = ['Ana sayfa', 'Canlı TV', 'Filmler', 'Diziler', 'Rafım', 'Ayarlar', 'İndirilenler'];
const navKeys = ['nav-home', 'nav-live', 'nav-movies', 'nav-series', 'nav-favorites', 'nav-settings', 'nav-downloads'];
const navIcons = [
  Icons.home_rounded,
  Icons.live_tv_rounded,
  Icons.movie_rounded,
  Icons.video_library_rounded,
  Icons.collections_bookmark_rounded,
  Icons.tune_rounded,
  Icons.download_for_offline_rounded,
];

/// Display order for vertical navigation menus (keeps İndirilenler above Ayarlar
/// without changing the existing tab indices 0..5).
const _verticalNavOrder = [0, 1, 2, 3, 4, 6, 5];

/// Blue square with a play mark, optionally followed by "IPTV".
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.showName = true});

  final bool showName;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.play_arrow_rounded, color: AppColors.onAccent, size: 24),
        ),
        if (showName) ...[const SizedBox(width: 10), Text('IPTV', style: AppText.title(20))],
      ]);
}

/// The white menu card on the left: brand, six sections, the account chip.
class SideMenu extends StatelessWidget {
  const SideMenu({super.key, required this.selected, required this.onSelect, required this.accountName, required this.onAccount, this.compact});

  final int selected;
  final ValueChanged<int> onSelect;
  final String accountName;
  final VoidCallback onAccount;

  /// null: decided by the window width (icons only below 1000 px).
  final bool? compact;

  @override
  Widget build(BuildContext context) {
    final narrow = compact ?? MediaQuery.sizeOf(context).width < 1000;
    final initial = accountName.trim().isEmpty ? '?' : String.fromCharCode(accountName.trim().runes.first).toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      child: SizedBox(
        width: narrow ? AppSizes.menuCompact : AppSizes.menuWidth,
        child: AppCard(
          padding: EdgeInsets.fromLTRB(narrow ? 2 : 6, 22, narrow ? 2 : 6, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(narrow ? 0 : 18, 0, 0, 16),
              child: Align(alignment: narrow ? Alignment.center : Alignment.centerLeft, child: BrandMark(showName: !narrow)),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: DownloadManager.instance,
                builder: (context, _) => ListView.separated(
                  padding: const EdgeInsets.all(AppSizes.scrollPad),
                  itemCount: _verticalNavOrder.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, idx) => _item(_verticalNavOrder[idx], narrow),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.scrollPad),
              child: FocusRing(
                key: const ValueKey('nav-account'),
                radius: 18,
                onTap: onAccount,
                tooltip: 'Kullanıcı değiştir',
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(18)),
                  child: Row(mainAxisAlignment: narrow ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                      child: Text(initial, style: AppText.title(15, color: AppColors.onAccent)),
                    ),
                    if (!narrow) ...[
                      const SizedBox(width: 10),
                      Expanded(child: Text(accountName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(15))),
                    ],
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _item(int i, bool narrow) {
    final on = i == selected;
    final fg = on ? AppColors.onAccent : AppColors.ink2;
    final badge = i == 6 ? DownloadManager.instance.activeCount : 0;
    return FocusRing(
      key: ValueKey(navKeys[i]),
      radius: AppSizes.itemRadius,
      selected: on,
      onTap: () => onSelect(i),
      tooltip: narrow ? navLabels[i] : null,
      semanticLabel: narrow ? navLabels[i] : null,
      hoverColor: on ? null : AppColors.surfaceAlt,
      child: Container(
        height: 48,
        padding: EdgeInsets.symmetric(horizontal: narrow ? 0 : 14),
        decoration: BoxDecoration(color: on ? AppColors.accent : null, borderRadius: BorderRadius.circular(AppSizes.itemRadius)),
        child: Row(mainAxisAlignment: narrow ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(navIcons[i], size: 20, color: fg),
              if (narrow && badge > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: on ? AppColors.onAccent : AppColors.accent, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
          if (!narrow) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(navLabels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: on ? AppText.title(15, color: fg) : AppText.meta(15, color: fg)),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: on ? AppColors.onAccent.withValues(alpha: 0.22) : AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$badge', style: AppText.label(11.5, color: on ? AppColors.onAccent : AppColors.accentInk)),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

/// Page title with an optional note beside it and actions on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: LayoutBuilder(
          builder: (context, c) => Row(children: [
            Expanded(
              child: Row(children: [
                Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(28))),
                if (subtitle != null) ...[
                  const SizedBox(width: 14),
                  Flexible(child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(15))),
                ],
              ]),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 16),
              // The actions keep their size and the title gives way; in a very narrow window they shrink as a whole
              // rather than overflow.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: c.maxWidth * 0.75),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 12), actions[i]],
                  ]),
                ),
              ),
            ],
          ]),
        ),
      );
}

/// Bottom 5-tab bar for iPhone portrait.
///
/// On iOS 26+ this hosts Apple's native `UITabBarController` Liquid Glass bar
/// via [NativeGlassTabBar] (real system optical refraction, sliding glass lens,
/// and haptics). On older iOS, Android, desktop and widget tests it falls back
/// to a dark frosted-glass capsule.
class PhoneBottomBar extends StatefulWidget {
  const PhoneBottomBar({
    super.key,
    required this.selected,
    required this.onSelect,
    this.lastMainTab = 0,
  });

  final int selected;
  final ValueChanged<int> onSelect;

  /// Last selected primary tab (`0..4`), kept active in native `UITabBar`
  /// when Settings (`5`) is opened from the top bar so tapping any tab returns.
  final int lastMainTab;

  static const _shortLabels = ['Ana sayfa', 'Canlı TV', 'Filmler', 'Diziler', 'Rafım'];

  /// Native iOS 26+ Liquid Glass tab definitions using SF Symbols.
  static const nativeTabs = [
    NativeGlassTab(id: 'nav-home', label: 'Ana sayfa', sfSymbol: 'house.fill'),
    NativeGlassTab(id: 'nav-live', label: 'Canlı TV', sfSymbol: 'tv.fill'),
    NativeGlassTab(id: 'nav-movies', label: 'Filmler', sfSymbol: 'film.fill'),
    NativeGlassTab(id: 'nav-series', label: 'Diziler', sfSymbol: 'play.square.stack.fill'),
    NativeGlassTab(id: 'nav-favorites', label: 'Rafım', sfSymbol: 'books.vertical.fill'),
  ];

  @override
  State<PhoneBottomBar> createState() => _PhoneBottomBarState();
}

class _PhoneBottomBarState extends State<PhoneBottomBar> {
  late int _lastMainTab = _clampedMainTab(widget.selected >= 0 && widget.selected < 5 ? widget.selected : widget.lastMainTab);

  static int _clampedMainTab(int i) => i.clamp(0, 4);

  @override
  void didUpdateWidget(PhoneBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected >= 0 && widget.selected < 5) {
      _lastMainTab = widget.selected;
    } else if (widget.lastMainTab != oldWidget.lastMainTab) {
      _lastMainTab = _clampedMainTab(widget.lastMainTab);
    }
  }

  void _selectNativeId(String id) {
    final idx = navKeys.indexOf(id);
    if (idx >= 0 && idx < 5) widget.onSelect(idx);
  }

  @override
  Widget build(BuildContext context) {
    if (isNativeLiquidGlassSupported) {
      final activeIndex = widget.selected >= 0 && widget.selected < 5 ? widget.selected : _lastMainTab;
      return NativeGlassTabBar(
        tabs: PhoneBottomBar.nativeTabs,
        selectedId: navKeys[activeIndex],
        onSelected: _selectNativeId,
        onReselect: (id) {
          if (widget.selected >= 5) _selectNativeId(id);
        },
        tintColor: AppColors.accent,
        isDark: true,
      );
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset > 0 ? bottomInset + 4 : 12),
      child: GlassSurface(
        radius: 32,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              for (var i = 0; i < 5; i++) Expanded(child: _tab(context, i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i) {
    final on = i == widget.selected;
    return Semantics(
      button: true,
      selected: on,
      label: navLabels[i],
      child: GestureDetector(
        key: ValueKey(navKeys[i]),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.selection(context);
          widget.onSelect(i);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          decoration: BoxDecoration(
            color: on ? AppColors.accentSoft : AppColors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(navIcons[i], size: 21, color: on ? AppColors.accentInk : AppColors.ink2),
              const SizedBox(height: 2),
              Text(
                PhoneBottomBar._shortLabels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(10.5, color: on ? AppColors.accentInk : AppColors.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim frosted-glass vertical rail on the right for iPhone landscape, clearing the right safe area.
class PhoneLandscapeRail extends StatelessWidget {
  const PhoneLandscapeRail({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.accountName,
    required this.onAccount,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final String accountName;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final right = pad.right > 0 ? pad.right : 10.0;
    final bottom = pad.bottom > 0 ? pad.bottom : 10.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 10, right, bottom),
      child: GlassSurface(
        radius: 26,
        interactive: true,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: SizedBox(
          width: 48,
          child: Column(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: DownloadManager.instance,
                  builder: (context, _) => SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final i in _verticalNavOrder) _railItem(context, i),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              PhoneAccountAvatar(name: accountName, size: 34, nativeGlass: false, onTap: onAccount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _railItem(BuildContext context, int i) {
    final on = i == selected;
    final hasBadge = i == 6 && DownloadManager.instance.activeCount > 0;
    return Tooltip(
      message: navLabels[i],
      child: Semantics(
        button: true,
        selected: on,
        label: navLabels[i],
        child: GestureDetector(
          key: ValueKey(navKeys[i]),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AppHaptics.selection(context);
            onSelect(i);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 44,
            height: 38,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: on ? AppColors.accent : AppColors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(navIcons[i], size: 20, color: on ? AppColors.onAccent : AppColors.ink2),
                if (hasBadge)
                  Positioned(
                    right: 8,
                    top: 6,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: on ? AppColors.onAccent : AppColors.accent, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular iPhone top-bar button with a comfortable 42×42 touch area.
///
/// On iOS 26+ this renders Apple's native interactive Liquid Glass `UIButton`
/// (`UIButton.Configuration.glass()` / `.clearGlass()` / `.prominentGlass()`).
class PhoneIconButton extends StatelessWidget {
  const PhoneIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.sfSymbol,
    this.active = false,
    this.translucent = false,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final String? sfSymbol;
  final bool active;
  final bool translucent;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.accent : (translucent ? AppColors.videoGlass : AppColors.surface);
    final fg = iconColor ?? (active ? AppColors.onAccent : AppColors.ink);
    Widget fallback = Semantics(
      button: true,
      selected: active,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                AppHaptics.selection(context);
                onTap!();
              },
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: active ? AppColors.transparent : AppColors.glassBorder, width: 1),
              ),
              child: Icon(icon, size: 19, color: fg),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) fallback = Tooltip(message: tooltip!, child: fallback);

    final symbol = sfSymbol ?? sfSymbolForIcon(icon);
    if (symbol == null) return fallback;

    return NativeGlassButton(
      sfSymbol: symbol,
      tooltip: tooltip,
      width: 42,
      height: 42,
      isRound: true,
      iconSize: 17,
      style: active
          ? NativeGlassStyle.prominentGlass
          : (translucent ? NativeGlassStyle.clearGlass : NativeGlassStyle.glass),
      foregroundColor: fg,
      tintColor: active ? AppColors.accent : null,
      onPressed: onTap,
      fallback: fallback,
    );
  }
}

/// Circular account initial avatar used in the iPhone top bar and landscape rail.
class PhoneAccountAvatar extends StatelessWidget {
  const PhoneAccountAvatar({
    super.key,
    required this.name,
    required this.onTap,
    this.size = 38,
    this.nativeGlass = true,
  });

  final String name;
  final VoidCallback onTap;
  final double size;
  final bool nativeGlass;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();
    final box = size < 42 ? 42.0 : size;
    final fallback = Tooltip(
      message: 'Kullanıcı değiştir',
      child: Semantics(
        button: true,
        label: 'Kullanıcı değiştir',
        child: GestureDetector(
          key: nativeGlass ? null : const ValueKey('nav-account'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AppHaptics.selection(context);
            onTap();
          },
          child: SizedBox(
            width: box,
            height: box,
            child: Center(
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.glassBorder, width: 1),
                ),
                child: Text(initial, style: AppText.title(size * 0.4, color: AppColors.onAccent)),
              ),
            ),
          ),
        ),
      ),
    );
    if (!nativeGlass) return fallback;
    return NativeGlassButton(
      key: const ValueKey('nav-account'),
      label: initial,
      tooltip: 'Kullanıcı değiştir',
      width: box,
      height: box,
      isRound: true,
      fontSize: size * 0.42,
      style: NativeGlassStyle.glass,
      foregroundColor: AppColors.ink,
      onPressed: onTap,
      fallback: fallback,
    );
  }
}

/// Compact header for iPhone portrait and landscape. Clears the Dynamic Island via SafeArea.
class PhoneTopBar extends StatelessWidget {
  const PhoneTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.landscape = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final top = landscape ? (pad.top > 0 ? pad.top : 10.0) : (pad.top > 0 ? pad.top + 6 : 14.0);
    final left = landscape ? (pad.left > 0 ? pad.left : 14.0) : 18.0;
    final right = landscape ? 12.0 : 16.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(left, top, right, landscape ? 6 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: landscape
                ? Row(
                    children: [
                      Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(22))),
                      if (subtitle != null) ...[
                        const SizedBox(width: 10),
                        Flexible(child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13))),
                      ],
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(26)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
                      ],
                    ],
                  ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 6), actions[i]],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
