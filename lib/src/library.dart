import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xtream.dart';

/// One watched item (a live channel, a movie or a single episode).
class HistoryEntry {
  HistoryEntry({required this.url, required this.title, required this.logo, required this.kind, this.positionMs = 0, this.durationMs = 0, required this.updatedMs});

  final String url;
  final String title;
  final String logo;
  final Kind kind;
  int positionMs;
  int durationMs;
  int updatedMs;

  bool get resumable => kind != Kind.live && positionMs >= 20000 && (durationMs == 0 || durationMs - positionMs >= 60000);
  double get progress => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {'url': url, 'title': title, 'logo': logo, 'kind': kind.name, 'pos': positionMs, 'dur': durationMs, 'at': updatedMs};

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        url: j['url'] as String,
        title: j['title'] as String,
        logo: (j['logo'] ?? '') as String,
        kind: Kind.values.byName(j['kind'] as String),
        positionMs: (j['pos'] ?? 0) as int,
        durationMs: (j['dur'] ?? 0) as int,
        updatedMs: (j['at'] ?? 0) as int,
      );
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
      return url is String ? {...j, 'url': account.fullUrl(account.portableUrl(url))} : j;
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

  /// Record that [url] was opened (moves it to the top of the history).
  Future<void> touch({required String url, required String title, required String logo, required Kind kind}) async {
    final old = _find(url);
    _history.removeWhere((e) => e.url == url);
    _history.insert(0, HistoryEntry(url: url, title: title, logo: logo, kind: kind, positionMs: old?.positionMs ?? 0, durationMs: old?.durationMs ?? 0, updatedMs: DateTime.now().millisecondsSinceEpoch));
    if (_history.length > _maxHistory) _history.removeRange(_maxHistory, _history.length);
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
    final json = jsonEncode([for (final e in _history) {...e.toJson(), 'url': a.portableUrl(e.url)}]);
    await (await SharedPreferences.getInstance()).setString(_scoped(_historyKey), json);
  }
}
