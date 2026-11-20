import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/catalog_cache.dart';
import 'package:iptv_app/src/detail_page.dart';
import 'package:iptv_app/src/global_search_page.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/settings_page.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/controls.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = Account(name: 'Demo', host: 'http://panel.example:8080', username: 'alice', password: 'SuperSecretPassword123');
final _accOther = Account(name: 'Other', host: 'http://other.example:8080', username: 'bob', password: 'OtherSecret456');

class _CountingClient extends XtreamClient {
  _CountingClient(
    super.acc, {
    this.liveItems = const [],
    this.movieItems = const [],
    this.seriesItems = const [],
  });

  List<Item> liveItems;
  List<Item> movieItems;
  List<Item> seriesItems;

  int liveCalls = 0;
  int movieCalls = 0;
  int seriesCalls = 0;

  @override
  Future<List<Item>> live() async {
    liveCalls++;
    return liveItems;
  }

  @override
  Future<List<Item>> movies() async {
    movieCalls++;
    return movieItems;
  }

  @override
  Future<List<Item>> series() async {
    seriesCalls++;
    return seriesItems;
  }

  @override
  Future<List<Programme>> shortEpg(int streamId) async => [];

  @override
  Future<Details> vodDetails(int streamId) async => Details(plot: 'Detay #$streamId', year: '2024');

  @override
  Future<SeriesData> seriesData(int seriesId) async => SeriesData(
        Details(plot: 'Dizi #$seriesId', year: '2023'),
        [Episode(season: 1, number: 1, title: '1. Bölüm', url: '${acc.host}/series/${acc.username}/${acc.password}/901.mkv')],
      );
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('CatalogCache disk persistence', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('iptv_catalog_cache_test_');
      // Exercise the real Isolate.run path in pure unit tests.
      CatalogCache.instance.setTestDirectory(tempDir, useIsolate: true);
    });

    tearDown(() {
      CatalogCache.instance.setTestDirectory(null);
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('round-trips items cleanly without leaking passwords to disk', () async {
      final savedAt = DateTime(2026, 11, 20, 12, 0);
      final items = [
        Item(
          id: 'm42',
          name: 'Dune |2024| TR-EN',
          logo: 'http://img.example/dune.jpg',
          group: 'TR/Film ⚡ Bilim Kurgu',
          kind: Kind.movie,
          url: 'http://panel.example:8080/movie/alice/SuperSecretPassword123/42.mkv',
          added: 1700000000,
        ),
        Item(
          id: 'm43',
          name: 'Arrival |2016|',
          logo: '',
          group: 'TR/Film ⚡ Bilim Kurgu',
          kind: Kind.movie,
          url: 'http://panel.example:8080/movie/alice/SuperSecretPassword123/43.mp4',
          added: 1699000000,
        ),
      ];

      await CatalogCache.instance.write(_acc, Kind.movie, items, now: savedAt);

      // Verify raw compressed AND decompressed payload on disk contains zero credentials.
      final files = tempDir.listSync().whereType<File>().toList();
      expect(files.length, 1);
      final decompressed = utf8.decode(gzip.decode(files.first.readAsBytesSync()));
      expect(decompressed, isNot(contains('SuperSecretPassword123')));
      expect(decompressed, isNot(contains('panel.example')));
      expect(decompressed, contains('movie/42.mkv'));

      // Verify read restores full playable URLs.
      final snap = await CatalogCache.instance.read(_acc, Kind.movie);
      expect(snap, isNotNull);
      expect(snap!.savedAt, savedAt);
      expect(snap.items.length, 2);
      expect(snap.items[0].name, 'Dune |2024| TR-EN');
      expect(snap.items[0].group, 'TR/Film ⚡ Bilim Kurgu');
      expect(snap.items[0].url, 'http://panel.example:8080/movie/alice/SuperSecretPassword123/42.mkv');
      expect(snap.items[0].added, 1700000000);

      // Password rotation still resolves valid URLs from portable paths.
      final rotated = Account(name: 'Demo', host: _acc.host, username: _acc.username, password: 'NewPassword999');
      final snapRotated = await CatalogCache.instance.read(rotated, Kind.movie);
      expect(snapRotated, isNotNull);
      expect(snapRotated!.items[0].url, 'http://panel.example:8080/movie/alice/NewPassword999/42.mkv');
    });

    test('deletes corrupt cache files and returns null gracefully', () async {
      final hash = CatalogCache.accountCacheKey(_acc);
      final corrupt = File('${tempDir.path}${Platform.pathSeparator}${hash}_live.json.gz');
      corrupt.writeAsBytesSync([0, 1, 2, 3, 4, 5]);

      final snap = await CatalogCache.instance.read(_acc, Kind.live);
      expect(snap, isNull);
      expect(corrupt.existsSync(), isFalse);
    });

    test('isolates accounts on summaryFor and clearAccount', () async {
      await CatalogCache.instance.write(_acc, Kind.movie, [
        Item(id: 'm1', name: 'A', logo: '', group: 'G', kind: Kind.movie, url: '${_acc.host}/movie/alice/SuperSecretPassword123/1.mkv'),
      ]);
      await CatalogCache.instance.write(_accOther, Kind.movie, [
        Item(id: 'm2', name: 'B', logo: '', group: 'G', kind: Kind.movie, url: '${_accOther.host}/movie/bob/OtherSecret456/2.mkv'),
      ]);

      final sumA = await CatalogCache.instance.summaryFor(_acc);
      expect(sumA.cachedKinds, 1);
      expect(sumA.totalBytes, greaterThan(0));

      await CatalogCache.instance.clearAccount(_acc);
      expect((await CatalogCache.instance.summaryFor(_acc)).cachedKinds, 0);
      expect((await CatalogCache.instance.summaryFor(_accOther)).cachedKinds, 1);
    });

    test('freshness TTL and Turkish cache age formatting work properly', () {
      final base = DateTime(2026, 11, 20, 15, 0);
      final snap = CatalogSnapshot(items: const [], savedAt: base);
      expect(snap.isFresh(const Duration(hours: 6), base.add(const Duration(hours: 2))), isTrue);
      expect(snap.isFresh(const Duration(hours: 6), base.add(const Duration(hours: 7))), isFalse);

      expect(formatCacheAge(base, now: base.add(const Duration(seconds: 20))), 'az önce');
      expect(formatCacheAge(base, now: base.add(const Duration(minutes: 15))), '15 dk önce');
      expect(formatCacheAge(base, now: base.add(const Duration(hours: 3))), '3 sa önce');
      expect(formatCacheAge(base, now: base.add(const Duration(days: 2))), '2 gün önce');
    });
  });

  group('rankSearchItems relevance & Turkish folding', () {
    test('ranks exact > prefix > word-prefix > substring and folds Turkish chars', () {
      final items = [
        Item(id: 'm1', name: 'Büyük Kışık Hikayesi |2020|', logo: '', group: 'Dram', kind: Kind.movie, url: 'u1'),
        Item(id: 'm2', name: 'Kara Işıklar |2022|', logo: '', group: 'Dram', kind: Kind.movie, url: 'u2'),
        Item(id: 'm3', name: 'Işık Hızı |2023|', logo: '', group: 'Bilim', kind: Kind.movie, url: 'u3'),
        Item(id: 'm4', name: 'Işık |2024| TR', logo: '', group: 'Dram', kind: Kind.movie, url: 'u4'),
        Item(id: 'm5', name: 'Işık |2024| TR', logo: '', group: '4K', kind: Kind.movie, url: 'u5'),
      ];

      final ranked = rankSearchItems(items, 'isik', dedupe: true);
      expect(ranked.map((e) => e.id).toList(), ['m4', 'm3', 'm2', 'm1']);
    });
  });

  group('HomePage disk cache & GlobalSearchPage integration', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Library.instance.use(_acc);
      tempDir = Directory.systemTemp.createTempSync('iptv_home_cache_test_');
      CatalogCache.instance.setTestDirectory(tempDir);
      AppSettings.instance
        ..tvMode = false
        ..groupOrder = {}
        ..hiddenGroups = {}
        ..hideAdult = false
        ..dedupe = true;
    });

    tearDown(() {
      CatalogCache.instance.setTestDirectory(null);
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<void> pumpHome(
      WidgetTester tester,
      _CountingClient client, {
      Size size = const Size(1500, 900),
      TargetPlatform? platform,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final theme = buildAppTheme();
      await tester.pumpWidget(MaterialApp(
        theme: platform == null ? theme : theme.copyWith(platform: platform),
        home: HomePage(
          client: client,
          info: AccountInfo(status: 'Active', maxConnections: 1),
          account: _acc,
        ),
      ));
      await _settle(tester, 5);
    }

    testWidgets('fresh disk cache opens Movies instantly with zero network calls; manual refresh fetches fresh list', (tester) async {
      await tester.runAsync(() => CatalogCache.instance.write(
            _acc,
            Kind.movie,
            [Item(id: 'm1', name: 'Önbellek Filmi', logo: '', group: 'Dram', kind: Kind.movie, url: '${_acc.host}/movie/alice/SuperSecretPassword123/1.mkv')],
            now: DateTime.now().subtract(const Duration(minutes: 10)),
          ));
      final client = _CountingClient(
        _acc,
        movieItems: [Item(id: 'm2', name: 'Güncel Ağ Filmi', logo: '', group: 'Dram', kind: Kind.movie, url: '${_acc.host}/movie/alice/SuperSecretPassword123/2.mkv')],
      );

      await pumpHome(tester, client);
      await tester.tap(find.byKey(const ValueKey('nav-movies')));
      await _settle(tester);

      expect(find.text('Önbellek Filmi'), findsOneWidget);
      expect(client.movieCalls, 0);

      // Manual refresh pulls the fresh list from the client and replaces the cached list.
      await tester.tap(find.byKey(const ValueKey('refresh-catalog')));
      await _settle(tester);

      expect(client.movieCalls, 1);
      expect(find.text('Güncel Ağ Filmi'), findsOneWidget);
    });

    testWidgets('stale disk cache displays immediately and refreshes silently in background', (tester) async {
      await tester.runAsync(() => CatalogCache.instance.write(
            _acc,
            Kind.movie,
            [Item(id: 'm1', name: 'Eski Film', logo: '', group: 'Dram', kind: Kind.movie, url: '${_acc.host}/movie/alice/SuperSecretPassword123/1.mkv')],
            now: DateTime.now().subtract(const Duration(hours: 10)),
          ));
      final client = _CountingClient(
        _acc,
        movieItems: [Item(id: 'm2', name: 'Taze Film', logo: '', group: 'Dram', kind: Kind.movie, url: '${_acc.host}/movie/alice/SuperSecretPassword123/2.mkv')],
      );

      await pumpHome(tester, client);
      await tester.tap(find.byKey(const ValueKey('nav-movies')));
      await _settle(tester);

      expect(client.movieCalls, 1);
      expect(find.text('Taze Film'), findsOneWidget);
    });

    testWidgets('GlobalSearchPage searches across Live, Movies and Series, filters by kind, and opens DetailPage', (tester) async {
      final client = _CountingClient(
        _acc,
        liveItems: [
          Item(id: 'l1', name: 'Matrix TV HD', logo: '', group: 'Sinema', kind: Kind.live, url: '${_acc.host}/live/alice/SuperSecretPassword123/1.ts'),
        ],
        movieItems: [
          Item(id: 'm10', name: 'The Matrix |1999| TR-EN', logo: '', group: 'Bilim Kurgu', kind: Kind.movie, url: '${_acc.host}/movie/alice/SuperSecretPassword123/10.mkv'),
        ],
        seriesItems: [
          Item(id: 's20', name: 'Matrix Chronicles |2023|', logo: '', group: 'Bilim Kurgu', kind: Kind.series, seriesId: 20),
        ],
      );

      await pumpHome(tester, client);
      await tester.tap(find.byKey(const ValueKey('global-search-button')));
      await _settle(tester, 8);

      expect(find.byType(GlobalSearchPage), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('global-search-input')), 'matrix');
      await _settle(tester, 6);

      expect(find.text('Matrix TV HD'), findsOneWidget);
      expect(find.text('The Matrix'), findsOneWidget);
      expect(find.text('Matrix Chronicles'), findsOneWidget);

      // Filter to Movies only.
      await tester.tap(find.byKey(const ValueKey('global-search-filter-movie')));
      await _settle(tester, 4);
      expect(find.text('The Matrix'), findsOneWidget);
      expect(find.text('Matrix TV HD'), findsNothing);

      // Tapping a movie opens DetailPage and records recent search.
      await tester.tap(find.text('The Matrix'));
      await _settle(tester, 6);
      expect(find.byType(DetailPage), findsOneWidget);
      expect(find.text('Detay #10'), findsOneWidget);
      expect(await RecentSearchStore.load(_acc), contains('matrix'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('GlobalSearch works cleanly on iPhone 15 portrait and landscape with zero overflow', (tester) async {
      final client = _CountingClient(
        _acc,
        liveItems: [Item(id: 'l1', name: 'TRT 1 HD', logo: '', group: 'Ulusal', kind: Kind.live, url: '${_acc.host}/live/alice/SuperSecretPassword123/1.ts')],
        movieItems: [Item(id: 'm1', name: 'TRT Belgesel Film', logo: '', group: 'Belgesel', kind: Kind.movie, url: '${_acc.host}/movie/alice/SuperSecretPassword123/1.mkv')],
        seriesItems: const [],
      );

      // Portrait (393x852)
      await pumpHome(tester, client, size: const Size(393, 852), platform: TargetPlatform.iOS);
      await tester.tap(find.byKey(const ValueKey('global-search-button')));
      await _settle(tester, 6);
      await tester.enterText(find.byKey(const ValueKey('global-search-input')), 'trt');
      await _settle(tester, 6);
      expect(find.text('TRT 1 HD'), findsOneWidget);
      expect(find.text('TRT Belgesel Film'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Landscape (852x393) — pop portrait GlobalSearchPage first.
      await tester.tap(find.byKey(const ValueKey('global-search-back')));
      await _settle(tester, 4);
      await pumpHome(tester, client, size: const Size(852, 393), platform: TargetPlatform.iOS);
      await tester.tap(find.byKey(const ValueKey('global-search-button')));
      await _settle(tester, 6);
      expect(find.byType(GlobalSearchPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty tab search offers widening to GlobalSearchPage with the typed query', (tester) async {
      final client = _CountingClient(
        _acc,
        liveItems: const [],
        movieItems: [Item(id: 'm1', name: 'Batman', logo: '', group: 'Aksiyon', kind: Kind.movie, url: '${_acc.host}/movie/alice/SuperSecretPassword123/1.mkv')],
        seriesItems: [Item(id: 's1', name: 'Dark', logo: '', group: 'Dram', kind: Kind.series, seriesId: 1)],
      );

      await pumpHome(tester, client);
      await tester.tap(find.byKey(const ValueKey('nav-movies')));
      await _settle(tester, 6);

      final movieSearch = find.descendant(of: find.byKey(const ValueKey('search2')), matching: find.byType(EditableText));
      await tester.enterText(movieSearch, 'dark');
      await _settle(tester, 4);
      expect(find.text('Sonuç yok'), findsOneWidget);
      expect(find.byKey(const ValueKey('widen-to-global-search')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('widen-to-global-search')));
      await _settle(tester, 8);
      expect(find.byType(GlobalSearchPage), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('SettingsPage shows cached disk size and clears cache on tap', (tester) async {
      await tester.runAsync(() => CatalogCache.instance.write(
            _acc,
            Kind.live,
            [Item(id: 'l1', name: 'TRT 1', logo: '', group: 'Ulusal', kind: Kind.live, url: '${_acc.host}/live/alice/SuperSecretPassword123/1.ts')],
          ));
      var clearedCallback = false;
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsPage(
            info: AccountInfo(status: 'Active', maxConnections: 1),
            account: _acc,
            client: XtreamClient(_acc),
            onLogout: () {},
            onCatalogCacheCleared: () => clearedCallback = true,
          ),
        ),
      ));
      await _settle(tester);

      await tester.tap(find.widgetWithText(SideItem, 'İçerik'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 liste diskte'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('clear-catalog-cache')));
      await _settle(tester);

      expect(clearedCallback, isTrue);
      final summary = await tester.runAsync(() => CatalogCache.instance.summaryFor(_acc));
      expect(summary!.cachedKinds, 0);
    });
  });
}
