import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'title_utils.dart';
import 'xtream.dart';

/// Saved audio or subtitle track choice for a watched item.
class TrackPref {
  const TrackPref({required this.id, this.language, this.title});

  final String id;
  final String? language;
  final String? title;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (language != null && language!.isNotEmpty) 'lang': language,
        if (title != null && title!.isNotEmpty) 'title': title,
      };

  static TrackPref? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final lang = raw['lang'];
    final title = raw['title'];
    return TrackPref(
      id: id,
      language: lang is String ? lang : null,
      title: title is String ? title : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TrackPref && other.id == id && other.language == language && other.title == title;

  @override
  int get hashCode => Object.hash(id, language, title);
}

/// One watched item (a live channel, a movie or a single episode).
class HistoryEntry {
  HistoryEntry({
    required this.url,
    required this.title,
    required this.logo,
    required this.kind,
    this.item,
    this.positionMs = 0,
    this.durationMs = 0,
    required this.updatedMs,
    this.audioTrack,
    this.subtitleTrack,
  });

  final String url;
  final String title;
  final String logo;
  final Kind kind;

  /// Backing catalog item (movie or parent series) so detail navigation works without re-querying.
  Item? item;
  int positionMs;
  int durationMs;
  int updatedMs;
  TrackPref? audioTrack;
  TrackPref? subtitleTrack;

  bool get resumable => kind != Kind.live && positionMs >= 20000 && (durationMs == 0 || durationMs - positionMs >= 60000);
  double get progress => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'logo': logo,
        'kind': kind.name,
        if (item != null) 'item': item!.toJson(),
        'pos': positionMs,
        'dur': durationMs,
        'at': updatedMs,
        if (audioTrack != null) 'audio': audioTrack!.toJson(),
        if (subtitleTrack != null) 'sub': subtitleTrack!.toJson(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) {
    Item? item;
    final rawItem = j['item'];
    if (rawItem is Map<String, dynamic>) {
      try {
        item = Item.fromJson(rawItem);
      } catch (_) {}
    }
    return HistoryEntry(
      url: j['url'] as String,
      title: j['title'] as String,
      logo: (j['logo'] ?? '') as String,
      kind: Kind.values.byName(j['kind'] as String),
      item: item,
      positionMs: (j['pos'] ?? 0) as int,
      durationMs: (j['dur'] ?? 0) as int,
      updatedMs: (j['at'] ?? 0) as int,
      audioTrack: TrackPref.fromJson(j['audio']),
      subtitleTrack: TrackPref.fromJson(j['sub']),
    );
  }
}

/// One viewing of a movie or series, as logged in the personal diary.
class WatchRecord {
  const WatchRecord({required this.watchedAtMs, this.rewatch = false});

  /// When the viewing happened (epoch milliseconds).
  final int watchedAtMs;

  /// True when the user had already seen the title before this viewing.
  final bool rewatch;

  DateTime get watchedAt => DateTime.fromMillisecondsSinceEpoch(watchedAtMs);

  Map<String, dynamic> toJson() => {'at': watchedAtMs, if (rewatch) 're': true};

  static WatchRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    if (at is! int || at <= 0) return null;
    return WatchRecord(watchedAtMs: at, rewatch: raw['re'] == true);
  }

  @override
  bool operator ==(Object other) => other is WatchRecord && other.watchedAtMs == watchedAtMs && other.rewatch == rewatch;

  @override
  int get hashCode => Object.hash(watchedAtMs, rewatch);
}

/// Personal diary entry for one movie or series ([Item.id]): rating, like, watchlist, review and viewings.
///
/// Entries are merged across devices last-writer-wins on [updatedAtMs]; a removed entry stays as a tombstone
/// ([deletedAtMs]) so the removal also reaches the other devices.
class MediaLogEntry {
  MediaLogEntry({
    required this.item,
    this.rating,
    this.liked = false,
    this.watchlist = false,
    this.watchlistAddedAtMs,
    this.review = '',
    List<WatchRecord>? watches,
    required this.updatedAtMs,
    this.deletedAtMs,
  }) : watches = watches ?? [];

  static const minRating = 0.5;
  static const maxRating = 5.0;

  /// Turkish one-word verdict for each half-star step (0.5 → index 0, 5.0 → index 9).
  static const moods = <String>[
    'Zaman kaybı',
    'Kötü',
    'Zayıf',
    'Vasat',
    'İdare eder',
    'İyi',
    'Çok iyi',
    'Harika',
    'Başyapıt',
    'Efsane',
  ];

  /// Snaps [value] to the nearest half star within 0.5–5.0; null, NaN and anything below 0.25 mean "not rated".
  static double? normalizeRating(num? value) {
    if (value == null || value.isNaN || value < 0.25) return null;
    final snapped = (value * 2).round() / 2;
    return snapped.clamp(minRating, maxRating).toDouble();
  }

  /// "4.5", "3.0".
  static String formatRating(double rating) => rating.toStringAsFixed(1);

  static String? moodFor(double? rating) {
    final r = normalizeRating(rating);
    return r == null ? null : moods[(r * 2).round() - 1];
  }

  Item item;
  String get id => item.id;

  /// 0.5–5.0 in half-star steps, or null when not rated.
  double? rating;
  bool liked;
  bool watchlist;
  int? watchlistAddedAtMs;
  String review;

  /// Viewings, oldest first.
  final List<WatchRecord> watches;
  int updatedAtMs;
  int? deletedAtMs;

  bool get isDeleted => deletedAtMs != null;
  bool get watched => watches.isNotEmpty;
  WatchRecord? get lastWatch => watches.isEmpty ? null : watches.last;
  int get rewatchCount => watches.where((w) => w.rewatch).length;

  /// Newest change of any kind (edit or removal), used for last-writer-wins merging.
  int get changedAtMs => deletedAtMs != null && deletedAtMs! > updatedAtMs ? deletedAtMs! : updatedAtMs;

  /// Nothing left worth keeping: the entry can become a tombstone.
  bool get isBlank => rating == null && !liked && !watchlist && review.trim().isEmpty && watches.isEmpty;

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        if (rating != null) 'rating': rating,
        if (liked) 'liked': true,
        if (watchlist) 'watchlist': true,
        if (watchlistAddedAtMs != null) 'wlAt': watchlistAddedAtMs,
        if (review.isNotEmpty) 'review': review,
        if (watches.isNotEmpty) 'watches': [for (final w in watches) w.toJson()],
        'updatedAtMs': updatedAtMs,
        if (deletedAtMs != null) 'deletedAtMs': deletedAtMs,
      };

  static MediaLogEntry? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final rawItem = raw['item'];
    if (rawItem is! Map<String, dynamic>) return null;
    final Item item;
    try {
      item = Item.fromJson(rawItem);
    } catch (_) {
      return null;
    }
    final rawRating = raw['rating'];
    final rawWatches = raw['watches'];
    final updated = raw['updatedAtMs'];
    final deleted = raw['deletedAtMs'];
    final wlAt = raw['wlAt'];
    final review = raw['review'];
    final watches = <WatchRecord>[
      if (rawWatches is List)
        for (final w in rawWatches) ?WatchRecord.fromJson(w),
    ]..sort((a, b) => a.watchedAtMs.compareTo(b.watchedAtMs));
    return MediaLogEntry(
      item: item,
      rating: normalizeRating(rawRating is num ? rawRating : null),
      liked: raw['liked'] == true,
      watchlist: raw['watchlist'] == true,
      watchlistAddedAtMs: wlAt is int ? wlAt : null,
      review: review is String ? review : '',
      watches: watches,
      updatedAtMs: updated is int ? updated : 0,
      deletedAtMs: deleted is int ? deleted : null,
    );
  }
}

/// Summary returned after merging remote library data during LAN sync.
class LibraryMergeStats {
  const LibraryMergeStats({
    required this.totalFavorites,
    required this.totalHistory,
    required this.favoritesChanged,
    required this.historyChanged,
    this.totalLogs = 0,
    this.logsChanged = 0,
  });

  final int totalFavorites;
  final int totalHistory;
  final int favoritesChanged;
  final int historyChanged;
  final int totalLogs;
  final int logsChanged;
}

/// Favorites and watch history of the signed-in account ([use]).
class Library extends ChangeNotifier {
  Library._();
  static final Library instance = Library._();

  static const _maxHistory = 60;

  final Map<String, Item> _favorites = {};
  final Map<String, int> _favoriteAddedAt = {};
  final Map<String, int> _favoriteRemovedAt = {};
  final List<HistoryEntry> _history = []; // newest first
  final Map<String, MediaLogEntry> _log = {}; // by Item.id, tombstones included

  List<Item> get favorites => _favorites.values.toList();
  bool isFavorite(Item i) => _favorites.containsKey(i.id);

  /// Live diary entries, most recently changed first.
  List<MediaLogEntry> get mediaLog =>
      [for (final e in _log.values) if (!e.isDeleted) e]..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));

  /// "Sonra İzle" list, most recently added first.
  List<MediaLogEntry> get watchlist => [for (final e in _log.values) if (!e.isDeleted && e.watchlist) e]
    ..sort((a, b) => (b.watchlistAddedAtMs ?? b.updatedAtMs).compareTo(a.watchlistAddedAtMs ?? a.updatedAtMs));

  /// Live diary entry for [itemId], or null.
  MediaLogEntry? logForId(String itemId) {
    final e = _log[itemId];
    return e == null || e.isDeleted ? null : e;
  }

  MediaLogEntry? logFor(Item i) => logForId(i.id);
  double? ratingForId(String itemId) => logForId(itemId)?.rating;
  double? ratingFor(Item i) => ratingForId(i.id);
  bool isInWatchlist(Item i) => logFor(i)?.watchlist ?? false;

  List<HistoryEntry> get history => List.unmodifiable(_history);
  List<HistoryEntry> get continueWatching => _history.where((e) => e.resumable).toList();

  HistoryEntry? _find(String url) {
    for (final e in _history) {
      if (e.url == url) return e;
    }
    return null;
  }

  static const _favoritesKey = 'favorites';
  static const _favoritesMetaKey = 'favoritesMeta';
  static const _historyKey = 'history';
  static const _logKey = 'mediaLog';

  Account? _account; // nothing is stored until an account is in use

  /// Switches to the favorites and history of [account]. Each account has its own lists, and stream URLs are
  /// stored without host and credentials ([Account.portableUrl]), so no password ends up in plain preferences.
  Future<void> use(Account account) async {
    _account = account;
    _favorites.clear();
    _favoriteAddedAt.clear();
    _favoriteRemovedAt.clear();
    _history.clear();
    _log.clear();
    final p = await SharedPreferences.getInstance();

    List<Map<String, dynamic>> read(String key) {
      try {
        final raw = p.getString(key);
        return raw == null ? [] : [for (final j in jsonDecode(raw) as List) j as Map<String, dynamic>];
      } catch (_) {
        return []; // corrupt data: start fresh
      }
    }

    // Older versions kept one list for all accounts, with full URLs. Take over the entries of this account
    // (those without a URL, i.e. series, go to the first account that signs in) and leave the rest.
    var migrated = false;
    Future<List<Map<String, dynamic>>> claim(String key) async {
      final old = read(key);
      bool mine(Map<String, dynamic> j) => j['url'] is! String || account.portableUrl(j['url'] as String) != j['url'];
      final rest = [for (final j in old) if (!mine(j)) j];
      if (rest.length == old.length) return [];
      migrated = true;
      rest.isEmpty ? await p.remove(key) : await p.setString(key, jsonEncode(rest));
      return [for (final j in old) if (mine(j)) j];
    }

    Map<String, dynamic> playable(Map<String, dynamic> j) {
      final url = j['url'];
      final rawItem = j['item'];
      return {
        ...j,
        if (url is String) 'url': account.fullUrl(account.portableUrl(url)),
        if (rawItem is Map<String, dynamic>)
          'item': {
            ...rawItem,
            if (rawItem['url'] is String) 'url': account.fullUrl(account.portableUrl(rawItem['url'] as String)),
          },
      };
    }

    final favorites = [...read(_scoped(_favoritesKey)), ...await claim(_favoritesKey)];
    final history = [...read(_scoped(_historyKey)), ...await claim(_historyKey)];
    final rawMeta = p.getString(_scoped(_favoritesMetaKey));
    final rawLog = read(_scoped(_logKey));
    if (_account != account) return; // another account was selected meanwhile
    for (final j in favorites) {
      try {
        final it = Item.fromJson(playable(j));
        _favorites.putIfAbsent(it.id, () => it);
      } catch (_) {
        // corrupt entry: skip it
      }
    }
    if (rawMeta != null) {
      try {
        final meta = jsonDecode(rawMeta);
        if (meta is Map<String, dynamic>) {
          final added = meta['added'];
          if (added is Map) {
            added.forEach((k, v) {
              if (k is String && v is int && _favorites.containsKey(k)) _favoriteAddedAt[k] = v;
            });
          }
          final removed = meta['removed'];
          if (removed is Map) {
            removed.forEach((k, v) {
              if (k is String && v is int && !_favorites.containsKey(k)) _favoriteRemovedAt[k] = v;
            });
          }
        }
      } catch (_) {}
    }
    for (final j in history) {
      try {
        final e = HistoryEntry.fromJson(playable(j));
        if (_find(e.url) == null && _history.length < _maxHistory) _history.add(e);
      } catch (_) {
        // corrupt entry: skip it
      }
    }
    for (final j in rawLog) {
      final e = MediaLogEntry.fromJson({...j, if (j['item'] is Map<String, dynamic>) 'item': playable(j['item'] as Map<String, dynamic>)});
      if (e != null) _log[e.id] = e;
    }
    notifyListeners();
    if (migrated) await Future.wait([_persistFavorites(), _persist()]);
  }

  String _scoped(String key) => '$key:${_account!.key}';

  Future<void> toggleFavorite(Item i) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_favorites.remove(i.id) == null) {
      _favorites[i.id] = i;
      _favoriteAddedAt[i.id] = now;
      _favoriteRemovedAt.remove(i.id);
    } else {
      _favoriteAddedAt.remove(i.id);
      _favoriteRemovedAt[i.id] = now;
    }
    notifyListeners();
    await _persistFavorites();
  }

  Future<void> _persistFavorites() async {
    final a = _account;
    if (a == null) return;
    final p = await SharedPreferences.getInstance();
    final json = jsonEncode([for (final f in _favorites.values) {...f.toJson(), 'url': f.url == null ? null : a.portableUrl(f.url!)}]);
    await p.setString(_scoped(_favoritesKey), json);
    await p.setString(
      _scoped(_favoritesMetaKey),
      jsonEncode({'added': _favoriteAddedAt, 'removed': _favoriteRemovedAt}),
    );
  }

  /// Change time for [prev]: now, but always after its last change so last-writer-wins stays ordered.
  int _stamp(MediaLogEntry? prev) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return prev == null || now > prev.changedAtMs ? now : prev.changedAtMs + 1;
  }

  /// Creates or updates the diary entry of [item]; only the given fields change.
  ///
  /// * [rating] is snapped to half stars (0.5–5.0); [clearRating] removes it.
  /// * [watched] `true` logs a first viewing when there is none, `false` drops all viewings.
  /// * [addRewatch] logs one more viewing marked as a rewatch.
  /// * Rating a title that has no viewing yet logs one (rating means "I watched it"), and the first viewing
  ///   takes the title off the watchlist.
  ///
  /// An entry left with nothing in it becomes a tombstone. Returns the live entry, or null.
  Future<MediaLogEntry?> saveLog(
    Item item, {
    double? rating,
    bool clearRating = false,
    bool? liked,
    String? review,
    bool? watched,
    bool addRewatch = false,
    DateTime? watchedAt,
  }) async {
    final prev = _log[item.id];
    final now = _stamp(prev);
    final at = watchedAt?.millisecondsSinceEpoch ?? now;
    final e = prev ?? MediaLogEntry(item: item, updatedAtMs: now);
    if (prev != null && prev.isDeleted) {
      e
        ..rating = null
        ..liked = false
        ..watchlist = false
        ..watchlistAddedAtMs = null
        ..review = ''
        ..watches.clear();
    }
    e.item = item;
    final hadWatch = e.watched;
    if (clearRating) {
      e.rating = null;
    } else if (rating != null) {
      e.rating = MediaLogEntry.normalizeRating(rating);
    }
    if (liked != null) e.liked = liked;
    if (review != null) e.review = review.trim();
    if (watched == false) {
      e.watches.clear();
    } else if ((watched == true || (rating != null && e.rating != null)) && e.watches.isEmpty) {
      e.watches.add(WatchRecord(watchedAtMs: at));
    }
    if (addRewatch) {
      e.watches
        ..add(WatchRecord(watchedAtMs: at, rewatch: true))
        ..sort((a, b) => a.watchedAtMs.compareTo(b.watchedAtMs));
    }
    if (!hadWatch && e.watched) {
      e.watchlist = false;
      e.watchlistAddedAtMs = null;
    }
    e.updatedAtMs = now;
    e.deletedAtMs = e.isBlank ? now : null;
    _log[item.id] = e;
    notifyListeners();
    await _persistLog();
    return e.isDeleted ? null : e;
  }

  /// Adds [item] to the "Sonra İzle" list, or takes it off.
  Future<void> toggleWatchlist(Item item) async {
    final prev = _log[item.id];
    final now = _stamp(prev);
    final live = prev != null && !prev.isDeleted;
    final e = live ? prev : MediaLogEntry(item: item, updatedAtMs: now);
    e.item = item;
    e.watchlist = !e.watchlist;
    e.watchlistAddedAtMs = e.watchlist ? now : null;
    e.updatedAtMs = now;
    e.deletedAtMs = e.isBlank ? now : null;
    _log[item.id] = e;
    notifyListeners();
    await _persistLog();
  }

  /// Removes the whole diary entry of [item] (kept as a tombstone for LAN sync).
  Future<void> removeLog(Item item) async {
    final prev = _log[item.id];
    if (prev == null || prev.isDeleted) return;
    final now = _stamp(prev);
    prev
      ..rating = null
      ..liked = false
      ..watchlist = false
      ..watchlistAddedAtMs = null
      ..review = ''
      ..watches.clear()
      ..updatedAtMs = now
      ..deletedAtMs = now;
    notifyListeners();
    await _persistLog();
  }

  Map<String, dynamic> _portableLogJson(MediaLogEntry e, Account a) => {
        ...e.toJson(),
        'item': {...e.item.toJson(), 'url': e.item.url == null ? null : a.portableUrl(e.item.url!)},
      };

  Future<void> _persistLog() async {
    final a = _account;
    if (a == null) return;
    final json = jsonEncode([for (final e in _log.values) _portableLogJson(e, a)]);
    await (await SharedPreferences.getInstance()).setString(_scoped(_logKey), json);
  }

  Duration? positionFor(String url) {
    final e = _find(url);
    return e == null || !e.resumable ? null : Duration(milliseconds: e.positionMs);
  }

  /// Backing catalog item stored for [url], if any.
  Item? itemFor(String url) => _find(url)?.item;

  /// Saved audio and subtitle track preferences for [url], falling back to the
  /// most recent episode of the same series ([item]) when [url] has none yet.
  ({TrackPref? audio, TrackPref? subtitle}) trackPreferencesFor(String url, {Item? item}) {
    final exact = _find(url);
    var audio = exact?.audioTrack;
    var subtitle = exact?.subtitleTrack;
    final seriesId = item?.kind == Kind.series ? item!.id : (exact?.item?.kind == Kind.series ? exact!.item!.id : null);
    if ((audio == null || subtitle == null) && seriesId != null) {
      for (final h in _history) {
        if (h.item?.id != seriesId) continue;
        audio ??= h.audioTrack;
        subtitle ??= h.subtitleTrack;
        if (audio != null && subtitle != null) break;
      }
    }
    return (audio: audio, subtitle: subtitle);
  }

  /// Persists the user's audio and/or subtitle track selection for [url].
  Future<void> saveTracks(String url, {TrackPref? audio, TrackPref? subtitle, Item? item}) async {
    final e = _find(url);
    if (e == null) return;
    var changed = false;
    if (audio != null && e.audioTrack != audio) {
      e.audioTrack = audio;
      changed = true;
    }
    if (subtitle != null && e.subtitleTrack != subtitle) {
      e.subtitleTrack = subtitle;
      changed = true;
    }
    if (item != null && e.item == null) {
      e.item = item;
      changed = true;
    }
    if (!changed) return;
    e.updatedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _persist();
  }

  /// Record that [url] was opened (moves it to the top of the history).
  Future<void> touch({required String url, required String title, required String logo, required Kind kind, Item? item}) async {
    final old = _find(url);
    _history.removeWhere((e) => e.url == url);
    _history.insert(
      0,
      HistoryEntry(
        url: url,
        title: title,
        logo: logo,
        kind: kind,
        item: item ?? old?.item,
        positionMs: old?.positionMs ?? 0,
        durationMs: old?.durationMs ?? 0,
        updatedMs: DateTime.now().millisecondsSinceEpoch,
        audioTrack: old?.audioTrack,
        subtitleTrack: old?.subtitleTrack,
      ),
    );
    if (_history.length > _maxHistory) _history.removeRange(_maxHistory, _history.length);
    notifyListeners();
    await _persist();
  }

  /// Associates a resolved catalog [item] with an existing history entry so future detail opens are instant.
  Future<void> attachItem(String url, Item item) async {
    final e = _find(url);
    if (e == null || e.item?.id == item.id) return;
    e.item = item;
    notifyListeners();
    await _persist();
  }

  Future<void> savePosition(String url, Duration position, Duration total) async {
    final e = _find(url);
    if (e == null || e.kind == Kind.live) return;
    // Nothing was loaded yet (the player was left while still opening): keep the position we have.
    if (position == Duration.zero && total == Duration.zero) return;
    final finished = total > Duration.zero && total - position < const Duration(seconds: 60);
    e.positionMs = finished ? 0 : position.inMilliseconds;
    e.durationMs = total.inMilliseconds;
    e.updatedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _persist();
  }

  /// Exports credential-free favorites (with LWW timestamps/tombstones) and watch history for LAN sync.
  Map<String, dynamic> exportSyncData(Account account) {
    Map<String, dynamic> portableItem(Item it) => {
          ...it.toJson(),
          'url': it.url == null ? null : account.portableUrl(it.url!),
        };
    return {
      'favorites': [
        for (final f in _favorites.values)
          {
            'item': portableItem(f),
            'at': _favoriteAddedAt[f.id] ?? 0,
          },
      ],
      'removedFavorites': Map<String, int>.from(_favoriteRemovedAt),
      'history': [
        for (final e in _history)
          {
            ...e.toJson(),
            'url': account.portableUrl(e.url),
            if (e.item != null) 'item': portableItem(e.item!),
          },
      ],
      'mediaLog': [for (final e in _log.values) _portableLogJson(e, account)],
    };
  }

  /// Merges remote credential-free favorites and watch history into the active account using LWW semantics.
  Future<LibraryMergeStats> mergeSyncData(Account account, Map<String, dynamic> remote) async {
    if (_account == null || _account!.key != account.key) {
      await use(account);
    }

    Map<String, dynamic> hydrateItemJson(Map<String, dynamic> raw) {
      final url = raw['url'];
      return {
        ...raw,
        if (url is String) 'url': account.fullUrl(account.portableUrl(url)),
      };
    }

    var favChanged = 0;
    final rawFavs = remote['favorites'];
    final remoteFavItems = <String, ({Item item, int at})>{};
    if (rawFavs is List) {
      for (final entry in rawFavs) {
        if (entry is! Map<String, dynamic>) continue;
        try {
          final itemRaw = entry['item'];
          final itemMap = itemRaw is Map<String, dynamic> ? itemRaw : entry;
          final item = Item.fromJson(hydrateItemJson(itemMap));
          final at = entry['at'] is int ? entry['at'] as int : 0;
          remoteFavItems[item.id] = (item: item, at: at);
        } catch (_) {}
      }
    }

    final remoteRemoved = <String, int>{};
    final rawRemoved = remote['removedFavorites'];
    if (rawRemoved is Map) {
      rawRemoved.forEach((k, v) {
        if (k is String && v is int) remoteRemoved[k] = v;
      });
    }

    final allFavIds = <String>{
      ..._favorites.keys,
      ..._favoriteRemovedAt.keys,
      ...remoteFavItems.keys,
      ...remoteRemoved.keys,
    };

    for (final id in allFavIds) {
      final localItem = _favorites[id];
      final localAdd = localItem != null ? (_favoriteAddedAt[id] ?? 0) : -1;
      final localRem = _favoriteRemovedAt[id] ?? -1;

      final remEntry = remoteFavItems[id];
      final remoteAdd = remEntry != null ? remEntry.at : -1;
      final remoteRem = remoteRemoved[id] ?? -1;

      final bestAdd = localAdd >= remoteAdd ? localAdd : remoteAdd;
      final bestRem = localRem >= remoteRem ? localRem : remoteRem;

      if (bestRem > bestAdd) {
        // Most recent explicit action is a removal.
        if (_favorites.remove(id) != null) favChanged++;
        _favoriteAddedAt.remove(id);
        _favoriteRemovedAt[id] = bestRem;
      } else if (bestAdd >= 0) {
        final chosenItem = (remoteAdd > localAdd && remEntry != null)
            ? remEntry.item
            : (localItem ?? remEntry?.item);
        if (chosenItem != null) {
          if (localItem == null) favChanged++;
          _favorites[id] = chosenItem;
          _favoriteAddedAt[id] = bestAdd;
          _favoriteRemovedAt.remove(id);
        }
      }
    }

    // Merge history keyed by portable URL; newer updatedMs wins while preserving metadata from either side.
    var histChanged = 0;
    final byPortable = <String, HistoryEntry>{
      for (final e in _history) account.portableUrl(e.url): e,
    };

    final rawHistory = remote['history'];
    if (rawHistory is List) {
      for (final raw in rawHistory) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          final rawUrl = raw['url'];
          if (rawUrl is! String || rawUrl.isEmpty) continue;
          final portable = account.portableUrl(rawUrl);
          final rawItem = raw['item'];
          final hydrated = <String, dynamic>{
            ...raw,
            'url': account.fullUrl(portable),
            if (rawItem is Map<String, dynamic>) 'item': hydrateItemJson(rawItem),
          };
          final incoming = HistoryEntry.fromJson(hydrated);
          final existing = byPortable[portable];
          if (existing == null) {
            byPortable[portable] = incoming;
            histChanged++;
          } else if (incoming.updatedMs > existing.updatedMs) {
            incoming.item ??= existing.item;
            incoming.audioTrack ??= existing.audioTrack;
            incoming.subtitleTrack ??= existing.subtitleTrack;
            if (incoming.durationMs <= 0 && existing.durationMs > 0) {
              incoming.durationMs = existing.durationMs;
            }
            byPortable[portable] = incoming;
            histChanged++;
          } else {
            // Keep existing timestamp/position, but backfill any missing metadata from incoming.
            var backfilled = false;
            if (existing.item == null && incoming.item != null) {
              existing.item = incoming.item;
              backfilled = true;
            }
            if (existing.audioTrack == null && incoming.audioTrack != null) {
              existing.audioTrack = incoming.audioTrack;
              backfilled = true;
            }
            if (existing.subtitleTrack == null && incoming.subtitleTrack != null) {
              existing.subtitleTrack = incoming.subtitleTrack;
              backfilled = true;
            }
            if (backfilled) histChanged++;
          }
        } catch (_) {}
      }
    }

    final mergedHistory = byPortable.values.toList()
      ..sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
    _history
      ..clear()
      ..addAll(mergedHistory.take(_maxHistory));

    // Diary entries: the newer change (edit or removal) wins as a whole.
    var logChanged = 0;
    final rawLog = remote['mediaLog'];
    if (rawLog is List) {
      for (final raw in rawLog) {
        if (raw is! Map<String, dynamic>) continue;
        final rawItem = raw['item'];
        if (rawItem is! Map<String, dynamic>) continue;
        final incoming = MediaLogEntry.fromJson({...raw, 'item': hydrateItemJson(rawItem)});
        if (incoming == null) continue;
        final existing = _log[incoming.id];
        if (existing == null || incoming.changedAtMs > existing.changedAtMs) {
          _log[incoming.id] = incoming;
          logChanged++;
        }
      }
    }

    notifyListeners();
    await Future.wait([_persistFavorites(), _persist(), _persistLog()]);

    return LibraryMergeStats(
      totalFavorites: _favorites.length,
      totalHistory: _history.length,
      favoritesChanged: favChanged,
      historyChanged: histChanged,
      totalLogs: _log.values.where((e) => !e.isDeleted).length,
      logsChanged: logChanged,
    );
  }

  Future<void> _persist() async {
    final a = _account;
    if (a == null) return;
    Map<String, dynamic> portableItem(Item it) => {
          ...it.toJson(),
          'url': it.url == null ? null : a.portableUrl(it.url!),
        };
    final json = jsonEncode([
      for (final e in _history)
        {
          ...e.toJson(),
          'url': a.portableUrl(e.url),
          if (e.item != null) 'item': portableItem(e.item!),
        },
    ]);
    await (await SharedPreferences.getInstance()).setString(_scoped(_historyKey), json);
  }
}

final _episodeSuffixPattern = RegExp(r'\s*S\d+\s*E\d+\s*$', caseSensitive: false);
final _urlStreamIdPattern = RegExp(r'/(\d+)(?:\.[^/?#]+)?(?:[?#].*)?$');

bool _isValidDetailItem(Kind kind, Item? item) {
  if (item == null || item.kind != kind) return false;
  if (kind == Kind.series) return item.seriesId != null;
  if (kind == Kind.movie) return item.streamId != null && item.url != null;
  return false;
}

/// Resolves the catalog [Item] needed to open `DetailPage` for a movie or series playback entry.
///
/// Entries saved with an attached [item] return immediately. Legacy history entries without one
/// reconstruct movies from their Xtream stream ID (preferring favorites/cache when available) and
/// match series by title against history, favorites, [cachedItems], or [loadCatalog], backfilling
/// the history record so subsequent taps need no lookup.
Future<Item?> resolveDetailItem({
  required Kind kind,
  required String url,
  required String title,
  String logo = '',
  Item? item,
  List<Item>? cachedItems,
  Future<List<Item>> Function()? loadCatalog,
}) async {
  if (kind == Kind.live) return null;
  if (_isValidDetailItem(kind, item)) return item;

  final stored = Library.instance.itemFor(url);
  if (_isValidDetailItem(kind, stored)) return stored;

  if (kind == Kind.movie) {
    final match = _urlStreamIdPattern.firstMatch(url);
    final streamId = match == null ? null : int.tryParse(match.group(1)!);

    Item? pickMovie(Iterable<Item> candidates) {
      for (final c in candidates) {
        if (!_isValidDetailItem(Kind.movie, c)) continue;
        if (c.url == url || (streamId != null && c.streamId == streamId)) return c;
      }
      return null;
    }

    final found = pickMovie(Library.instance.favorites) ?? (cachedItems == null ? null : pickMovie(cachedItems));
    if (found != null) {
      await Library.instance.attachItem(url, found);
      return found;
    }
    if (streamId != null) {
      final built = Item(id: 'm$streamId', name: title, logo: logo, group: '', kind: Kind.movie, url: url);
      await Library.instance.attachItem(url, built);
      return built;
    }
    if (loadCatalog != null) {
      try {
        final loaded = await loadCatalog();
        final fromCatalog = pickMovie(loaded);
        if (fromCatalog != null) {
          await Library.instance.attachItem(url, fromCatalog);
          return fromCatalog;
        }
      } catch (_) {}
    }
    return null;
  }

  // Kind.series
  final rawSeriesName = title.replaceAll(_episodeSuffixPattern, '').trim();
  final foldedRaw = foldTr(rawSeriesName);
  final foldedClean = foldTr(parseTitle(rawSeriesName).title.trim());

  Item? pickSeries(Iterable<Item> candidates) {
    Item? foldedMatch;
    Item? parsedMatch;
    for (final c in candidates) {
      if (!_isValidDetailItem(Kind.series, c)) continue;
      if (c.name == rawSeriesName) return c;
      if (foldedMatch == null && foldTr(c.name.trim()) == foldedRaw) {
        foldedMatch = c;
      }
      if (foldTr(parsedTitleOf(c).title.trim()) == foldedClean) {
        if (parsedMatch == null || (logo.isNotEmpty && c.logo == logo)) {
          parsedMatch = c;
        }
      }
    }
    return foldedMatch ?? parsedMatch;
  }

  final fromHistory = pickSeries(Library.instance.history.map((h) => h.item).whereType<Item>());
  if (fromHistory != null) {
    await Library.instance.attachItem(url, fromHistory);
    return fromHistory;
  }
  final fromFavs = pickSeries(Library.instance.favorites);
  if (fromFavs != null) {
    await Library.instance.attachItem(url, fromFavs);
    return fromFavs;
  }
  if (cachedItems != null) {
    final fromCache = pickSeries(cachedItems);
    if (fromCache != null) {
      await Library.instance.attachItem(url, fromCache);
      return fromCache;
    }
  }
  if (loadCatalog != null) {
    try {
      final loaded = await loadCatalog();
      final fromCatalog = pickSeries(loaded);
      if (fromCatalog != null) {
        await Library.instance.attachItem(url, fromCatalog);
        return fromCatalog;
      }
    } catch (_) {}
  }
  return null;
}
