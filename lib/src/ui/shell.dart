import 'package:flutter/material.dart';

import 'basics.dart';
import 'focus_ring.dart';
import 'layout.dart';
import 'tokens.dart';

const navLabels = ['Ana sayfa', 'Canlı TV', 'Filmler', 'Diziler', 'Favoriler', 'Ayarlar'];
const navKeys = ['nav-home', 'nav-live', 'nav-movies', 'nav-series', 'nav-favorites', 'nav-settings'];
const navIcons = [
  Icons.home_rounded,
  Icons.live_tv_rounded,
  Icons.movie_rounded,
  Icons.video_library_rounded,
  Icons.favorite_rounded,
  Icons.tune_rounded,
];

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
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSizes.scrollPad),
                itemCount: navLabels.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _item(i, narrow),
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
          Icon(navIcons[i], size: 20, color: fg),
          if (!narrow) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(navLabels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: on ? AppText.title(15, color: fg) : AppText.meta(15, color: fg)),
            ),
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

/// Floating frosted-glass 5-tab capsule pinned above the iPhone Home Indicator (portrait).
class PhoneBottomBar extends StatelessWidget {
  const PhoneBottomBar({super.key, required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  static const _shortLabels = ['Ana sayfa', 'Canlı TV', 'Filmler', 'Diziler', 'Favoriler'];

  @override
  Widget build(BuildContext context) {
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
    final on = i == selected;
    return Semantics(
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
                _shortLabels[i],
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

/// Slim frosted-glass vertical rail on the left for iPhone landscape, clearing the Dynamic Island.
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
    final left = pad.left > 0 ? pad.left : 10.0;
    final bottom = pad.bottom > 0 ? pad.bottom : 10.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(left, 10, 0, bottom),
      child: GlassSurface(
        radius: 26,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: SizedBox(
          width: 48,
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AppHaptics.selection(context);
                  onSelect(0);
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.play_arrow_rounded, color: AppColors.onAccent, size: 22),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < navLabels.length; i++) _railItem(context, i),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              PhoneAccountAvatar(name: accountName, size: 34, onTap: onAccount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _railItem(BuildContext context, int i) {
    final on = i == selected;
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
            child: Icon(navIcons[i], size: 20, color: on ? AppColors.onAccent : AppColors.ink2),
          ),
        ),
      ),
    );
  }
}

/// Circular iPhone top-bar button with a comfortable 44×44 touch area.
class PhoneIconButton extends StatelessWidget {
  const PhoneIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.translucent = false,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool active;
  final bool translucent;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.accent : (translucent ? AppColors.videoGlass : AppColors.surface);
    final fg = iconColor ?? (active ? AppColors.onAccent : AppColors.ink);
    Widget button = Semantics(
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
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}

/// Circular account initial avatar used in the iPhone top bar and landscape rail.
class PhoneAccountAvatar extends StatelessWidget {
  const PhoneAccountAvatar({super.key, required this.name, required this.onTap, this.size = 38});

  final String name;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return Tooltip(
      message: 'Kullanıcı değiştir',
      child: Semantics(
        button: true,
        label: 'Kullanıcı değiştir',
        child: GestureDetector(
          key: const ValueKey('nav-account'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AppHaptics.selection(context);
            onTap();
          },
          child: SizedBox(
            width: size < 42 ? 42 : size,
            height: size < 42 ? 42 : size,
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
    final right = landscape ? (pad.right > 0 ? pad.right : 14.0) : 16.0;
    final left = landscape ? 12.0 : 18.0;
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
