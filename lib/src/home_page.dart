import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'detail_page.dart';
import 'epg_widgets.dart';
import 'library.dart';
import 'mini_player.dart';
import 'player_chrome.dart';
import 'player_page.dart';
import 'poster_card.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'title_utils.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/focus_ring.dart';
import 'ui/format.dart';
import 'ui/layout.dart';
import 'ui/liquid_glass.dart';
import 'ui/shell.dart';
import 'ui/tokens.dart';
import 'xtream.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.client, required this.info, required this.account});

  final XtreamClient client;
  final AccountInfo info;
  final Account account;

  @override
  State<HomePage> createState() => _HomePageState();
}

// Navigation tabs: 0 home, 1 live, 2 movies, 3 series, 4 favorites, 5 settings
enum _Sort { provider, added, name, year }

const _homeTab = 0;
const _favoritesTab = 4;
const _settingsTab = 5;

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  int _lastMainTab = 0;
  final Map<Kind, List<Item>> _items = {};
  final Map<Kind, String?> _errors = {};
  final Set<Kind> _loading = {};
  String? _group;
  String _query = '';
  String _groupQuery = ''; // filters the category sidebar
  _Sort _sort = _Sort.provider;

  Kind? get _kind => _tab >= 1 && _tab <= 3 ? Kind.values[_tab - 1] : null;

  late final EpgCache _epg = EpgCache(widget.client);

  Future<void> _ensureLoaded(Kind kind) async {
    if (_items.containsKey(kind) || _loading.contains(kind)) return;
    setState(() {
      _loading.add(kind);
      _errors[kind] = null;
    });
    try {
      final c = widget.client;
      _items[kind] = switch (kind) {
        Kind.live => await c.live(),
        Kind.movie => await c.movies(),
        Kind.series => await c.series(),
      };
    } on XtreamException catch (e) {
      _errors[kind] = e.message;
    } catch (e) {
      _errors[kind] = 'Liste yüklenemedi: $e';
    } finally {
      if (mounted) setState(() => _loading.remove(kind));
    }
  }

  void _select(int tab) {
    setState(() {
      _tab = tab;
      if (tab >= 0 && tab < 5) _lastMainTab = tab;
      _group = null;
      _query = '';
      _groupQuery = '';
    });
    final k = _kind;
    if (k != null) _ensureLoaded(k);
  }

  void _open(Item item) {
    if (item.kind == Kind.live) {
      _playLive(item);
    } else {
      Navigator.of(context).push(
        appRoute(context, (_) => DetailPage(client: widget.client, item: item)),
      );
    }
  }

  void _playLive(Item item) {
    // Next/previous channel follows the list the user is looking at (category + search).
    List<Item> list = [item];
    if (_kind == Kind.live) {
      list = _viewOf(Kind.live).shown;
    } else if (_tab == _favoritesTab || _tab == _homeTab) {
      list = Library.instance.favorites.where(_allowed).where((i) => i.kind == Kind.live).toList();
    }
    var index = list.indexWhere((i) => i.id == item.id);
    if (index < 0) {
      list = [item];
      index = 0;
    }
    PlayerEntry entry(Item i) {
      final id = i.streamId;
      return PlayerEntry(url: i.url!, title: i.name, logo: i.logo, group: groupLabel(i.group), epg: id == null ? null : () => _epg.get(id));
    }

    Navigator.of(context).push(
      appRoute(
        context,
        (_) => PlayerPage(queue: [for (final i in list) entry(i)], index: index, kind: Kind.live, client: widget.client),
      ),
    );
  }

  void _openHistory(HistoryEntry e) {
    Navigator.of(context).push(
      appRoute(
        context,
        (_) => PlayerPage(
          queue: [PlayerEntry(url: e.url, title: e.title, logo: e.logo, item: e.item)],
          kind: e.kind,
          client: widget.client,
        ),
      ),
    );
  }

  bool _openingDetail = false;

  Future<void> _openHistoryDetail(HistoryEntry e) async {
    if (_openingDetail || e.kind == Kind.live) return;
    _openingDetail = true;
    try {
      final item = await resolveDetailItem(
        kind: e.kind,
        url: e.url,
        title: e.title,
        logo: e.logo,
        item: e.item,
        cachedItems: _items[e.kind],
        loadCatalog: () async {
          await _ensureLoaded(e.kind);
          return _items[e.kind] ?? const [];
        },
      );
      if (!mounted) return;
      if (item != null) {
        _open(item);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e.kind == Kind.series ? 'Dizi' : 'Film'} sayfası bulunamadı')),
        );
      }
    } finally {
      _openingDetail = false;
    }
  }

  bool _allowed(Item i) {
    final s = AppSettings.instance;
    if (s.hiddenGroups.contains(AppSettings.groupKey(i.kind, i.group))) return false;
    return !s.hideAdult || !_isAdult(i);
  }

  static final _adult = Expando<bool>();
  bool _isAdult(Item i) => _adult[i] ??= AppSettings.adultPattern.hasMatch(i.group) || AppSettings.adultPattern.hasMatch(i.name);

  _View? _view;

  /// The filtered/sorted list and category counts of a list tab. Recomputed only when an input changes, not
  /// on every rebuild: the page also rebuilds under the player (position saves every 10 s) and on each
  /// favorite toggle, and redoing this for ~20 000 items is slow on a TV stick.
  _View _viewOf(Kind kind) {
    final s = AppSettings.instance;
    final all = _items[kind] ?? const <Item>[];
    final key = (kind, all, s.hiddenGroups, s.hideAdult, s.dedupe, _group, _query, _sort);
    final cached = _view;
    if (cached != null && cached.key == key) return cached;

    final allowed = all.where(_allowed).toList();
    final groups = <String, int>{};
    for (final i in allowed) {
      groups[i.group] = (groups[i.group] ?? 0) + 1;
    }
    final List<Item> shown;
    if (_query.trim().isNotEmpty) {
      final match = queryMatcher(_query);
      shown = allowed.where((i) => match(foldedNameOf(i))).toList();
    } else {
      shown = _group == null ? allowed : allowed.where((i) => i.group == _group).toList();
    }
    // Same title listed in several categories: collapse only in the mixed "Tümü" view.
    final collapse = kind != Kind.live && s.dedupe;
    var result = collapse && _group == null ? _dedupe(shown) : shown;
    if (kind != Kind.live) result = _sorted(result);
    return _view = _View(key, result, groups, collapse ? _dedupe(allowed).length : allowed.length);
  }

  List<Item> _sorted(List<Item> items) {
    switch (_sort) {
      case _Sort.provider:
        return items;
      case _Sort.added:
        return [...items]..sort((a, b) => b.added.compareTo(a.added));
      case _Sort.name:
        return [...items]..sort((a, b) => parsedTitleOf(a).title.toLowerCase().compareTo(parsedTitleOf(b).title.toLowerCase()));
      case _Sort.year:
        int y(Item i) => int.tryParse(parsedTitleOf(i).year ?? '') ?? 0;
        return [...items]..sort((a, b) => y(b).compareTo(y(a)));
    }
  }

  static final _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Keeps the first entry of each name (case, spacing and punctuation ignored).
  static final _nameKeys = Expando<String>();

  List<Item> _dedupe(List<Item> items) {
    final seen = <String>{};
    return [
      for (final i in items)
        if (seen.add(_nameKeys[i] ??= i.name.toLowerCase().replaceAll(_nonAlnum, ''))) i,
    ];
  }

  /// Right-click menu on a category: move to top / hide.
  Future<void> _groupMenu(Kind kind, String name, Offset at) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: const [
        PopupMenuItem(value: 'top', child: Text('En üste al')),
        PopupMenuItem(value: 'hide', child: Text('Gizle')),
        PopupMenuItem(value: 'edit', child: Text('Kategorileri düzenle...')),
      ],
    );
    final s = AppSettings.instance;
    final all = _allGroups(kind);
    switch (choice) {
      case 'top':
        final order = s.orderedGroups(kind, all)..remove(name);
        s.update(
          groupOrder: {
            ...s.groupOrder,
            kind.name: [name, ...order],
          },
        );
      case 'hide':
        s.update(hiddenGroups: {...s.hiddenGroups, AppSettings.groupKey(kind, name)});
        if (_group == name) setState(() => _group = null);
      case 'edit':
        _manageGroups(kind);
    }
  }

  /// All category names of a kind in provider order (hidden ones included).
  List<String> _allGroups(Kind kind) {
    final seen = <String>{};
    return [
      for (final i in _items[kind] ?? const <Item>[])
        if (seen.add(i.group)) i.group,
    ];
  }

  Future<void> _manageGroups(Kind kind) async {
    final counts = <String, int>{};
    for (final i in _items[kind] ?? const <Item>[]) {
      counts[i.group] = (counts[i.group] ?? 0) + 1;
    }
    String filter = '';
    final phone = isPhoneLayout(context);

    Widget buildBody(BuildContext ctx, StateSetter setLocal, {required bool compact}) {
      final s = AppSettings.instance;
      final ordered = s.orderedGroups(kind, counts.keys);
      final visible = [
        for (final n in ordered)
          if (filter.isEmpty || matchesQuery(n, filter)) n,
      ];
      final canReorder = filter.isEmpty;

      void save(List<String> order) {
        s.update(groupOrder: {...s.groupOrder, kind.name: order});
        setLocal(() {});
      }

      void move(int from, int to) {
        final list = [...ordered];
        final item = list.removeAt(from);
        list.insert(to.clamp(0, list.length), item);
        save(list);
      }

      Widget tile(int index, String n) {
        final key = AppSettings.groupKey(kind, n);
        return Container(
          key: ValueKey(n),
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            if (canReorder)
              ReorderableDragStartListener(
                index: index,
                child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.drag_indicator_rounded, size: 20, color: AppColors.ink3)),
              ),
            Checkbox(
              value: !s.hiddenGroups.contains(key),
              onChanged: (v) {
                AppHaptics.selection(ctx);
                final next = {...s.hiddenGroups};
                (v ?? true) ? next.remove(key) : next.add(key);
                s.update(hiddenGroups: next);
                setLocal(() {});
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(groupLabel(n), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(14)),
                Text('${counts[n]} öğe', style: AppText.meta(12.5)),
              ]),
            ),
            if (canReorder) ...[
              AppButton(icon: Icons.vertical_align_top_rounded, height: compact ? 36 : AppSizes.buttonHeight, tooltip: 'En üste al', onPressed: index == 0 ? null : () => move(index, 0)),
              if (!compact) ...[
                const SizedBox(width: 4),
                AppButton(icon: Icons.keyboard_arrow_up_rounded, tooltip: 'Yukarı', onPressed: index == 0 ? null : () => move(index, index - 1)),
                const SizedBox(width: 4),
                AppButton(icon: Icons.keyboard_arrow_down_rounded, tooltip: 'Aşağı', onPressed: index >= ordered.length - 1 ? null : () => move(index, index + 1)),
              ],
            ],
          ]),
        );
      }

      return Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            compact ? 'Sürükleyerek sırayı değiştir. Kutuyu kaldırarak gizle.' : 'Sürükleyerek ya da oklarla sırayı değiştir. Kutuyu kaldırarak kategoriyi gizle.',
            style: AppText.meta(13),
          ),
        ),
        const SizedBox(height: 10),
        SearchField(hint: 'Kategori ara (arama sırasında sıralama kapalı)', onPage: false, onChanged: (v) => setLocal(() => filter = v)),
        const SizedBox(height: 6),
        Expanded(
          child: canReorder
              ? ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(vertical: AppSizes.scrollPad),
                  itemCount: visible.length,
                  itemExtent: 56,
                  onReorderItem: (from, to) => move(from, to),
                  itemBuilder: (_, i) => tile(i, visible[i]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppSizes.scrollPad),
                  itemExtent: 56,
                  itemCount: visible.length,
                  itemBuilder: (_, i) => tile(i, visible[i]),
                ),
        ),
      ]);
    }

    if (phone) {
      await showAppSheet<void>(
        context: context,
        title: 'Kategorileri düzenle',
        maxHeightFraction: 0.88,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                Expanded(child: buildBody(ctx, setLocal, compact: true)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: AppButton(
                      label: 'Sırayı sıfırla',
                      onPressed: () {
                        AppSettings.instance.update(groupOrder: {...AppSettings.instance.groupOrder}..remove(kind.name));
                        setLocal(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(label: 'Tamam', variant: AppButtonVariant.primary, onPressed: () => Navigator.pop(ctx)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Kategorileri düzenle'),
          content: SizedBox(width: 560, height: 520, child: buildBody(ctx, setLocal, compact: false)),
          actions: [
            AppButton(
              label: 'Sırayı sıfırla',
              onPressed: () {
                AppSettings.instance.update(groupOrder: {...AppSettings.instance.groupOrder}..remove(kind.name));
                setLocal(() {});
              },
            ),
            AppButton(label: 'Tamam', variant: AppButtonVariant.primary, onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  /// Searchable iOS bottom sheet for picking a category when playlists have many categories.
  Future<void> _openCategorySheet(Kind kind, _View view) async {
    String q = '';
    await showAppSheet<void>(
      context: context,
      title: 'Kategoriler',
      subtitle: '${groupCount(view.groups.length)} kategori',
      trailing: AppButton(
        dense: true,
        height: 36,
        icon: Icons.tune_rounded,
        label: 'Düzenle',
        onPressed: () {
          Navigator.of(context).pop();
          _manageGroups(kind);
        },
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final names = AppSettings.instance.orderedGroups(kind, view.groups.keys).where((n) => matchesQuery(groupLabel(n), q)).toList();
          final showAll = q.trim().isEmpty;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SearchField(hint: 'Kategori ara', onPage: false, onChanged: (v) => setLocal(() => q = v)),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: names.length + (showAll ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (showAll && i == 0) {
                      return SheetOptionTile(
                        label: 'Tümü',
                        trailingText: groupCount(view.total),
                        selected: _group == null,
                        onTap: () {
                          setState(() => _group = null);
                          Navigator.of(ctx).pop();
                        },
                      );
                    }
                    final name = names[i - (showAll ? 1 : 0)];
                    return SheetOptionTile(
                      label: groupLabel(name),
                      trailingText: groupCount(view.groups[name] ?? 0),
                      selected: _group == name,
                      onTap: () {
                        setState(() => _group = name);
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickSortSheet() async {
    final picked = await showAppSheet<_Sort>(
      context: context,
      title: 'Sırala',
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final e in _sortLabels.entries)
            SheetOptionTile(
              label: e.value,
              selected: e.key == _sort,
              onTap: () => Navigator.of(ctx).pop(e.key),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  void _logout() {
    PlayerSession.instance.close();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppSettings.instance, Library.instance, PlayerSession.instance]),
      // Back (TV remote) never lands on the profile page: it steps back to "Tümü", then to Ana Sayfa,
      // then leaves the app. Switching user goes through Ayarlar (Navigator.pop ignores this PopScope).
      builder: (context, _) {
        final mode = layoutModeOf(context);
        final pad = MediaQuery.paddingOf(context);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_group != null && _kind != null) {
              setState(() => _group = null);
            } else if (_tab != _homeTab) {
              _select(_homeTab);
            } else {
              SystemNavigator.pop();
            }
          },
          child: switch (mode) {
            AppLayoutMode.desktop => Scaffold(
                body: Row(
                  children: [
                    SideMenu(selected: _tab, onSelect: _select, accountName: widget.account.name, onAccount: _logout),
                    const SizedBox(width: 8),
                    Expanded(child: _content()),
                  ],
                ),
              ),
            AppLayoutMode.phonePortrait => Scaffold(
                resizeToAvoidBottomInset: false,
                body: Stack(
                  children: [
                    Positioned.fill(child: _phonePortraitContent()),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                            child: PhoneMiniPlayerSlot(onExpand: () => expandMiniPlayer(context)),
                          ),
                          PhoneBottomBar(selected: _tab, lastMainTab: _lastMainTab, onSelect: _select),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            AppLayoutMode.phoneLandscape => Scaffold(
                body: Row(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(child: _phoneLandscapeContent()),
                          Positioned(
                            left: pad.left > 0 ? pad.left : 14,
                            bottom: pad.bottom > 0 ? pad.bottom + 4 : 10,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 340),
                              child: PhoneMiniPlayerSlot(
                                compact: true,
                                onExpand: () => expandMiniPlayer(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    PhoneLandscapeRail(
                      selected: _tab,
                      onSelect: _select,
                      accountName: widget.account.name,
                      onAccount: _logout,
                    ),
                  ],
                ),
              ),
          },
        );
      },
    );
  }

  // ─── Phone Portrait & Landscape shells ─────────────────────

  List<Widget> _phoneHeaderEndActions() => [
        PhoneIconButton(
          key: const ValueKey('nav-settings'),
          icon: Icons.tune_rounded,
          tooltip: 'Ayarlar',
          active: _tab == _settingsTab,
          onTap: () => _select(_tab == _settingsTab ? _homeTab : _settingsTab),
        ),
        PhoneAccountAvatar(
          name: widget.account.name,
          onTap: _logout,
        ),
      ];

  Widget _phoneSortButton({required double height}) {
    final label = _sort == _Sort.provider ? 'Sırala' : _sortLabels[_sort]!;
    return NativeGlassMenuButton(
      menuTitle: 'Sırala',
      sfSymbol: 'arrow.up.arrow.down',
      fallbackIcon: Icons.swap_vert_rounded,
      label: label,
      tooltip: 'Sırala',
      style: NativeGlassStyle.glass,
      isRound: false,
      height: height,
      iconSize: 15,
      fontSize: 13.5,
      items: [
        for (final e in _sortLabels.entries)
          GlassMenuItem(
            id: e.key.name,
            title: e.value,
            selected: e.key == _sort,
          ),
      ],
      onSelected: (id) {
        for (final e in _Sort.values) {
          if (e.name == id) {
            setState(() => _sort = e);
            return;
          }
        }
      },
      fallbackBuilder: (_, _) => AppButton(
        variant: AppButtonVariant.onPage,
        height: height,
        dense: true,
        icon: Icons.swap_vert_rounded,
        label: label,
        tooltip: 'Sırala',
        onPressed: _pickSortSheet,
      ),
    );
  }

  Widget _phonePortraitContent() {
    if (_tab == _homeTab) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneTopBar(
            title: '${greeting(DateTime.now())}, ${widget.account.name}',
            actions: _phoneHeaderEndActions(),
          ),
          Expanded(child: _phoneHomeView(landscape: false)),
        ],
      );
    }
    if (_tab == _settingsTab) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneTopBar(title: 'Ayarlar', actions: _phoneHeaderEndActions()),
          Expanded(
            child: SettingsPage(
              info: widget.info,
              account: widget.account,
              client: widget.client,
              onLogout: _logout,
            ),
          ),
        ],
      );
    }
    if (_tab == _favoritesTab) {
      final match = queryMatcher(_query);
      final favs = Library.instance.favorites.where(_allowed).where((i) => match(foldedNameOf(i))).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneTopBar(title: 'Favoriler', subtitle: favs.isEmpty ? null : '${groupCount(favs.length)} kayıt', actions: _phoneHeaderEndActions()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SearchField(key: ValueKey('search$_tab'), hint: 'Favorilerde ara', onChanged: (v) => setState(() => _query = v)),
          ),
          Expanded(child: _favoritesView(favs, phonePortrait: true)),
        ],
      );
    }

    final kind = _kind!;
    final view = _viewOf(kind);
    final shown = view.shown;
    final ready = !_loading.contains(kind) && _errors[kind] == null;
    final n = groupCount(shown.length);
    final (title, hint, subtitle) = switch (kind) {
      Kind.live => ('Canlı TV', 'Kanal ara', '${_group == null ? 'Tümü' : groupLabel(_group!)}, $n kanal'),
      Kind.movie => ('Filmler', 'Film ara', '${_group == null ? '' : '${groupLabel(_group!)} · '}$n film'),
      Kind.series => ('Diziler', 'Dizi ara', '${_group == null ? '' : '${groupLabel(_group!)} · '}$n dizi'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhoneTopBar(title: title, subtitle: ready ? subtitle : null, actions: _phoneHeaderEndActions()),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(child: SearchField(key: ValueKey('search$_tab'), hint: hint, onChanged: (v) => setState(() => _query = v))),
              if (kind != Kind.live) ...[
                const SizedBox(width: 8),
                _phoneSortButton(height: 44),
              ],
            ],
          ),
        ),
        if (ready && view.groups.isNotEmpty) ...[
          _phoneCategoryStrip(kind, view),
          const SizedBox(height: 8),
        ],
        Expanded(child: _body(kind, shown, phonePortrait: true)),
      ],
    );
  }

  Widget _phoneLandscapeContent() {
    final pad = MediaQuery.paddingOf(context);
    final leftPad = pad.left > 0 ? pad.left : 14.0;
    final bottomPad = pad.bottom > 0 ? pad.bottom : 10.0;

    if (_tab == _homeTab) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneTopBar(title: '${greeting(DateTime.now())}, ${widget.account.name}', landscape: true),
          Expanded(child: _phoneHomeView(landscape: true)),
        ],
      );
    }
    if (_tab == _settingsTab) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PhoneTopBar(title: 'Ayarlar', landscape: true),
          Expanded(
            child: SettingsPage(
              info: widget.info,
              account: widget.account,
              client: widget.client,
              onLogout: _logout,
            ),
          ),
        ],
      );
    }
    if (_tab == _favoritesTab) {
      final match = queryMatcher(_query);
      final favs = Library.instance.favorites.where(_allowed).where((i) => match(foldedNameOf(i))).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneTopBar(
            title: 'Favoriler',
            subtitle: favs.isEmpty ? null : '${groupCount(favs.length)} kayıt',
            landscape: true,
            actions: [
              SearchField(key: ValueKey('search$_tab'), hint: 'Favorilerde ara', width: 220, onChanged: (v) => setState(() => _query = v)),
            ],
          ),
          Expanded(child: _favoritesView(favs, phoneLandscape: true)),
        ],
      );
    }

    final kind = _kind!;
    final view = _viewOf(kind);
    final shown = view.shown;
    final ready = !_loading.contains(kind) && _errors[kind] == null;
    final n = groupCount(shown.length);
    final (title, hint, subtitle) = switch (kind) {
      Kind.live => ('Canlı TV', 'Kanal ara', '${_group == null ? 'Tümü' : groupLabel(_group!)}, $n kanal'),
      Kind.movie => ('Filmler', 'Film ara', '$n film'),
      Kind.series => ('Diziler', 'Dizi ara', '$n dizi'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhoneTopBar(
          title: title,
          subtitle: ready ? subtitle : null,
          landscape: true,
          actions: [
            SearchField(key: ValueKey('search$_tab'), hint: hint, width: 200, onChanged: (v) => setState(() => _query = v)),
            if (kind != Kind.live) _phoneSortButton(height: 40),
          ],
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: leftPad > 14 ? leftPad - 6 : 10, right: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 4, bottom: bottomPad),
                  child: SizedBox(width: 188, child: _categoryPanel(kind, view, compact: true)),
                ),
                const SizedBox(width: 8),
                Expanded(child: _body(kind, shown, phoneLandscape: true)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Horizontal category chip bar for iPhone portrait, with searchable sheet & editor shortcuts.
  Widget _phoneCategoryStrip(Kind kind, _View view) {
    final names = AppSettings.instance.orderedGroups(kind, view.groups.keys);
    Widget chip({required String label, String? count, required bool selected, required VoidCallback onTap}) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AppHaptics.selection(context);
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.accentSoft : AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? AppColors.accent.withValues(alpha: 0.45) : AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: selected ? AppText.title(13.5, color: AppColors.accentInk) : AppText.label(13.5, color: AppColors.ink2)),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(count, style: AppText.meta(11.5, color: selected ? AppColors.accentInk : AppColors.ink3)),
                ],
              ],
            ),
          ),
        );

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: NativeGlassButton(
              sfSymbol: 'square.grid.2x2',
              tooltip: 'Tüm kategoriler',
              width: 40,
              height: 36,
              isRound: false,
              cornerRadius: 18,
              iconSize: 15,
              style: NativeGlassStyle.glass,
              foregroundColor: AppColors.ink,
              onPressed: () => _openCategorySheet(kind, view),
              fallback: Tooltip(
                message: 'Tüm kategoriler',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    AppHaptics.selection(context);
                    _openCategorySheet(kind, view);
                  },
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.grid_view_rounded, size: 16, color: AppColors.ink),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 16),
              children: [
                chip(label: 'Tümü', count: groupCount(view.total), selected: _group == null, onTap: () => setState(() => _group = null)),
                for (final name in names) ...[
                  const SizedBox(width: 8),
                  chip(
                    label: groupLabel(name),
                    count: groupCount(view.groups[name] ?? 0),
                    selected: _group == name,
                    onTap: () => setState(() => _group = name),
                  ),
                ],
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Kategorileri düzenle / gizle',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      AppHaptics.selection(context);
                      _manageGroups(kind);
                    },
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune_rounded, size: 15, color: AppColors.ink2),
                          const SizedBox(width: 6),
                          Text('Düzenle', style: AppText.label(13, color: AppColors.ink2)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneHomeView({required bool landscape}) {
    final lib = Library.instance;
    final continueList = lib.continueWatching.take(7).toList();
    final favs = lib.favorites.where(_allowed).toList();
    List<Item> of(Kind k) => favs.where((i) => i.kind == k).toList();
    final channels = of(Kind.live);
    final movies = of(Kind.movie);
    final series = of(Kind.series);
    final recents = continueList.skip(1).toList();
    final pad = MediaQuery.paddingOf(context);

    Widget continueHero(HistoryEntry e) {
      final title = playerTitle(e.title).$1;
      final left = _left(e);
      return AppCard(
        radius: AppSizes.cardRadius,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Pill('Kaldığın yerden', tone: PillTone.accent, height: 26),
                  const SizedBox(height: 10),
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.display(landscape ? 22 : 24)),
                  if (left != null) ...[
                    const SizedBox(height: 10),
                    ProgressBar(value: e.progress, height: 6),
                    const SizedBox(height: 5),
                    Text(left, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12.5)),
                  ],
                  const SizedBox(height: 14),
                  AppButton(
                    label: 'Devam et',
                    icon: Icons.play_arrow_rounded,
                    variant: AppButtonVariant.primary,
                    height: 42,
                    onPressed: () {
                      AppHaptics.light(context);
                      _openHistory(e);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Semantics(
              button: true,
              label: '$title sayfasına git',
              child: GestureDetector(
                key: const ValueKey('home-continue-poster'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AppHaptics.light(context);
                  _openHistoryDetail(e);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: landscape ? 88 : 96,
                    height: landscape ? 132 : 144,
                    child: ColoredBox(color: AppColors.surfaceAlt, child: PosterImage(e.logo, cacheWidth: 320)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget recentsCarousel() => SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: landscape ? 4 : 16),
            itemCount: recents.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final e = recents[i];
              final sub = [?episodeLabel(e.title), ?_left(e)].join(', ');
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AppHaptics.light(context);
                  _openHistory(e);
                },
                child: Container(
                  width: 248,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: '${playerTitle(e.title).$1} sayfasına git',
                        child: GestureDetector(
                          key: ValueKey('home-recent-poster-$i'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            AppHaptics.light(context);
                            _openHistoryDetail(e);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(width: 60, height: 90, child: ColoredBox(color: AppColors.surfaceAlt, child: PosterImage(e.logo))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(playerTitle(e.title).$1, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.title(14.5)),
                            if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.meta(12))),
                            if (e.durationMs > 0) Padding(padding: const EdgeInsets.only(top: 8, right: 4), child: ProgressBar(value: e.progress, height: 4)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );

    Widget posterRow(List<Item> items) => SizedBox(
          height: 152,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: landscape ? 4 : 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final it = items[i];
              return GestureDetector(
                onTap: () {
                  AppHaptics.light(context);
                  _open(it);
                },
                child: Container(
                  width: 100,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSizes.itemRadius),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: ClipRRect(borderRadius: BorderRadius.circular(AppSizes.itemRadius - 1), child: PosterImage(it.logo)),
                ),
              );
            },
          ),
        );

    if (continueList.isEmpty && favs.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(landscape ? (pad.left > 0 ? pad.left : 14) : 16, 12, landscape ? 12 : 16, landscape ? 16 : phoneBottomClearance(context)),
        child: Align(
          alignment: Alignment.topCenter,
          child: AppCard(
            radius: AppSizes.cardRadius,
            padding: const EdgeInsets.all(28),
            child: Text(
              'Burası senin sayfan.\nBeğendiğin kanal, film ve dizilerin kalp ikonuna dokun, burada görünsün.',
              textAlign: TextAlign.center,
              style: AppText.body(),
            ),
          ),
        ),
      );
    }

    if (landscape) {
      final leftPad = pad.left > 0 ? pad.left : 14.0;
      final bottomPad = pad.bottom > 0 ? pad.bottom + 8 : 14.0;
      final hasLeft = continueList.isNotEmpty || recents.isNotEmpty || movies.isNotEmpty || series.isNotEmpty;
      return Padding(
        padding: EdgeInsets.fromLTRB(leftPad, 4, 12, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasLeft)
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(bottom: bottomPad),
                  children: [
                    if (continueList.isNotEmpty) ...[continueHero(continueList.first), const SizedBox(height: 16)],
                    if (recents.isNotEmpty) ...[_sectionTitle('Son izlediklerin'), recentsCarousel(), const SizedBox(height: 16)],
                    if (movies.isNotEmpty) ...[_sectionTitle('Filmlerim'), posterRow(movies), const SizedBox(height: 14)],
                    if (series.isNotEmpty) ...[_sectionTitle('Dizilerim'), posterRow(series)],
                  ],
                ),
              ),
            if (hasLeft && channels.isNotEmpty) const SizedBox(width: 14),
            if (channels.isNotEmpty)
              if (hasLeft)
                SizedBox(
                  width: 268,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: bottomPad),
                    child: _channelPanel(channels),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: bottomPad),
                    child: _channelPanel(channels),
                  ),
                ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.only(top: 4, bottom: phoneBottomClearance(context)),
      children: [
        if (continueList.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: continueHero(continueList.first)),
          const SizedBox(height: 20),
        ],
        if (recents.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _sectionTitle('Son izlediklerin')),
          const SizedBox(height: 4),
          recentsCarousel(),
          const SizedBox(height: 20),
        ],
        if (channels.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _channelPanel(channels)),
          const SizedBox(height: 20),
        ],
        if (movies.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _sectionTitle('Filmlerim')),
          const SizedBox(height: 4),
          posterRow(movies),
          const SizedBox(height: 18),
        ],
        if (series.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _sectionTitle('Dizilerim')),
          const SizedBox(height: 4),
          posterRow(series),
        ],
      ],
    );
  }

  /// Heading + body of a tab. The body gets the full width; scroll areas inside keep their own 8 px margin.
  Widget _page(PageHeader header, Widget body) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(padding: const EdgeInsets.fromLTRB(AppSizes.scrollPad, 16, 16, 0), child: header),
      const SizedBox(height: 14),
      Expanded(child: body),
    ],
  );

  /// The content search box of the current tab; its key changes per tab so switching tabs empties it.
  Widget _searchField(String hint) => LayoutBuilder(
    builder: (context, c) {
      final w = MediaQuery.sizeOf(context).width;
      return SearchField(key: ValueKey('search$_tab'), hint: hint, width: (w * 0.22).clamp(180.0, 300.0), onChanged: (v) => setState(() => _query = v));
    },
  );

  Widget _content() {
    if (_tab == _homeTab) {
      return _page(PageHeader(title: '${greeting(DateTime.now())}, ${widget.account.name}', actions: const [ClockPill()]), _homeView());
    }
    if (_tab == _settingsTab) {
      return _page(
        const PageHeader(title: 'Ayarlar', actions: [ClockPill()]),
        SettingsPage(info: widget.info, account: widget.account, client: widget.client, onLogout: _logout),
      );
    }
    if (_tab == _favoritesTab) {
      final match = queryMatcher(_query);
      final favs = Library.instance.favorites.where(_allowed).where((i) => match(foldedNameOf(i))).toList();
      return _page(
        PageHeader(title: 'Favoriler', actions: [_searchField('Favorilerde ara'), const ClockPill()]),
        _favoritesView(favs),
      );
    }

    final kind = _kind!;
    final view = _viewOf(kind);
    final shown = view.shown;
    final ready = !_loading.contains(kind) && _errors[kind] == null;
    final n = groupCount(shown.length);
    final (title, hint, subtitle) = switch (kind) {
      Kind.live => ('Canlı TV', 'Kanal ara', '${_group == null ? 'Tümü' : groupLabel(_group!)}, $n kanal'),
      Kind.movie => ('Filmler', 'Film ara', '$n film'),
      Kind.series => ('Diziler', 'Dizi ara', '$n dizi'),
    };

    return _page(
      PageHeader(title: title, subtitle: ready ? subtitle : null, actions: [_searchField(hint), if (kind != Kind.live) _sortButton(), const ClockPill()]),
      Padding(
        padding: const EdgeInsets.only(left: AppSizes.scrollPad),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSizes.scrollPad, bottom: 16),
            child: SizedBox(width: AppSizes.sideWidth, child: _categoryPanel(kind, view)),
          ),
          const SizedBox(width: 8),
          Expanded(child: _body(kind, shown)),
        ]),
      ),
    );
  }

  /// Category search, "Tümü" and the categories with their counts, and the key that opens the editor.
  Widget _categoryPanel(Kind kind, _View view, {bool compact = false}) {
    final names = AppSettings.instance.orderedGroups(kind, view.groups.keys).where((n) => matchesQuery(groupLabel(n), _groupQuery)).toList();
    final showAll = _groupQuery.trim().isEmpty;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SearchField(key: ValueKey('groupSearch$_tab'), hint: 'Kategori ara', onPage: false, onChanged: (v) => setState(() => _groupQuery = v)),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSizes.scrollPad),
            itemExtent: 46,
            itemCount: names.length + (showAll ? 1 : 0),
            itemBuilder: (_, i) {
              if (showAll && i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SideItem(label: 'Tümü', count: groupCount(view.total), selected: _group == null, onTap: () => setState(() => _group = null)),
                );
              }
              final name = names[i - (showAll ? 1 : 0)];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SideItem(
                  label: groupLabel(name),
                  count: groupCount(view.groups[name] ?? 0),
                  selected: _group == name,
                  tooltip: name,
                  onTap: () => setState(() => _group = name),
                  onLongPress: () => _manageGroups(kind),
                  onSecondaryTapUp: (d) => _groupMenu(kind, name, d.globalPosition), // right click: quick pin / hide
                ),
              );
            },
          ),
        ),
        AppButton(
          icon: Icons.tune_rounded,
          label: compact ? 'Düzenle' : 'Kategorileri düzenle',
          tooltip: 'Kategorileri düzenle / gizle',
          dense: true,
          onPressed: () => _manageGroups(kind),
        ),
      ]),
    );
  }

  // ─── Home tab ──────────────────────────────────────────────

  Widget _homeView() {
    final lib = Library.instance;
    final continueList = lib.continueWatching.take(7).toList();
    final favs = lib.favorites.where(_allowed).toList();
    List<Item> of(Kind k) => favs.where((i) => i.kind == k).toList();
    final channels = of(Kind.live);
    final movies = of(Kind.movie);
    final series = of(Kind.series);
    final recents = continueList.skip(1).toList();

    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (recents.isNotEmpty) ...[_sectionTitle('Son izlediklerin'), _recents(recents), const SizedBox(height: 18)],
      if (movies.isNotEmpty) ...[_sectionTitle('Filmlerim'), _posterStrip(movies), const SizedBox(height: 10)],
      if (series.isNotEmpty) ...[_sectionTitle('Dizilerim'), _posterStrip(series)],
    ]);
    final hasLeft = recents.isNotEmpty || movies.isNotEmpty || series.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSizes.scrollPad, AppSizes.scrollPad, 16, 16),
      children: [
        if (continueList.isNotEmpty) ...[_continueCard(continueList.first), const SizedBox(height: 22)],
        if (hasLeft || channels.isNotEmpty)
          LayoutBuilder(builder: (context, c) {
            if (channels.isEmpty) return left;
            if (!hasLeft) return _channelPanel(channels);
            if (c.maxWidth < 900) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 20), _channelPanel(channels)]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: left),
              const SizedBox(width: 20),
              SizedBox(width: 326, child: _channelPanel(channels)),
            ]);
          }),
        if (continueList.isEmpty && favs.isEmpty)
          AppCard(
            padding: const EdgeInsets.all(48),
            child: Text(
              'Burası senin sayfan.\nBeğendiğin kanal, film ve dizilerin kalp ikonuna dokun, burada görünsün.',
              textAlign: TextAlign.center,
              style: AppText.body(),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: AppText.title(18)));

  /// Time left of a history entry, or null when its duration is unknown.
  String? _left(HistoryEntry e) => e.durationMs > 0 ? remainingText(Duration(milliseconds: e.durationMs - e.positionMs)) : null;

  Widget _continueCard(HistoryEntry e) {
    final title = playerTitle(e.title).$1;
    final left = _left(e);
    return SizedBox(
      height: 246,
      child: AppCard(
        child: LayoutBuilder(builder: (context, c) {
          // the cover keeps its own 2:3 shape: never stretched or cropped into a wide strip
          final art = c.maxWidth < 560 ? 104.0 : 150.0;
          return Stack(children: [
            Positioned(
              right: 20,
              top: 16,
              bottom: 16,
              width: art,
              child: FocusRing(
                key: const ValueKey('home-continue-poster'),
                radius: AppSizes.tileRadius,
                tooltip: '$title sayfasına git',
                semanticLabel: '$title sayfasına git',
                onTap: () => _openHistoryDetail(e),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                  child: ColoredBox(color: AppColors.surfaceAlt, child: PosterImage(e.logo, cacheWidth: 400)),
                ),
              ),
            ),
            Positioned(
              left: 32,
              top: 0,
              bottom: 0,
              right: art + 44,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Pill('Kaldığın yerden', tone: PillTone.accent),
                const SizedBox(height: 12),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.display(32)),
                if (left != null) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    Flexible(flex: 3, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: ProgressBar(value: e.progress, height: 8))),
                    const SizedBox(width: 14),
                    Flexible(child: Text(left, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(14))),
                  ]),
                ],
                const SizedBox(height: 18),
                AppButton(
                  label: 'Devam et',
                  icon: Icons.play_arrow_rounded,
                  variant: AppButtonVariant.primary,
                  height: AppSizes.primaryHeight,
                  autofocus: AppSettings.instance.tvMode,
                  onPressed: () => _openHistory(e),
                ),
              ]),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _recents(List<HistoryEntry> list) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth < 420 ? 2 : 3;
        final w = (c.maxWidth - 16 - 18 * (cols - 1)) / cols;
        return Padding(
          padding: const EdgeInsets.all(AppSizes.scrollPad),
          child: Wrap(spacing: 18, runSpacing: 18, children: [
            for (final e in list.take(cols * 2)) SizedBox(width: w, child: RepaintBoundary(child: _recentCard(e))),
          ]),
        );
      });

  Widget _recentCard(HistoryEntry e) {
    final title = playerTitle(e.title).$1;
    final sub = [?episodeLabel(e.title), ?_left(e)].join(', ');
    return FocusRing(
      radius: AppSizes.cardRadius,
      onTap: () => _openHistory(e),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          boxShadow: AppShadows.forRepeated(),
          border: AppShadows.repeatedBorder(),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          FocusRing(
            key: ValueKey('home-recent-poster-${e.url}'),
            radius: AppSizes.smallRadius,
            lift: false,
            tooltip: '$title sayfasına git',
            semanticLabel: '$title sayfasına git',
            onTap: () => _openHistoryDetail(e),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.smallRadius),
              child: SizedBox(width: 72, height: 108, child: ColoredBox(color: AppColors.surfaceAlt, child: PosterImage(e.logo))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.title(15)),
              if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.meta(13))),
              if (e.durationMs > 0) Padding(padding: const EdgeInsets.only(top: 10, right: 6), child: ProgressBar(value: e.progress, height: 4)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _posterStrip(List<Item> items) => SizedBox(
        height: 132 + 2 * AppSizes.scrollPad,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(AppSizes.scrollPad),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final it = items[i];
            return FocusRing(
              radius: AppSizes.itemRadius,
              onTap: () => _open(it),
              tooltip: parsedTitleOf(it).title,
              child: Container(
                width: 92,
                height: 132,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppSizes.itemRadius), boxShadow: AppShadows.forRepeated(), border: AppShadows.repeatedBorder()),
                child: ClipRRect(borderRadius: BorderRadius.circular(AppSizes.itemRadius), child: PosterImage(it.logo)),
              ),
            );
          },
        ),
      );

  Widget _channelPanel(List<Item> channels) => AppCard(
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Row(children: [
              Expanded(child: Text('Kanallarım', style: AppText.title(18))),
              const LiveDot(),
              const SizedBox(width: 7),
              Text('Canlı', style: AppText.label(13, color: AppColors.liveText)),
            ]),
          ),
          SizedBox(
            height: (channels.length * 60.0 + 2 * AppSizes.scrollPad).clamp(0, 420),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSizes.scrollPad),
              itemExtent: 60,
              itemCount: channels.length,
              itemBuilder: (_, i) => _panelChannel(channels[i]),
            ),
          ),
        ]),
      );

  Widget _panelChannel(Item it) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: FocusRing(
          radius: AppSizes.itemRadius,
          lift: false,
          hoverColor: AppColors.surfaceAlt,
          onTap: () => _open(it),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: NowPlaying(
              cache: _epg,
              item: it,
              fallback: groupLabel(it.group),
              builder: (context, now) => Row(children: [
                ChannelBadge(name: it.name, logo: it.logo, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(15)),
                    Text(now?.title ?? groupLabel(it.group), maxLines: 1, overflow: TextOverflow.ellipsis, style: now == null ? AppText.meta(13) : AppText.note(13)),
                  ]),
                ),
                if (now != null) ...[const SizedBox(width: 10), SizedBox(width: 54, child: ProgressBar(value: now.progress))],
              ]),
            ),
          ),
        ),
      );

  static const _sortLabels = {
    _Sort.provider: 'Varsayılan',
    _Sort.added: 'Yeni eklenen',
    _Sort.name: 'A – Z',
    _Sort.year: 'Yıl, yeniden eskiye',
  };

  Widget _sortButton() => Builder(
        builder: (context) => AppButton(
          variant: AppButtonVariant.onPage,
          prefix: 'Sırala:',
          label: _sortLabels[_sort],
          trailingIcon: Icons.expand_more_rounded,
          onPressed: () async {
            final box = context.findRenderObject()! as RenderBox;
            final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
            final at = box.localToGlobal(Offset(0, box.size.height + 6), ancestor: overlay);
            final picked = await showMenu<_Sort>(
              context: context,
              position: RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx - box.size.width, 0),
              items: [for (final e in _sortLabels.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
            );
            if (picked != null && mounted) setState(() => _sort = picked);
          },
        ),
      );

  Widget _body(Kind kind, List<Item> shown, {bool phonePortrait = false, bool phoneLandscape = false}) {
    if (_loading.contains(kind)) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 220, child: ClipRRect(borderRadius: BorderRadius.circular(3), child: const LinearProgressIndicator(minHeight: 6))),
          const SizedBox(height: 14),
          Text('Yükleniyor...', style: AppText.meta(15)),
        ]),
      );
    }
    final err = _errors[kind];
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(err, textAlign: TextAlign.center, style: AppText.label(15, color: AppColors.liveText)),
            const SizedBox(height: 14),
            AppButton(label: 'Tekrar dene', variant: AppButtonVariant.primary, onPressed: () => _ensureLoaded(kind)),
          ]),
        ),
      );
    }
    if (shown.isEmpty) return Center(child: Text('Sonuç yok', style: AppText.meta(15)));
    return kind == Kind.live
        ? _liveList(shown, phonePortrait: phonePortrait, phoneLandscape: phoneLandscape)
        : _posterGrid(shown, phonePortrait: phonePortrait, phoneLandscape: phoneLandscape);
  }

  Widget _heart(Item it, {double size = 22}) {
    final fav = Library.instance.isFavorite(it);
    return FocusRing(
      radius: 22,
      lift: false,
      tooltip: fav ? 'Favorilerden çıkar' : 'Favorilere ekle',
      hoverColor: AppColors.surfaceAlt,
      onTap: () {
        AppHaptics.selection(context);
        Library.instance.toggleFavorite(it);
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: size, color: fav ? AppColors.live : AppColors.ink3),
      ),
    );
  }

  Widget _liveList(List<Item> shown, {bool phonePortrait = false, bool phoneLandscape = false}) {
    final pad = MediaQuery.paddingOf(context);
    final listPad = phonePortrait
        ? EdgeInsets.fromLTRB(16, 4, 16, phoneBottomClearance(context))
        : phoneLandscape
            ? EdgeInsets.fromLTRB(4, 4, 10, pad.bottom > 0 ? pad.bottom + 8 : 14)
            : const EdgeInsets.fromLTRB(AppSizes.scrollPad, AppSizes.scrollPad, 16, 16);
    return ListView.builder(
      key: const ValueKey('channel-list'),
      padding: listPad,
      itemExtent: phonePortrait ? 78 : 76,
      itemCount: shown.length,
      itemBuilder: (_, i) => phonePortrait ? _phoneChannelRow(shown[i], i) : _channelRow(shown[i], i),
    );
  }

  /// Touch-optimized iPhone portrait channel row with inline EPG bar and crisp hierarchy.
  Widget _phoneChannelRow(Item it, int index) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RepaintBoundary(
          child: Stack(children: [
            Positioned.fill(
              child: FocusRing(
                radius: 18,
                lift: false,
                onTap: () {
                  AppHaptics.light(context);
                  _open(it);
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 52, 0),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line, width: 1),
                  ),
                  child: NowPlaying(
                    cache: _epg,
                    item: it,
                    fallback: groupLabel(it.group),
                    builder: (context, now) => Row(children: [
                      ChannelBadge(name: it.name, logo: it.logo, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text('${index + 1}', style: AppText.meta(12, color: AppColors.ink3)),
                              const SizedBox(width: 6),
                              Expanded(child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(15))),
                            ]),
                            const SizedBox(height: 2),
                            Text(
                              now?.title ?? groupLabel(it.group),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: now == null ? AppText.meta(12.5) : AppText.note(12.5),
                            ),
                            if (now != null) ...[
                              const SizedBox(height: 5),
                              Row(children: [
                                Expanded(child: ProgressBar(value: now.progress, height: 3.5)),
                                const SizedBox(width: 8),
                                Text('${hhmm(now.start)}–${hhmm(now.end)}', style: AppText.meta(11, color: AppColors.ink3)),
                              ]),
                            ],
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            Positioned(right: 6, top: 13, child: _heart(it, size: 21)),
          ]),
        ),
      );

  /// A channel on its own white row: number, badge, name, programme now, time range and bar, heart.
  /// The heart sits beside the row's focus area (not inside it) so each has its own ring.
  Widget _channelRow(Item it, int index) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RepaintBoundary(
          child: Stack(children: [
            Positioned.fill(
              child: FocusRing(
                radius: AppSizes.tileRadius,
                onTap: () => _open(it),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 12 + 44 + 8, 0),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                    boxShadow: AppShadows.forRepeated(),
                    border: AppShadows.repeatedBorder(),
                  ),
                  child: NowPlaying(
                    cache: _epg,
                    item: it,
                    fallback: groupLabel(it.group),
                    // Narrow rows (small window, large UI scale) drop the number, then the time block.
                    builder: (context, now) => LayoutBuilder(builder: (context, c) => Row(children: [
                      if (c.maxWidth >= 240) ...[
                        SizedBox(width: 28, child: Text('${index + 1}', textAlign: TextAlign.right, style: AppText.meta(14))),
                        const SizedBox(width: 14),
                      ],
                      ChannelBadge(name: it.name, logo: it.logo),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(16)),
                          Text(now?.title ?? groupLabel(it.group), maxLines: 1, overflow: TextOverflow.ellipsis, style: now == null ? AppText.meta(13) : AppText.note(13)),
                        ]),
                      ),
                      if (now != null && c.maxWidth >= 340) ...[
                        const SizedBox(width: 12),
                        SizedBox(
                          width: c.maxWidth >= 440 ? 150 : 110,
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('${hhmm(now.start)} – ${hhmm(now.end)}', maxLines: 1, style: AppText.meta(c.maxWidth >= 440 ? 13 : 12)),
                            const SizedBox(height: 6),
                            ProgressBar(value: now.progress),
                          ]),
                        ),
                      ],
                    ])),
                  ),
                ),
              ),
            ),
            Positioned(right: 12, top: 12, child: _heart(it)),
          ]),
        ),
      );

  Widget _posterGrid(List<Item> shown, {bool phonePortrait = false, bool phoneLandscape = false}) => LayoutBuilder(builder: (context, c) {
        final safe = MediaQuery.paddingOf(context);
        final pad = phonePortrait
            ? EdgeInsets.fromLTRB(16, 4, 16, phoneBottomClearance(context))
            : phoneLandscape
                ? EdgeInsets.fromLTRB(4, 4, 10, safe.bottom > 0 ? safe.bottom + 8 : 14)
                : const EdgeInsets.fromLTRB(AppSizes.scrollPad, AppSizes.scrollPad, 16, 16);
        final gap = phonePortrait ? 12.0 : 16.0;
        final inner = c.maxWidth - pad.horizontal;
        final cols = phonePortrait ? (inner < 310 ? 2 : 3) : posterColumns(inner);
        final tile = (inner - gap * (cols - 1)) / cols;
        return GridView.builder(
          key: const ValueKey('poster-grid'),
          padding: pad,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: gap,
            mainAxisSpacing: phonePortrait ? 14 : 20,
            mainAxisExtent: tile * 1.50 + (phonePortrait ? 46 : 52),
          ),
          itemCount: shown.length,
          itemBuilder: (_, i) => _posterTile(shown[i], compact: phonePortrait),
        );
      });

  Widget _posterTile(Item it, {bool compact = false}) => RepaintBoundary(
        child: _PosterTile(
          key: ValueKey(it.id),
          item: it,
          favorite: Library.instance.isFavorite(it),
          compact: compact,
          onOpen: () => _open(it),
          onToggleFavorite: () {
            AppHaptics.selection(context);
            Library.instance.toggleFavorite(it);
          },
        ),
      );

  /// Favorites in three sections: channels as rows, movies and series as posters. Empty sections are left out.
  Widget _favoritesView(List<Item> favs, {bool phonePortrait = false, bool phoneLandscape = false}) {
    final safe = MediaQuery.paddingOf(context);
    final pad = phonePortrait
        ? EdgeInsets.fromLTRB(16, 4, 16, phoneBottomClearance(context))
        : phoneLandscape
            ? EdgeInsets.fromLTRB(safe.left > 0 ? safe.left : 14, 4, 12, safe.bottom > 0 ? safe.bottom + 8 : 14)
            : const EdgeInsets.fromLTRB(AppSizes.scrollPad, AppSizes.scrollPad, 16, 16);
    if (favs.isEmpty) {
      return Padding(
        padding: pad,
        child: Align(
          alignment: Alignment.topCenter,
          child: AppCard(
            padding: EdgeInsets.all(phonePortrait ? 28 : 48),
            child: Center(heightFactor: 1, child: Text('Henüz favori yok. Bir içeriğin kalp ikonuna dokun.', textAlign: TextAlign.center, style: AppText.body())),
          ),
        ),
      );
    }
    final channels = [for (final i in favs) if (i.kind == Kind.live) i];
    final movies = [for (final i in favs) if (i.kind == Kind.movie) i];
    final series = [for (final i in favs) if (i.kind == Kind.series) i];
    return LayoutBuilder(builder: (context, c) {
      final gap = phonePortrait ? 12.0 : 16.0;
      final inner = c.maxWidth - pad.horizontal;
      final cols = phonePortrait ? (inner < 310 ? 2 : 3) : posterColumns(inner);
      final tile = (inner - gap * (cols - 1)) / cols;
      Widget heading(String t, {bool first = false}) =>
          SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: first ? 0 : 14, bottom: 10), child: Text(t, style: AppText.title(18))));
      Widget grid(List<Item> items) => SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: gap,
              mainAxisSpacing: phonePortrait ? 14 : 20,
              mainAxisExtent: tile * 1.50 + (phonePortrait ? 46 : 52),
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _posterTile(items[i], compact: phonePortrait),
          );
      return CustomScrollView(slivers: [
        SliverPadding(
          padding: pad,
          sliver: SliverMainAxisGroup(slivers: [
            if (channels.isNotEmpty) ...[
              heading('Kanallar', first: true),
              SliverFixedExtentList.builder(
                itemExtent: phonePortrait ? 78 : 76,
                itemCount: channels.length,
                itemBuilder: (_, i) => phonePortrait ? _phoneChannelRow(channels[i], i) : _channelRow(channels[i], i),
              ),
            ],
            if (movies.isNotEmpty) ...[heading('Filmler', first: channels.isEmpty), grid(movies)],
            if (series.isNotEmpty) ...[heading('Diziler', first: channels.isEmpty && movies.isEmpty), grid(series)],
          ]),
        ),
      ]);
    });
  }
}

class _View {
  _View(this.key, this.shown, this.groups, this.total);

  final Object key;
  final List<Item> shown;
  final Map<String, int> groups; // category -> item count
  final int total; // count shown next to "Tümü"
}

/// Number of poster columns that fit [width]: 118 px posters with 16 px gaps, at least two.
int posterColumns(double width) => max(2, ((width + 16) / 134).floor());

/// A poster with its title and "year, language" below and a favorite heart in its top right corner. The heart
/// is its own focus stop; when the item is not a favorite it only shows while the poster or the heart has focus
/// or the mouse.
class _PosterTile extends StatefulWidget {
  const _PosterTile({super.key, required this.item, required this.favorite, required this.onOpen, required this.onToggleFavorite, this.compact = false});

  final Item item;
  final bool favorite;
  final bool compact;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;

  @override
  State<_PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<_PosterTile> {
  bool _tileFocus = false, _tileHover = false, _heartFocus = false, _heartHover = false;

  @override
  Widget build(BuildContext context) {
    final t = parsedTitleOf(widget.item);
    final sub = [?t.year, if (t.tags.isNotEmpty) t.tags.first].join(', ');
    final radius = widget.compact ? 15.0 : AppSizes.tileRadius;
    final showHeart = widget.favorite || _tileFocus || _tileHover || _heartFocus || _heartHover;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: Stack(children: [
          Positioned.fill(
            child: FocusRing(
              radius: radius,
              onTap: widget.onOpen,
              onLongPress: widget.compact ? widget.onToggleFavorite : null,
              onFocusChange: (f) => setState(() => _tileFocus = f),
              onHoverChange: (h) => setState(() => _tileHover = h),
              builder: (context, focused, hovered) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: hovered && !focused ? AppShadows.lift : AppShadows.forRepeated(),
                    border: AppShadows.repeatedBorder() ?? (widget.compact ? Border.all(color: AppColors.line, width: 0.8) : null),
                  ),
                  child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: PosterImage(widget.item.logo)),
                );
              },
            ),
          ),
          Positioned(
            top: widget.compact ? 0 : 1,
            right: widget.compact ? 0 : 1,
            child: Opacity(
              opacity: showHeart ? 1 : 0,
              child: FocusRing(
                radius: 22,
                lift: false,
                tooltip: widget.favorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
                onTap: widget.onToggleFavorite,
                onFocusChange: (f) => setState(() => _heartFocus = f),
                onHoverChange: (h) => setState(() => _heartHover = h),
                builder: (context, focused, hovered) {
                  return SizedBox(
                    width: widget.compact ? 38 : 44,
                    height: widget.compact ? 38 : 44,
                    child: Center(
                      child: Container(
                        width: widget.compact ? 26 : 30,
                        height: widget.compact ? 26 : 30,
                        decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, boxShadow: AppShadows.chip),
                        child: Icon(
                          widget.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: widget.compact ? 14 : 16,
                          color: widget.favorite ? AppColors.live : AppColors.ink2,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ]),
      ),
      SizedBox(height: widget.compact ? 6 : 8),
      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(widget.compact ? 13.5 : 15)),
      SizedBox(height: widget.compact ? 17 : 20, child: sub.isEmpty ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(widget.compact ? 12 : 13))),
    ]);
  }
}
