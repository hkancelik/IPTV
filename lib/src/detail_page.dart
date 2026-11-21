import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'downloads.dart';
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

  static final List<String> _openItemIds = [];

  /// True when the topmost mounted [DetailPage] in the navigator stack is for [itemId].
  static bool isTopFor(String itemId) => _openItemIds.isNotEmpty && _openItemIds.last == itemId;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Future<SeriesData>? _series;
  Future<Details>? _movie;
  late String _trackedId;
  late final TextEditingController _reviewCtrl = TextEditingController();
  double? _draftRating;
  bool _draftRewatch = false;
  bool _reviewDirty = false;
  bool _savedFlash = false;
  int _lastSyncedLogMs = -1;

  bool get _isSeries => widget.item.kind == Kind.series;

  void _syncDraftFromLibrary({bool force = false}) {
    final log = Library.instance.logFor(widget.item);
    final stamp = log?.changedAtMs ?? 0;
    if (!force && stamp == _lastSyncedLogMs) return;
    _lastSyncedLogMs = stamp;
    _draftRating = log?.rating;
    if (force || !_reviewDirty) {
      final text = log?.review ?? '';
      if (_reviewCtrl.text != text) {
        _reviewCtrl.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      _reviewDirty = false;
    }
  }

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
    _trackedId = widget.item.id;
    DetailPage._openItemIds.add(_trackedId);
    _syncDraftFromLibrary(force: true);
    _load();
  }

  @override
  void didUpdateWidget(DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id || oldWidget.item.kind != widget.item.kind) {
      final idx = DetailPage._openItemIds.lastIndexOf(_trackedId);
      if (idx >= 0) DetailPage._openItemIds[idx] = widget.item.id;
      _trackedId = widget.item.id;
      _season = null;
      _plotExpanded = false;
      _draftRewatch = false;
      _savedFlash = false;
      _syncDraftFromLibrary(force: true);
      _load();
    }
  }

  @override
  void dispose() {
    final idx = DetailPage._openItemIds.lastIndexOf(_trackedId);
    if (idx >= 0) DetailPage._openItemIds.removeAt(idx);
    _reviewCtrl.dispose();
    super.dispose();
  }

  void _play(List<PlayerEntry> queue, int index) {
    Navigator.of(context).push(appRoute(
      context,
      (_) => PlayerPage(queue: queue, index: index, kind: widget.item.kind, client: widget.client),
    ));
  }

  void _showNotice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _warnIfStreamingOnline() {
    if (PlayerSession.instance.active && !PlayerSession.instance.isPlayingLocal) {
      _showNotice('İndirme başladı. Tek bağlantılı aboneliklerde aynı anda canlı yayın/video izlemek bağlantıyı kesebilir.');
    }
  }

  Future<void> _handleMovieDownload() async {
    final url = widget.item.url;
    if (url == null || url.isEmpty) return;
    final mgr = DownloadManager.instance;
    final existing = mgr.entryForUrl(url, account: widget.client.acc);
    if (existing == null) {
      final res = await mgr.enqueueMovie(widget.item, widget.client.acc);
      if (res.error != null) {
        _showNotice(res.error!);
      } else if (res.added > 0) {
        if (PlayerSession.instance.active && !PlayerSession.instance.isPlayingLocal) {
          _warnIfStreamingOnline();
        } else {
          _showNotice('İndirme kuyruğuna eklendi');
        }
      }
      return;
    }
    if (existing.isDownloading || existing.isQueued) {
      await mgr.pause(existing.id);
      _showNotice('İndirme duraklatıldı');
    } else if (existing.isPaused || existing.isFailed) {
      await mgr.resume(existing.id, account: widget.client.acc);
      _warnIfStreamingOnline();
    } else if (existing.isCompleted) {
      await _confirmDeleteDownload(existing);
    }
  }

  Future<void> _handleEpisodeDownload(Episode e) async {
    final mgr = DownloadManager.instance;
    final existing = mgr.entryForUrl(e.url, account: widget.client.acc);
    if (existing == null) {
      final res = await mgr.enqueueEpisode(widget.item, e, widget.client.acc);
      if (res.error != null) {
        _showNotice(res.error!);
      } else if (res.added > 0) {
        if (PlayerSession.instance.active && !PlayerSession.instance.isPlayingLocal) {
          _warnIfStreamingOnline();
        } else {
          _showNotice('${e.number}. bölüm indirme kuyruğuna eklendi');
        }
      }
      return;
    }
    if (existing.isDownloading || existing.isQueued) {
      await mgr.pause(existing.id);
    } else if (existing.isPaused || existing.isFailed) {
      await mgr.resume(existing.id, account: widget.client.acc);
      _warnIfStreamingOnline();
    } else if (existing.isCompleted) {
      await _confirmDeleteDownload(existing);
    }
  }

  Future<void> _handleSeasonDownload(List<Episode> episodes) async {
    if (episodes.isEmpty) return;
    final res = await DownloadManager.instance.enqueueSeason(widget.item, episodes, widget.client.acc);
    if (res.error != null) {
      _showNotice(res.error!);
    } else if (res.added > 0) {
      if (PlayerSession.instance.active && !PlayerSession.instance.isPlayingLocal) {
        _warnIfStreamingOnline();
      } else {
        _showNotice('${res.added} bölüm indirme kuyruğuna eklendi');
      }
    } else {
      _showNotice('Bu sezondaki tüm bölümler zaten indirildi veya kuyrukta');
    }
  }

  Future<void> _confirmDeleteDownload(DownloadEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İndirilen silinsin mi?'),
        content: Text('"${e.title}" cihazdan silinecek (${formatBytes(e.effectiveBytes)}).'),
        actions: [
          AppButton(label: 'İptal', autofocus: true, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'Sil', variant: AppButtonVariant.danger, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true) {
      await DownloadManager.instance.delete(e.id);
      _showNotice('İndirilen dosya silindi');
    }
  }

  Widget _movieDownloadButton({bool fullWidth = false, bool iconOnly = false, double height = AppSizes.primaryHeight}) {
    final url = widget.item.url ?? '';
    final dl = DownloadManager.instance.entryForUrl(url, account: widget.client.acc);
    final IconData icon;
    final String label;
    final String tooltip;
    AppButtonVariant variant = AppButtonVariant.secondary;

    if (dl == null) {
      icon = Icons.download_rounded;
      label = 'İndir';
      tooltip = 'Çevrimdışı izlemek için indir';
    } else if (dl.isCompleted) {
      icon = Icons.download_done_rounded;
      label = 'İndirildi (${formatBytes(dl.effectiveBytes)})';
      tooltip = 'İndirildi · silmek için dokun';
    } else if (dl.isDownloading) {
      icon = Icons.pause_rounded;
      final pct = dl.totalBytes > 0 ? '%${(dl.progress * 100).round()}' : '...';
      label = 'İndiriliyor $pct';
      tooltip = 'İndirmeyi duraklat';
    } else if (dl.isQueued) {
      icon = Icons.schedule_rounded;
      label = 'Sırada';
      tooltip = 'Duraklat';
    } else if (dl.isPaused) {
      icon = Icons.play_arrow_rounded;
      label = 'Devam et (%${(dl.progress * 100).round()})';
      tooltip = 'İndirmeye devam et';
    } else {
      icon = Icons.refresh_rounded;
      label = 'Tekrar dene';
      tooltip = dl.error ?? 'İndirme başarısız · tekrar dene';
      variant = AppButtonVariant.danger;
    }

    return AppButton(
      key: const ValueKey('detail-download-movie'),
      variant: variant,
      height: height,
      width: fullWidth ? double.infinity : null,
      icon: icon,
      label: iconOnly ? null : label,
      tooltip: tooltip,
      onPressed: () {
        AppHaptics.selection(context);
        _handleMovieDownload();
      },
    );
  }

  Widget _episodeDownloadControl(Episode e, {double size = 34}) {
    final dl = DownloadManager.instance.entryForUrl(e.url, account: widget.client.acc);
    final IconData icon;
    final Color fg;
    final String tooltip;
    if (dl == null) {
      icon = Icons.download_rounded;
      fg = AppColors.ink2;
      tooltip = '${e.number}. bölümü indir';
    } else if (dl.isCompleted) {
      icon = Icons.download_done_rounded;
      fg = AppColors.accentInk;
      tooltip = 'İndirildi · silmek için dokun';
    } else if (dl.isDownloading) {
      icon = Icons.pause_rounded;
      fg = AppColors.accentInk;
      tooltip = 'İndiriliyor %${(dl.progress * 100).round()} · duraklat';
    } else if (dl.isQueued) {
      icon = Icons.schedule_rounded;
      fg = AppColors.ink2;
      tooltip = 'Sırada · duraklat';
    } else if (dl.isFailed) {
      icon = Icons.refresh_rounded;
      fg = AppColors.liveText;
      tooltip = 'Tekrar dene';
    } else {
      icon = Icons.play_arrow_rounded;
      fg = AppColors.warnInk;
      tooltip = 'Devam et';
    }

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: ValueKey('episode-download-${e.season}-${e.number}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.selection(context);
          _handleEpisodeDownload(e);
        },
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: dl != null && (dl.isCompleted || dl.isDownloading) ? AppColors.accentSoft : AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
              ),
              if (dl != null && dl.isDownloading)
                SizedBox(
                  width: size - 4,
                  height: size - 4,
                  child: CircularProgressIndicator(
                    value: dl.totalBytes > 0 ? dl.progress : null,
                    strokeWidth: 2.2,
                    color: AppColors.accent,
                    backgroundColor: AppColors.line,
                  ),
                ),
              Icon(icon, size: size * 0.54, color: fg),
            ],
          ),
        ),
      ),
    );
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
      listenable: Listenable.merge([Library.instance, DownloadManager.instance]),
      builder: (context, _) {
        final seasons = <int, List<Episode>>{};
        for (final e in episodes ?? const <Episode>[]) {
          seasons.putIfAbsent(e.season, () => []).add(e);
        }
        String two(int n) => n.toString().padLeft(2, '0');
        final queue = <PlayerEntry>[
          for (final s in seasons.entries)
            for (final e in s.value)
              PlayerEntry(url: e.url, title: '${widget.item.name} S${two(s.key)}E${two(e.number)}', logo: e.image.isNotEmpty ? e.image : widget.item.logo, item: widget.item),
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
        _play([PlayerEntry(url: widget.item.url!, title: widget.item.name, logo: widget.item.logo, item: widget.item)], 0);
      },
    );
  }

  List<Widget> _metaTags(Details details, ParsedTitle t, Map<int, List<Episode>> seasons) {
    final year = details.year.isNotEmpty ? details.year : t.year;
    final duration = minutesLabel(details.duration);
    final log = Library.instance.logFor(widget.item);
    final lastWatch = log?.lastWatch;
    return <Widget>[
      if (lastWatch != null)
        Pill(
          '✓ İzlendi (${shortDateTr(lastWatch.watchedAt)})',
          tone: PillTone.ok,
          height: 26,
        ),
      if (details.rating.isNotEmpty && details.rating != '0') Pill(details.rating, tone: PillTone.warn, icon: Icons.star_rounded, height: 26),
      if (year != null && year.isNotEmpty) Pill(year, height: 26),
      if (details.genre.isNotEmpty) Pill(details.genre, height: 26),
      for (final tag in t.tags) Pill(tag, height: 26),
      if (!_isSeries && duration.isNotEmpty) Pill(duration, height: 26),
      if (_isSeries && seasons.isNotEmpty) Pill('${seasons.length} sezon', height: 26),
    ];
  }

  Widget _watchlistButton({bool fullWidth = false, bool iconOnly = false, double height = AppSizes.primaryHeight}) {
    final inWl = Library.instance.isInWatchlist(widget.item);
    final label = inWl ? 'Listemde ✓' : 'Sonra İzle';
    return AppButton(
      key: const ValueKey('detail-watchlist-button'),
      variant: inWl ? AppButtonVariant.primary : AppButtonVariant.secondary,
      height: height,
      width: fullWidth ? double.infinity : null,
      icon: inWl ? Icons.bookmark_added_rounded : Icons.schedule_rounded,
      label: iconOnly ? null : label,
      tooltip: inWl ? 'Sonra İzle listesinden çıkar' : 'Sonra İzle listesine ekle',
      onPressed: () {
        AppHaptics.selection(context);
        Library.instance.toggleWatchlist(widget.item);
      },
    );
  }

  Future<void> _saveInlineLog() async {
    final existing = Library.instance.logFor(widget.item);
    final hasExisting = existing != null;
    await Library.instance.saveLog(
      widget.item,
      rating: _draftRating,
      clearRating: _draftRating == null && hasExisting,
      review: _reviewCtrl.text,
      watched: _draftRating != null || _draftRewatch || _reviewCtrl.text.trim().isNotEmpty ? true : null,
      addRewatch: _draftRewatch,
    );
    if (!mounted) return;
    setState(() {
      _draftRewatch = false;
      _reviewDirty = false;
      _savedFlash = true;
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _savedFlash = false);
    });
  }

  Widget _desktopInlineLogCard() {
    _syncDraftFromLibrary();
    final log = Library.instance.logFor(widget.item);
    final rating = _draftRating;
    final mood = MediaLogEntry.moodFor(rating);
    final rewatchCount = log?.rewatchCount ?? 0;

    return Container(
      key: const ValueKey('detail-inline-log-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('KİŞİSEL GÜNLÜK KAYDIN', style: AppText.label(12, color: AppColors.ink2)),
                    const SizedBox(height: 2),
                    Text(
                      'Yarım yıldız (0.5) adımlarla puanla · LAN Sync ile cihazlarına eşitlenir',
                      style: AppText.meta(12, color: AppColors.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                key: const ValueKey('detail-rewatch-toggle'),
                dense: true,
                height: 32,
                variant: _draftRewatch ? AppButtonVariant.primary : AppButtonVariant.onPage,
                icon: Icons.replay_rounded,
                label: rewatchCount > 0 && !_draftRewatch ? 'Tekrar İzleme ($rewatchCount)' : 'Tekrar İzleme',
                onPressed: () {
                  AppHaptics.selection(context);
                  setState(() => _draftRewatch = !_draftRewatch);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              HalfStarRatingPicker(
                key: const ValueKey('detail-inline-star-picker'),
                rating: rating,
                size: 28,
                onChanged: (next) {
                  AppHaptics.selection(context);
                  setState(() => _draftRating = next);
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    rating == null ? '—' : MediaLogEntry.formatRating(rating),
                    key: const ValueKey('detail-inline-rating-readout'),
                    style: AppText.title(24, color: rating == null ? AppColors.ink2 : AppColors.star),
                  ),
                  const SizedBox(width: 4),
                  Text('/ 5.0', style: AppText.meta(12)),
                ],
              ),
              if (mood != null) Pill(mood, tone: PillTone.warn, height: 26),
              if (log != null && log.watched && log.lastWatch != null)
                Pill('✓ ${shortDateTr(log.lastWatch!.watchedAt)}', tone: PillTone.ok, height: 26),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.ground,
                    borderRadius: BorderRadius.circular(AppSizes.smallRadius),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: RemoteTextField(
                    key: const ValueKey('detail-inline-review-input'),
                    controller: _reviewCtrl,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _reviewDirty = true,
                    onSubmitted: (_) => _saveInlineLog(),
                    decoration: InputDecoration(
                      hintText: 'Bu yapım hakkında kısa notun veya yorumun...',
                      hintStyle: AppText.meta(13.5),
                      isCollapsed: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AppButton(
                key: const ValueKey('detail-inline-save-button'),
                height: 40,
                variant: _savedFlash ? AppButtonVariant.primary : AppButtonVariant.onPage,
                icon: _savedFlash ? Icons.check_rounded : null,
                label: _savedFlash ? 'Kaydedildi' : (log == null ? 'Günlüğe Kaydet' : 'Kaydı Güncelle'),
                onPressed: () {
                  AppHaptics.light(context);
                  _saveInlineLog();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _phoneGlassRatingButton({double height = 38}) {
    final r = Library.instance.ratingFor(widget.item);
    final label = r == null ? 'Puanla' : MediaLogEntry.formatRating(r);
    final fg = r == null ? AppColors.ink : AppColors.star;
    final fallback = Tooltip(
      message: 'Puanla ve günlüğe ekle',
      child: GestureDetector(
        key: const ValueKey('detail-phone-glass-rating-button'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.selection(context);
          _openPhoneRatingSheet();
        },
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.videoGlass,
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: AppColors.glassBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(r == null ? Icons.star_border_rounded : Icons.star_rounded, size: 16, color: AppColors.star),
              const SizedBox(width: 5),
              Text(label, style: AppText.meta(13, color: fg)),
            ],
          ),
        ),
      ),
    );

    return NativeGlassButton(
      sfSymbol: r == null ? 'star' : 'star.fill',
      label: label,
      tooltip: 'Puanla ve günlüğe ekle',
      isRound: false,
      height: height,
      iconSize: 14,
      fontSize: 13,
      style: NativeGlassStyle.glass,
      foregroundColor: fg,
      onPressed: () {
        AppHaptics.selection(context);
        _openPhoneRatingSheet();
      },
      fallback: fallback,
    );
  }

  Widget _phonePersonalLogCard() {
    final log = Library.instance.logFor(widget.item);
    final rating = log?.rating;
    final lastWatch = log?.lastWatch;
    final review = log?.review.trim() ?? '';

    return GestureDetector(
      key: const ValueKey('detail-phone-log-card'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.selection(context);
        _openPhoneRatingSheet();
      },
      child: AppCard(
        radius: AppSizes.tileRadius,
        padding: const EdgeInsets.all(14),
        border: Border.all(color: AppColors.line),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('GÜNLÜK KAYDIN', style: AppText.label(11.5, color: AppColors.ink2)),
                ),
                Text(
                  log == null ? 'Puanla ›' : 'Düzenle ›',
                  style: AppText.label(12, color: AppColors.accent),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (rating != null) ...[
                  Text(
                    starGlyphs(rating),
                    key: const ValueKey('detail-phone-stars-display'),
                    style: AppText.title(18, color: AppColors.star),
                  ),
                  const SizedBox(width: 8),
                  Text(MediaLogEntry.formatRating(rating), style: AppText.meta(13, color: AppColors.warnInk)),
                  const Spacer(),
                ] else
                  Expanded(
                    child: Text(
                      'Henüz puanlanmadı · Dokunarak puanla',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.meta(13, color: AppColors.ink2),
                    ),
                  ),
                if (lastWatch != null)
                  Text(
                    shortDateTr(lastWatch.watchedAt, includeYear: true),
                    style: AppText.meta(12, color: AppColors.ink2),
                  ),
              ],
            ),
            if (review.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '"$review"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openPhoneRatingSheet() async {
    final t = parsedTitleOf(widget.item);
    await showAppSheet<void>(
      context: context,
      title: t.title,
      subtitle: 'Puanla & Günlüğe Ekle',
      builder: (ctx) => _PhoneRatingSheetBody(item: widget.item),
    );
    if (mounted) {
      setState(() => _syncDraftFromLibrary(force: true));
    }
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
                                child: PosterImage(poster, cacheWidth: 320, rating: Library.instance.ratingFor(widget.item)),
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
                        Row(
                          children: [
                            Expanded(child: _primaryCta(queue, position, resumeEpisode)),
                            const SizedBox(width: 8),
                            _watchlistButton(iconOnly: true),
                            if (!_isSeries) ...[
                              const SizedBox(width: 8),
                              _movieDownloadButton(iconOnly: true),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        _phonePersonalLogCard(),
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
                        const SizedBox(width: 8),
                        AppButton(
                          key: const ValueKey('detail-download-season'),
                          dense: true,
                          height: 36,
                          variant: AppButtonVariant.onPage,
                          icon: Icons.download_rounded,
                          label: 'Sezonu indir',
                          onPressed: shownEpisodes.isEmpty
                              ? null
                              : () {
                                  AppHaptics.selection(context);
                                  _handleSeasonDownload(shownEpisodes);
                                },
                        ),
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
        // Floating translucent Back + Rating + Favorite controls below Dynamic Island.
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
              _phoneGlassRatingButton(height: 38),
              const SizedBox(width: 8),
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
                    const SizedBox(width: 6),
                    _phoneGlassRatingButton(height: 36),
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
                                child: SizedBox(
                                  width: 84,
                                  height: 126,
                                  child: PosterImage(poster, cacheWidth: 240, rating: Library.instance.ratingFor(widget.item)),
                                ),
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
                          const SizedBox(height: 10),
                          _phonePersonalLogCard(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _primaryCta(queue, position, resumeEpisode)),
                    const SizedBox(width: 8),
                    _watchlistButton(iconOnly: true),
                    if (!_isSeries) ...[
                      const SizedBox(width: 8),
                      _movieDownloadButton(iconOnly: true),
                    ],
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
                            const SizedBox(width: 8),
                            AppButton(
                              key: const ValueKey('detail-download-season'),
                              dense: true,
                              height: 34,
                              variant: AppButtonVariant.onPage,
                              icon: Icons.download_rounded,
                              label: 'Sezonu indir',
                              onPressed: shownEpisodes.isEmpty
                                  ? null
                                  : () {
                                      AppHaptics.selection(context);
                                      _handleSeasonDownload(shownEpisodes);
                                    },
                            ),
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
            _episodeDownloadControl(e, size: 34),
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
      listenable: Listenable.merge([Library.instance, DownloadManager.instance]),
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
              PlayerEntry(url: e.url, title: '${widget.item.name} S${two(s.key)}E${two(e.number)}', logo: e.image.isNotEmpty ? e.image : widget.item.logo, item: widget.item),
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
        onPressed: () => _play([PlayerEntry(url: widget.item.url!, title: widget.item.name, logo: widget.item.logo, item: widget.item)], 0),
      );
    }
    final duration = minutesLabel(details.duration);
    final log = Library.instance.logFor(widget.item);
    final lastWatch = log?.lastWatch;
    final tags = <Widget>[
      if (lastWatch != null) Pill('✓ İzlendi (${shortDateTr(lastWatch.watchedAt)})', tone: PillTone.ok),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                child: SizedBox(
                  width: 168,
                  height: 252,
                  child: PosterImage(poster, rating: Library.instance.ratingFor(widget.item)),
                ),
              ),
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
                      _watchlistButton(),
                      if (!_isSeries) _movieDownloadButton(),
                    ]),
                    const SizedBox(height: 18),
                    _desktopInlineLogCard(),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _seasonRow(Map<int, List<Episode>> seasons) {
    final currentEpisodes = seasons[_season] ?? const <Episode>[];
    return Padding(
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
        Text('${currentEpisodes.length} bölüm', style: AppText.meta(15)),
        const SizedBox(width: 12),
        AppButton(
          key: const ValueKey('detail-download-season'),
          dense: true,
          height: 38,
          variant: AppButtonVariant.onPage,
          icon: Icons.download_rounded,
          label: 'Sezonu indir',
          onPressed: currentEpisodes.isEmpty ? null : () => _handleSeasonDownload(currentEpisodes),
        ),
      ]),
    );
  }

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
                Positioned(right: 8, top: 8, child: _episodeDownloadControl(e, size: 32)),
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

/// Interactive 5-star picker supporting half-star (0.5) steps via tap, horizontal drag, and D-pad / keyboard arrows.
class HalfStarRatingPicker extends StatefulWidget {
  const HalfStarRatingPicker({
    super.key,
    required this.rating,
    required this.onChanged,
    this.size = 28,
    this.gap = 4,
    this.allowClear = true,
  });

  final double? rating;
  final ValueChanged<double?> onChanged;
  final double size;
  final double gap;
  final bool allowClear;

  @override
  State<HalfStarRatingPicker> createState() => _HalfStarRatingPickerState();
}

class _HalfStarRatingPickerState extends State<HalfStarRatingPicker> {
  bool _focused = false;

  double _ratingAtDx(double dx, double totalWidth) {
    final slotWidth = widget.size + widget.gap;
    final starIdx = (dx / slotWidth).floor().clamp(0, 4);
    final localX = (dx - starIdx * slotWidth).clamp(0.0, widget.size);
    final half = localX < widget.size / 2 ? 0.5 : 1.0;
    return (starIdx + half).clamp(MediaLogEntry.minRating, MediaLogEntry.maxRating);
  }

  void _handleTap(double dx, double totalWidth) {
    final picked = _ratingAtDx(dx, totalWidth);
    if (widget.allowClear && widget.rating == picked) {
      widget.onChanged(null);
    } else {
      widget.onChanged(picked);
    }
  }

  void _handleDrag(double dx, double totalWidth) {
    final picked = _ratingAtDx(dx, totalWidth);
    if (widget.rating != picked) {
      widget.onChanged(picked);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final cur = widget.rating ?? 0.0;
    if (k == LogicalKeyboardKey.arrowRight) {
      final next = (cur + 0.5).clamp(MediaLogEntry.minRating, MediaLogEntry.maxRating);
      widget.onChanged(next);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      final next = cur - 0.5;
      if (next < MediaLogEntry.minRating) {
        if (widget.allowClear && widget.rating != null) widget.onChanged(null);
      } else {
        widget.onChanged(next);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      if (widget.allowClear && widget.rating != null) {
        widget.onChanged(null);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.size * 5 + widget.gap * 4;
    final current = widget.rating ?? 0.0;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _handleKey,
      child: Semantics(
        label: 'Puan seçici',
        value: widget.rating == null ? 'Puanlanmadı' : '${MediaLogEntry.formatRating(widget.rating!)} yıldız',
        slider: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _handleTap(d.localPosition.dx, totalWidth),
          onHorizontalDragUpdate: (d) => _handleDrag(d.localPosition.dx, totalWidth),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: _focused
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.ink, width: 2),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 5; i++) ...[
                  if (i > 1) SizedBox(width: widget.gap),
                  _StarGlyph(
                    key: ValueKey('star-slot-$i'),
                    size: widget.size,
                    fill: current >= i ? 1.0 : (current >= i - 0.5 ? 0.5 : 0.0),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StarGlyph extends StatelessWidget {
  const _StarGlyph({super.key, required this.size, required this.fill});

  final double size;
  final double fill; // 0.0, 0.5, or 1.0

  @override
  Widget build(BuildContext context) {
    if (fill >= 1.0) {
      return Icon(Icons.star_rounded, size: size, color: AppColors.star);
    }
    if (fill <= 0.0) {
      return Icon(Icons.star_rounded, size: size, color: AppColors.dashed);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Icon(Icons.star_rounded, size: size, color: AppColors.dashed),
          ClipRect(
            clipper: const _LeftHalfClipper(),
            child: Icon(Icons.star_rounded, size: size, color: AppColors.star),
          ),
        ],
      ),
    );
  }
}

class _LeftHalfClipper extends CustomClipper<Rect> {
  const _LeftHalfClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width / 2, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class _PhoneRatingSheetBody extends StatefulWidget {
  const _PhoneRatingSheetBody({required this.item});

  final Item item;

  @override
  State<_PhoneRatingSheetBody> createState() => _PhoneRatingSheetBodyState();
}

class _PhoneRatingSheetBodyState extends State<_PhoneRatingSheetBody> {
  late final TextEditingController _reviewCtrl;
  double? _rating;
  bool _watched = false;
  bool _liked = false;
  bool _rewatch = false;

  @override
  void initState() {
    super.initState();
    final log = Library.instance.logFor(widget.item);
    _rating = log?.rating;
    _watched = log?.watched ?? false;
    _liked = (log?.liked ?? false) || Library.instance.isFavorite(widget.item);
    _rewatch = false;
    _reviewCtrl = TextEditingController(text: log?.review ?? '');
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final existing = Library.instance.logFor(widget.item);
    final hasExisting = existing != null;
    final effectiveWatched = _watched || _rating != null || _rewatch || _reviewCtrl.text.trim().isNotEmpty;
    await Library.instance.saveLog(
      widget.item,
      rating: _rating,
      clearRating: _rating == null && hasExisting,
      liked: _liked,
      review: _reviewCtrl.text,
      watched: effectiveWatched,
      addRewatch: _rewatch,
    );
    if (_liked != Library.instance.isFavorite(widget.item)) {
      await Library.instance.toggleFavorite(widget.item);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _togglePill({
    required Key key,
    required String label,
    required bool active,
    required Color activeBg,
    required Color activeFg,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.selection(context);
          onTap();
        },
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? activeBg : AppColors.ground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? activeFg : AppColors.line, width: 1),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label(12.5, color: active ? activeFg : AppColors.ink2),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mood = MediaLogEntry.moodFor(_rating);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                HalfStarRatingPicker(
                  key: const ValueKey('sheet-star-picker'),
                  rating: _rating,
                  size: 27,
                  gap: 3,
                  onChanged: (next) {
                    AppHaptics.selection(context);
                    setState(() {
                      _rating = next;
                      if (next != null) _watched = true;
                    });
                  },
                ),
                const Spacer(),
                if (mood != null) ...[
                  Flexible(child: Pill(mood, tone: PillTone.warn, height: 24)),
                  const SizedBox(width: 6),
                ],
                Text(
                  _rating == null ? '—' : MediaLogEntry.formatRating(_rating!),
                  key: const ValueKey('sheet-rating-value'),
                  style: AppText.title(21, color: _rating == null ? AppColors.ink2 : AppColors.star),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _togglePill(
                key: const ValueKey('sheet-toggle-watched'),
                label: '✓ İzlendi',
                active: _watched,
                activeBg: AppColors.okSoft,
                activeFg: AppColors.ok,
                onTap: () => setState(() => _watched = !_watched),
              ),
              const SizedBox(width: 8),
              _togglePill(
                key: const ValueKey('sheet-toggle-liked'),
                label: '♥ Beğendim',
                active: _liked,
                activeBg: AppColors.liveSoft,
                activeFg: AppColors.live,
                onTap: () => setState(() => _liked = !_liked),
              ),
              const SizedBox(width: 8),
              _togglePill(
                key: const ValueKey('sheet-toggle-rewatch'),
                label: '↻ Tekrar',
                active: _rewatch,
                activeBg: AppColors.accentSoft,
                activeFg: AppColors.accentInk,
                onTap: () => setState(() {
                  _rewatch = !_rewatch;
                  if (_rewatch) _watched = true;
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.ground,
              borderRadius: BorderRadius.circular(AppSizes.smallRadius),
              border: Border.all(color: AppColors.line),
            ),
            child: TextField(
              key: const ValueKey('sheet-review-input'),
              controller: _reviewCtrl,
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.done,
              style: AppText.body(size: 13.5, color: AppColors.ink),
              decoration: InputDecoration(
                hintText: 'Kısa notun veya yorumun...',
                hintStyle: AppText.meta(13),
                isCollapsed: true,
              ),
            ),
          ),
          const SizedBox(height: 14),
          AppButton(
            key: const ValueKey('sheet-save-button'),
            variant: AppButtonVariant.primary,
            height: 44,
            width: double.infinity,
            label: 'Kaydet',
            onPressed: () {
              AppHaptics.light(context);
              _save();
            },
          ),
        ],
      ),
    );
  }
}

