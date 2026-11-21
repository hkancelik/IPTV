import 'dart:async';
import 'dart:math' show Random, max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog_cache.dart';
import 'detail_page.dart';
import 'downloads.dart';
import 'downloads_page.dart';
import 'epg_widgets.dart';
import 'global_search_page.dart';
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

// Navigation tabs: 0 home, 1 live, 2 movies, 3 series, 4 shelf (Rafım), 5 settings, 6 downloads
enum _Sort { provider, added, name, year }
enum _ShelfTab { favorites, diary, watchlist }
enum _DiaryViewMode { feed, wall }
enum _DiarySort { recent, ratingDesc, ratingAsc, name }

const _homeTab = 0;
const _favoritesTab = 4;
const _settingsTab = 5;
const _downloadsTab = 6;

class _CatalogSignal extends ChangeNotifier {
  void bump() => notifyListeners();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  int _lastMainTab = 0;
  final Map<Kind, List<Item>> _items = {};
  final Map<Kind, String?> _errors = {};
  final Set<Kind> _loading = {};
  final Set<Kind> _refreshing = {};
  final Map<Kind, DateTime> _cachedAt = {};
  final _CatalogSignal _catalogSignal = _CatalogSignal();
  String? _group;
  String _query = '';
  String _groupQuery = ''; // filters the category sidebar
  _Sort _sort = _Sort.provider;

  // Rafım (shelf hub) state
  _ShelfTab _shelfTab = _ShelfTab.favorites;
  _DiaryViewMode _diaryView = _DiaryViewMode.feed;
  _DiarySort _diarySort = _DiarySort.recent;
  Kind? _diaryKind;
  int? _diaryYear;
  double? _diaryRatingFilter;
  bool _diaryOnlyReviews = false;
  bool _diaryOnlyRewatch = false;
  Kind? _watchlistKind;
  final Random _rng = Random();
  String? _lastRandomPickId;

  Kind? get _kind => _tab >= 1 && _tab <= 3 ? Kind.values[_tab - 1] : null;

  late final EpgCache _epg = EpgCache(widget.client);

  @override
  void initState() {
    super.initState();
    DownloadManager.instance.setAccount(widget.account);
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.key != widget.account.key) {
      _items.clear();
      _errors.clear();
      _loading.clear();
      _refreshing.clear();
      _cachedAt.clear();
      _view = null;
      _diaryKind = null;
      _diaryYear = null;
      _diaryRatingFilter = null;
      _diaryOnlyReviews = false;
      _diaryOnlyRewatch = false;
      _watchlistKind = null;
      _lastRandomPickId = null;
      _catalogSignal.bump();
      DownloadManager.instance.setAccount(widget.account);
    }
  }

  @override
  void dispose() {
    _catalogSignal.dispose();
    super.dispose();
  }

  Future<void> _ensureLoaded(Kind kind, {bool forceRefresh = false}) async {
    if (!forceRefresh && (_items.containsKey(kind) || _loading.contains(kind))) return;
    if (forceRefresh && (_loading.contains(kind) || _refreshing.contains(kind))) return;

    final account = widget.account;

    // Fast path: hydrate immediately from compressed disk cache when available.
    if (!forceRefresh && !_items.containsKey(kind) && CatalogCache.instance.isEnabled) {
      _loading.add(kind);
      final snapshot = await CatalogCache.instance.read(account, kind);
      if (!mounted || widget.account.key != account.key) return;
      if (snapshot != null) {
        setState(() {
          _loading.remove(kind);
          _items[kind] = snapshot.items;
          _cachedAt[kind] = snapshot.savedAt;
          _errors[kind] = null;
        });
        _catalogSignal.bump();
        if (!snapshot.isFresh(CatalogCache.defaultFreshTtl)) {
          unawaited(_fetchFromNetwork(kind, account, background: true, userTriggered: false));
        }
        return;
      }
      _loading.remove(kind);
    }

    final background = forceRefresh && _items.containsKey(kind);
    await _fetchFromNetwork(kind, account, background: background, userTriggered: forceRefresh);
  }

  Future<void> _fetchFromNetwork(
    Kind kind,
    Account account, {
    required bool background,
    required bool userTriggered,
  }) async {
    if (background) {
      if (_refreshing.contains(kind)) return;
      setState(() => _refreshing.add(kind));
    } else {
      if (_loading.contains(kind)) return;
      setState(() {
        _loading.add(kind);
        _errors[kind] = null;
      });
    }
    _catalogSignal.bump();

    try {
      final c = widget.client;
      final fetched = switch (kind) {
        Kind.live => await c.live(),
        Kind.movie => await c.movies(),
        Kind.series => await c.series(),
      };
      if (!mounted || widget.account.key != account.key) return;
      final now = DateTime.now();
      setState(() {
        _items[kind] = fetched;
        _cachedAt[kind] = now;
        _errors[kind] = null;
      });
      unawaited(CatalogCache.instance.write(account, kind, fetched, now: now));
    } on XtreamException catch (e) {
      if (!mounted || widget.account.key != account.key) return;
      if (background) {
        if (userTriggered) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Liste yenilenemedi: ${e.message}')));
        }
      } else {
        _errors[kind] = e.message;
      }
    } catch (e) {
      if (!mounted || widget.account.key != account.key) return;
      if (background) {
        if (userTriggered) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Liste yenilenemedi: $e')));
        }
      } else {
        _errors[kind] = 'Liste yüklenemedi: $e';
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading.remove(kind);
          _refreshing.remove(kind);
        });
        _catalogSignal.bump();
      }
    }
  }

  void _onCatalogCacheCleared() {
    setState(() {
      _items.clear();
      _cachedAt.clear();
      _errors.clear();
      _view = null;
    });
    _catalogSignal.bump();
  }

  void _openGlobalSearch([String initialQuery = '']) {
    Navigator.of(context).push(
      appRoute(
        context,
        (_) => GlobalSearchPage(
          account: widget.account,
          client: widget.client,
          epg: _epg,
          catalogListenable: _catalogSignal,
          itemsFor: (k) => _items[k] ?? const <Item>[],
          isLoading: (k) => _loading.contains(k),
          errorFor: (k) => _errors[k],
          ensureLoaded: (k) => _ensureLoaded(k),
          isAllowed: _allowed,
          onPlayLive: _playLiveFromQueue,
          initialQuery: initialQuery,
        ),
      ),
    );
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
    _playLiveFromQueue(item, list);
  }

  void _playLiveFromQueue(Item item, List<Item> queue) {
    var list = queue;
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
      listenable: Listenable.merge([AppSettings.instance, Library.instance, PlayerSession.instance, DownloadManager.instance]),
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
            AppLayoutMode.desktop => CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openGlobalSearch,
                  const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openGlobalSearch,
                },
                child: Scaffold(
                  body: Row(
                    children: [
                      SideMenu(selected: _tab, onSelect: _select, accountName: widget.account.name, onAccount: _logout),
                      const SizedBox(width: 8),
                      Expanded(child: _content()),
                    ],
                  ),
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

  List<Widget> _phoneHeaderEndActions() {
    final activeDownloads = DownloadManager.instance.activeCount;
    return [
      Stack(
        clipBehavior: Clip.none,
        children: [
          PhoneIconButton(
            key: const ValueKey('nav-downloads'),
            icon: Icons.download_for_offline_rounded,
            tooltip: 'İndirilenler',
            active: _tab == _downloadsTab,
            onTap: () => _select(_tab == _downloadsTab ? _lastMainTab : _downloadsTab),
          ),
          if (activeDownloads > 0)
            Positioned(
              right: 2,
              top: 2,
              child: IgnorePointer(
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _tab == _downloadsTab ? AppColors.onAccent : AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.ground, width: 1.5),
                  ),
                ),
              ),
            ),
        ],
      ),
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
  }

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

  Widget _refreshCatalogButton(Kind kind, {double height = AppSizes.buttonHeight}) {
    final busy = _refreshing.contains(kind) || _loading.contains(kind);
    return AppButton(
      key: const ValueKey('refresh-catalog'),
      variant: AppButtonVariant.onPage,
      height: height,
      width: height,
      tooltip: busy ? 'Yenileniyor...' : 'Listeyi yenile',
      icon: busy ? null : Icons.refresh_rounded,
      onPressed: busy ? null : () => _ensureLoaded(kind, forceRefresh: true),
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink2),
            )
          : null,
    );
  }

  Widget _phoneHomeSearchTrigger() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GestureDetector(
          key: const ValueKey('global-search-button'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AppHaptics.selection(context);
            _openGlobalSearch();
          },
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.line),
              boxShadow: AppShadows.chip,
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, size: 18, color: AppColors.ink2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kanal, film veya dizi ara...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta(14.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _phonePortraitContent() {
    if (_tab == _homeTab) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneTopBar(
            title: '${greeting(DateTime.now())}, ${widget.account.name}',
            actions: _phoneHeaderEndActions(),
          ),
          _phoneHomeSearchTrigger(),
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
              onCatalogCacheCleared: _onCatalogCacheCleared,
            ),
          ),
        ],
      );
    }
    if (_tab == _downloadsTab) {
      final mgr = DownloadManager.instance;
      final sub = mgr.completedCount > 0 || mgr.activeCount > 0
          ? [if (mgr.completedCount > 0) '${mgr.completedCount} hazır', if (mgr.activeCount > 0) '${mgr.activeCount} iniyor'].join(' · ')
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneTopBar(title: 'İndirilenler', subtitle: sub, actions: _phoneHeaderEndActions()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SearchField(key: ValueKey('search$_tab'), hint: 'İndirilenlerde ara', onChanged: (v) => setState(() => _query = v)),
          ),
          Expanded(
            child: DownloadsPage(
              account: widget.account,
              client: widget.client,
              embedded: true,
              query: _query,
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
          PhoneTopBar(title: 'Rafım', subtitle: _shelfSubtitle(favs), actions: _phoneHeaderEndActions()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SearchField(
              key: ValueKey('search$_tab-${_shelfTab.name}'),
              hint: _shelfSearchHint(),
              onChanged: (v) => setState(() => _query = v),
            ),
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
              const SizedBox(width: 8),
              _refreshCatalogButton(kind, height: 44),
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
          PhoneTopBar(
            title: '${greeting(DateTime.now())}, ${widget.account.name}',
            landscape: true,
            actions: [
              PhoneIconButton(
                key: const ValueKey('global-search-button'),
                icon: Icons.search_rounded,
                tooltip: 'Kanal, film veya dizi ara',
                onTap: _openGlobalSearch,
              ),
            ],
          ),
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
              onCatalogCacheCleared: _onCatalogCacheCleared,
            ),
          ),
        ],
      );
    }
    if (_tab == _downloadsTab) {
      final mgr = DownloadManager.instance;
      final sub = mgr.completedCount > 0 || mgr.activeCount > 0
          ? [if (mgr.completedCount > 0) '${mgr.completedCount} hazır', if (mgr.activeCount > 0) '${mgr.activeCount} iniyor'].join(' · ')
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneTopBar(
            title: 'İndirilenler',
            subtitle: sub,
            landscape: true,
            actions: [
              SearchField(key: ValueKey('search$_tab'), hint: 'İndirilenlerde ara', width: 220, onChanged: (v) => setState(() => _query = v)),
            ],
          ),
          Expanded(
            child: DownloadsPage(
              account: widget.account,
              client: widget.client,
              embedded: true,
              query: _query,
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
            title: 'Rafım',
            subtitle: _shelfSubtitle(favs),
            landscape: true,
            actions: [
              SearchField(
                key: ValueKey('search$_tab-${_shelfTab.name}'),
                hint: _shelfSearchHint(),
                width: 220,
                onChanged: (v) => setState(() => _query = v),
              ),
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
            _refreshCatalogButton(kind, height: 40),
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSizes.itemRadius - 1),
                    child: PosterImage(it.logo, rating: Library.instance.ratingFor(it)),
                  ),
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
  Widget _searchField(String hint, {String? keySuffix}) => LayoutBuilder(
    builder: (context, c) {
      final w = MediaQuery.sizeOf(context).width;
      return SearchField(
        key: ValueKey('search$_tab${keySuffix ?? ''}'),
        hint: hint,
        width: (w * 0.22).clamp(180.0, 300.0),
        onChanged: (v) => setState(() => _query = v),
      );
    },
  );

  Widget _content() {
    if (_tab == _homeTab) {
      return _page(
        PageHeader(
          title: '${greeting(DateTime.now())}, ${widget.account.name}',
          actions: [
            AppButton(
              key: const ValueKey('global-search-button'),
              variant: AppButtonVariant.onPage,
              icon: Icons.search_rounded,
              label: 'Ara',
              tooltip: 'Kanal, film ve dizi ara (Ctrl+K)',
              onPressed: _openGlobalSearch,
            ),
            const ClockPill(),
          ],
        ),
        _homeView(),
      );
    }
    if (_tab == _settingsTab) {
      return _page(
        const PageHeader(title: 'Ayarlar', actions: [ClockPill()]),
        SettingsPage(
          info: widget.info,
          account: widget.account,
          client: widget.client,
          onLogout: _logout,
          onCatalogCacheCleared: _onCatalogCacheCleared,
        ),
      );
    }
    if (_tab == _downloadsTab) {
      final mgr = DownloadManager.instance;
      final sub = mgr.completedCount > 0 || mgr.activeCount > 0
          ? [if (mgr.completedCount > 0) '${mgr.completedCount} hazır', if (mgr.activeCount > 0) '${mgr.activeCount} kuyrukta'].join(' · ')
          : null;
      return _page(
        PageHeader(title: 'İndirilenler', subtitle: sub, actions: [_searchField('İndirilenlerde ara'), const ClockPill()]),
        DownloadsPage(
          account: widget.account,
          client: widget.client,
          embedded: true,
          query: _query,
        ),
      );
    }
    if (_tab == _favoritesTab) {
      final match = queryMatcher(_query);
      final favs = Library.instance.favorites.where(_allowed).where((i) => match(foldedNameOf(i))).toList();
      return _page(
        PageHeader(
          title: 'Rafım',
          subtitle: _shelfSubtitle(favs),
          actions: [_searchField(_shelfSearchHint(), keySuffix: '-${_shelfTab.name}'), const ClockPill()],
        ),
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
      PageHeader(
        title: title,
        subtitle: ready ? subtitle : null,
        actions: [_searchField(hint), if (kind != Kind.live) _sortButton(), _refreshCatalogButton(kind), const ClockPill()],
      ),
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSizes.itemRadius),
                  child: PosterImage(it.logo, rating: Library.instance.ratingFor(it)),
                ),
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
    if (shown.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sonuç yok', style: AppText.meta(15)),
            if (_query.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              AppButton(
                key: const ValueKey('widen-to-global-search'),
                icon: Icons.search_rounded,
                label: 'Tüm katalogda ara',
                onPressed: () => _openGlobalSearch(_query),
              ),
            ],
          ],
        ),
      );
    }
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

  // ─── Rafım (Favoriler · Günlüğüm · Sonra İzle) ────────────

  void _selectShelfTab(_ShelfTab next) {
    if (_shelfTab == next) return;
    setState(() {
      _shelfTab = next;
      _query = '';
    });
  }

  bool _isDiaryEntry(MediaLogEntry e) =>
      _allowed(e.item) && (e.watched || e.rating != null || e.review.trim().isNotEmpty || e.liked);

  List<MediaLogEntry> _allDiaryEntries() => [
        for (final e in Library.instance.mediaLog)
          if (_isDiaryEntry(e)) e,
      ];

  List<MediaLogEntry> _allWatchlistEntries() => [
        for (final e in Library.instance.watchlist)
          if (_allowed(e.item)) e,
      ];

  String _shelfSearchHint() => switch (_shelfTab) {
        _ShelfTab.favorites => 'Favorilerde ara',
        _ShelfTab.diary => 'Günlükte ara',
        _ShelfTab.watchlist => 'Sonra İzle\'de ara',
      };

  String? _shelfSubtitle(List<Item> favs) => switch (_shelfTab) {
        _ShelfTab.favorites => favs.isEmpty ? null : '${groupCount(favs.length)} kayıt',
        _ShelfTab.diary => () {
            final n = _allDiaryEntries().length;
            return n == 0 ? null : '${groupCount(n)} yapım';
          }(),
        _ShelfTab.watchlist => () {
            final n = _allWatchlistEntries().length;
            return n == 0 ? null : '${groupCount(n)} yapım';
          }(),
      };

  static const _diarySortLabels = {
    _DiarySort.recent: 'Son izlenen',
    _DiarySort.ratingDesc: 'Puan, yüksekten düşüğe',
    _DiarySort.ratingAsc: 'Puan, düşükten yükseğe',
    _DiarySort.name: 'A – Z',
  };

  /// Three-tab "Rafım" hub: Favoriler, Günlüğüm, and Sonra İzle.
  Widget _favoritesView(List<Item> favs, {bool phonePortrait = false, bool phoneLandscape = false}) {
    final safe = MediaQuery.paddingOf(context);
    final pad = phonePortrait
        ? EdgeInsets.fromLTRB(16, 4, 16, phoneBottomClearance(context))
        : phoneLandscape
            ? EdgeInsets.fromLTRB(safe.left > 0 ? safe.left : 14, 4, 12, safe.bottom > 0 ? safe.bottom + 8 : 14)
            : const EdgeInsets.fromLTRB(AppSizes.scrollPad, AppSizes.scrollPad, 16, 16);
    final headerPad = phonePortrait
        ? const EdgeInsets.fromLTRB(16, 0, 16, 10)
        : phoneLandscape
            ? EdgeInsets.fromLTRB(safe.left > 0 ? safe.left : 14, 0, 12, 8)
            : const EdgeInsets.fromLTRB(AppSizes.scrollPad, 0, 16, 12);

    final favTotal = Library.instance.favorites.where(_allowed).length;
    final diaryEntries = _allDiaryEntries();
    final watchlistEntries = _allWatchlistEntries();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: headerPad,
          child: _shelfSubTabBar(
            favCount: favTotal,
            diaryCount: diaryEntries.length,
            watchlistCount: watchlistEntries.length,
            phonePortrait: phonePortrait,
          ),
        ),
        Expanded(
          child: switch (_shelfTab) {
            _ShelfTab.favorites => _favoritesListBody(
                favs,
                hasAnyFavorites: favTotal > 0,
                pad: pad,
                phonePortrait: phonePortrait,
              ),
            _ShelfTab.diary => _diaryBody(
                diaryEntries,
                pad: pad,
                phonePortrait: phonePortrait,
              ),
            _ShelfTab.watchlist => _watchlistBody(
                watchlistEntries,
                pad: pad,
                phonePortrait: phonePortrait,
              ),
          },
        ),
      ],
    );
  }

  Widget _shelfSubTabBar({
    required int favCount,
    required int diaryCount,
    required int watchlistCount,
    required bool phonePortrait,
  }) {
    final tabs = [
      (tab: _ShelfTab.favorites, key: 'shelf-tab-favorites', label: 'Favoriler', icon: Icons.favorite_rounded, count: favCount),
      (tab: _ShelfTab.diary, key: 'shelf-tab-diary', label: 'Günlüğüm', icon: Icons.auto_stories_rounded, count: diaryCount),
      (tab: _ShelfTab.watchlist, key: 'shelf-tab-watchlist', label: 'Sonra İzle', icon: Icons.bookmark_rounded, count: watchlistCount),
    ];

    Widget buildTab(({_ShelfTab tab, String key, String label, IconData icon, int count}) t, {required bool expand}) {
      final on = _shelfTab == t.tab;
      final item = Semantics(
        button: true,
        selected: on,
        inMutuallyExclusiveGroup: true,
        child: FocusRing(
          key: ValueKey(t.key),
          selected: on,
          radius: AppSizes.smallRadius,
          lift: false,
          onTap: () {
            AppHaptics.selection(context);
            _selectShelfTab(t.tab);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 38,
            padding: EdgeInsets.symmetric(horizontal: phonePortrait ? 8 : 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.surface : AppColors.transparent,
              borderRadius: BorderRadius.circular(AppSizes.smallRadius),
              boxShadow: on ? AppShadows.chip : null,
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(t.icon, size: 16, color: on ? AppColors.accentInk : AppColors.ink2),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(phonePortrait ? 12.5 : 13.5, color: on ? AppColors.ink : AppColors.ink2),
                  ),
                ),
                if (t.count > 0 && !phonePortrait) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: on ? AppColors.accentSoft : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      groupCount(t.count),
                      style: AppText.meta(11.5, color: on ? AppColors.accentInk : AppColors.ink2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      return expand ? Expanded(child: item) : item;
    }

    if (phonePortrait) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            for (final t in tabs) buildTab(t, expand: true),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                buildTab(tabs[i], expand: false),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Favorites in three sections: channels as rows, movies and series as posters. Empty sections are left out.
  Widget _favoritesListBody(
    List<Item> favs, {
    required bool hasAnyFavorites,
    required EdgeInsets pad,
    required bool phonePortrait,
  }) {
    if (favs.isEmpty) {
      return Padding(
        padding: pad,
        child: Align(
          alignment: Alignment.topCenter,
          child: AppCard(
            padding: EdgeInsets.all(phonePortrait ? 28 : 48),
            child: Center(
              heightFactor: 1,
              child: Text(
                hasAnyFavorites
                    ? 'Aramayla eşleşen favori yok.'
                    : 'Henüz favori yok. Bir içeriğin kalp ikonuna dokun.',
                textAlign: TextAlign.center,
                style: AppText.body(),
              ),
            ),
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

  // ─── Günlüğüm (Diary) sub-tab ──────────────────────────────

  Widget _diaryBody(
    List<MediaLogEntry> allDiary, {
    required EdgeInsets pad,
    required bool phonePortrait,
  }) {
    if (allDiary.isEmpty) {
      return Padding(
        padding: pad,
        child: Align(
          alignment: Alignment.topCenter,
          child: AppCard(
            padding: EdgeInsets.all(phonePortrait ? 28 : 48),
            child: Center(
              heightFactor: 1,
              child: Text(
                'Günlüğün henüz boş.\nİzlediğin film veya dizilerin detay sayfasından yarım yıldızlı puan verip kısa notunu ekleyebilirsin.',
                textAlign: TextAlign.center,
                style: AppText.body(),
              ),
            ),
          ),
        ),
      );
    }

    final yearSet = <int>{};
    for (final e in allDiary) {
      if (e.watches.isNotEmpty) {
        for (final w in e.watches) {
          yearSet.add(w.watchedAt.year);
        }
      } else {
        yearSet.add(DateTime.fromMillisecondsSinceEpoch(e.updatedAtMs).year);
      }
    }
    final years = yearSet.toList()..sort((a, b) => b.compareTo(a));
    final effectiveYear = _diaryYear != null && yearSet.contains(_diaryYear) ? _diaryYear : null;
    final query = _query.trim();
    final matchTitle = queryMatcher(query);

    bool matchesEntry(MediaLogEntry e) {
      if (_diaryKind != null && e.item.kind != _diaryKind) return false;
      if (_diaryOnlyReviews && e.review.trim().isEmpty) return false;
      if (_diaryOnlyRewatch && e.rewatchCount == 0) return false;
      if (effectiveYear != null) {
        final inYear = e.watches.isNotEmpty
            ? e.watches.any((w) => w.watchedAt.year == effectiveYear)
            : DateTime.fromMillisecondsSinceEpoch(e.updatedAtMs).year == effectiveYear;
        if (!inYear) return false;
      }
      if (query.isNotEmpty) {
        final hitTitle = matchTitle(foldedNameOf(e.item));
        final hitReview = matchesQuery(e.review, query);
        if (!hitTitle && !hitReview) return false;
      }
      return true;
    }

    final baseEntries = [for (final e in allDiary) if (matchesEntry(e)) e];
    final statsYear = effectiveYear ?? DateTime.now().year;

    var yearlyWatches = 0;
    var movieCount = 0;
    var seriesCount = 0;
    var ratedCount = 0;
    var ratingSum = 0.0;
    final buckets = List<int>.filled(10, 0);

    for (final e in baseEntries) {
      if (e.item.kind == Kind.movie) {
        movieCount++;
      } else if (e.item.kind == Kind.series) {
        seriesCount++;
      }
      if (e.watches.isNotEmpty) {
        for (final w in e.watches) {
          if (w.watchedAt.year == statsYear) yearlyWatches++;
        }
      } else if (DateTime.fromMillisecondsSinceEpoch(e.updatedAtMs).year == statsYear) {
        yearlyWatches++;
      }
      final r = e.rating;
      if (r != null) {
        ratedCount++;
        ratingSum += r;
        final idx = ((r * 2).round() - 1).clamp(0, 9);
        buckets[idx]++;
      }
    }
    final avgRating = ratedCount == 0 ? null : ratingSum / ratedCount;

    final shownEntries = _diaryRatingFilter == null
        ? baseEntries
        : [for (final e in baseEntries) if (e.rating == _diaryRatingFilter) e];

    final hasFilters = _diaryKind != null ||
        effectiveYear != null ||
        _diaryRatingFilter != null ||
        _diaryOnlyReviews ||
        _diaryOnlyRewatch;

    void clearFilters() {
      setState(() {
        _diaryKind = null;
        _diaryYear = null;
        _diaryRatingFilter = null;
        _diaryOnlyReviews = false;
        _diaryOnlyRewatch = false;
      });
    }

    return LayoutBuilder(builder: (context, c) {
      final gap = phonePortrait ? 12.0 : 16.0;
      final inner = c.maxWidth - pad.horizontal;
      final cols = phonePortrait ? (inner < 310 ? 2 : 3) : posterColumns(inner);
      final tile = (inner - gap * (cols - 1)) / cols;

      final List<Widget> contentSlivers;
      if (shownEntries.isEmpty) {
        contentSlivers = [
          SliverToBoxAdapter(
            child: AppCard(
              radius: AppSizes.cardRadius,
              padding: EdgeInsets.all(phonePortrait ? 24 : 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Seçili filtrelere uyan günlük kaydı yok.', textAlign: TextAlign.center, style: AppText.body()),
                  if (hasFilters) ...[
                    const SizedBox(height: 14),
                    AppButton(
                      key: const ValueKey('diary-clear-filters'),
                      label: 'Filtreleri temizle',
                      variant: AppButtonVariant.primary,
                      onPressed: clearFilters,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ];
      } else if (_diaryView == _DiaryViewMode.feed) {
        contentSlivers = _diaryFeedSlivers(shownEntries, effectiveYear: effectiveYear, compact: phonePortrait);
      } else {
        contentSlivers = _diaryWallSlivers(
          shownEntries,
          cols: cols,
          gap: gap,
          tileWidth: tile,
          compact: phonePortrait,
        );
      }

      return CustomScrollView(
        key: const ValueKey('diary-scroll'),
        slivers: [
          SliverPadding(
            padding: pad,
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: _diaryStatsCard(
                    statsYear: statsYear,
                    yearlyWatches: yearlyWatches,
                    totalTitles: baseEntries.length,
                    movieCount: movieCount,
                    seriesCount: seriesCount,
                    avgRating: avgRating,
                    ratedCount: ratedCount,
                    buckets: buckets,
                    compact: inner < 620,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                SliverToBoxAdapter(
                  child: _diaryControlsBar(
                    years: years,
                    effectiveYear: effectiveYear,
                    hasFilters: hasFilters,
                    onClearFilters: clearFilters,
                    compact: phonePortrait,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ...contentSlivers,
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _diaryStatsCard({
    required int statsYear,
    required int yearlyWatches,
    required int totalTitles,
    required int movieCount,
    required int seriesCount,
    required double? avgRating,
    required int ratedCount,
    required List<int> buckets,
    required bool compact,
  }) {
    final kindSummary = [
      if (movieCount > 0) '$movieCount film',
      if (seriesCount > 0) '$seriesCount dizi',
    ].join(' · ');

    Widget metricTile({
      required Key valueKey,
      required String value,
      String? suffix,
      required Color valueColor,
      required String label,
      required String meta,
    }) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: compact ? 12 : 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(11.5, color: AppColors.ink2)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    key: valueKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(compact ? 26 : 30, color: valueColor),
                  ),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(suffix, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12.5)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12)),
          ],
        ),
      );
    }

    final yearlyMetric = metricTile(
      valueKey: const ValueKey('diary-yearly-count'),
      value: groupCount(yearlyWatches),
      valueColor: AppColors.ink,
      label: '$statsYear İZLEME',
      meta: kindSummary.isEmpty ? 'Toplam ${groupCount(totalTitles)} yapım' : kindSummary,
    );

    final avgMetric = metricTile(
      valueKey: const ValueKey('diary-average-rating'),
      value: avgRating == null ? '—' : avgRating.toStringAsFixed(1),
      suffix: '/ 5.0',
      valueColor: avgRating == null ? AppColors.ink2 : AppColors.star,
      label: 'ORTALAMA PUAN',
      meta: ratedCount == 0
          ? 'Henüz puan yok'
          : '${groupCount(ratedCount)} puan · ${starGlyphs(MediaLogEntry.normalizeRating(avgRating)!)}',
    );

    final histogram = _DiaryRatingHistogram(
      buckets: buckets,
      selectedRating: _diaryRatingFilter,
      compact: compact,
      onSelectRating: (next) {
        AppHaptics.selection(context);
        setState(() => _diaryRatingFilter = next);
      },
    );

    return AppCard(
      key: const ValueKey('diary-stats-card'),
      radius: AppSizes.cardRadius,
      padding: EdgeInsets.all(compact ? 14 : 18),
      border: Border.all(color: AppColors.line),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: yearlyMetric),
                    const SizedBox(width: 10),
                    Expanded(child: avgMetric),
                  ],
                ),
                const SizedBox(height: 12),
                histogram,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 168, child: yearlyMetric),
                const SizedBox(width: 12),
                SizedBox(width: 184, child: avgMetric),
                const SizedBox(width: 14),
                Expanded(child: histogram),
              ],
            ),
    );
  }

  Future<void> _pickDiarySort({BuildContext? anchorContext}) async {
    if (isPhoneLayout(context) || anchorContext == null) {
      final picked = await showAppSheet<_DiarySort>(
        context: context,
        title: 'Poster Duvarı Sıralaması',
        builder: (ctx) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final e in _diarySortLabels.entries)
              SheetOptionTile(
                label: e.value,
                selected: e.key == _diarySort,
                onTap: () => Navigator.of(ctx).pop(e.key),
              ),
          ],
        ),
      );
      if (picked != null && mounted) setState(() => _diarySort = picked);
      return;
    }
    final box = anchorContext.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(anchorContext).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height + 6), ancestor: overlay);
    final picked = await showMenu<_DiarySort>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx - box.size.width, 0),
      items: [for (final e in _diarySortLabels.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
    );
    if (picked != null && mounted) setState(() => _diarySort = picked);
  }

  Widget _filterChip({
    Key? key,
    required String label,
    IconData? icon,
    required bool selected,
    Color? activeBg,
    Color? activeFg,
    required VoidCallback onTap,
  }) {
    final bg = selected ? (activeBg ?? AppColors.accentSoft) : AppColors.surface;
    final fg = selected ? (activeFg ?? AppColors.accentInk) : AppColors.ink2;
    return FocusRing(
      key: key,
      selected: selected,
      radius: 18,
      lift: false,
      onTap: () {
        AppHaptics.selection(context);
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? fg.withValues(alpha: 0.5) : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
            ],
            Text(label, style: AppText.label(12.5, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _diaryControlsBar({
    required List<int> years,
    required int? effectiveYear,
    required bool hasFilters,
    required VoidCallback onClearFilters,
    required bool compact,
  }) {
    Widget buildViewSegment(
      ({_DiaryViewMode mode, String key, String label, IconData icon}) v, {
      required bool expand,
    }) {
      final seg = FocusRing(
        key: ValueKey(v.key),
        selected: _diaryView == v.mode,
        radius: 13,
        lift: false,
        onTap: () {
          AppHaptics.selection(context);
          setState(() => _diaryView = v.mode);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          height: 32,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _diaryView == v.mode ? AppColors.surface : AppColors.transparent,
            borderRadius: BorderRadius.circular(13),
            boxShadow: _diaryView == v.mode ? AppShadows.chip : null,
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(v.icon, size: 15, color: _diaryView == v.mode ? AppColors.accentInk : AppColors.ink2),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  v.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(12.5, color: _diaryView == v.mode ? AppColors.ink : AppColors.ink2),
                ),
              ),
            ],
          ),
        ),
      );
      return expand ? Expanded(child: seg) : seg;
    }

    final viewModes = [
      (mode: _DiaryViewMode.feed, key: 'diary-view-feed', label: 'Günlük Akışı', icon: Icons.view_agenda_rounded),
      (mode: _DiaryViewMode.wall, key: 'diary-view-wall', label: 'Poster Duvarı', icon: Icons.grid_view_rounded),
    ];

    final viewToggle = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: compact
          ? Row(
              children: [
                for (final v in viewModes) buildViewSegment(v, expand: true),
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final v in viewModes) buildViewSegment(v, expand: false),
                ],
              ),
            ),
    );

    final filterChips = <Widget>[
      _filterChip(
        key: const ValueKey('diary-filter-all'),
        label: 'Tümü',
        selected: _diaryKind == null,
        onTap: () => setState(() => _diaryKind = null),
      ),
      _filterChip(
        key: const ValueKey('diary-filter-movie'),
        label: 'Film',
        selected: _diaryKind == Kind.movie,
        onTap: () => setState(() => _diaryKind = _diaryKind == Kind.movie ? null : Kind.movie),
      ),
      _filterChip(
        key: const ValueKey('diary-filter-series'),
        label: 'Dizi',
        selected: _diaryKind == Kind.series,
        onTap: () => setState(() => _diaryKind = _diaryKind == Kind.series ? null : Kind.series),
      ),
      if (years.length > 1) ...[
        for (final y in years.take(4))
          _filterChip(
            key: ValueKey('diary-filter-year-$y'),
            label: '$y',
            selected: effectiveYear == y,
            onTap: () => setState(() => _diaryYear = effectiveYear == y ? null : y),
          ),
      ],
      _filterChip(
        key: const ValueKey('diary-filter-reviews'),
        label: 'Notlu',
        icon: Icons.notes_rounded,
        selected: _diaryOnlyReviews,
        onTap: () => setState(() => _diaryOnlyReviews = !_diaryOnlyReviews),
      ),
      _filterChip(
        key: const ValueKey('diary-filter-rewatch'),
        label: 'Tekrar',
        icon: Icons.replay_rounded,
        selected: _diaryOnlyRewatch,
        onTap: () => setState(() => _diaryOnlyRewatch = !_diaryOnlyRewatch),
      ),
      if (_diaryRatingFilter != null)
        _filterChip(
          key: const ValueKey('diary-filter-rating-clear'),
          label: '${MediaLogEntry.formatRating(_diaryRatingFilter!)} ★ ×',
          selected: true,
          activeBg: AppColors.warnSoft,
          activeFg: AppColors.warnInk,
          onTap: () => setState(() => _diaryRatingFilter = null),
        ),
      if (hasFilters)
        _filterChip(
          label: 'Temizle',
          icon: Icons.close_rounded,
          selected: false,
          onTap: onClearFilters,
        ),
    ];

    final sortButton = _diaryView == _DiaryViewMode.wall
        ? Builder(
            builder: (btnCtx) => AppButton(
              key: const ValueKey('diary-wall-sort'),
              variant: AppButtonVariant.onPage,
              height: 36,
              dense: true,
              icon: Icons.swap_vert_rounded,
              label: _diarySort == _DiarySort.recent ? 'Sırala' : _diarySortLabels[_diarySort],
              onPressed: () => _pickDiarySort(anchorContext: btnCtx),
            ),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            viewToggle,
            ?sortButton,
          ],
        ),
        const SizedBox(height: 10),
        if (compact)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filterChips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Center(child: filterChips[i]),
            ),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: filterChips),
      ],
    );
  }

  List<Widget> _diaryFeedSlivers(
    List<MediaLogEntry> entries, {
    required int? effectiveYear,
    required bool compact,
  }) {
    final feed = <_DiaryFeedItem>[];
    for (final e in entries) {
      if (e.watches.isNotEmpty) {
        for (final w in e.watches) {
          if (effectiveYear == null || w.watchedAt.year == effectiveYear) {
            feed.add(_DiaryFeedItem(entry: e, date: w.watchedAt, rewatch: w.rewatch));
          }
        }
      } else {
        final d = DateTime.fromMillisecondsSinceEpoch(e.updatedAtMs);
        if (effectiveYear == null || d.year == effectiveYear) {
          feed.add(_DiaryFeedItem(entry: e, date: d, rewatch: false));
        }
      }
    }
    feed.sort((a, b) => b.date.millisecondsSinceEpoch.compareTo(a.date.millisecondsSinceEpoch));

    // Group consecutive feed rows by (year, month).
    final groups = <({DateTime month, List<_DiaryFeedItem> items})>[];
    for (final row in feed) {
      if (groups.isEmpty || groups.last.month.year != row.date.year || groups.last.month.month != row.date.month) {
        groups.add((month: DateTime(row.date.year, row.date.month), items: [row]));
      } else {
        groups.last.items.add(row);
      }
    }

    return [
      for (var g = 0; g < groups.length; g++) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: g == 0 ? 2 : 16, bottom: 10),
            child: Row(
              children: [
                Text(monthYearTr(groups[g].month), style: AppText.title(17)),
                const SizedBox(width: 8),
                Pill('${groups[g].items.length}', height: 22),
              ],
            ),
          ),
        ),
        SliverList.separated(
          itemCount: groups[g].items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final row = groups[g].items[i];
            final liked = row.entry.liked || Library.instance.isFavorite(row.entry.item);
            return RepaintBoundary(
              child: _DiaryFeedRow(
                key: ValueKey('diary-feed-${row.entry.id}-${row.date.millisecondsSinceEpoch}'),
                item: row,
                liked: liked,
                compact: compact,
                onOpen: () => _open(row.entry.item),
              ),
            );
          },
        ),
      ],
    ];
  }

  List<Widget> _diaryWallSlivers(
    List<MediaLogEntry> entries, {
    required int cols,
    required double gap,
    required double tileWidth,
    required bool compact,
  }) {
    final sorted = [...entries];
    int ts(MediaLogEntry e) => e.lastWatch?.watchedAtMs ?? e.updatedAtMs;
    switch (_diarySort) {
      case _DiarySort.recent:
        sorted.sort((a, b) => ts(b).compareTo(ts(a)));
      case _DiarySort.ratingDesc:
        sorted.sort((a, b) {
          final ra = a.rating ?? -1;
          final rb = b.rating ?? -1;
          return rb != ra ? rb.compareTo(ra) : ts(b).compareTo(ts(a));
        });
      case _DiarySort.ratingAsc:
        sorted.sort((a, b) {
          final ra = a.rating ?? 99;
          final rb = b.rating ?? 99;
          return ra != rb ? ra.compareTo(rb) : ts(b).compareTo(ts(a));
        });
      case _DiarySort.name:
        sorted.sort((a, b) => parsedTitleOf(a.item).title.toLowerCase().compareTo(parsedTitleOf(b.item).title.toLowerCase()));
    }

    return [
      SliverGrid.builder(
        key: const ValueKey('diary-poster-wall'),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: gap,
          mainAxisSpacing: compact ? 14 : 20,
          mainAxisExtent: tileWidth * 1.50 + (compact ? 48 : 54),
        ),
        itemCount: sorted.length,
        itemBuilder: (_, i) {
          final e = sorted[i];
          return RepaintBoundary(
            child: _DiaryPosterTile(
              key: ValueKey('diary-wall-${e.id}'),
              entry: e,
              liked: e.liked || Library.instance.isFavorite(e.item),
              compact: compact,
              onOpen: () => _open(e.item),
            ),
          );
        },
      ),
    ];
  }

  // ─── Sonra İzle (Watchlist) sub-tab ────────────────────────

  Widget _watchlistBody(
    List<MediaLogEntry> allWatchlist, {
    required EdgeInsets pad,
    required bool phonePortrait,
  }) {
    if (allWatchlist.isEmpty) {
      return Padding(
        padding: pad,
        child: Align(
          alignment: Alignment.topCenter,
          child: AppCard(
            padding: EdgeInsets.all(phonePortrait ? 28 : 48),
            child: Center(
              heightFactor: 1,
              child: Text(
                'Sonra İzle listen boş.\nMerak ettiğin film veya dizilerin detay sayfasındaki "Sonra İzle" butonuna dokun.',
                textAlign: TextAlign.center,
                style: AppText.body(),
              ),
            ),
          ),
        ),
      );
    }

    final match = queryMatcher(_query);
    final shown = [
      for (final e in allWatchlist)
        if ((_watchlistKind == null || e.item.kind == _watchlistKind) && match(foldedNameOf(e.item))) e,
    ];

    final toolbar = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip(
              key: const ValueKey('watchlist-filter-all'),
              label: 'Tümü',
              selected: _watchlistKind == null,
              onTap: () => setState(() => _watchlistKind = null),
            ),
            _filterChip(
              key: const ValueKey('watchlist-filter-movie'),
              label: 'Film',
              selected: _watchlistKind == Kind.movie,
              onTap: () => setState(() => _watchlistKind = _watchlistKind == Kind.movie ? null : Kind.movie),
            ),
            _filterChip(
              key: const ValueKey('watchlist-filter-series'),
              label: 'Dizi',
              selected: _watchlistKind == Kind.series,
              onTap: () => setState(() => _watchlistKind = _watchlistKind == Kind.series ? null : Kind.series),
            ),
          ],
        ),
        AppButton(
          key: const ValueKey('watchlist-random-pick'),
          variant: AppButtonVariant.primary,
          height: phonePortrait ? 38 : 40,
          dense: phonePortrait,
          icon: Icons.shuffle_rounded,
          label: 'Rastgele Seç',
          onPressed: shown.isEmpty
              ? null
              : () {
                  AppHaptics.medium(context);
                  _pickRandomWatchlist(shown);
                },
        ),
      ],
    );

    return LayoutBuilder(builder: (context, c) {
      final gap = phonePortrait ? 12.0 : 16.0;
      final inner = c.maxWidth - pad.horizontal;
      final cols = phonePortrait ? (inner < 310 ? 2 : 3) : posterColumns(inner);
      final tile = (inner - gap * (cols - 1)) / cols;

      return CustomScrollView(
        key: const ValueKey('watchlist-scroll'),
        slivers: [
          SliverPadding(
            padding: pad,
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(child: toolbar),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                if (shown.isEmpty)
                  SliverToBoxAdapter(
                    child: AppCard(
                      radius: AppSizes.cardRadius,
                      padding: EdgeInsets.all(phonePortrait ? 24 : 36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Aramayla eşleşen yapım yok.', textAlign: TextAlign.center, style: AppText.body()),
                          if (_watchlistKind != null) ...[
                            const SizedBox(height: 12),
                            AppButton(
                              label: 'Filtreyi temizle',
                              onPressed: () => setState(() => _watchlistKind = null),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  SliverGrid.builder(
                    key: const ValueKey('watchlist-grid'),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: phonePortrait ? 14 : 20,
                      mainAxisExtent: tile * 1.50 + (phonePortrait ? 46 : 52),
                    ),
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final entry = shown[i];
                      return RepaintBoundary(
                        child: _WatchlistTile(
                          key: ValueKey('watchlist-tile-${entry.id}'),
                          entry: entry,
                          compact: phonePortrait,
                          onOpen: () => _open(entry.item),
                          onRemove: () {
                            AppHaptics.selection(context);
                            Library.instance.toggleWatchlist(entry.item);
                          },
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }

  MediaLogEntry _drawRandomEntry(List<MediaLogEntry> pool) {
    if (pool.length <= 1) {
      _lastRandomPickId = pool.first.id;
      return pool.first;
    }
    final candidates = [for (final e in pool) if (e.id != _lastRandomPickId) e];
    final source = candidates.isEmpty ? pool : candidates;
    final picked = source[_rng.nextInt(source.length)];
    _lastRandomPickId = picked.id;
    return picked;
  }

  Future<void> _pickRandomWatchlist(List<MediaLogEntry> pool) async {
    if (pool.isEmpty) return;
    var current = _drawRandomEntry(pool);
    final phone = isPhoneLayout(context);

    Widget buildBody(BuildContext ctx, StateSetter setLocal, {required bool compact}) {
      final t = parsedTitleOf(current.item);
      final addedAt = current.watchlistAddedAtMs;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: compact ? 88 : 104,
                  height: compact ? 132 : 156,
                  child: ColoredBox(
                    color: AppColors.surfaceAlt,
                    child: PosterImage(current.item.logo, cacheWidth: 320),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(current.item.kind == Kind.series ? 'Dizi' : 'Film', tone: PillTone.accent, height: 24),
                        if (t.year != null) Pill(t.year!, height: 24),
                        if (t.tags.isNotEmpty) Pill(t.tags.first, height: 24),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t.title,
                      key: const ValueKey('random-pick-title'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.display(compact ? 21 : 24),
                    ),
                    if (addedAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Listeye eklendi: ${shortDateTr(DateTime.fromMillisecondsSinceEpoch(addedAt), includeYear: true)}',
                        style: AppText.meta(12.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (pool.length > 1) ...[
                Expanded(
                  child: AppButton(
                    key: const ValueKey('random-pick-reroll'),
                    icon: Icons.shuffle_rounded,
                    label: 'Başka seç',
                    onPressed: () {
                      AppHaptics.selection(ctx);
                      setLocal(() => current = _drawRandomEntry(pool));
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: AppButton(
                  key: const ValueKey('random-pick-open'),
                  variant: AppButtonVariant.primary,
                  icon: Icons.play_arrow_rounded,
                  label: 'Detaya git',
                  autofocus: true,
                  onPressed: () {
                    AppHaptics.light(ctx);
                    Navigator.of(ctx).pop(current.item);
                  },
                ),
              ),
            ],
          ),
        ],
      );
    }

    Item? chosen;
    if (phone) {
      chosen = await showAppSheet<Item>(
        context: context,
        title: 'Rastgele Seçim',
        subtitle: 'Bu akşam ne izlesem?',
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: buildBody(ctx, setLocal, compact: true),
          ),
        ),
      );
    } else {
      chosen = await showDialog<Item>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Bu akşam ne izlesem?'),
            content: SizedBox(width: 440, child: buildBody(ctx, setLocal, compact: false)),
          ),
        ),
      );
    }
    if (chosen != null && mounted) {
      _open(chosen);
    }
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: PosterImage(widget.item.logo, rating: Library.instance.ratingFor(widget.item)),
                  ),
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

class _DiaryFeedItem {
  const _DiaryFeedItem({required this.entry, required this.date, required this.rewatch});

  final MediaLogEntry entry;
  final DateTime date;
  final bool rewatch;
}

/// Interactive 10-column half-star rating distribution chart (0.5★ – 5.0★).
///
/// Tapping any column filters the diary below to that exact rating; tapping the active column clears the filter.
class _DiaryRatingHistogram extends StatelessWidget {
  const _DiaryRatingHistogram({
    required this.buckets,
    required this.selectedRating,
    required this.onSelectRating,
    this.compact = false,
  });

  final List<int> buckets;
  final double? selectedRating;
  final ValueChanged<double?> onSelectRating;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final maxCount = buckets.fold<int>(0, max);
    final trackHeight = compact ? 58.0 : 68.0;
    final selectedIdx = selectedRating == null ? null : ((selectedRating! * 2).round() - 1).clamp(0, 9);

    return Container(
      key: const ValueKey('diary-rating-histogram'),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14, vertical: compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PUAN DAĞILIMI · 0.5★–5★',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(11.5, color: AppColors.ink2),
                ),
              ),
              if (selectedRating != null && selectedIdx != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelectRating(null),
                  child: Pill(
                    '${MediaLogEntry.formatRating(selectedRating!)} ★ · ${buckets[selectedIdx]} ×',
                    tone: PillTone.warn,
                    height: 22,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: trackHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 10; i++) ...[
                  if (i > 0) SizedBox(width: compact ? 4 : 6),
                  Expanded(child: _bar(i, maxCount, trackHeight)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0.5★', style: AppText.meta(10.5, color: AppColors.ink2)),
              Text('2.5★', style: AppText.meta(10.5, color: AppColors.ink2)),
              Text('5.0★', style: AppText.meta(10.5, color: AppColors.ink2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(int index, int maxCount, double trackHeight) {
    final step = (index + 1) * 0.5;
    final count = index < buckets.length ? buckets[index] : 0;
    final selected = selectedRating == step;
    final dimmed = selectedRating != null && !selected;
    final barHeight = count == 0 || maxCount == 0
        ? 4.0
        : (10.0 + (trackHeight - 10.0) * (count / maxCount)).clamp(10.0, trackHeight);
    final Color barColor;
    if (count == 0) {
      barColor = selected ? AppColors.accent : AppColors.line;
    } else if (selected) {
      barColor = AppColors.accent;
    } else if (dimmed) {
      barColor = AppColors.star.withValues(alpha: 0.3);
    } else {
      barColor = AppColors.star;
    }

    return FocusRing(
      key: ValueKey('diary-hist-bar-${step.toStringAsFixed(1)}'),
      radius: 6,
      lift: false,
      selected: selected,
      tooltip: '${MediaLogEntry.formatRating(step)} ★ · $count yapım',
      semanticLabel: '${MediaLogEntry.formatRating(step)} yıldız, $count yapım',
      onTap: () => onSelectRating(selected ? null : step),
      child: SizedBox(
        height: trackHeight,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: barHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(3)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chronological diary feed row: day badge, poster, title, rating stars, rewatch/like tags, and review note.
class _DiaryFeedRow extends StatelessWidget {
  const _DiaryFeedRow({
    super.key,
    required this.item,
    required this.liked,
    required this.onOpen,
    this.compact = false,
  });

  final _DiaryFeedItem item;
  final bool liked;
  final bool compact;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final t = parsedTitleOf(entry.item);
    final rating = entry.rating;
    final review = entry.review.trim();
    final radius = compact ? 18.0 : AppSizes.tileRadius;

    return FocusRing(
      radius: radius,
      lift: false,
      onTap: () {
        AppHaptics.light(context);
        onOpen();
      },
      child: Container(
        padding: EdgeInsets.all(compact ? 10 : 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(radius),
          border: AppShadows.repeatedBorder() ?? Border.all(color: AppColors.line),
          boxShadow: AppShadows.forRepeated(),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 42 : 48,
              padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${item.date.day}', style: AppText.display(compact ? 17 : 19)),
                  Text(shortMonthTr(item.date.month).toUpperCase(), style: AppText.label(10, color: AppColors.ink2)),
                ],
              ),
            ),
            SizedBox(width: compact ? 10 : 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: compact ? 42 : 48,
                height: compact ? 63 : 72,
                child: ColoredBox(
                  color: AppColors.surfaceAlt,
                  child: PosterImage(entry.item.logo, cacheWidth: 160),
                ),
              ),
            ),
            SizedBox(width: compact ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title(compact ? 15 : 16),
                        ),
                      ),
                      if (t.year != null) ...[
                        const SizedBox(width: 8),
                        Text(t.year!, style: AppText.meta(12.5)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (rating != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(starGlyphs(rating), style: AppText.title(14.5, color: AppColors.star)),
                            const SizedBox(width: 5),
                            Text(MediaLogEntry.formatRating(rating), style: AppText.meta(12.5, color: AppColors.warnInk)),
                          ],
                        )
                      else
                        const Pill('İzlendi', tone: PillTone.ok, height: 22),
                      Pill(entry.item.kind == Kind.series ? 'Dizi' : 'Film', height: 22),
                      if (liked)
                        const Icon(Icons.favorite_rounded, size: 15, color: AppColors.live),
                      if (item.rewatch)
                        const Pill('Tekrar', tone: PillTone.accent, icon: Icons.replay_rounded, height: 22),
                    ],
                  ),
                  if (review.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '"$review"',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: compact ? 12.5 : 13.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Poster wall tile for Günlüğüm: poster with corner rating badge, title, and compact watch/review/like indicators.
class _DiaryPosterTile extends StatelessWidget {
  const _DiaryPosterTile({
    super.key,
    required this.entry,
    required this.liked,
    required this.onOpen,
    this.compact = false,
  });

  final MediaLogEntry entry;
  final bool liked;
  final bool compact;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = parsedTitleOf(entry.item);
    final radius = compact ? 15.0 : AppSizes.tileRadius;
    final date = entry.lastWatch?.watchedAt ?? DateTime.fromMillisecondsSinceEpoch(entry.updatedAtMs);
    final hasReview = entry.review.trim().isNotEmpty;
    final hasRewatch = entry.rewatchCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: FocusRing(
            radius: radius,
            onTap: () {
              AppHaptics.light(context);
              onOpen();
            },
            builder: (context, focused, hovered) => Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: hovered && !focused ? AppShadows.lift : AppShadows.forRepeated(),
                border: AppShadows.repeatedBorder() ?? (compact ? Border.all(color: AppColors.line, width: 0.8) : null),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: PosterImage(entry.item.logo, rating: entry.rating),
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(compact ? 13.5 : 15)),
        SizedBox(
          height: compact ? 18 : 20,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shortDateTr(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta(compact ? 11.5 : 12.5),
                ),
              ),
              if (liked) ...[
                const SizedBox(width: 4),
                const Icon(Icons.favorite_rounded, size: 13, color: AppColors.live),
              ],
              if (hasRewatch) ...[
                const SizedBox(width: 4),
                const Icon(Icons.replay_rounded, size: 13, color: AppColors.accentInk),
              ],
              if (hasReview) ...[
                const SizedBox(width: 4),
                const Icon(Icons.notes_rounded, size: 13, color: AppColors.ink2),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Poster tile for the "Sonra İzle" watchlist with a quick bookmark-remove button in the top-right corner.
class _WatchlistTile extends StatelessWidget {
  const _WatchlistTile({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onRemove,
    this.compact = false,
  });

  final MediaLogEntry entry;
  final bool compact;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = parsedTitleOf(entry.item);
    final addedAt = entry.watchlistAddedAtMs;
    final sub = [
      ?t.year,
      if (addedAt != null) shortDateTr(DateTime.fromMillisecondsSinceEpoch(addedAt)),
    ].join(' · ');
    final radius = compact ? 15.0 : AppSizes.tileRadius;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: FocusRing(
                  radius: radius,
                  onTap: () {
                    AppHaptics.light(context);
                    onOpen();
                  },
                  builder: (context, focused, hovered) => Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: hovered && !focused ? AppShadows.lift : AppShadows.forRepeated(),
                      border: AppShadows.repeatedBorder() ?? (compact ? Border.all(color: AppColors.line, width: 0.8) : null),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: PosterImage(entry.item.logo),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: compact ? 0 : 1,
                right: compact ? 0 : 1,
                child: FocusRing(
                  key: ValueKey('watchlist-remove-${entry.id}'),
                  radius: 22,
                  lift: false,
                  tooltip: 'Sonra İzle listesinden çıkar',
                  onTap: onRemove,
                  child: SizedBox(
                    width: compact ? 38 : 44,
                    height: compact ? 38 : 44,
                    child: Center(
                      child: Container(
                        width: compact ? 26 : 30,
                        height: compact ? 26 : 30,
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          boxShadow: AppShadows.chip,
                        ),
                        child: Icon(
                          Icons.bookmark_rounded,
                          size: compact ? 14 : 16,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(compact ? 13.5 : 15)),
        SizedBox(
          height: compact ? 17 : 20,
          child: sub.isEmpty ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(compact ? 12 : 13)),
        ),
      ],
    );
  }
}
