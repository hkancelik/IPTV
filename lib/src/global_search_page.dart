import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'detail_page.dart';
import 'downloads.dart';
import 'epg_widgets.dart';
import 'library.dart';
import 'mini_player.dart';
import 'player_page.dart';
import 'poster_card.dart';
import 'settings.dart';
import 'title_utils.dart';
import 'tv_text_field.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/focus_ring.dart';
import 'ui/layout.dart';
import 'ui/tokens.dart';
import 'xtream.dart';

final _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _wordSplit = RegExp(r'\s+');
final _dedupeKeys = Expando<String>();
final _foldedCleanTitles = Expando<String>();

String _foldedCleanTitle(Item item) => _foldedCleanTitles[item] ??= foldTr(parsedTitleOf(item).title.trim());

String _dedupeKey(Item item) => _dedupeKeys[item] ??= item.name.toLowerCase().replaceAll(_nonAlnum, '');

/// Filters and ranks [items] against [query] using Turkish-aware diacritic folding.
///
/// Ranking tiers (preserving provider order inside each tier):
///   0. Exact normalized title match
///   1. Normalized title starts with full query
///   2. Any word in normalized title starts with the first query word
///   3. General multi-word substring match (title or raw name)
List<Item> rankSearchItems(
  Iterable<Item> items,
  String query, {
  bool dedupe = false,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];
  final foldedQuery = foldTr(trimmed);
  final words = foldedQuery.split(_wordSplit).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  final firstWord = words.first;
  final match = queryMatcher(trimmed);

  final buckets = [for (var i = 0; i < 4; i++) <Item>[]];
  final seen = dedupe ? <String>{} : null;

  for (final item in items) {
    final foldedRaw = foldedNameOf(item);
    if (!match(foldedRaw)) continue;
    if (seen != null && !seen.add(_dedupeKey(item))) continue;

    final clean = _foldedCleanTitle(item);
    final int tier;
    if (clean == foldedQuery || foldedRaw == foldedQuery) {
      tier = 0;
    } else if (clean.startsWith(foldedQuery) || foldedRaw.startsWith(foldedQuery)) {
      tier = 1;
    } else if (clean.split(_wordSplit).any((w) => w.startsWith(firstWord))) {
      tier = 2;
    } else {
      tier = 3;
    }
    buckets[tier].add(item);
  }

  return [for (final b in buckets) ...b];
}

/// Persists recent global-search queries per account in [SharedPreferences].
class RecentSearchStore {
  static const _prefix = 'recentSearches_v1:';
  static const maxEntries = 8;

  static Future<List<String>> load(Account account) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getStringList('$_prefix${account.key}') ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> add(Account account, String query) async {
    final clean = query.trim();
    if (clean.length < 2) return load(account);
    final current = await load(account);
    final lower = foldTr(clean);
    final updated = [
      clean,
      for (final q in current)
        if (foldTr(q) != lower) q,
    ].take(maxEntries).toList();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('$_prefix${account.key}', updated);
    } catch (_) {}
    return updated;
  }

  static Future<void> clear(Account account) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('$_prefix${account.key}');
    } catch (_) {}
  }

  /// Merges [incoming] recent searches with local ones (case/diacritic deduped).
  static Future<List<String>> merge(Account account, List<String> incoming) async {
    final current = await load(account);
    final seen = <String>{};
    final combined = <String>[];
    for (final q in [...current, ...incoming]) {
      final clean = q.trim();
      if (clean.length < 2) continue;
      if (seen.add(foldTr(clean))) combined.add(clean);
      if (combined.length >= maxEntries) break;
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('$_prefix${account.key}', combined);
    } catch (_) {}
    return combined;
  }
}

/// Unified search screen across Canlı TV, Filmler and Diziler.
class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({
    super.key,
    required this.account,
    required this.client,
    required this.epg,
    required this.catalogListenable,
    required this.itemsFor,
    required this.isLoading,
    required this.errorFor,
    required this.ensureLoaded,
    required this.isAllowed,
    required this.onPlayLive,
    this.initialQuery = '',
  });

  final Account account;
  final XtreamClient client;
  final EpgCache epg;
  final Listenable catalogListenable;
  final List<Item> Function(Kind kind) itemsFor;
  final bool Function(Kind kind) isLoading;
  final String? Function(Kind kind) errorFor;
  final Future<void> Function(Kind kind) ensureLoaded;
  final bool Function(Item item) isAllowed;
  final void Function(Item item, List<Item> queue) onPlayLive;
  final String initialQuery;

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  String _query = '';
  Kind? _filter; // null = Tümü
  List<String> _recents = const [];

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    _loadRecents();
    // Kick off loading all three catalogs in parallel (disk cache makes warm ones instant).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final k in Kind.values) {
        widget.ensureLoaded(k);
      }
    });
  }

  Future<void> _loadRecents() async {
    final list = await RecentSearchStore.load(widget.account);
    if (mounted) setState(() => _recents = list);
  }

  Future<void> _recordSearch(String q) async {
    final updated = await RecentSearchStore.add(widget.account, q);
    if (mounted) setState(() => _recents = updated);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _query = '');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 110), () {
      if (mounted) setState(() => _query = trimmed);
    });
  }

  void _applyQuery(String value) {
    _debounce?.cancel();
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    setState(() => _query = value.trim());
  }

  void _openItem(Item item, List<Item> liveQueue) {
    if (_query.length >= 2) _recordSearch(_query);
    if (item.kind == Kind.live) {
      widget.onPlayLive(item, liveQueue);
    } else {
      Navigator.of(context).push(
        appRoute(context, (_) => DetailPage(client: widget.client, item: item)),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = isPhoneLayout(context);
    final pad = MediaQuery.paddingOf(context);
    final listenable = Listenable.merge([
      widget.catalogListenable,
      Library.instance,
      AppSettings.instance,
      DownloadManager.instance,
    ]);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        backgroundColor: AppColors.ground,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              ListenableBuilder(
                listenable: listenable,
                builder: (context, _) {
                  final dedupe = AppSettings.instance.dedupe;
                  final liveAll = widget.itemsFor(Kind.live).where(widget.isAllowed);
                  final movieAll = widget.itemsFor(Kind.movie).where(widget.isAllowed);
                  final seriesAll = widget.itemsFor(Kind.series).where(widget.isAllowed);

                  final liveHits = _query.isEmpty ? const <Item>[] : rankSearchItems(liveAll, _query);
                  final movieHits = _query.isEmpty ? const <Item>[] : rankSearchItems(movieAll, _query, dedupe: dedupe);
                  final seriesHits = _query.isEmpty ? const <Item>[] : rankSearchItems(seriesAll, _query, dedupe: dedupe);
                  final totalHits = liveHits.length + movieHits.length + seriesHits.length;

                  final loadingKinds = [for (final k in Kind.values) if (widget.isLoading(k)) k];
                  final erroredKinds = [for (final k in Kind.values) if (widget.errorFor(k) != null && widget.itemsFor(k).isEmpty) k];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(phone: phone),
                      if (loadingKinds.isNotEmpty || erroredKinds.isNotEmpty)
                        _statusStrip(loadingKinds, erroredKinds, phone: phone),
                      if (_query.isNotEmpty)
                        _filterStrip(
                          liveCount: liveHits.length,
                          movieCount: movieHits.length,
                          seriesCount: seriesHits.length,
                          totalCount: totalHits,
                          phone: phone,
                        ),
                      Expanded(
                        child: _query.isEmpty
                            ? _emptyQueryView(phone: phone, bottomPad: pad.bottom)
                            : _resultsView(
                                liveHits: liveHits,
                                movieHits: movieHits,
                                seriesHits: seriesHits,
                                loadingAny: loadingKinds.isNotEmpty,
                                phone: phone,
                                bottomPad: pad.bottom,
                              ),
                      ),
                    ],
                  );
                },
              ),
              if (phone)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: pad.bottom + 10,
                  child: PhoneMiniPlayerSlot(
                    onExpand: () => expandMiniPlayer(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header({required bool phone}) {
    final hPad = phone ? 16.0 : 24.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, phone ? 10 : 18, hPad, 10),
      child: Row(
        children: [
          AppButton(
            key: const ValueKey('global-search-back'),
            icon: Icons.arrow_back_rounded,
            label: phone ? null : 'Geri',
            tooltip: 'Geri',
            variant: AppButtonVariant.onPage,
            height: 44,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: AppShadows.chip,
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: RemoteTextField(
                      key: const ValueKey('global-search-input'),
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onQueryChanged,
                      onSubmitted: (v) {
                        _debounce?.cancel();
                        final t = v.trim();
                        setState(() => _query = t);
                        if (t.length >= 2) _recordSearch(t);
                      },
                      decoration: InputDecoration(
                        hintText: 'Kanal, film veya dizi ara...',
                        hintStyle: AppText.meta(15),
                        prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.ink2),
                        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 20),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  if (_controller.text.isNotEmpty)
                    FocusRing(
                      radius: 16,
                      lift: false,
                      tooltip: 'Temizle',
                      onTap: () => _applyQuery(''),
                      child: const SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(Icons.close_rounded, size: 18, color: AppColors.ink3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _kindLabel(Kind k) => switch (k) {
        Kind.live => 'Canlı TV',
        Kind.movie => 'Filmler',
        Kind.series => 'Diziler',
      };

  Widget _statusStrip(List<Kind> loading, List<Kind> errored, {required bool phone}) {
    final hPad = phone ? 16.0 : 24.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (loading.isNotEmpty)
            Pill(
              '${loading.map(_kindLabel).join(', ')} yükleniyor...',
              tone: PillTone.accent,
              leading: const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentInk),
              ),
            ),
          for (final k in errored)
            GestureDetector(
              onTap: () => widget.ensureLoaded(k),
              child: Pill(
                '${_kindLabel(k)} yüklenemedi · Tekrar dene',
                tone: PillTone.live,
                icon: Icons.refresh_rounded,
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterStrip({
    required int liveCount,
    required int movieCount,
    required int seriesCount,
    required int totalCount,
    required bool phone,
  }) {
    final hPad = phone ? 16.0 : 24.0;
    Widget chip({
      required Key key,
      required String label,
      required int count,
      required bool selected,
      required VoidCallback onTap,
    }) =>
        FocusRing(
          key: key,
          radius: 18,
          lift: false,
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
                const SizedBox(width: 6),
                Text(groupCount(count), style: AppText.meta(11.5, color: selected ? AppColors.accentInk : AppColors.ink3)),
              ],
            ),
          ),
        );

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(hPad, 2, hPad, 6),
        children: [
          chip(
            key: const ValueKey('global-search-filter-all'),
            label: 'Tümü',
            count: totalCount,
            selected: _filter == null,
            onTap: () => setState(() => _filter = null),
          ),
          const SizedBox(width: 8),
          chip(
            key: const ValueKey('global-search-filter-live'),
            label: 'Canlı TV',
            count: liveCount,
            selected: _filter == Kind.live,
            onTap: () => setState(() => _filter = Kind.live),
          ),
          const SizedBox(width: 8),
          chip(
            key: const ValueKey('global-search-filter-movie'),
            label: 'Filmler',
            count: movieCount,
            selected: _filter == Kind.movie,
            onTap: () => setState(() => _filter = Kind.movie),
          ),
          const SizedBox(width: 8),
          chip(
            key: const ValueKey('global-search-filter-series'),
            label: 'Diziler',
            count: seriesCount,
            selected: _filter == Kind.series,
            onTap: () => setState(() => _filter = Kind.series),
          ),
        ],
      ),
    );
  }

  Widget _emptyQueryView({required bool phone, required double bottomPad}) {
    final hPad = phone ? 16.0 : 24.0;
    final liveCount = widget.itemsFor(Kind.live).length;
    final movieCount = widget.itemsFor(Kind.movie).length;
    final seriesCount = widget.itemsFor(Kind.series).length;
    final stats = [
      if (liveCount > 0) '${groupCount(liveCount)} kanal',
      if (movieCount > 0) '${groupCount(movieCount)} film',
      if (seriesCount > 0) '${groupCount(seriesCount)} dizi',
    ].join(' · ');

    return ListView(
      padding: EdgeInsets.fromLTRB(hPad, 12, hPad, bottomPad + 96),
      children: [
        if (_recents.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: Text('Son aramalar', style: AppText.title(17))),
              AppButton(
                label: 'Temizle',
                dense: true,
                height: 34,
                onPressed: () async {
                  await RecentSearchStore.clear(widget.account);
                  if (mounted) setState(() => _recents = const []);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in _recents)
                FocusRing(
                  radius: 18,
                  lift: false,
                  onTap: () => _applyQuery(q),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history_rounded, size: 15, color: AppColors.ink3),
                        const SizedBox(width: 6),
                        Text(q, style: AppText.label(13.5, color: AppColors.ink)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        AppCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Icon(Icons.search_rounded, size: 32, color: AppColors.ink3),
              const SizedBox(height: 10),
              Text(
                'Canlı TV, Filmler ve Diziler arasında tek yerden ara.',
                textAlign: TextAlign.center,
                style: AppText.body(),
              ),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('$stats aramaya hazır', textAlign: TextAlign.center, style: AppText.meta(13)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultsView({
    required List<Item> liveHits,
    required List<Item> movieHits,
    required List<Item> seriesHits,
    required bool loadingAny,
    required bool phone,
    required double bottomPad,
  }) {
    final hPad = phone ? 16.0 : 24.0;
    final listBottom = bottomPad + (phone ? 100 : 24);

    if (_filter == Kind.live) {
      if (liveHits.isEmpty) return _noResult(loadingAny);
      return ListView.builder(
        padding: EdgeInsets.fromLTRB(hPad, 8, hPad, listBottom),
        itemExtent: 74,
        itemCount: liveHits.length,
        itemBuilder: (_, i) => _channelRow(liveHits[i], liveHits),
      );
    }

    if (_filter == Kind.movie || _filter == Kind.series) {
      final list = _filter == Kind.movie ? movieHits : seriesHits;
      if (list.isEmpty) return _noResult(loadingAny);
      return LayoutBuilder(
        builder: (context, c) {
          final innerW = (c.maxWidth - hPad * 2).clamp(240.0, 4000.0);
          final cols = _posterCols(innerW, phone: phone);
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(hPad, 8, hPad, listBottom),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: phone ? 12 : 16,
              mainAxisSpacing: phone ? 14 : 18,
              childAspectRatio: 0.56,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) => _posterCard(list[i]),
          );
        },
      );
    }

    if (liveHits.isEmpty && movieHits.isEmpty && seriesHits.isEmpty) {
      return _noResult(loadingAny);
    }

    const livePreviewCap = 6;
    const posterPreviewCap = 12;

    return ListView(
      padding: EdgeInsets.fromLTRB(hPad, 8, hPad, listBottom),
      children: [
        if (liveHits.isNotEmpty) ...[
          _sectionHeader(
            title: 'Canlı TV',
            total: liveHits.length,
            capped: liveHits.length > livePreviewCap,
            onSeeAll: () => setState(() => _filter = Kind.live),
          ),
          const SizedBox(height: 8),
          for (final ch in liveHits.take(livePreviewCap))
            SizedBox(height: 74, child: _channelRow(ch, liveHits)),
          const SizedBox(height: 18),
        ],
        if (movieHits.isNotEmpty) ...[
          _sectionHeader(
            title: 'Filmler',
            total: movieHits.length,
            capped: movieHits.length > posterPreviewCap,
            onSeeAll: () => setState(() => _filter = Kind.movie),
          ),
          const SizedBox(height: 8),
          _posterSectionGrid(movieHits.take(posterPreviewCap).toList(), phone: phone),
          const SizedBox(height: 18),
        ],
        if (seriesHits.isNotEmpty) ...[
          _sectionHeader(
            title: 'Diziler',
            total: seriesHits.length,
            capped: seriesHits.length > posterPreviewCap,
            onSeeAll: () => setState(() => _filter = Kind.series),
          ),
          const SizedBox(height: 8),
          _posterSectionGrid(seriesHits.take(posterPreviewCap).toList(), phone: phone),
        ],
      ],
    );
  }

  Widget _noResult(bool loadingAny) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            loadingAny ? 'Katalog yükleniyor, eşleşmeler gelince görünecek...' : '"$_query" için sonuç bulunamadı',
            textAlign: TextAlign.center,
            style: AppText.meta(15),
          ),
        ),
      );

  Widget _sectionHeader({
    required String title,
    required int total,
    required bool capped,
    required VoidCallback onSeeAll,
  }) =>
      Row(
        children: [
          Text(title, style: AppText.title(18)),
          const SizedBox(width: 8),
          Text(groupCount(total), style: AppText.meta(13.5)),
          const Spacer(),
          if (capped)
            AppButton(
              label: 'Tümünü gör (${groupCount(total)})',
              dense: true,
              height: 34,
              onPressed: onSeeAll,
            ),
        ],
      );

  int _posterCols(double width, {required bool phone}) {
    if (phone) return (width / 118).floor().clamp(3, 6);
    return ((width + 16) / 144).floor().clamp(2, 10);
  }

  Widget _posterSectionGrid(List<Item> items, {required bool phone}) => LayoutBuilder(
        builder: (context, c) {
          final cols = _posterCols(c.maxWidth, phone: phone);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: phone ? 12 : 16,
              mainAxisSpacing: phone ? 14 : 18,
              childAspectRatio: 0.56,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _posterCard(items[i]),
          );
        },
      );

  Widget _channelRow(Item item, List<Item> liveQueue) {
    final fav = Library.instance.isFavorite(item);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FocusRing(
        radius: AppSizes.cardRadius,
        lift: false,
        onTap: () => _openItem(item, liveQueue),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: AppShadows.repeatedBorder(),
            boxShadow: AppShadows.forRepeated(),
          ),
          child: Row(
            children: [
              ChannelBadge(name: item.name, logo: item.logo, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: NowPlaying(
                  cache: widget.epg,
                  item: item,
                  fallback: groupLabel(item.group),
                  builder: (_, now) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(15)),
                      const SizedBox(height: 2),
                      Text(
                        now?.title ?? groupLabel(item.group),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: now == null ? AppText.meta(12.5) : AppText.note(12.5),
                      ),
                    ],
                  ),
                ),
              ),
              FocusRing(
                radius: 20,
                lift: false,
                tooltip: fav ? 'Favorilerden çıkar' : 'Favorilere ekle',
                onTap: () {
                  AppHaptics.selection(context);
                  Library.instance.toggleFavorite(item);
                },
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 20,
                    color: fav ? AppColors.live : AppColors.ink3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _posterCard(Item item) {
    final parsed = parsedTitleOf(item);
    final meta = [?parsed.year, ...parsed.tags.take(1)].join(' · ');
    final fav = Library.instance.isFavorite(item);
    final downloaded = item.url != null && DownloadManager.instance.localPathForUrl(item.url!, account: widget.account) != null;

    return FocusRing(
      radius: AppSizes.itemRadius,
      onTap: () => _openItem(item, const []),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSizes.itemRadius),
                    boxShadow: AppShadows.forRepeated(),
                    border: AppShadows.repeatedBorder(),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSizes.itemRadius),
                    child: PosterImage(item.logo, rating: downloaded ? null : Library.instance.ratingFor(item)),
                  ),
                ),
                if (downloaded && Library.instance.ratingFor(item) != null)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: PosterRatingBadge(rating: Library.instance.ratingFor(item)!, compact: true),
                  ),
                if (downloaded)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.download_done_rounded, size: 14, color: AppColors.accent),
                    ),
                  ),
                if (fav)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.favorite_rounded, size: 14, color: AppColors.live),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(parsed.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(13.5)),
          if (meta.isNotEmpty)
            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(11.5))
          else
            Text(groupLabel(item.group), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(11.5)),
        ],
      ),
    );
  }
}
