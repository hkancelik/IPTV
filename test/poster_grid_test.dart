import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/tokens.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = Account(name: 'Demo', host: 'http://x', username: 'u', password: 'p');

class _FakeClient extends XtreamClient {
  _FakeClient(this._movies) : super(_acc);

  final List<Item> _movies;
  @override
  Future<List<Item>> live() async => [];
  @override
  Future<List<Item>> movies() async => _movies;
  @override
  Future<List<Item>> series() async => [];
  @override
  Future<List<Programme>> shortEpg(int streamId) async => [];
}

var _n = 0;
Item _movie(String name) => Item(id: 'm${++_n}', name: name, logo: '', group: 'Sinema', kind: Kind.movie, url: 'http://x/movie/u/p/$_n.mkv');

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpHome(WidgetTester tester, {List<Item> movies = const []}) async {
  SharedPreferences.setMockInitialValues({});
  await Library.instance.use(_acc);
  if (tester.view.physicalSize != const Size(800, 600)) {
    tester.view.physicalSize = const Size(1500, 900);
  }
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  AppSettings.instance
    ..tvMode = false
    ..groupOrder = {}
    ..hiddenGroups = {};
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: HomePage(client: _FakeClient(movies), info: AccountInfo(status: 'Active', maxConnections: 1), account: _acc),
  ));
  await _settle(tester, 5);
}

void main() {
  test('posterColumns', () {
    expect(posterColumns(756), 5);
    expect(posterColumns(788), 6);
    expect(posterColumns(300), 2);
    expect(posterColumns(100), 2);
  });

  testWidgets('a poster shows its clean title and year with language', (tester) async {
    await _pumpHome(tester, movies: [_movie('Kış Uykusu |2014| TR')]);
    await tester.tap(find.byKey(const ValueKey('nav-movies')));
    await _settle(tester);
    expect(find.text('Kış Uykusu'), findsOneWidget);
    expect(find.text('2014, TR'), findsOneWidget);
  });

  testWidgets('the sort key opens the four orders and applies the chosen one', (tester) async {
    await _pumpHome(tester, movies: [_movie('Zeta'), _movie('Alfa')]);
    await tester.tap(find.byKey(const ValueKey('nav-movies')));
    await _settle(tester);
    await tester.tap(find.text('Sırala:'));
    await _settle(tester);
    expect(find.text('Yıl, yeniden eskiye'), findsOneWidget);
    await tester.tap(find.text('A – Z').last);
    await _settle(tester);
    expect(tester.getTopLeft(find.text('Alfa')).dx < tester.getTopLeft(find.text('Zeta')).dx, isTrue);
  });

  testWidgets('live TV has no sort key', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('nav-live')));
    await _settle(tester);
    expect(find.text('Sırala:'), findsNothing);
  });

  testWidgets('a long title and an 800 px window do not overflow', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    await _pumpHome(tester, movies: [_movie('Çok Uzun Bir Film Adı: Şeytanın Ağzından Çıkmış Öyküler ve Diğerleri |1999| TR')]);
    await tester.tap(find.byKey(const ValueKey('nav-movies')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the grid leaves room for the focus ring', (tester) async {
    await _pumpHome(tester, movies: [_movie('A')]);
    await tester.tap(find.byKey(const ValueKey('nav-movies')));
    await _settle(tester);
    final grid = tester.widget<GridView>(find.byKey(const ValueKey('poster-grid')));
    expect(grid.padding!.resolve(TextDirection.ltr).left, greaterThanOrEqualTo(AppSizes.scrollPad));
  });

  testWidgets('the poster heart adds the movie to the favorites', (tester) async {
    await _pumpHome(tester, movies: [_movie('Arrival |2016| EN')]);
    await tester.tap(find.byKey(const ValueKey('nav-movies')));
    await _settle(tester);
    await tester.tap(find.byTooltip('Favorilere ekle'));
    await tester.pump();
    expect(Library.instance.favorites, hasLength(1));
  });
}
