import 'package:flutter/material.dart';

import 'library.dart';
import 'player_page.dart';
import 'title_utils.dart';
import 'poster_card.dart';
import 'settings.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/focus_ring.dart';
import 'ui/format.dart';
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
  late final Future<SeriesData> _series;
  late final Future<Details> _movie;

  bool get _isSeries => widget.item.kind == Kind.series;

  @override
  void initState() {
    super.initState();
    if (_isSeries) {
      _series = widget.client.seriesData(widget.item.seriesId!);
    } else {
      _movie = widget.client.vodDetails(widget.item.streamId!);
    }
  }

  void _play(List<PlayerEntry> queue, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(queue: queue, index: index, kind: widget.item.kind, client: widget.client),
    ));
  }

  /// Season shown below the info card; chosen once the episodes are known.
  int? _season;

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
