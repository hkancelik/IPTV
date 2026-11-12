import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _a = Account(name: 'Ev', host: 'http://a.example:8080', username: 'ua', password: 'secret-a');
final _b = Account(name: 'Ofis', host: 'http://b.example:8080', username: 'ub', password: 'secret-b');

Item _movie(Account a, int id) =>
    Item(id: 'm$id', name: 'Film $id', logo: '', group: 'G', kind: Kind.movie, url: '${a.host}/movie/${a.username}/${a.password}/$id.mkv');

/// Everything the app wrote to the plain preferences, as one string.
Future<String> _stored() async {
  final p = await SharedPreferences.getInstance();
  return [for (final k in p.getKeys()) '$k=${p.get(k)}'].join('\n');
}

void main() {
  final lib = Library.instance;

  test('favorites are kept per account', () async {
    SharedPreferences.setMockInitialValues({});
    await lib.use(_a);
    await lib.toggleFavorite(_movie(_a, 1));
    await lib.use(_b);
    expect(lib.favorites, isEmpty);
    await lib.use(_a);
    expect(lib.favorites.map((i) => i.id), ['m1']);
  });

  test('watch history is kept per account', () async {
    SharedPreferences.setMockInitialValues({});
    await lib.use(_a);
    await lib.touch(url: _movie(_a, 1).url!, title: 'Film 1', logo: '', kind: Kind.movie);
    await lib.use(_b);
    expect(lib.history, isEmpty);
    await lib.use(_a);
    expect(lib.history.map((e) => e.title), ['Film 1']);
  });

  test('the password is never written to the plain preferences', () async {
    SharedPreferences.setMockInitialValues({});
    await lib.use(_a);
    await lib.toggleFavorite(_movie(_a, 1));
    await lib.touch(url: _movie(_a, 2).url!, title: 'Film 2', logo: '', kind: Kind.movie);
    await lib.savePosition(_movie(_a, 2).url!, const Duration(minutes: 5), const Duration(hours: 1));
    final stored = await _stored();
    expect(stored, contains('Film 1'));
    expect(stored, contains('Film 2'));
    expect(stored, isNot(contains('secret-a')));
  });

  test('favorites and resume positions keep working after the account password changed', () async {
    SharedPreferences.setMockInitialValues({});
    await lib.use(_a);
    await lib.toggleFavorite(_movie(_a, 1));
    await lib.touch(url: _movie(_a, 1).url!, title: 'Film 1', logo: '', kind: Kind.movie);
    await lib.savePosition(_movie(_a, 1).url!, const Duration(minutes: 5), const Duration(hours: 1));

    await lib.use(Account(name: 'Ev', host: 'http://a.example:8080', username: 'ua', password: 'new-pass'));
    expect(lib.favorites.single.url, 'http://a.example:8080/movie/ua/new-pass/1.mkv');
    expect(lib.positionFor('http://a.example:8080/movie/ua/new-pass/1.mkv'), const Duration(minutes: 5));
  });

  test('favorites saved by older versions (one list for all accounts) go to the account they belong to', () async {
    SharedPreferences.setMockInitialValues({
      'favorites': jsonEncode([_movie(_a, 1).toJson(), _movie(_b, 2).toJson()]),
    });
    await lib.use(_a);
    expect(lib.favorites.map((i) => i.id), ['m1']);
    await lib.use(_b);
    expect(lib.favorites.map((i) => i.id), ['m2']);
    final stored = await _stored();
    expect(stored, isNot(contains('secret-a')));
    expect(stored, isNot(contains('secret-b')));
  });

  test('history saved by older versions goes to the account it belongs to', () async {
    SharedPreferences.setMockInitialValues({
      'history': jsonEncode([
        {'url': _movie(_a, 1).url, 'title': 'Film 1', 'logo': '', 'kind': 'movie', 'pos': 300000, 'dur': 3600000, 'at': 2},
        {'url': _movie(_b, 2).url, 'title': 'Film 2', 'logo': '', 'kind': 'movie', 'pos': 0, 'dur': 0, 'at': 1},
      ]),
    });
    await lib.use(_b);
    expect(lib.history.map((e) => e.title), ['Film 2']);
    await lib.use(_a);
    expect(lib.history.map((e) => e.title), ['Film 1']);
    expect(lib.positionFor(_movie(_a, 1).url!), const Duration(minutes: 5));
  });

  test('a save made before the video loaded (position 0 of 0) keeps the resume position', () async {
    SharedPreferences.setMockInitialValues({});
    final url = _movie(_a, 1).url!;
    await lib.use(_a);
    await lib.touch(url: url, title: 'Film 1', logo: '', kind: Kind.movie);
    await lib.savePosition(url, const Duration(minutes: 45), const Duration(hours: 2));

    await lib.savePosition(url, Duration.zero, Duration.zero);

    expect(lib.positionFor(url), const Duration(minutes: 45));
  });

  test('watching to the end clears the resume position', () async {
    SharedPreferences.setMockInitialValues({});
    final url = _movie(_a, 1).url!;
    await lib.use(_a);
    await lib.touch(url: url, title: 'Film 1', logo: '', kind: Kind.movie);
    await lib.savePosition(url, const Duration(minutes: 45), const Duration(hours: 2));

    await lib.savePosition(url, const Duration(hours: 1, minutes: 59, seconds: 30), const Duration(hours: 2));

    expect(lib.positionFor(url), isNull);
  });
}
