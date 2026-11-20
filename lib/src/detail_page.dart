import 'package:flutter/material.dart';

import 'library.dart';
import 'mini_player.dart';
import 'player_page.dart';
import 'title_utils.dart';
import 'poster_card.dart';
import 'settings.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/focus_ring.dart';
import 'ui/format.dart';
import 'ui/layout.dart';
import 'ui/liquid_glass.dart';
import 'ui/shell.dart';
import 'ui/tokens.dart';
import 'xtream.dart';

/// Detail page for a movie or a series (with seasons and episodes).
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.client, required this.item});

  final XtreamClient client;
  final Item item;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Future<SeriesData>? _series;
  Future<Details>? _movie;

  bool get _isSeries => widget.item.kind == Kind.series;

  void _load() {
    if (_isSeries) {
      _series = widget.client.seriesData(widget.item.seriesId!);
      _movie = null;
    } else {
      _movie = widget.client.vodDetails(widget.item.streamId!);
      _series = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id || oldWidget.item.kind != widget.item.kind) {
      _season = null;
      _plotExpanded = false;
      _load();
    }
  }

  void _play(List<PlayerEntry> queue, int index) {
    Navigator.of(context).push(appRoute(
      context,
      (_) => PlayerPage(queue: queue, index: index, kind: widget.item.kind, client: widget.client),
    ));
  }

  /// Season shown below the info card; chosen once the episodes are known.
  int? _season;
  bool _plotExpanded = false;

  /// First episode (season and number order) with a saved position.
  Episode? _resumeEpisode(List<Episode> episodes) {
    final sorted = [...episodes]..sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.number.compareTo(b.number));
    for (final e in sorted) {
      if (Library.instance.positionFor(e.url) != null) return e;
    }
    return null;
  }

  HistoryEntry? _historyOf(String url) {
    for (final h in Library.instance.history) {
      if (h.url == url) return h;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final mode = layoutModeOf(context);
    if (mode != AppLayoutMode.desktop) {
      final landscape = mode == AppLayoutMode.phoneLandscape;
      final pad = MediaQuery.paddingOf(context);
      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: _isSeries
                  ? FutureBuilder<SeriesData>(
                      future: _series,
                      builder: (context, snap) => _buildPhone(context, landscape, snap.connectionState, snap.error, snap.data?.details, snap.data?.episodes),
                    )
                  : FutureBuilder<Details>(
                      future: _movie,
                      builder: (context, snap) => _buildPhone(context, landscape, snap.connectionState, snap.error, snap.data, null),
                    ),
            ),
            if (landscape)
              Positioned(
                left: pad.left > 0 ? pad.left : 14,
                bottom: pad.bottom > 0 ? pad.bottom + 4 : 10,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: PhoneMiniPlayerSlot(compact: true, onExpand: () => expandMiniPlayer(context)),
                ),
              )
            else
              Positioned(
                left: 14,
                right: 14,
                bottom: pad.bottom > 0 ? pad.bottom + 6 : 12,
                child: PhoneMiniPlayerSlot(onExpand: () => expandMiniPlayer(context)),
              ),
          ],
        ),
      );
    }
    final name = parsedTitleOf(widget.item).title;
    return Scaffold(
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 0),
          child: Row(children: [
            AppButton(variant: AppButtonVariant.onPage, icon: Icons.chevron_left_rounded, label: 'Geri', onPressed: () => Navigator.of(context).maybePop()),
            const SizedBox(width: 14),
            Flexible(
              child: Row(children: [
                Text(_isSeries ? 'Diziler' : 'Filmler', style: AppText.meta(15)),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink3),
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(15))),
              ]),
            ),
            const SizedBox(width: 12),
            const ClockPill(),
          ]),
        ),
        Expanded(
          child: _isSeries
              ? FutureBuilder<SeriesData>(
                  future: _series,
                  builder: (context, snap) => _build(context, snap.connectionState, snap.error, snap.data?.details, snap.data?.episodes),
                )
              : FutureBuilder<Details>(
                  future: _movie,
                  builder: (context, snap) => _build(context, snap.connectionState, snap.error, snap.data, null),
                ),
        ),
      ]),
    );
  }

  Widget _buildPhone(BuildContext context, bool landscape, ConnectionState state, Object? error, Details? d, List<Episode>? episodes) {
    final loading = state != ConnectionState.done;
    final details = d ?? Details();
    return ListenableBuilder(
      listenable: Library.instance,
      builder: (context, _) {
        final seasons = <int, List<Episode>>{};
        for (final e in episodes ?? const <Episode>[]) {
          seasons.putIfAbsent(e.season, () => []).add(e);
        }
        String two(int n) => n.toString().padLeft(2, '0');
        final queue = <PlayerEntry>[
          for (final s in seasons.entries)
            for (final e in s.value)
              PlayerEntry(url: e.url, title: '${widget.item.name} S${two(s.key)}E${two(e.number)}', logo: e.image.isNotEmpty ? e.image : widget.item.logo),
        ];
        final position = <Episode, int>{};
        for (final s in seasons.values) {
          for (final e in s) {
            position[e] = position.length;
          }
        }
        final resumeEpisode = episodes == null ? null : _resumeEpisode(episodes);
        if (seasons.isNotEmpty) _season ??= resumeEpisode?.season ?? seasons.keys.first;
        final shownEpisodes = seasons[_season] ?? const <Episode>[];

        if (landscape) {
          return _buildPhoneLandscape(context, details, loading, error, seasons, shownEpisodes, queue, position, resumeEpisode);
        }
        return _buildPhonePortrait(context, details, loading, error, seasons, shownEpisodes, queue, position, resumeEpisode);
      },
    );
  }

  Widget _primaryCta(List<PlayerEntry> queue, Map<Episode, int> position, Episode? resumeEpisode, {bool fullWidth = false}) {
    if (_isSeries) {
      return AppButton(
        variant: AppButtonVariant.primary,
        height: AppSizes.primaryHeight,
        width: fullWidth ? double.infinity : null,
        icon: Icons.play_arrow_rounded,
        label: resumeEpisode != null ? '${resumeEpisode.number}. bölümden devam et' : 'İlk bölümü oynat',
        onPressed: queue.isEmpty
            ? null
            : () {
                AppHaptics.light(context);
                _play(queue, resumeEpisode == null ? 0 : position[resumeEpisode]!);
              },
      );
    }
    final resume = Library.instance.positionFor(widget.item.url!);
    return AppButton(
      variant: AppButtonVariant.primary,
      height: AppSizes.primaryHeight,
      width: fullWidth ? double.infinity : null,
      icon: Icons.play_arrow_rounded,
      label: resume == null ? 'Oynat' : 'Devam et ${clockTime(resume)}',
      onPressed: () {
        AppHaptics.light(context);
        _play([PlayerEntry(url: widget.item.url!, title: widget.item.name, logo: widget.item.logo)], 0);
      },
    );
  }

  List<Widget> _metaTags(Details details, ParsedTitle t, Map<int, List<Episode>> seasons) {
    final year = details.year.isNotEmpty ? details.year : t.year;
    final duration = minutesLabel(details.duration);
    return <Widget>[
      if (details.rating.isNotEmpty && details.rating != '0') Pill(details.rating, tone: PillTone.warn, icon: Icons.star_rounded, height: 26),
      if (year != null && year.isNotEmpty) Pill(year, height: 26),
      if (details.genre.isNotEmpty) Pill(details.genre, height: 26),
      for (final tag in t.tags) Pill(tag, height: 26),
      if (!_isSeries && duration.isNotEmpty) Pill(duration, height: 26),
      if (_isSeries && seasons.isNotEmpty) Pill('${seasons.length} sezon', height: 26),
    ];
  }

  Widget _buildPhonePortrait(
    BuildContext context,
    Details details,
    bool loading,
    Object? error,
    Map<int, List<Episode>> seasons,
    List<Episode> shownEpisodes,
    List<PlayerEntry> queue,
    Map<Episode, int> position,
    Episode? resumeEpisode,
  ) {
    final t = parsedTitleOf(widget.item);
    final poster = details.poster.isNotEmpty ? details.poster : widget.item.logo;
    final backdrop = details.backdrop.isNotEmpty ? details.backdrop : poster;
    final fav = Library.instance.isFavorite(widget.item);
    final tags = _metaTags(details, t, seasons);
    final pad = MediaQuery.paddingOf(context);
    final topInset = pad.top > 0 ? pad.top : 12.0;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  // Cinematic backdrop extending behind Dynamic Island, fading seamlessly into OLED charcoal.
                  SizedBox(
                    height: topInset + 215,
                    width: double.infinity,
                    child: Stack(fit: StackFit.expand, children: [
                      if (backdrop.isNotEmpty)
                        Opacity(opacity: 0.42, child: PosterImage(backdrop, cacheWidth: 640))
                      else
                        const ColoredBox(color: AppColors.surface),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [AppColors.videoScrim, AppColors.groundClear, AppColors.ground],
                            stops: [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, topInset + 56, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              width: 112,
                              height: 168,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: AppShadows.lift,
                                border: Border.all(color: AppColors.glassBorder, width: 1),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(17),
                                child: PosterImage(poster, cacheWidth: 320),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_isSeries ? 'Dizi' : 'Film', style: AppText.meta(12, color: AppColors.accentInk)),
                                  const SizedBox(height: 4),
                                  Text(t.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.display(25)),
                                  if (tags.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Wrap(spacing: 6, runSpacing: 6, children: tags),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _primaryCta(queue, position, resumeEpisode, fullWidth: true),
                        const SizedBox(height: 10),
                        fav
                            ? AppButton(
                                variant: AppButtonVariant.danger,
                                height: 44,
                                width: double.infinity,
                                icon: Icons.favorite_rounded,
                                label: 'Favorilerde',
                                onPressed: () {
                                  AppHaptics.selection(context);
                                  Library.instance.toggleFavorite(widget.item);
                                },
                              )
                            : AppButton(
                                height: 44,
                                width: double.infinity,
                                icon: Icons.favorite_border_rounded,
                                label: 'Favorilere ekle',
                                onPressed: () {
                                  AppHaptics.selection(context);
                                  Library.instance.toggleFavorite(widget.item);
                                },
                              ),
                        if (loading) ...[
                          const SizedBox(height: 18),
                          ClipRRect(borderRadius: BorderRadius.circular(3), child: const LinearProgressIndicator(minHeight: 5)),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: 14),
                          Text('Bilgi alınamadı: $error', style: AppText.label(14, color: AppColors.liveText)),
                        ],
                        if (details.plot.isNotEmpty || details.cast.isNotEmpty || details.director.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          AppCard(
                            radius: AppSizes.cardRadius,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (details.plot.isNotEmpty) ...[
                                  Text(
                                    details.plot,
                                    maxLines: _plotExpanded ? null : 4,
                                    overflow: _plotExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                    style: AppText.body(size: 14),
                                  ),
                                  if (details.plot.length > 150) ...[
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () => setState(() => _plotExpanded = !_plotExpanded),
                                      child: Text(
                                        _plotExpanded ? 'Daha az göster' : 'Devamını oku',
                                        style: AppText.label(13, color: AppColors.accentInk),
                                      ),
                                    ),
                                  ],
                                ],
                                if (details.cast.isNotEmpty) ...[
                                  SizedBox(height: details.plot.isNotEmpty ? 10 : 0),
                                  Text('Oyuncular: ${details.cast}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
                                ],
                                if (details.director.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('Yönetmen: ${details.director}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isSeries && !loading) ...[
              if (seasons.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    child: Text('Bölüm bulunamadı', style: AppText.meta(15)),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: seasons.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (_, idx) {
                                final s = seasons.keys.elementAt(idx);
                                return AppButton(
                                  label: '$s. sezon',
                                  height: 38,
                                  dense: true,
                                  variant: s == _season ? AppButtonVariant.primary : AppButtonVariant.onPage,
                                  onPressed: () {
                                    AppHaptics.selection(context);
                                    setState(() => _season = s);
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('${seasons[_season]?.length ?? 0} bölüm', style: AppText.meta(13)),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, pad.bottom + 24),
                  sliver: SliverList.separated(
                    itemCount: shownEpisodes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final e = shownEpisodes[i];
                      return RepaintBoundary(child: _phoneEpisodeRow(e, () => _play(queue, position[e]!)));
                    },
                  ),
                ),
              ],
            ] else
              SliverToBoxAdapter(child: SizedBox(height: pad.bottom + 24)),
          ],
        ),
        // Floating translucent Back + Favorite controls below Dynamic Island.
        Positioned(
          left: 14,
          right: 14,
          top: topInset + 4,
          child: Row(
            children: [
              PhoneIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Geri',
                translucent: true,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              PhoneIconButton(
                icon: fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                tooltip: fav ? 'Favorilerden çıkar' : 'Favorilere ekle',
                translucent: true,
                iconColor: fav ? AppColors.live : AppColors.ink,
                onTap: () => Library.instance.toggleFavorite(widget.item),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneLandscape(
    BuildContext context,
    Details details,
    bool loading,
    Object? error,
    Map<int, List<Episode>> seasons,
    List<Episode> shownEpisodes,
    List<PlayerEntry> queue,
    Map<Episode, int> position,
    Episode? resumeEpisode,
  ) {
    final t = parsedTitleOf(widget.item);
    final poster = details.poster.isNotEmpty ? details.poster : widget.item.logo;
    final backdrop = details.backdrop.isNotEmpty ? details.backdrop : poster;
    final fav = Library.instance.isFavorite(widget.item);
    final tags = _metaTags(details, t, seasons);
    final pad = MediaQuery.paddingOf(context);
    final leftInset = pad.left > 0 ? pad.left : 14.0;
    final rightInset = pad.right > 0 ? pad.right : 14.0;
    final bottomInset = pad.bottom > 0 ? pad.bottom : 12.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(leftInset, 10, rightInset, bottomInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left pane: back bar, compact poster + title + tags + CTAs.
          SizedBox(
            width: _isSeries ? 336 : 360,
            child: AppCard(
              radius: AppSizes.cardRadius,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    NativeGlassButton(
                      sfSymbol: 'chevron.left',
                      label: 'Geri',
                      tooltip: 'Geri',
                      isRound: false,
                      width: 86,
                      height: 36,
                      iconSize: 15,
                      fontSize: 13.5,
                      style: NativeGlassStyle.glass,
                      foregroundColor: AppColors.ink,
                      onPressed: () => Navigator.of(context).maybePop(),
                      fallback: AppButton(
                        variant: AppButtonVariant.secondary,
                        height: 36,
                        dense: true,
                        icon: Icons.chevron_left_rounded,
                        label: 'Geri',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isSeries ? 'Diziler' : 'Filmler',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.meta(13),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(width: 84, height: 126, child: PosterImage(poster, cacheWidth: 240)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.display(21)),
                                    if (tags.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Wrap(spacing: 5, runSpacing: 5, children: tags),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (loading) ...[
                            const SizedBox(height: 12),
                            ClipRRect(borderRadius: BorderRadius.circular(3), child: const LinearProgressIndicator(minHeight: 5)),
                          ],
                          if (error != null) ...[
                            const SizedBox(height: 10),
                            Text('Bilgi alınamadı: $error', style: AppText.label(13, color: AppColors.liveText)),
                          ],
                          if (_isSeries && details.plot.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(details.plot, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.body(size: 13)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _primaryCta(queue, position, resumeEpisode)),
                    const SizedBox(width: 8),
                    NativeGlassButton(
                      sfSymbol: fav ? 'heart.fill' : 'heart',
                      tooltip: fav ? 'Favorilerde' : 'Favorilere ekle',
                      height: AppSizes.primaryHeight,
                      iconSize: 20,
                      style: NativeGlassStyle.glass,
                      foregroundColor: fav ? AppColors.live : AppColors.ink,
                      onPressed: () {
                        AppHaptics.selection(context);
                        Library.instance.toggleFavorite(widget.item);
                      },
                      fallback: AppButton(
                        variant: fav ? AppButtonVariant.danger : AppButtonVariant.secondary,
                        height: AppSizes.primaryHeight,
                        icon: fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        tooltip: fav ? 'Favorilerde' : 'Favorilere ekle',
                        onPressed: () {
                          AppHaptics.selection(context);
                          Library.instance.toggleFavorite(widget.item);
                        },
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Right pane: episodes (for series) or rich synopsis + backdrop (for movies).
          Expanded(
            child: _isSeries
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!loading && seasons.isNotEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 38,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: seasons.length,
                                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                                  itemBuilder: (_, idx) {
                                    final s = seasons.keys.elementAt(idx);
                                    return AppButton(
                                      label: '$s. sezon',
                                      height: 36,
                                      dense: true,
                                      variant: s == _season ? AppButtonVariant.primary : AppButtonVariant.onPage,
                                      onPressed: () {
                                        AppHaptics.selection(context);
                                        setState(() => _season = s);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('${seasons[_season]?.length ?? 0} bölüm', style: AppText.meta(13)),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : seasons.isEmpty
                                ? Center(child: Text('Bölüm bulunamadı', style: AppText.meta(15)))
                                : ListView.separated(
                                    itemCount: shownEpisodes.length,
                                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                                    itemBuilder: (_, i) {
                                      final e = shownEpisodes[i];
                                      return RepaintBoundary(child: _phoneEpisodeRow(e, () => _play(queue, position[e]!)));
                                    },
                                  ),
                      ),
                    ],
                  )
                : AppCard(
                    radius: AppSizes.cardRadius,
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (backdrop.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(height: 146, child: PosterImage(backdrop, cacheWidth: 640)),
                            ),
                            const SizedBox(height: 14),
                          ],
                          if (details.plot.isNotEmpty) Text(details.plot, style: AppText.body(size: 14)),
                          if (details.cast.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text('Oyuncular: ${details.cast}', style: AppText.meta(13)),
                          ],
                          if (details.director.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Yönetmen: ${details.director}', style: AppText.meta(13)),
                          ],
                          if (details.plot.isEmpty && details.cast.isEmpty && details.director.isEmpty && !loading)
                            Text('Bu film için ek açıklama bulunmuyor.', style: AppText.meta(14)),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _phoneEpisodeRow(Episode e, VoidCallback onTap) {
    final saved = Library.instance.positionFor(e.url);
    final h = saved == null ? null : _historyOf(e.url);
    final known = h != null && h.durationMs > 0;
    final String? meta;
    Color metaColor = AppColors.ink2;
    if (saved != null && known) {
      meta = remainingText(Duration(milliseconds: h.durationMs - h.positionMs));
      metaColor = AppColors.accentInk;
    } else if (saved != null) {
      meta = 'Devam ediliyor';
      metaColor = AppColors.accentInk;
    } else {
      final m = minutesLabel(e.duration);
      meta = m.isEmpty ? null : m;
    }
    return FocusRing(
      radius: AppSizes.tileRadius,
      lift: false,
      onTap: () {
        AppHaptics.light(context);
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          border: Border.all(color: AppColors.line, width: 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: SizedBox(
                width: 118,
                height: 70,
                child: Stack(fit: StackFit.expand, children: [
                  PosterImage(e.image.isNotEmpty ? e.image : widget.item.logo, cacheWidth: 260),
                  Positioned(left: 6, top: 6, child: Pill('${e.number}. bölüm', tone: PillTone.onImage, height: 22)),
                  if (known) Positioned(left: 8, right: 8, bottom: 6, child: ProgressBar(value: h.progress, height: 3.5, onImage: true)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.title.isEmpty ? '${e.number}. bölüm' : e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(15),
                  ),
                  if (meta != null) ...[
                    const SizedBox(height: 4),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(12.5, color: metaColor)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, size: 20, color: AppColors.accentInk),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build(BuildContext context, ConnectionState state, Object? error, Details? d, List<Episode>? episodes) {
    final loading = state != ConnectionState.done;
    final details = d ?? Details();
    return ListenableBuilder(
      listenable: Library.instance,
      builder: (context, _) {
        // Everything in the order shown, so the player can move on to the next episode (and into the next season).
        final seasons = <int, List<Episode>>{};
        for (final e in episodes ?? const <Episode>[]) {
          seasons.putIfAbsent(e.season, () => []).add(e);
        }
        String two(int n) => n.toString().padLeft(2, '0');
        final queue = <PlayerEntry>[
          for (final s in seasons.entries)
            for (final e in s.value)
              PlayerEntry(url: e.url, title: '${widget.item.name} S${two(s.key)}E${two(e.number)}', logo: e.image.isNotEmpty ? e.image : widget.item.logo),
        ];
        final position = <Episode, int>{};
        for (final s in seasons.values) {
          for (final e in s) {
            position[e] = position.length;
          }
        }
        final resumeEpisode = episodes == null ? null : _resumeEpisode(episodes);
        if (seasons.isNotEmpty) _season ??= resumeEpisode?.season ?? seasons.keys.first;
        final shownEpisodes = seasons[_season] ?? const <Episode>[];

        return Builder(builder: (context) {
          final w = MediaQuery.sizeOf(context).width;
          final cols = w < 800 ? 2 : (w < 1100 ? 3 : 4);
          const pad = EdgeInsets.fromLTRB(26, 16, 26, 24);
          return CustomScrollView(slivers: [
            SliverPadding(
              padding: pad,
              sliver: SliverMainAxisGroup(slivers: [
                SliverToBoxAdapter(child: _infoCard(details, loading, error, seasons, queue, position, resumeEpisode, showBackdrop: w >= 1100)),
                if (_isSeries && !loading) ...[
                  if (seasons.isEmpty)
                    SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 32), child: Text('Bölüm bulunamadı', style: AppText.meta(15))))
                  else ...[
                    SliverToBoxAdapter(child: _seasonRow(seasons)),
                    SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 16, mainAxisSpacing: 16, mainAxisExtent: 204),
                      itemCount: shownEpisodes.length,
                      itemBuilder: (_, i) {
                        final e = shownEpisodes[i];
                        return RepaintBoundary(child: _episodeCard(e, () => _play(queue, position[e]!)));
                      },
                    ),
                  ],
                ],
              ]),
            ),
          ]);
        });
      },
    );
  }

  Widget _infoCard(
    Details details,
    bool loading,
    Object? error,
    Map<int, List<Episode>> seasons,
    List<PlayerEntry> queue,
    Map<Episode, int> position,
    Episode? resumeEpisode, {
    required bool showBackdrop,
  }) {
    final t = parsedTitleOf(widget.item);
    final poster = details.poster.isNotEmpty ? details.poster : widget.item.logo;
    final year = details.year.isNotEmpty ? details.year : t.year;
    final fav = Library.instance.isFavorite(widget.item);
    final backdrop = showBackdrop && details.backdrop.isNotEmpty;

    final Widget primary;
    if (_isSeries) {
      primary = AppButton(
        variant: AppButtonVariant.primary,
        height: AppSizes.primaryHeight,
        icon: Icons.play_arrow_rounded,
        autofocus: AppSettings.instance.tvMode,
        label: resumeEpisode != null ? '${resumeEpisode.number}. bölümden devam et' : 'İlk bölümü oynat',
        onPressed: queue.isEmpty ? null : () => _play(queue, resumeEpisode == null ? 0 : position[resumeEpisode]!),
      );
    } else {
      final resume = Library.instance.positionFor(widget.item.url!);
      primary = AppButton(
        variant: AppButtonVariant.primary,
        height: AppSizes.primaryHeight,
        icon: Icons.play_arrow_rounded,
        autofocus: AppSettings.instance.tvMode,
        label: resume == null ? 'Oynat' : 'Devam et ${clockTime(resume)}',
        onPressed: () => _play([PlayerEntry(url: widget.item.url!, title: widget.item.name, logo: widget.item.logo)], 0),
      );
    }
    final duration = minutesLabel(details.duration);
    final tags = <Widget>[
      if (details.rating.isNotEmpty && details.rating != '0') Pill(details.rating, tone: PillTone.warn, icon: Icons.star_rounded),
      if (year != null && year.isNotEmpty) Pill(year),
      if (details.genre.isNotEmpty) Pill(details.genre),
      for (final tag in t.tags) Pill(tag),
      if (!_isSeries && duration.isNotEmpty) Pill(duration),
      if (_isSeries && seasons.isNotEmpty) Pill('${seasons.length} sezon'),
    ];

    return AppCard(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 300),
        child: Stack(children: [
          if (backdrop)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 600,
              child: ClipRRect(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppSizes.panelRadius)),
                child: Stack(fit: StackFit.expand, children: [
                  PosterImage(details.backdrop, cacheWidth: 640),
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
          Padding(
            padding: EdgeInsets.fromLTRB(24, 24, backdrop ? 420 : 28, 24),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(AppSizes.tileRadius), child: SizedBox(width: 168, height: 252, child: PosterImage(poster))),
              const SizedBox(width: 28),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 4),
                    Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.display(38)),
                    if (tags.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: tags)],
                    if (loading) ...[
                      const SizedBox(height: 18),
                      SizedBox(width: 220, child: ClipRRect(borderRadius: BorderRadius.circular(3), child: const LinearProgressIndicator(minHeight: 6))),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      Text('Bilgi alınamadı: $error', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.label(14, color: AppColors.liveText)),
                    ],
                    if (details.plot.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(details.plot, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.body()),
                    ],
                    if (details.cast.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Oyuncular: ${details.cast}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
                    ],
                    if (details.director.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Yönetmen: ${details.director}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
                    ],
                    const SizedBox(height: 18),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      primary,
                      fav
                          ? AppButton(
                              variant: AppButtonVariant.danger,
                              height: AppSizes.primaryHeight,
                              icon: Icons.favorite_rounded,
                              label: 'Favorilerde',
                              onPressed: () => Library.instance.toggleFavorite(widget.item),
                            )
                          : AppButton(
                              height: AppSizes.primaryHeight,
                              icon: Icons.favorite_border_rounded,
                              label: 'Favorilere ekle',
                              onPressed: () => Library.instance.toggleFavorite(widget.item),
                            ),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _seasonRow(Map<int, List<Episode>> seasons) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in seasons.keys)
                AppButton(
                  label: '$s. sezon',
                  variant: s == _season ? AppButtonVariant.primary : AppButtonVariant.onPage,
                  onPressed: () => setState(() => _season = s),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Text('${seasons[_season]?.length ?? 0} bölüm', style: AppText.meta(15)),
        ]),
      );

  Widget _episodeCard(Episode e, VoidCallback onTap) {
    final saved = Library.instance.positionFor(e.url);
    final h = saved == null ? null : _historyOf(e.url);
    final known = h != null && h.durationMs > 0;
    final String? meta;
    Color metaColor = AppColors.ink2;
    if (saved != null && known) {
      meta = remainingText(Duration(milliseconds: h.durationMs - h.positionMs));
      metaColor = AppColors.accentInk;
    } else if (saved != null) {
      meta = 'Devam ediliyor';
      metaColor = AppColors.accentInk;
    } else {
      final m = minutesLabel(e.duration);
      meta = m.isEmpty ? null : m;
    }
    return FocusRing(
      radius: AppSizes.cardRadius,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
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
              height: 128,
              child: Stack(fit: StackFit.expand, children: [
                PosterImage(e.image.isNotEmpty ? e.image : widget.item.logo),
                Positioned(left: 10, top: 10, child: Pill('${e.number}. bölüm', tone: PillTone.onImage, height: 26)),
                if (known) Positioned(left: 12, right: 12, bottom: 10, child: ProgressBar(value: h.progress, height: 4, onImage: true)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title.isEmpty ? '${e.number}. bölüm' : e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(15)),
              if (meta != null) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(13, color: metaColor)),
            ]),
          ),
        ]),
      ),
    );
  }
}
