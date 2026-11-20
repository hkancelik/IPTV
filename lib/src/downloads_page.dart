import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'downloads.dart';
import 'library.dart';
import 'mini_player.dart';
import 'player_page.dart';
import 'poster_card.dart';
import 'title_utils.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/focus_ring.dart';
import 'ui/format.dart';
import 'ui/layout.dart';
import 'ui/shell.dart';
import 'ui/tokens.dart';
import 'xtream.dart';

/// Displays active downloads and offline-ready movies & series episodes.
///
/// Works both embedded inside [HomePage] (`embedded: true`) and as a standalone
/// offline screen launched from [LoginPage] without a network connection.
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({
    super.key,
    this.account,
    this.client,
    this.embedded = true,
    this.query = '',
  });

  const DownloadsPage.offline({
    super.key,
    this.account,
  })  : client = null,
        embedded = false,
        query = '';

  final Account? account;
  final XtreamClient? client;
  final bool embedded;
  final String query;

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  String _localQuery = '';

  String get _effectiveQuery => widget.embedded ? widget.query : _localQuery;

  bool get _isIos => !kIsWeb && (Theme.of(context).platform == TargetPlatform.iOS || Platform.isIOS);
  bool get _isDesktop => !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  String _historyUrlFor(DownloadEntry e) {
    final acc = widget.account;
    return acc != null ? acc.fullUrl(e.portableUrl) : e.portableUrl;
  }

  PlayerEntry _playerEntryFor(DownloadEntry e) => PlayerEntry(
        url: _historyUrlFor(e),
        localPath: e.filePath,
        title: e.title,
        logo: e.logo,
        item: e.item,
      );

  void _playMovie(DownloadEntry e) {
    if (!e.fileExistsSync()) {
      _showMissingFileError(e);
      return;
    }
    Navigator.of(context).push(appRoute(
      context,
      (_) => PlayerPage(
        queue: [_playerEntryFor(e)],
        index: 0,
        kind: Kind.movie,
        client: widget.client,
      ),
    ));
  }

  void _playEpisodeGroup(List<DownloadEntry> episodes, int index) {
    final target = episodes[index];
    if (!target.fileExistsSync()) {
      _showMissingFileError(target);
      return;
    }
    Navigator.of(context).push(appRoute(
      context,
      (_) => PlayerPage(
        queue: [for (final ep in episodes) _playerEntryFor(ep)],
        index: index,
        kind: Kind.series,
        client: widget.client,
      ),
    ));
  }

  void _showMissingFileError(DownloadEntry e) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('İndirilen dosya diskte bulunamadı; silinmiş veya taşınmış olabilir.')),
    );
    DownloadManager.instance.load();
  }

  Future<void> _confirmDelete(DownloadEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İndirilen silinsin mi?'),
        content: Text('"${e.title}" cihazdan kalıcı olarak silinecek (${formatBytes(e.effectiveBytes)}).'),
        actions: [
          AppButton(label: 'İptal', autofocus: true, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'Sil', variant: AppButtonVariant.danger, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true) {
      await DownloadManager.instance.delete(e.id);
    }
  }

  Future<void> _confirmDeleteAll() async {
    final mgr = DownloadManager.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm indirilenler silinsin mi?'),
        content: Text('${mgr.entries.length} öğe ve tüm video dosyaları (${formatBytes(mgr.totalStorageBytes)}) cihazdan silinecek.'),
        actions: [
          AppButton(label: 'İptal', autofocus: true, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'Tümünü sil', variant: AppButtonVariant.danger, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true) {
      await mgr.deleteAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = ListenableBuilder(
      listenable: Listenable.merge([DownloadManager.instance, Library.instance]),
      builder: (context, _) => _buildBody(context),
    );

    if (widget.embedded) return body;

    final mode = layoutModeOf(context);
    final pad = MediaQuery.paddingOf(context);
    if (mode != AppLayoutMode.desktop) {
      final landscape = mode == AppLayoutMode.phoneLandscape;
      return Scaffold(
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PhoneTopBar(
                  title: 'İndirilenler',
                  subtitle: 'Çevrimdışı izleme',
                  landscape: landscape,
                  actions: [
                    PhoneIconButton(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Geri',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(landscape ? (pad.left > 0 ? pad.left : 14) : 16, 0, 16, 10),
                  child: SearchField(
                    hint: 'İndirilenlerde ara',
                    onChanged: (v) => setState(() => _localQuery = v),
                  ),
                ),
                Expanded(child: body),
              ],
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

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 0),
            child: Row(
              children: [
                AppButton(
                  variant: AppButtonVariant.onPage,
                  icon: Icons.chevron_left_rounded,
                  label: 'Geri',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: PageHeader(
                    title: 'İndirilenler',
                    subtitle: 'Çevrimdışı izleme',
                    actions: [
                      SearchField(hint: 'İndirilenlerde ara', width: 240, onChanged: (v) => setState(() => _localQuery = v)),
                      const ClockPill(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final mgr = DownloadManager.instance;
    final mode = layoutModeOf(context);
    final phonePortrait = mode == AppLayoutMode.phonePortrait;
    final phoneLandscape = mode == AppLayoutMode.phoneLandscape;
    final pad = MediaQuery.paddingOf(context);
    final leftPad = phonePortrait ? 16.0 : (phoneLandscape ? (pad.left > 0 ? pad.left : 14.0) : AppSizes.scrollPad);
    final rightPad = phonePortrait ? 16.0 : (phoneLandscape ? 12.0 : 16.0);
    final bottomPad = phonePortrait
        ? (widget.embedded ? phoneBottomClearance(context) : pad.bottom + 24)
        : (phoneLandscape ? (pad.bottom > 0 ? pad.bottom + 14 : 20.0) : 24.0);

    final q = _effectiveQuery.trim();
    final match = queryMatcher(q);
    bool matchesEntry(DownloadEntry e) {
      if (q.isEmpty) return true;
      return match(foldTr('${e.title} ${e.seriesTitle} ${e.episodeTitle}'));
    }

    final active = mgr.activeEntries.where(matchesEntry).toList();
    final completed = mgr.completedEntries.where(matchesEntry).toList();
    final movies = completed.where((e) => e.kind == Kind.movie).toList();
    final seriesEntries = completed.where((e) => e.kind == Kind.series).toList();

    // Group downloaded episodes by series title, sorted by season & episode number.
    final seriesGroups = <String, List<DownloadEntry>>{};
    for (final ep in seriesEntries) {
      final key = ep.seriesTitle.isNotEmpty ? ep.seriesTitle : ep.title;
      seriesGroups.putIfAbsent(key, () => []).add(ep);
    }
    for (final list in seriesGroups.values) {
      list.sort((a, b) {
        final s = (a.season ?? 0).compareTo(b.season ?? 0);
        if (s != 0) return s;
        return (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
      });
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(leftPad, 4, rightPad, bottomPad),
      children: [
        _summaryCard(mgr, compact: phonePortrait),
        if (mgr.entries.isEmpty) ...[
          const SizedBox(height: 16),
          _emptyCard(),
        ] else if (active.isEmpty && movies.isEmpty && seriesGroups.isEmpty) ...[
          const SizedBox(height: 16),
          AppCard(
            radius: AppSizes.cardRadius,
            padding: const EdgeInsets.all(28),
            child: Text('Aramana uyan indirilen içerik bulunamadı.', textAlign: TextAlign.center, style: AppText.meta(15)),
          ),
        ] else ...[
          if (active.isNotEmpty) ...[
            _sectionHeader('Devam edenler', '${active.length} öğe'),
            for (var i = 0; i < active.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _activeTile(active[i], compact: phonePortrait),
            ],
          ],
          if (movies.isNotEmpty) ...[
            _sectionHeader('Filmler', '${movies.length} film'),
            for (var i = 0; i < movies.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _movieTile(movies[i], compact: phonePortrait),
            ],
          ],
          if (seriesGroups.isNotEmpty) ...[
            _sectionHeader('Diziler', '${seriesEntries.length} bölüm'),
            for (final group in seriesGroups.entries) ...[
              _seriesGroupCard(group.key, group.value, compact: phonePortrait),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ],
    );
  }

  Widget _summaryCard(DownloadManager mgr, {required bool compact}) {
    final locationHint = _isIos
        ? 'Konum: Dosyalar (Files) → iPhone\'umda → IPTV'
        : 'Klasör: ${mgr.baseDir}';
    final stats = [
      '${mgr.completedCount} hazır',
      if (mgr.activeCount > 0) '${mgr.activeCount} kuyrukta',
      formatBytes(mgr.totalStorageBytes),
    ].join(' · ');

    final actions = <Widget>[
      if (_isDesktop)
        AppButton(
          dense: true,
          height: 36,
          icon: Icons.folder_open_rounded,
          label: 'Klasörü aç',
          onPressed: () async {
            final ok = await mgr.openDownloadFolder();
            if (!ok && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Klasör açılamadı: ${mgr.baseDir}')),
              );
            }
          },
        ),
      if (mgr.hasAny)
        AppButton(
          dense: true,
          height: 36,
          variant: AppButtonVariant.danger,
          icon: Icons.delete_outline_rounded,
          label: 'Tümünü sil',
          onPressed: _confirmDeleteAll,
        ),
    ];

    return AppCard(
      radius: AppSizes.cardRadius,
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.download_for_offline_rounded, size: 22, color: AppColors.accentInk),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Çevrimdışı depolama', style: AppText.title(15.5)),
                          const SizedBox(height: 2),
                          Text(stats, style: AppText.meta(13, color: AppColors.accentInk)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(locationHint, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.meta(12.5)),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            )
          : Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(15)),
                  child: const Icon(Icons.download_for_offline_rounded, size: 24, color: AppColors.accentInk),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Çevrimdışı depolama · $stats', style: AppText.title(16)),
                      const SizedBox(height: 3),
                      Text(locationHint, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
                    ],
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
    );
  }

  Widget _emptyCard() => AppCard(
        radius: AppSizes.cardRadius,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download_for_offline_rounded, size: 42, color: AppColors.ink3),
            const SizedBox(height: 12),
            Text('Henüz indirilen film veya dizi yok', textAlign: TextAlign.center, style: AppText.title(17)),
            const SizedBox(height: 6),
            Text(
              'Bir filmin veya dizi bölümünün detay sayfasından İndir\'e dokunarak internet olmadan da izleyebilirsin.',
              textAlign: TextAlign.center,
              style: AppText.meta(14),
            ),
          ],
        ),
      );

  Widget _sectionHeader(String title, String trailing) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(
          children: [
            Expanded(child: Text(title, style: AppText.title(17))),
            Text(trailing, style: AppText.meta(13)),
          ],
        ),
      );

  Widget _activeTile(DownloadEntry e, {required bool compact}) {
    final mgr = DownloadManager.instance;
    final pct = (e.progress * 100).round();
    final speed = formatSpeed(e.speedBytesPerSec);
    final sizeText = e.totalBytes > 0
        ? '${formatBytes(e.downloadedBytes)} / ${formatBytes(e.totalBytes)}'
        : (e.downloadedBytes > 0 ? formatBytes(e.downloadedBytes) : '');

    final (statusLabel, pillTone) = switch (e.status) {
      DownloadStatus.downloading => (e.totalBytes > 0 ? '%$pct' : 'İndiriliyor', PillTone.accent),
      DownloadStatus.queued => ('Sırada', PillTone.neutral),
      DownloadStatus.paused => ('Duraklatıldı', PillTone.warn),
      DownloadStatus.failed => ('Hata', PillTone.live),
      DownloadStatus.completed => ('Hazır', PillTone.accent),
    };

    final metaParts = <String>[
      if (sizeText.isNotEmpty) sizeText,
      if (e.isDownloading && speed.isNotEmpty) speed,
    ];

    final canResume = widget.account != null || e.isActive;
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (e.isDownloading || e.isQueued)
          AppButton(
            dense: true,
            height: 36,
            icon: Icons.pause_rounded,
            tooltip: 'Duraklat',
            onPressed: () => mgr.pause(e.id),
          )
        else
          AppButton(
            dense: true,
            height: 36,
            variant: AppButtonVariant.primary,
            icon: e.isFailed ? Icons.refresh_rounded : Icons.play_arrow_rounded,
            tooltip: e.isFailed ? 'Tekrar dene' : 'Devam et',
            onPressed: canResume ? () => mgr.resume(e.id, account: widget.account) : null,
          ),
        const SizedBox(width: 6),
        AppButton(
          dense: true,
          height: 36,
          variant: AppButtonVariant.danger,
          icon: Icons.close_rounded,
          tooltip: 'İptal et',
          onPressed: () => mgr.cancel(e.id),
        ),
      ],
    );

    return AppCard(
      radius: AppSizes.tileRadius,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: compact ? 54 : 62,
              height: compact ? 76 : 86,
              child: PosterImage(e.logo, cacheWidth: 200),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(15)),
                    ),
                    const SizedBox(width: 8),
                    Pill(statusLabel, tone: pillTone, height: 22),
                  ],
                ),
                if (e.episodeTitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(e.episodeTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12.5)),
                ],
                const SizedBox(height: 8),
                if (e.isDownloading && e.totalBytes <= 0)
                  ClipRRect(borderRadius: BorderRadius.circular(3), child: const LinearProgressIndicator(minHeight: 5))
                else
                  ProgressBar(value: e.progress, height: 5),
                if (metaParts.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(metaParts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12)),
                ],
                if (e.error != null && e.error!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(e.error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.label(12, color: AppColors.liveText)),
                ],
                if (compact) ...[
                  const SizedBox(height: 8),
                  controls,
                ],
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 12),
            controls,
          ],
        ],
      ),
    );
  }

  Widget _movieTile(DownloadEntry e, {required bool compact}) {
    final histUrl = _historyUrlFor(e);
    final resume = Library.instance.positionFor(histUrl);
    HistoryEntry? h;
    for (final x in Library.instance.history) {
      if (x.url == histUrl || portableKeyOfUrl(x.url) == e.portableUrl) {
        h = x;
        break;
      }
    }
    final hasProgress = h != null && h.durationMs > 0 && h.positionMs > 0;
    final subParts = <String>[
      formatBytes(e.effectiveBytes),
      if (resume != null) 'Kaldığın yer ${clockTime(resume)}',
    ];

    return FocusRing(
      radius: AppSizes.tileRadius,
      lift: false,
      onTap: () {
        AppHaptics.light(context);
        _playMovie(e);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: compact ? 56 : 64,
                height: compact ? 82 : 92,
                child: PosterImage(e.logo, cacheWidth: 200),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.title(15.5)),
                  const SizedBox(height: 4),
                  Text(subParts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
                  if (hasProgress) ...[
                    const SizedBox(height: 8),
                    ProgressBar(value: h.progress, height: 4),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              dense: true,
              height: 36,
              variant: AppButtonVariant.primary,
              icon: Icons.play_arrow_rounded,
              label: compact ? null : (resume != null ? 'Devam et' : 'Oynat'),
              tooltip: 'Oynat',
              onPressed: () {
                AppHaptics.light(context);
                _playMovie(e);
              },
            ),
            const SizedBox(width: 6),
            AppButton(
              dense: true,
              height: 36,
              icon: Icons.delete_outline_rounded,
              tooltip: 'Sil',
              onPressed: () => _confirmDelete(e),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seriesGroupCard(String seriesTitle, List<DownloadEntry> episodes, {required bool compact}) {
    final totalBytes = episodes.fold<int>(0, (sum, e) => sum + e.effectiveBytes);
    final poster = episodes.first.item?.logo ?? episodes.first.logo;

    return AppCard(
      radius: AppSizes.cardRadius,
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 46, height: 66, child: PosterImage(poster, cacheWidth: 160)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(seriesTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(16)),
                    const SizedBox(height: 3),
                    Text('${episodes.length} bölüm · ${formatBytes(totalBytes)}', style: AppText.meta(13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < episodes.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _downloadedEpisodeRow(episodes, i, compact: compact),
          ],
        ],
      ),
    );
  }

  Widget _downloadedEpisodeRow(List<DownloadEntry> episodes, int index, {required bool compact}) {
    final e = episodes[index];
    final code = e.season != null && e.episodeNumber != null
        ? 'S${e.season!.toString().padLeft(2, '0')}E${e.episodeNumber!.toString().padLeft(2, '0')}'
        : '';
    final label = [if (code.isNotEmpty) code, if (e.episodeTitle.isNotEmpty) e.episodeTitle else e.title].join(' · ');
    final histUrl = _historyUrlFor(e);
    final resume = Library.instance.positionFor(histUrl);

    return FocusRing(
      radius: AppSizes.itemRadius,
      lift: false,
      onTap: () {
        AppHaptics.light(context);
        _playEpisodeGroup(episodes, index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppSizes.itemRadius),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, size: 19, color: AppColors.accentInk),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(14)),
                  Text(
                    [formatBytes(e.effectiveBytes), if (resume != null) 'Kaldığın yer ${clockTime(resume)}'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta(12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            AppButton(
              dense: true,
              height: 32,
              icon: Icons.delete_outline_rounded,
              tooltip: 'Bölümü sil',
              onPressed: () => _confirmDelete(e),
            ),
          ],
        ),
      ),
    );
  }
}
