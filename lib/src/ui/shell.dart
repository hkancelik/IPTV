import 'package:flutter/material.dart';

import 'basics.dart';
import 'focus_ring.dart';
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
      padding: const EdgeInsets.fromLTRB(24, 24, 0, 24),
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
