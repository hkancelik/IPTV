import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/detail_page.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = Account(name: 'Demo', host: 'http://x', username: 'u', password: 'p');
const _movieUrl = 'http://x/movie/u/p/7.mkv';
String _episodeUrl(int season, int number) => 'http://x/series/u/p/$season$number.mkv';

class _FakeClient extends XtreamClient {
  _FakeClient({this.data, this.details}) : super(_acc);

  final SeriesData? data;
  final Details? details;

  @override
  Future<SeriesData> seriesData(int seriesId) async => data!;
  @override
  Future<Details> vodDetails(int streamId) async => details ?? Details();
}

typedef _Case = (Item, _FakeClient);

_Case _series({required Map<int, List<String>> seasons, String duration = '00:48:00'}) {
  final episodes = [
    for (final s in seasons.entries)
      for (var i = 0; i < s.value.length; i++) Episode(season: s.key, number: i + 1, title: s.value[i], url: _episodeUrl(s.key, i + 1), duration: duration),
  ];
  return (
    Item(id: 's1', name: 'Breaking Bad', logo: '', group: 'Dram', kind: Kind.series, seriesId: 1),
    _FakeClient(data: SeriesData(Details(plot: 'Bir kimya öğretmeni.'), episodes)),
  );
}

_Case _movie({Details? details}) => (
      Item(id: 'm7', name: 'Arrival |2016| EN', logo: '', group: 'Bilim kurgu', kind: Kind.movie, url: _movieUrl),
      _FakeClient(details: details ?? Details(plot: 'Uzaylılar geldi.', cast: 'Amy Adams', director: 'Denis Villeneuve', rating: '7.9')),
    );

Future<void> _seedPosition(String url, Duration position, Duration total) async {
  await Library.instance.touch(url: url, title: 'x', logo: '', kind: url.contains('/series/') ? Kind.series : Kind.movie);
  await Library.instance.savePosition(url, position, total);
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpDetail(WidgetTester tester, _Case c) async {
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  AppSettings.instance.tvMode = false;
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: DetailPage(client: c.$2, item: c.$1)));
  await _settle(tester);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Library.instance.use(_acc);
  });

  testWidgets('only the selected season is listed and its key switches the list', (tester) async {
    await _pumpDetail(tester, _series(seasons: {1: ['Pilot', 'İkinci'], 2: ['Dönüş']}));
    expect(find.text('Pilot'), findsOneWidget);
    expect(find.text('Dönüş'), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    await tester.tap(find.text('2. sezon'));
    await _settle(tester);
    expect(find.text('Dönüş'), findsOneWidget);
    expect(find.text('Pilot'), findsNothing);
  });

  testWidgets('the season of the episode in progress is selected and offered on open', (tester) async {
    await _seedPosition(_episodeUrl(2, 1), const Duration(minutes: 21), const Duration(minutes: 48));
    await _pumpDetail(tester, _series(seasons: {1: ['Pilot'], 2: ['Dönüş']}));
    expect(find.text('Dönüş'), findsOneWidget);
    expect(find.text('27 dk kaldı'), findsOneWidget);
    expect(find.text('1. bölümden devam et'), findsOneWidget);
  });

  testWidgets('a series with nothing in progress offers the first episode', (tester) async {
    await _pumpDetail(tester, _series(seasons: {1: ['Pilot']}));
    expect(find.text('İlk bölümü oynat'), findsOneWidget);
    expect(find.text('48 dk'), findsOneWidget);
  });

  testWidgets('a movie with a saved position offers to resume', (tester) async {
    await _seedPosition(_movieUrl, const Duration(minutes: 21, seconds: 4), const Duration(hours: 2));
    await _pumpDetail(tester, _movie());
    expect(find.text('Devam et 21:04'), findsOneWidget);
  });

  testWidgets('a movie shows its facts as tags and lines', (tester) async {
    await _pumpDetail(tester, _movie());
    expect(find.text('Arrival'), findsWidgets);
    expect(find.text('7.9'), findsOneWidget);
    expect(find.text('2016'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
    expect(find.textContaining('Yönetmen: Denis Villeneuve'), findsOneWidget);
  });

  testWidgets('empty facts are left out and nothing breaks', (tester) async {
    await _pumpDetail(tester, _movie(details: Details()));
    expect(find.textContaining('Yönetmen'), findsNothing);
    expect(find.textContaining('Oyuncular'), findsNothing);
    expect(find.text('Oynat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an episode with an unknown duration shows no minutes', (tester) async {
    await _pumpDetail(tester, _series(seasons: {1: ['Pilot']}, duration: ''));
    expect(find.textContaining(' dk'), findsNothing);
  });

  testWidgets('the favorite key toggles between the two looks', (tester) async {
    await _pumpDetail(tester, _movie());
    await tester.tap(find.text('Favorilere ekle'));
    await _settle(tester, 2);
    expect(find.text('Favorilerde'), findsOneWidget);
  });

  testWidgets('an 800 px window does not overflow', (tester) async {
    await _pumpDetail(tester, _series(seasons: {1: ['Çok uzun bir bölüm adı burada duruyor ve hiç bitmiyor', 'İkinci']}));
    tester.view.physicalSize = const Size(800, 600);
    await _settle(tester, 2);
    expect(tester.takeException(), isNull);
  });
}
