import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'detail_page.dart';
import 'epg_widgets.dart';
import 'library.dart';
import 'player_page.dart';
import 'poster_card.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'title_utils.dart';
import 'tv_text_field.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/focus_ring.dart';
import 'ui/format.dart';
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
        MaterialPageRoute(
          builder: (_) => DetailPage(client: widget.client, item: item),
        ),
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
      return PlayerEntry(url: i.url!, title: i.name, logo: i.logo, epg: id == null ? null : () => _epg.get(id));
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(queue: [for (final i in list) entry(i)], index: index, kind: Kind.live, client: widget.client),
      ),
    );
  }

  void _openHistory(HistoryEntry e) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          queue: [PlayerEntry(url: e.url, title: e.title, logo: e.logo)],
          kind: e.kind,
          client: widget.client,
        ),
      ),
    );
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
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
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
            return ListTile(
              key: ValueKey(n),
              dense: true,
              contentPadding: const EdgeInsets.only(left: 0, right: 4),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canReorder)
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.drag_indicator, size: 20)),
                    ),
                  Checkbox(
                    value: !s.hiddenGroups.contains(key),
                    onChanged: (v) {
                      final next = {...s.hiddenGroups};
                      (v ?? true) ? next.remove(key) : next.add(key);
                      s.update(hiddenGroups: next);
                      setLocal(() {});
                    },
                  ),
                ],
              ),
              title: Text(groupLabel(n), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${counts[n]} öğe', style: const TextStyle(fontSize: 11)),
              trailing: canReorder
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'En üste al',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.vertical_align_top, size: 18),
                          onPressed: index == 0 ? null : () => move(index, 0),
                        ),
                        IconButton(
                          tooltip: 'Yukarı',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                          onPressed: index == 0 ? null : () => move(index, index - 1),
                        ),
                        IconButton(
                          tooltip: 'Aşağı',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                          onPressed: index >= ordered.length - 1 ? null : () => move(index, index + 1),
                        ),
                      ],
                    )
                  : null,
            );
          }

          return AlertDialog(
            title: const Text('Kategorileri düzenle'),
            content: SizedBox(
              width: 520,
              height: 520,
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Sürükleyerek ya da oklarla sırayı değiştir. Kutuyu kaldırarak kategoriyi gizle.', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  RemoteTextField(
                    onChanged: (v) => setLocal(() => filter = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Kategori ara (arama sırasında sıralama kapalı)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: canReorder
                        ? ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            itemCount: visible.length,
                            onReorderItem: (from, to) => move(from, to),
                            itemBuilder: (_, i) => tile(i, visible[i]),
                          )
                        : ListView(children: [for (var i = 0; i < visible.length; i++) tile(i, visible[i])]),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  s.update(groupOrder: {...s.groupOrder}..remove(kind.name));
                  setLocal(() {});
                },
                child: const Text('Sırayı sıfırla'),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppSettings.instance, Library.instance]),
      // Back (TV remote) never lands on the profile page: it steps back to "Tümü", then to Ana Sayfa,
      // then leaves the app. Switching user goes through Ayarlar (Navigator.pop ignores this PopScope).
      builder: (context, _) => PopScope(
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
        child: Scaffold(
          body: Row(
            children: [
              SideMenu(selected: _tab, onSelect: _select, accountName: widget.account.name, onAccount: () => Navigator.of(context).pop()),
              const SizedBox(width: 26),
              Expanded(child: _content()),
            ],
          ),
        ),
      ),
    );
  }

  /// Heading + body of a tab. The body gets the full width; scroll areas inside keep their own 8 px margin.
  Widget _page(PageHeader header, Widget body) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(padding: const EdgeInsets.fromLTRB(AppSizes.scrollPad, 26, 26, 0), child: header),
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
        SettingsPage(info: widget.info, account: widget.account, client: widget.client, onLogout: () => Navigator.of(context).pop()),
      );
    }
    if (_tab == _favoritesTab) {
      final match = queryMatcher(_query);
      final favs = Library.instance.favorites.where(_allowed).where((i) => match(foldedNameOf(i))).toList();
      return _page(
        PageHeader(title: 'Favoriler', actions: [_searchField('Favorilerde ara'), const ClockPill()]),
        favs.isEmpty ? const Center(child: Text('Henüz favori yok. Bir içeriğin kalp ikonuna dokun.')) : _mixedList(favs),
      );
    }

    final kind = _kind!;
    final view = _viewOf(kind);
    final groups = view.groups;
    final shown = view.shown;
    final totalCount = view.total;
    final ready = !_loading.contains(kind) && _errors[kind] == null;
    final n = groupCount(shown.length);
    final (title, hint, subtitle) = switch (kind) {
      Kind.live => ('Canlı TV', 'Kanal ara', '${_group == null ? 'Tümü' : groupLabel(_group!)}, $n kanal'),
      Kind.movie => ('Filmler', 'Film ara', '$n film'),
      Kind.series => ('Diziler', 'Dizi ara', '$n dizi'),
    };

    return _page(
      PageHeader(title: title, subtitle: ready ? subtitle : null, actions: [_searchField(hint), if (kind != Kind.live) _sortButton(), const ClockPill()]),
      Row(
        children: [
          SizedBox(
            width: 260,
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text(widget.account.name, style: Theme.of(context).textTheme.titleSmall)),
                      IconButton(tooltip: 'Kategorileri düzenle / gizle', icon: const Icon(Icons.tune, size: 20), onPressed: () => _manageGroups(kind)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: RemoteTextField(
                    key: ValueKey('groupSearch$_tab'),
                    onChanged: (v) => setState(() => _groupQuery = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Kategori ara',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                if (_groupQuery.trim().isEmpty)
                  ListTile(
                    dense: true,
                    selected: _group == null,
                    title: const Text('Tümü'),
                    trailing: Text('$totalCount'),
                    onTap: () => setState(() => _group = null),
                  ),
                for (final name in AppSettings.instance.orderedGroups(kind, groups.keys).where((n) => matchesQuery(groupLabel(n), _groupQuery)))
                  Tooltip(
                    message: name,
                    waitDuration: const Duration(milliseconds: 500),
                    child: GestureDetector(
                      // right click: quick pin / hide
                      onSecondaryTapUp: (d) => _groupMenu(kind, name, d.globalPosition),
                      child: ListTile(
                        dense: true,
                        selected: _group == name,
                        title: Text(groupLabel(name), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text('${groups[name]}'),
                        onTap: () => setState(() => _group = name),
                        onLongPress: () => _manageGroups(kind),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _body(kind, shown)),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(AppSizes.scrollPad, AppSizes.scrollPad, 26, 24),
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
    final title = parseTitle(e.title).title;
    final left = _left(e);
    return SizedBox(
      height: 246,
      child: AppCard(
        child: LayoutBuilder(builder: (context, c) {
          final art = c.maxWidth < 900 ? c.maxWidth * 0.45 : 560.0;
          return Stack(children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: art,
              child: ClipRRect(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppSizes.panelRadius)),
                child: Stack(fit: StackFit.expand, children: [
                  PosterImage(e.logo, cacheWidth: 640),
                  // the only gradient allowed: the scene fades into the white card
                  const Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 200,
                    child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.surface, AppColors.surfaceClear]))),
                  ),
                ]),
              ),
            ),
            Positioned(
              left: 32,
              top: 0,
              bottom: 0,
              right: art - 40,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Pill('Kaldığın yerden', tone: PillTone.accent),
                const SizedBox(height: 12),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.display(32)),
                if (left != null) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    SizedBox(width: 220, child: ProgressBar(value: e.progress, height: 8)),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 104,
              child: Stack(fit: StackFit.expand, children: [
                PosterImage(e.logo),
                if (e.durationMs > 0) Positioned(left: 12, right: 12, bottom: 10, child: ProgressBar(value: e.progress, height: 4, onImage: true)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(parseTitle(e.title).title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(15)),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
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
                    Text(now?.title ?? groupLabel(it.group), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
                  ]),
                ),
                if (now != null) ...[const SizedBox(width: 10), SizedBox(width: 54, child: ProgressBar(value: now.progress))],
              ]),
            ),
          ),
        ),
      );

  Widget _sortButton() => DropdownButton<_Sort>(
    value: _sort,
    underline: const SizedBox.shrink(),
    onChanged: (v) => setState(() => _sort = v ?? _sort),
    items: const [
      DropdownMenuItem(value: _Sort.provider, child: Text('Varsayılan')),
      DropdownMenuItem(value: _Sort.added, child: Text('Yeni eklenen')),
      DropdownMenuItem(value: _Sort.name, child: Text('A – Z')),
      DropdownMenuItem(value: _Sort.year, child: Text('Yıl, yeniden eskiye')),
    ],
  );

  Widget _body(Kind kind, List<Item> shown) {
    if (_loading.contains(kind)) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Yükleniyor...')]),
      );
    }
    final err = _errors[kind];
    if (err != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(err),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => _ensureLoaded(kind), child: const Text('Tekrar dene')),
          ],
        ),
      );
    }
    if (shown.isEmpty) return const Center(child: Text('Sonuç yok'));
    return kind == Kind.live ? _liveList(shown) : _posterGrid(shown);
  }

  Widget _heart(Item it, {double size = 22}) => IconButton(
    iconSize: size,
    visualDensity: VisualDensity.compact,
    tooltip: Library.instance.isFavorite(it) ? 'Favorilerden çıkar' : 'Favorilere ekle',
    icon: Icon(Library.instance.isFavorite(it) ? Icons.favorite : Icons.favorite_border, color: Library.instance.isFavorite(it) ? Colors.redAccent : null),
    onPressed: () => Library.instance.toggleFavorite(it),
  );

  Widget _liveList(List<Item> shown) => ListView.builder(
    itemCount: shown.length,
    itemBuilder: (_, i) {
      final it = shown[i];
      return ListTile(
        leading: PosterImage(it.logo, size: 40, fit: BoxFit.contain),
        title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: NowPlaying(cache: _epg, item: it, fallback: it.group),
        trailing: _heart(it),
        onTap: () => _open(it),
      );
    },
  );

  Widget _posterGrid(List<Item> shown) => GridView.builder(
    padding: const EdgeInsets.all(12),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, childAspectRatio: 0.6, crossAxisSpacing: 14, mainAxisSpacing: 14),
    itemCount: shown.length,
    itemBuilder: (_, i) {
      final it = shown[i];
      final t = parsedTitleOf(it);
      return PosterCard(
        logo: it.logo,
        title: t.title,
        year: t.year,
        tags: t.tags,
        onTap: () => _open(it),
        topRight: DecoratedBox(
          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
          child: _heart(it, size: 18),
        ),
      );
    },
  );

  Widget _mixedList(List<Item> items) => ListView.builder(
    itemCount: items.length,
    itemBuilder: (_, i) {
      final it = items[i];
      final icon = switch (it.kind) {
        Kind.live => Icons.tv,
        Kind.movie => Icons.movie,
        Kind.series => Icons.video_library,
      };
      return ListTile(
        leading: Stack(
          children: [
            PosterImage(it.logo, size: 44, fit: BoxFit.contain),
            Positioned(right: 0, bottom: 0, child: Icon(icon, size: 14, color: Colors.white70)),
          ],
        ),
        title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(it.group, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: _heart(it),
        onTap: () => _open(it),
      );
    },
  );
}

class _View {
  _View(this.key, this.shown, this.groups, this.total);

  final Object key;
  final List<Item> shown;
  final Map<String, int> groups; // category -> item count
  final int total; // count shown next to "Tümü"
}
