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

/// Favorites and watch history of the signed-in account ([use]).
class Library extends ChangeNotifier {
  Library._();
  static final Library instance = Library._();

  static const _maxHistory = 60;

  final Map<String, Item> _favorites = {};
  final List<HistoryEntry> _history = []; // newest first

  List<Item> get favorites => _favorites.values.toList();
  bool isFavorite(Item i) => _favorites.containsKey(i.id);

  List<HistoryEntry> get history => List.unmodifiable(_history);
  List<HistoryEntry> get continueWatching => _history.where((e) => e.resumable).toList();

  HistoryEntry? _find(String url) {
    for (final e in _history) {
      if (e.url == url) return e;
    }
    return null;
  }

  static const _favoritesKey = 'favorites';
  static const _historyKey = 'history';

  Account? _account; // nothing is stored until an account is in use

  /// Switches to the favorites and history of [account]. Each account has its own lists, and stream URLs are
  /// stored without host and credentials ([Account.portableUrl]), so no password ends up in plain preferences.
  Future<void> use(Account account) async {
    _account = account;
    _favorites.clear();
    _history.clear();
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
    if (_account != account) return; // another account was selected meanwhile
    for (final j in favorites) {
      try {
        final it = Item.fromJson(playable(j));
        _favorites.putIfAbsent(it.id, () => it);
      } catch (_) {
        // corrupt entry: skip it
      }
    }
    for (final j in history) {
      try {
        final e = HistoryEntry.fromJson(playable(j));
        if (_find(e.url) == null && _history.length < _maxHistory) _history.add(e);
      } catch (_) {
        // corrupt entry: skip it
      }
    }
    notifyListeners();
    if (migrated) await Future.wait([_persistFavorites(), _persist()]);
  }

  String _scoped(String key) => '$key:${_account!.key}';

  Future<void> toggleFavorite(Item i) async {
    if (_favorites.remove(i.id) == null) _favorites[i.id] = i;
    notifyListeners();
    await _persistFavorites();
  }

  Future<void> _persistFavorites() async {
    final a = _account;
    if (a == null) return;
    final json = jsonEncode([for (final f in _favorites.values) {...f.toJson(), 'url': f.url == null ? null : a.portableUrl(f.url!)}]);
    await (await SharedPreferences.getInstance()).setString(_scoped(_favoritesKey), json);
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
    notifyListeners();
    await _persist();
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
