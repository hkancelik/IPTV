import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

const _userAgent = 'VLC/3.0.20 LibVLC/3.0.20';

enum Kind { live, movie, series }

class Account {
  Account({required this.name, required this.host, required this.username, required this.password});

  final String name;
  final String host; // http://host:port, no trailing slash
  final String username;
  final String password;

  /// Identifies an account without the password.
  String get key => '$host|$username';

  Map<String, String> toJson() => {'name': name, 'host': host, 'username': username, 'password': password};

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        name: j['name'] as String,
        host: j['host'] as String,
        username: j['username'] as String,
        password: j['password'] as String,
      );

  /// A stream URL of this account without host and credentials ("movie/42.mkv"), so favorites and the watch
  /// history can be stored in plain preferences. URLs that are not this account's are returned unchanged.
  String portableUrl(String url) {
    if (!url.startsWith('$host/')) return url;
    final parts = url.substring(host.length + 1).split('/');
    // kind / username / password / file: the password is not compared, it may have changed since.
    if (parts.length < 4 || parts[1] != Uri.encodeComponent(username)) return url;
    return [parts[0], ...parts.skip(3)].join('/');
  }

  /// The playable URL of a [portableUrl] with the current host and credentials.
  String fullUrl(String portable) {
    final slash = portable.indexOf('/');
    if (portable.contains('://') || slash < 0) return portable;
    return _streamUrl(_authOf(this), portable.substring(0, slash), portable.substring(slash + 1));
  }

  static String normalizeHost(String input) {
    var h = input.trim().replaceAll(RegExp(r'/+$'), '');
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(h)) h = 'http://$h';
    return h;
  }
}

class AccountInfo {
  AccountInfo({required this.status, this.expiry, required this.maxConnections, this.activeConnections = 0});

  final String status;
  final DateTime? expiry;
  final int maxConnections;
  final int activeConnections;

  /// True when every allowed connection is in use (a new stream will be refused or will kick another device).
  bool get limitReached => maxConnections > 0 && activeConnections >= maxConnections;
}

class Item {
  Item({required this.id, required this.name, required this.logo, required this.group, required this.kind, this.url, this.seriesId, this.added = 0});

  final String id;
  final String name;
  final String logo;
  final String group;
  final Kind kind;
  final String? url; // null for a series (episodes are fetched on demand)
  final int? seriesId;
  final int added; // unix seconds, 0 when unknown

  /// Xtream stream id of a live channel / movie (ids are stored as "l123" / "m123").
  int? get streamId => int.tryParse(id.substring(1));

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'logo': logo, 'group': group, 'kind': kind.name, 'url': url, 'seriesId': seriesId, 'added': added};

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        name: j['name'] as String,
        logo: j['logo'] as String,
        group: j['group'] as String,
        kind: Kind.values.byName(j['kind'] as String),
        url: j['url'] as String?,
        seriesId: j['seriesId'] as int?,
        added: (j['added'] ?? 0) as int,
      );
}

class Episode {
  Episode({required this.season, required this.number, required this.title, required this.url, this.plot = '', this.duration = '', this.image = ''});

  final int season;
  final int number;
  final String title;
  final String url;
  final String plot;
  final String duration;
  final String image;
}

/// Metadata shown on the movie / series detail page.
class Details {
  Details({this.plot = '', this.rating = '', this.year = '', this.duration = '', this.genre = '', this.cast = '', this.director = '', this.backdrop = '', this.poster = ''});

  final String plot;
  final String rating;
  final String year;
  final String duration;
  final String genre;
  final String cast;
  final String director;
  final String backdrop;
  final String poster;
}

class SeriesData {
  SeriesData(this.details, this.episodes);

  final Details details;
  final List<Episode> episodes;
}

/// A programme from the short EPG.
class Programme {
  Programme({required this.title, required this.start, required this.end});

  final String title;
  final DateTime start;
  final DateTime end;

  bool get isNow {
    final n = DateTime.now();
    return !n.isBefore(start) && n.isBefore(end);
  }

  double get progress {
    final total = end.difference(start).inSeconds;
    return total <= 0 ? 0 : (DateTime.now().difference(start).inSeconds / total).clamp(0, 1).toDouble();
  }
}

class XtreamException implements Exception {
  XtreamException(this.message);
  final String message;
  @override
  String toString() => message;
}

class XtreamClient {
  XtreamClient(this.acc);

  final Account acc;

  Uri _api(String? action, [Map<String, String> extra = const {}]) {
    final base = Uri.parse('${acc.host}/player_api.php');
    return base.replace(queryParameters: {
      'username': acc.username,
      'password': acc.password,
      if (action != null) 'action': action,
      ...extra,
    });
  }

  String _stream(String kind, Object? id, String ext) => _streamUrl(_auth, kind, '$id.$ext');

  /// Host and credentials for stream URLs, as plain strings so they can be sent to a background isolate.
  _Auth get _auth => _authOf(acc);

  Future<dynamic> _getJson(Uri uri, {Duration timeout = const Duration(seconds: 90)}) async {
    final body = await _getBytes(uri, timeout: timeout);
    try {
      // Large lists (tens of thousands of entries) are decoded off the UI isolate.
      return await Isolate.run(() => jsonDecode(utf8.decode(body)));
    } catch (_) {
      throw XtreamException('Sunucu geçersiz (JSON olmayan) yanıt verdi');
    }
  }

  /// A stream list (live/movies/series). Categories and streams are fetched in parallel, and the [Item]s are
  /// built on the background isolate too: only the slim items come back, not the full decoded maps (plots,
  /// ratings, ...), which on a TV stick cost seconds of UI-thread copying and a lot of memory.
  Future<List<Item>> _streams(String categoriesAction, String streamsAction, _ToItem toItem) async {
    final auth = _auth;
    final categories = _categories(categoriesAction); // never fails: falls back to no categories
    final body = await _getBytes(_api(streamsAction), timeout: const Duration(seconds: 90));
    final cats = await categories;
    try {
      return await Isolate.run(() {
        final list = jsonDecode(utf8.decode(body));
        return list is List ? [for (final s in list) if (s is Map) toItem(s, cats, auth)] : <Item>[];
      });
    } catch (_) {
      throw XtreamException('Sunucu geçersiz (JSON olmayan) yanıt verdi');
    }
  }

  Future<List<int>> _getBytes(Uri uri, {required Duration timeout}) async {
    final http.Response res;
    try {
      res = await http.get(uri, headers: {'User-Agent': _userAgent}).timeout(timeout);
    } catch (e) {
      throw XtreamException('Sunucuya erişilemiyor: $e');
    }
    if (res.statusCode != 200) throw XtreamException('Sunucu HTTP ${res.statusCode} döndürdü');
    return res.bodyBytes;
  }

  Future<AccountInfo> authenticate() async {
    final data = await _getJson(_api(null), timeout: const Duration(seconds: 30));
    final info = _map(data is Map ? data['user_info'] : null);
    if (info == null || '${info['auth']}' == '0') {
      throw XtreamException('Giriş reddedildi: kullanıcı adı veya parola hatalı');
    }
    final exp = int.tryParse('${info['exp_date']}');
    return AccountInfo(
      status: '${info['status'] ?? ''}',
      expiry: exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      maxConnections: int.tryParse('${info['max_connections']}') ?? 0,
      activeConnections: int.tryParse('${info['active_cons']}') ?? 0,
    );
  }

  Future<Map<String, String>> _categories(String action) async {
    try {
      final list = await _getJson(_api(action));
      if (list is! List) return {};
      return {for (final c in list) '${c['category_id']}': '${c['category_name']}'};
    } catch (_) {
      return {};
    }
  }

  Future<List<Item>> live() => _streams('get_live_categories', 'get_live_streams', _liveItem);

  Future<List<Item>> movies() => _streams('get_vod_categories', 'get_vod_streams', _movieItem);

  Future<List<Item>> series() => _streams('get_series_categories', 'get_series', _seriesItem);


  /// PHP panels send an empty object as `[]`: anything that is not a map counts as "no data".
  static Map? _map(dynamic v) => v is Map ? v : null;

  static String _first(dynamic v) {
    if (v is List) return v.isEmpty ? '' : '${v.first}';
    return v == null ? '' : '$v';
  }

  static Details _details(Map? info) {
    if (info == null) return Details();
    String year = '${info['releasedate'] ?? info['releaseDate'] ?? info['year'] ?? ''}';
    if (year.length >= 4) year = year.substring(0, 4);
    return Details(
      plot: '${info['plot'] ?? info['description'] ?? ''}',
      rating: '${info['rating'] ?? ''}',
      year: year,
      duration: '${info['duration'] ?? ''}',
      genre: '${info['genre'] ?? ''}',
      cast: '${info['cast'] ?? info['actors'] ?? ''}',
      director: '${info['director'] ?? ''}',
      backdrop: _first(info['backdrop_path']),
      poster: '${info['movie_image'] ?? info['cover'] ?? ''}',
    );
  }

  Future<Details> vodDetails(int streamId) async {
    final data = await _getJson(_api('get_vod_info', {'vod_id': '$streamId'}));
    return _details(_map(data is Map ? data['info'] : null));
  }

  Future<SeriesData> seriesData(int seriesId) async {
    final data = await _getJson(_api('get_series_info', {'series_id': '$seriesId'}));
    final map = data is Map ? data : const {};
    final eps = map['episodes'];
    final out = <Episode>[];
    void add(String seasonKey, dynamic list) {
      if (list is! List) return;
      for (final e in list) {
        if (e is! Map) continue;
        final info = _map(e['info']) ?? const {};
        out.add(Episode(
          season: int.tryParse('${e['season'] ?? seasonKey}') ?? 1,
          number: int.tryParse('${e['episode_num']}') ?? 1,
          title: '${e['title'] ?? ''}',
          url: _stream('series', e['id'], '${e['container_extension'] ?? 'mp4'}'),
          plot: '${info['plot'] ?? ''}',
          duration: '${info['duration'] ?? ''}',
          image: '${info['movie_image'] ?? ''}',
        ));
      }
    }

    if (eps is Map) {
      eps.forEach((k, v) => add('$k', v));
    } else if (eps is List) {
      for (var i = 0; i < eps.length; i++) {
        add('${i + 1}', eps[i]);
      }
    }
    out.sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.number.compareTo(b.number));
    return SeriesData(_details(_map(map['info'])), out);
  }

  /// Current and upcoming programmes of a live channel (empty when the provider has no EPG).
  Future<List<Programme>> shortEpg(int streamId) async {
    try {
      final data = await _getJson(_api('get_short_epg', {'stream_id': '$streamId', 'limit': '3'}), timeout: const Duration(seconds: 15));
      final list = data is Map ? data['epg_listings'] : null;
      if (list is! List) return [];
      String dec(dynamic v) {
        try {
          return utf8.decode(base64.decode('$v'));
        } catch (_) {
          return '$v';
        }
      }

      DateTime? ts(dynamic v) {
        final n = int.tryParse('$v');
        return n == null ? null : DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }

      final out = <Programme>[];
      for (final e in list) {
        final st = ts(e['start_timestamp']);
        final en = ts(e['stop_timestamp']);
        if (st != null && en != null) out.add(Programme(title: dec(e['title']), start: st, end: en));
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      return out.where((p) => p.end.isAfter(DateTime.now())).toList();
    } catch (_) {
      return [];
    }
  }
}

typedef _Auth = ({String host, String user, String pass});
typedef _ToItem = Item Function(Map s, Map<String, String> cats, _Auth auth);

_Auth _authOf(Account a) => (host: a.host, user: Uri.encodeComponent(a.username), pass: Uri.encodeComponent(a.password));

/// [file] is the stream id with its extension, e.g. "42.mkv".
String _streamUrl(_Auth a, String kind, String file) => '${a.host}/$kind/${a.user}/${a.pass}/$file';

// Top-level (not closures) so they can run on the background isolate without capturing the client.
Item _liveItem(Map s, Map<String, String> cats, _Auth auth) => Item(
      id: 'l${s['stream_id']}',
      name: '${s['name'] ?? ''}',
      logo: '${s['stream_icon'] ?? ''}',
      group: cats['${s['category_id']}'] ?? 'Kategorisiz',
      kind: Kind.live,
      url: _streamUrl(auth, 'live', '${s['stream_id']}.ts'),
    );

Item _movieItem(Map s, Map<String, String> cats, _Auth auth) => Item(
      id: 'm${s['stream_id']}',
      name: '${s['name'] ?? ''}',
      logo: '${s['stream_icon'] ?? ''}',
      group: cats['${s['category_id']}'] ?? 'Kategorisiz',
      kind: Kind.movie,
      url: _streamUrl(auth, 'movie', '${s['stream_id']}.${s['container_extension'] ?? 'mp4'}'),
      added: int.tryParse('${s['added']}') ?? 0,
    );

Item _seriesItem(Map s, Map<String, String> cats, _Auth auth) => Item(
      id: 's${s['series_id']}',
      name: '${s['name'] ?? ''}',
      logo: '${s['cover'] ?? ''}',
      group: cats['${s['category_id']}'] ?? 'Kategorisiz',
      kind: Kind.series,
      seriesId: int.tryParse('${s['series_id']}'),
      added: int.tryParse('${s['last_modified']}') ?? 0,
    );
