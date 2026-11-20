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

  test('history item metadata persists across password changes without storing the password', () async {
    SharedPreferences.setMockInitialValues({});
    await lib.use(_a);
    final movie = _movie(_a, 7);
    final series = Item(id: 's42', name: 'Loki', logo: 'http://img/loki.jpg', group: 'Diziler', kind: Kind.series, seriesId: 42);
    final epUrl = '${_a.host}/series/${_a.username}/${_a.password}/901.mkv';

    await lib.touch(url: movie.url!, title: movie.name, logo: movie.logo, kind: Kind.movie, item: movie);
    await lib.touch(url: epUrl, title: 'Loki S01E01', logo: '', kind: Kind.series, item: series);

    final stored = await _stored();
    expect(stored, isNot(contains('secret-a')));

    // Re-touching without item preserves the attached series item.
    await lib.touch(url: epUrl, title: 'Loki S01E01', logo: '', kind: Kind.series);
    expect(lib.itemFor(epUrl)?.seriesId, 42);

    // Reloading with a new password restores both items and updates portable URLs.
    await lib.use(Account(name: 'Ev', host: 'http://a.example:8080', username: 'ua', password: 'new-pass'));
    final restoredMovie = lib.itemFor('http://a.example:8080/movie/ua/new-pass/7.mkv');
    expect(restoredMovie?.id, 'm7');
    expect(restoredMovie?.url, 'http://a.example:8080/movie/ua/new-pass/7.mkv');
    final restoredSeries = lib.itemFor('http://a.example:8080/series/ua/new-pass/901.mkv');
    expect(restoredSeries?.id, 's42');
    expect(restoredSeries?.seriesId, 42);
  });

  test('resolveDetailItem resolves legacy movies from stream ID and legacy series from catalog with backfill', () async {
    SharedPreferences.setMockInitialValues({});
    await lib.use(_a);

    // Legacy movie history entry (no item attached)
    final movieUrl = '${_a.host}/movie/${_a.username}/${_a.password}/55.mkv';
    await lib.touch(url: movieUrl, title: 'Denk Geliş |2021| TR-EN.', logo: 'http://img/dg.jpg', kind: Kind.movie);
    var catalogCalls = 0;
    final resolvedMovie = await resolveDetailItem(
      kind: Kind.movie,
      url: movieUrl,
      title: 'Denk Geliş |2021| TR-EN.',
      logo: 'http://img/dg.jpg',
      loadCatalog: () async {
        catalogCalls++;
        return const [];
      },
    );
    expect(resolvedMovie?.id, 'm55');
    expect(resolvedMovie?.streamId, 55);
    expect(catalogCalls, 0);
    expect(lib.itemFor(movieUrl)?.id, 'm55');

    // Legacy series history entry (no item attached)
    final epUrl = '${_a.host}/series/${_a.username}/${_a.password}/801.mkv';
    await lib.touch(url: epUrl, title: 'Loki S01E01', logo: '', kind: Kind.series);
    final loki = Item(id: 's99', name: 'Loki', logo: 'http://img/loki.jpg', group: 'Marvel', kind: Kind.series, seriesId: 99);
    final resolvedSeries = await resolveDetailItem(
      kind: Kind.series,
      url: epUrl,
      title: 'Loki S01E01',
      loadCatalog: () async {
        catalogCalls++;
        return [loki];
      },
    );
    expect(resolvedSeries?.seriesId, 99);
    expect(catalogCalls, 1);

    // Second lookup uses the backfilled item on Library without calling loadCatalog again.
    final resolvedAgain = await resolveDetailItem(
      kind: Kind.series,
      url: epUrl,
      title: 'Loki S01E01',
      loadCatalog: () async {
        catalogCalls++;
        return [loki];
      },
    );
    expect(resolvedAgain?.seriesId, 99);
    expect(catalogCalls, 1);

    // Live channels return null.
    expect(
      await resolveDetailItem(kind: Kind.live, url: '${_a.host}/live/${_a.username}/${_a.password}/1.ts', title: 'TRT 1'),
      isNull,
    );
  });

  test('saved audio and subtitle tracks persist across restarts and series episodes', () async {
    await Library.instance.use(_a);
    final loki = Item(id: 's99', name: 'Loki', logo: '', group: 'Diziler', kind: Kind.series);
    final ep1Url = '${_a.host}/series/${_a.username}/${_a.password}/101.mkv';
    final ep2Url = '${_a.host}/series/${_a.username}/${_a.password}/102.mkv';
    final ep3Url = '${_a.host}/series/${_a.username}/${_a.password}/103.mkv';

    await Library.instance.touch(url: ep1Url, title: 'Loki S01E01', logo: '', kind: Kind.series, item: loki);
    await Library.instance.saveTracks(
      ep1Url,
      audio: const TrackPref(id: '2', language: 'tur', title: 'Türkçe'),
      subtitle: const TrackPref(id: 'no'),
      item: loki,
    );

    // Re-touching the same episode preserves saved track choices.
    await Library.instance.touch(url: ep1Url, title: 'Loki S01E01', logo: '', kind: Kind.series, item: loki);
    final sameEp = Library.instance.trackPreferencesFor(ep1Url, item: loki);
    expect(sameEp.audio, const TrackPref(id: '2', language: 'tur', title: 'Türkçe'));
    expect(sameEp.subtitle, const TrackPref(id: 'no'));

    // Reloading from SharedPreferences (app restart) preserves saved track choices.
    await Library.instance.use(_a);
    final afterRestart = Library.instance.trackPreferencesFor(ep1Url, item: loki);
    expect(afterRestart.audio, const TrackPref(id: '2', language: 'tur', title: 'Türkçe'));
    expect(afterRestart.subtitle, const TrackPref(id: 'no'));

    // Opening episode 2 of the same series inherits episode 1's track preferences.
    final ep2Inherited = Library.instance.trackPreferencesFor(ep2Url, item: loki);
    expect(ep2Inherited.audio, const TrackPref(id: '2', language: 'tur', title: 'Türkçe'));
    expect(ep2Inherited.subtitle, const TrackPref(id: 'no'));

    // Overriding subtitle on episode 2 applies to episode 3, while keeping Turkish audio.
    await Library.instance.touch(url: ep2Url, title: 'Loki S01E02', logo: '', kind: Kind.series, item: loki);
    await Library.instance.saveTracks(
      ep2Url,
      subtitle: const TrackPref(id: '4', language: 'tur', title: 'Türkçe Altyazı'),
      item: loki,
    );
    final ep3Inherited = Library.instance.trackPreferencesFor(ep3Url, item: loki);
    expect(ep3Inherited.audio, const TrackPref(id: '2', language: 'tur', title: 'Türkçe'));
    expect(ep3Inherited.subtitle, const TrackPref(id: '4', language: 'tur', title: 'Türkçe Altyazı'));
  });
}
