import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/xtream.dart';

/// Serves a fake Xtream `player_api.php` that returns [userInfo].
Future<(HttpServer, XtreamClient)> _fake(Map<String, dynamic> userInfo) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode({'user_info': userInfo}));
    req.response.close();
  });
  final client = XtreamClient(Account(name: 't', host: 'http://127.0.0.1:${server.port}', username: 'u', password: 'p'));
  return (server, client);
}

void main() {
  test('reports active/max connections and detects a full limit', () async {
    final (server, client) = await _fake({'auth': 1, 'status': 'Active', 'exp_date': '1893456000', 'active_cons': '2', 'max_connections': '2'});
    final info = await client.authenticate();
    expect(info.activeConnections, 2);
    expect(info.maxConnections, 2);
    expect(info.limitReached, isTrue);
    expect(info.expiry, isNotNull);
    await server.close(force: true);
  });

  test('limit is not reached while a connection is free', () async {
    final (server, client) = await _fake({'auth': 1, 'status': 'Active', 'active_cons': '1', 'max_connections': '2'});
    final info = await client.authenticate();
    expect(info.limitReached, isFalse);
    await server.close(force: true);
  });

  test('unknown limit (0) never counts as reached', () async {
    final (server, client) = await _fake({'auth': 1, 'status': 'Active', 'active_cons': '3', 'max_connections': '0'});
    expect((await client.authenticate()).limitReached, isFalse);
    await server.close(force: true);
  });

  test('wrong credentials raise a clear error', () async {
    final (server, client) = await _fake({'auth': 0});
    expect(client.authenticate(), throwsA(isA<XtreamException>()));
    await server.close(force: true);
  });

  test('movie list is parsed off the UI isolate with categories and stream URLs', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      final action = req.uri.queryParameters['action'];
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(switch (action) {
        'get_vod_categories' => [{'category_id': '7', 'category_name': 'Aksiyon'}],
        'get_vod_streams' => [
            {'stream_id': 42, 'name': 'Film A', 'stream_icon': 'http://x/a.jpg', 'category_id': '7', 'container_extension': 'mkv', 'added': '1700000000', 'plot': 'long text'},
            {'stream_id': 43, 'name': 'Film B', 'category_id': '99'},
          ],
        _ => <Object>[],
      }));
      req.response.close();
    });
    final host = 'http://127.0.0.1:${server.port}';
    final items = await XtreamClient(Account(name: 't', host: host, username: 'u ser', password: 'p')).movies();
    expect(items.map((i) => i.id), ['m42', 'm43']);
    expect(items.first.group, 'Aksiyon');
    expect(items.first.url, '$host/movie/u%20ser/p/42.mkv');
    expect(items.first.added, 1700000000);
    expect(items.last.group, 'Kategorisiz');
    await server.close(force: true);
  });

  /// Serves a fake `player_api.php`: [answer] returns the JSON for an action, or an int HTTP status to fail with.
  Future<(HttpServer, XtreamClient)> api(Object? Function(String? action) answer) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      final a = answer(req.uri.queryParameters['action']);
      if (a is int) {
        req.response.statusCode = a;
      } else {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(a));
      }
      req.response.close();
    });
    return (server, XtreamClient(Account(name: 't', host: 'http://127.0.0.1:${server.port}', username: 'u', password: 'p')));
  }

  test('a stream list the server refuses raises an XtreamException with the HTTP status', () async {
    final (server, client) = await api((action) => action == 'get_vod_streams' ? 500 : <Object>[]);
    await expectLater(client.movies(), throwsA(isA<XtreamException>().having((e) => e.message, 'message', 'Sunucu HTTP 500 döndürdü')));
    await server.close(force: true);
  });

  test('a movie without metadata ("info": []) gives empty details instead of failing', () async {
    final (server, client) = await api((_) => {'info': <Object>[], 'movie_data': {'stream_id': 1}});
    final details = await client.vodDetails(1);
    expect(details.plot, '');
    expect(details.poster, '');
    await server.close(force: true);
  });

  test('a series without metadata ("info": []) still lists its episodes', () async {
    final (server, client) = await api((_) => {
          'info': <Object>[],
          'episodes': {
            '1': [{'id': 5, 'episode_num': 1, 'title': 'Pilot', 'container_extension': 'mkv'}],
          },
        });
    final data = await client.seriesData(9);
    expect(data.episodes.map((e) => e.title), ['Pilot']);
    expect(data.episodes.single.url, endsWith('/series/u/p/5.mkv'));
    await server.close(force: true);
  });
}
