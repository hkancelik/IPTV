import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/detail_page.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/poster_card.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = Account(name: 'Demo', host: 'http://x', username: 'u', password: 'p');

class _FakeClient extends XtreamClient {
  _FakeClient() : super(_acc);

  @override
  Future<List<Item>> live() async => [];
  @override
  Future<List<Item>> movies() async => [];
  @override
  Future<List<Item>> series() async => [];
  @override
  Future<List<Programme>> shortEpg(int streamId) async => [];
  @override
  Future<Details> vodDetails(int streamId) async => Details(plot: 'Test özet', year: '2024');
  @override
  Future<SeriesData> seriesData(int seriesId) async => SeriesData(Details(plot: 'Dizi özet', year: '2022'), const []);
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _seedFavorites({List<String> channels = const [], List<String> movies = const []}) async {
  var n = 0;
  for (final c in channels) {
    await Library.instance.toggleFavorite(Item(id: 'l${++n}', name: c, logo: '', group: 'Ulusal', kind: Kind.live, url: 'http://x/live/u/p/$n.ts'));
  }
  for (final m in movies) {
    await Library.instance.toggleFavorite(Item(id: 'm${++n}', name: m, logo: '', group: 'Sinema', kind: Kind.movie, url: 'http://x/movie/u/p/$n.mkv'));
  }
}

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  AppSettings.instance
    ..tvMode = false
    ..groupOrder = {}
    ..hiddenGroups = {};
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: HomePage(client: _FakeClient(), info: AccountInfo(status: 'Active', maxConnections: 1), account: _acc),
  ));
  await _settle(tester, 5);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Library.instance.use(_acc);
  });

  testWidgets('favorites are grouped by kind and empty groups are not drawn', (tester) async {
    await _seedFavorites(channels: ['TRT 1'], movies: ['Arrival |2016| EN']);
    await _pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('nav-favorites')));
    await _settle(tester);
    expect(find.text('Kanallar'), findsOneWidget);
    expect(find.text('Filmler'), findsNWidgets(2), reason: 'the section heading and the menu item');
    expect(find.text('Diziler'), findsOneWidget, reason: 'only the menu item');
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('TRT 1'), findsOneWidget);
  });

  testWidgets('no favorites shows the existing hint', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('nav-favorites')));
    await _settle(tester);
    expect(find.textContaining('Henüz favori yok'), findsOneWidget);
  });

  testWidgets('Günlüğüm shows yearly count, average rating, 10-bar histogram, feed/wall views and filters', (tester) async {
    final nowYear = DateTime.now().year;
    final prevYear = nowYear - 1;
    final movieA = Item(id: 'm10', name: 'Dune |2021| TR', logo: '', group: 'Sinema', kind: Kind.movie, url: 'http://x/movie/u/p/10.mkv');
    final movieB = Item(id: 'm11', name: 'Blade Runner 2049 |2017| EN', logo: '', group: 'Sinema', kind: Kind.movie, url: 'http://x/movie/u/p/11.mkv');
    final seriesA = Item(id: 's20', name: 'Severance |2022| EN', logo: '', group: 'Diziler', kind: Kind.series, seriesId: 20);
    final watchlistOnly = Item(id: 'm12', name: 'Interstellar |2014| EN', logo: '', group: 'Sinema', kind: Kind.movie, url: 'http://x/movie/u/p/12.mkv');

    // Movie A: 4.5★ watched this year + rewatched this year + review
    await Library.instance.saveLog(movieA, rating: 4.5, review: 'Muhteşem atmosfer', watchedAt: DateTime(nowYear, 10, 5));
    await Library.instance.saveLog(movieA, addRewatch: true, watchedAt: DateTime(nowYear, 11, 12));
    // Series A: 5.0★ watched this year, no review
    await Library.instance.saveLog(seriesA, rating: 5.0, liked: true, watchedAt: DateTime(nowYear, 11, 18));
    // Movie B: 3.5★ watched previous year
    await Library.instance.saveLog(movieB, rating: 3.5, watchedAt: DateTime(prevYear, 6, 10));
    // Watchlist-only item: must NOT appear in Günlüğüm
    await Library.instance.toggleWatchlist(watchlistOnly);

    await _pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('nav-favorites')));
    await _settle(tester);
    expect(find.text('Rafım'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('shelf-tab-diary')));
    await _settle(tester);

    // Yearly counter: 2 watches for movieA (1st + rewatch) + 1 for seriesA = 3 in nowYear
    expect(tester.widget<Text>(find.byKey(const ValueKey('diary-yearly-count'))).data, '3');
    // Average rating across 3 rated entries: (4.5 + 5.0 + 3.5) / 3 = 4.333 -> 4.3
    expect(tester.widget<Text>(find.byKey(const ValueKey('diary-average-rating'))).data, '4.3');

    // All 10 half-star histogram bars (0.5..5.0) are rendered
    expect(find.byKey(const ValueKey('diary-rating-histogram')), findsOneWidget);
    for (var i = 1; i <= 10; i++) {
      final step = (i * 0.5).toStringAsFixed(1);
      expect(find.byKey(ValueKey('diary-hist-bar-$step')), findsOneWidget);
    }

    // Feed shows diary items and excludes watchlist-only item
    expect(find.text('Dune'), findsWidgets);
    expect(find.text('Severance'), findsOneWidget);
    expect(find.text('Blade Runner 2049'), findsOneWidget);
    expect(find.text('Interstellar'), findsNothing);
    expect(find.text('"Muhteşem atmosfer"'), findsWidgets);

    // Histogram bar click filters by 5.0★ (only Severance)
    await tester.tap(find.byKey(const ValueKey('diary-hist-bar-5.0')));
    await _settle(tester);
    expect(find.text('Severance'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
    expect(find.byKey(const ValueKey('diary-filter-rating-clear')), findsOneWidget);

    // Clear rating filter
    await tester.tap(find.byKey(const ValueKey('diary-filter-rating-clear')));
    await _settle(tester);
    expect(find.text('Dune'), findsWidgets);

    // Kind filter: Dizi
    await tester.tap(find.byKey(const ValueKey('diary-filter-series')));
    await _settle(tester);
    expect(find.text('Severance'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('diary-filter-all')));
    await _settle(tester);

    // Review filter: Notlu (only Dune)
    await tester.tap(find.byKey(const ValueKey('diary-filter-reviews')));
    await _settle(tester);
    expect(find.text('Dune'), findsWidgets);
    expect(find.text('Severance'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('diary-filter-reviews')));
    await _settle(tester);

    // Rewatch filter: Tekrar (only Dune)
    await tester.tap(find.byKey(const ValueKey('diary-filter-rewatch')));
    await _settle(tester);
    expect(find.text('Dune'), findsWidgets);
    expect(find.text('Severance'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('diary-filter-rewatch')));
    await _settle(tester);

    // Year filter: prevYear (only Blade Runner 2049, yearly count becomes 1)
    await tester.tap(find.byKey(ValueKey('diary-filter-year-$prevYear')));
    await _settle(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('diary-yearly-count'))).data, '1');
    expect(find.text('Blade Runner 2049'), findsOneWidget);
    expect(find.text('Severance'), findsNothing);
    await tester.tap(find.byKey(ValueKey('diary-filter-year-$prevYear')));
    await _settle(tester);

    // Switch to Poster Duvarı
    await tester.tap(find.byKey(const ValueKey('diary-view-wall')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('diary-poster-wall')), findsOneWidget);
    expect(find.byType(PosterRatingBadge), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sonra İzle displays watchlist, filters by kind, supports Rastgele Seç and removal', (tester) async {
    final movieA = Item(id: 'm20', name: 'Arrival |2016| EN', logo: '', group: 'Sinema', kind: Kind.movie, url: 'http://x/movie/u/p/20.mkv');
    final seriesA = Item(id: 's21', name: 'Andor |2022| EN', logo: '', group: 'Diziler', kind: Kind.series, seriesId: 21);
    final diaryOnly = Item(id: 'm22', name: 'Oppenheimer |2023| EN', logo: '', group: 'Sinema', kind: Kind.movie, url: 'http://x/movie/u/p/22.mkv');

    await Library.instance.toggleWatchlist(movieA);
    await Library.instance.toggleWatchlist(seriesA);
    await Library.instance.saveLog(diaryOnly, rating: 4.0);

    await _pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('nav-favorites')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('shelf-tab-watchlist')));
    await _settle(tester);

    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Andor'), findsOneWidget);
    expect(find.text('Oppenheimer'), findsNothing);

    // Filter to Film
    await tester.tap(find.byKey(const ValueKey('watchlist-filter-movie')));
    await _settle(tester);
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Andor'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('watchlist-filter-all')));
    await _settle(tester);

    // Tap "Rastgele Seç" -> opens dialog with reroll & open
    await tester.tap(find.byKey(const ValueKey('watchlist-random-pick')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('random-pick-title')), findsOneWidget);
    final firstTitle = tester.widget<Text>(find.byKey(const ValueKey('random-pick-title'))).data!;
    expect(['Arrival', 'Andor'], contains(firstTitle));

    // Reroll must pick the other item when pool has 2 items
    await tester.tap(find.byKey(const ValueKey('random-pick-reroll')));
    await _settle(tester);
    final secondTitle = tester.widget<Text>(find.byKey(const ValueKey('random-pick-title'))).data!;
    expect(secondTitle, isNot(firstTitle));

    // Open DetailPage from random pick dialog
    await tester.tap(find.byKey(const ValueKey('random-pick-open')));
    await _settle(tester);
    expect(find.byType(DetailPage), findsOneWidget);

    // Return to Sonra İzle and remove Arrival
    await tester.tap(find.text('Geri'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('watchlist-remove-m20')));
    await _settle(tester);
    expect(find.text('Arrival'), findsNothing);
    expect(find.text('Andor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rafım 3 sub-tabs render cleanly on iPhone portrait without overflow', (tester) async {
    final movieA = Item(id: 'm30', name: 'Dune |2021| TR', logo: '', group: 'Sinema', kind: Kind.movie, url: 'http://x/movie/u/p/30.mkv');
    final movieB = Item(id: 'm31', name: 'Arrival |2016| EN', logo: '', group: 'Sinema', kind: Kind.movie, url: 'http://x/movie/u/p/31.mkv');
    await Library.instance.toggleFavorite(movieA);
    await Library.instance.saveLog(movieA, rating: 4.5, review: 'Harika');
    await Library.instance.toggleWatchlist(movieB);

    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AppSettings.instance
      ..tvMode = false
      ..groupOrder = {}
      ..hiddenGroups = {};

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
      home: HomePage(client: _FakeClient(), info: AccountInfo(status: 'Active', maxConnections: 1), account: _acc),
    ));
    await _settle(tester, 5);

    await tester.tap(find.byKey(const ValueKey('nav-favorites')));
    await _settle(tester);
    expect(find.text('Rafım'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('shelf-tab-diary')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('diary-rating-histogram')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('diary-view-wall')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('diary-poster-wall')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('shelf-tab-watchlist')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('watchlist-random-pick')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('random-pick-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
