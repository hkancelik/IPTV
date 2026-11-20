import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:iptv_app/src/catalog_cache.dart';
import 'package:iptv_app/src/global_search_page.dart';
import 'package:iptv_app/src/lan_sync.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/settings_page.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/controls.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = Account(name: 'Demo', host: 'http://panel.example:8080', username: 'hakan', password: 'VerySecretPassword999');
final _otherAcc = Account(name: 'Other', host: 'http://other.example:8080', username: 'someone', password: 'OtherPassword111');

void _resetSettings() {
  AppSettings.instance
    ..audioLang = 'auto'
    ..subLang = 'off'
    ..deinterlace = 'auto'
    ..skipSecs = 10
    ..hideAdult = false
    ..resume = true
    ..autoNext = true
    ..dedupe = true
    ..tvMode = false
    ..uiScale = 1.0
    ..phoneRemote = false
    ..downloadDir = ''
    ..hiddenGroups = {}
    ..groupOrder = {}
    ..syncUpdatedMs = 0;
}

void main() {
  group('SyncSnapshot, LWW merge & security', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      _resetSettings();
      await Library.instance.use(_acc);
    });

    test('captured snapshot never exposes password or host credentials', () async {
      final movie = Item(
        id: 'm42',
        name: 'Dune |2024|',
        logo: 'http://img.example/dune.jpg',
        group: 'Bilim Kurgu',
        kind: Kind.movie,
        url: '${_acc.host}/movie/${_acc.username}/${_acc.password}/42.mkv',
      );
      await Library.instance.toggleFavorite(movie);
      await Library.instance.touch(url: movie.url!, title: movie.name, logo: movie.logo, kind: Kind.movie, item: movie);
      await Library.instance.savePosition(movie.url!, const Duration(minutes: 25), const Duration(hours: 2));
      await Library.instance.saveTracks(
        movie.url!,
        audio: const TrackPref(id: '2', language: 'tr', title: 'Türkçe'),
        subtitle: const TrackPref(id: 'no'),
      );
      await RecentSearchStore.add(_acc, 'dune');

      final snap = await SyncSnapshot.capture(_acc, deviceName: 'Linux PC');
      final raw = snap.toJsonString();

      expect(raw, isNot(contains('VerySecretPassword999')));
      expect(raw, isNot(contains('panel.example')));
      expect(raw, contains('movie/42.mkv'));
      expect(snap.accountHash, CatalogCache.accountCacheKey(_acc));
      expect(snap.recentSearches, contains('dune'));
    });

    test('favorites LWW merges unions, honors newer tombstones, and allows newer re-adds', () async {
      final ch1 = Item(id: 'l1', name: 'TRT 1', logo: '', group: 'Ulusal', kind: Kind.live, url: '${_acc.host}/live/${_acc.username}/${_acc.password}/1.ts');
      final ch2 = Item(id: 'l2', name: 'NTV', logo: '', group: 'Haber', kind: Kind.live, url: '${_acc.host}/live/${_acc.username}/${_acc.password}/2.ts');
      final ch3 = Item(id: 'l3', name: 'TV8', logo: '', group: 'Ulusal', kind: Kind.live, url: '${_acc.host}/live/${_acc.username}/${_acc.password}/3.ts');

      await Library.instance.toggleFavorite(ch1); // added now (~T)
      await Library.instance.toggleFavorite(ch2); // added now (~T)
      final now = DateTime.now().millisecondsSinceEpoch;

      final remote = SyncSnapshot(
        version: 1,
        accountHash: CatalogCache.accountCacheKey(_acc),
        deviceName: 'iPhone',
        createdAtMs: now + 5000,
        library: {
          'favorites': [
            {
              'item': {...ch3.toJson(), 'url': 'live/3.ts'},
              'at': now + 1000,
            },
          ],
          'removedFavorites': {
            'l2': now + 2000, // removed AFTER local add → should remove ch2
            'l1': now - 60000, // older removal than local add → ch1 must STAY
          },
          'history': const [],
        },
        settings: const {'updatedMs': 0},
        recentSearches: const [],
      );

      final result = await SyncSnapshot.applyAndMerge(_acc, remote);
      final ids = Library.instance.favorites.map((e) => e.id).toSet();
      expect(ids, {'l1', 'l3'});
      expect(result.libraryStats.totalFavorites, 2);
    });

    test('history LWW picks newer position while preserving track preferences and catalog items', () async {
      final epUrl = '${_acc.host}/series/${_acc.username}/${_acc.password}/101.mkv';
      final loki = Item(id: 's77', name: 'Loki', logo: '', group: 'Marvel', kind: Kind.series, seriesId: 77);
      await Library.instance.touch(url: epUrl, title: 'Loki S01E01', logo: '', kind: Kind.series, item: loki);
      await Library.instance.savePosition(epUrl, const Duration(minutes: 10), const Duration(minutes: 50));
      await Library.instance.saveTracks(
        epUrl,
        audio: const TrackPref(id: '2', language: 'tr', title: 'Türkçe'),
        subtitle: const TrackPref(id: 'no'),
      );
      final localAt = Library.instance.history.first.updatedMs;

      final remote = SyncSnapshot(
        version: 1,
        accountHash: CatalogCache.accountCacheKey(_acc),
        deviceName: 'iPhone',
        createdAtMs: localAt + 5000,
        library: {
          'favorites': const [],
          'removedFavorites': const <String, int>{},
          'history': [
            {
              'url': 'series/101.mkv',
              'title': 'Loki S01E01',
              'logo': '',
              'kind': 'series',
              'pos': const Duration(minutes: 34).inMilliseconds,
              'dur': const Duration(minutes: 50).inMilliseconds,
              'at': localAt + 4000, // newer playback position, no audio/item fields
            },
          ],
        },
        settings: const {'updatedMs': 0},
        recentSearches: const ['loki'],
      );

      await SyncSnapshot.applyAndMerge(_acc, remote);
      expect(Library.instance.positionFor(epUrl), const Duration(minutes: 34));
      expect(Library.instance.itemFor(epUrl)?.id, 's77');
      final prefs = Library.instance.trackPreferencesFor(epUrl);
      expect(prefs.audio?.language, 'tr');
      expect(prefs.subtitle?.id, 'no');
    });

    test('settings LWW syncs cross-device preferences without overwriting device-local settings', () async {
      await AppSettings.instance.update(tvMode: true, uiScale: 0.7, downloadDir: '/custom/tv');
      final newerTs = DateTime.now().millisecondsSinceEpoch + 10000;

      final remote = SyncSnapshot(
        version: 1,
        accountHash: CatalogCache.accountCacheKey(_acc),
        deviceName: 'iPhone',
        createdAtMs: newerTs,
        library: const {'favorites': [], 'removedFavorites': <String, int>{}, 'history': []},
        settings: {
          'updatedMs': newerTs,
          'audioLang': 'tr',
          'subLang': 'en',
          'deinterlace': 'yes',
          'skipSecs': 15,
          'hideAdult': true,
          'resume': true,
          'autoNext': false,
          'dedupe': false,
          'hiddenGroups': ['live:Spam'],
          'groupOrder': {
            'live': ['Ulusal', 'Spor'],
          },
          // Even if a hostile/stale payload had device-local keys, they must be ignored:
          'tvMode': false,
          'uiScale': 1.0,
          'downloadDir': '/iphone',
        },
        recentSearches: const [],
      );

      final res = await SyncSnapshot.applyAndMerge(_acc, remote);
      expect(res.settingsUpdated, isTrue);
      expect(AppSettings.instance.audioLang, 'tr');
      expect(AppSettings.instance.subLang, 'en');
      expect(AppSettings.instance.deinterlace, 'yes');
      expect(AppSettings.instance.skipSecs, 15);
      expect(AppSettings.instance.hideAdult, isTrue);
      expect(AppSettings.instance.autoNext, isFalse);
      expect(AppSettings.instance.hiddenGroups, {'live:Spam'});
      expect(AppSettings.instance.groupOrder['live'], ['Ulusal', 'Spor']);

      // Device-local settings stayed intact!
      expect(AppSettings.instance.tvMode, isTrue);
      expect(AppSettings.instance.uiScale, 0.7);
      expect(AppSettings.instance.downloadDir, '/custom/tv');
    });

    test('rejects snapshot from a different IPTV account', () async {
      final snapOther = SyncSnapshot(
        version: 1,
        accountHash: CatalogCache.accountCacheKey(_otherAcc),
        deviceName: 'Other PC',
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        library: const {'favorites': [], 'removedFavorites': <String, int>{}, 'history': []},
        settings: const {'updatedMs': 0},
        recentSearches: const [],
      );

      await expectLater(
        SyncSnapshot.applyAndMerge(_acc, snapOther),
        throwsA(isA<LanSyncException>().having((e) => e.statusCode, 'statusCode', HttpStatus.conflict)),
      );
    });

    test('parseTarget handles QR URLs, bare IP:port + PIN, and rejects incomplete input', () {
      final byUrl = LanSyncClient.parseTarget('http://192.168.1.20:51234/s/abc123xyz0');
      expect(byUrl.endpoint.toString(), 'http://192.168.1.20:51234/api/sync');
      expect(byUrl.token, 'abc123xyz0');
      expect(byUrl.pin, isNull);

      final byPin = LanSyncClient.parseTarget('192.168.1.20:51234', pin: '482 915');
      expect(byPin.endpoint.toString(), 'http://192.168.1.20:51234/api/sync');
      expect(byPin.pin, '482915');
      expect(byPin.token, isNull);

      expect(
        () => LanSyncClient.parseTarget('192.168.1.20:51234'),
        throwsA(isA<LanSyncException>()),
      );
    });
  });

  group('Real loopback HTTP bidirectional LAN sync', () {
    HttpOverrides? savedOverrides;

    setUp(() async {
      savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      _resetSettings();
      await Library.instance.use(_acc);
    });

    tearDown(() {
      HttpOverrides.global = savedOverrides;
    });

    test('host and client converge to identical state in a single POST /api/sync round-trip', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final hash = CatalogCache.accountCacheKey(_acc);

      // Host starts with movie A (at 10 min) + favorite channel 1.
      var hostFavorites = <String, Map<String, dynamic>>{
        'l1': {
          'item': {
            'id': 'l1',
            'name': 'TRT 1',
            'logo': '',
            'group': 'Ulusal',
            'kind': 'live',
            'url': 'live/1.ts',
            'seriesId': null,
            'added': 0,
          },
          'at': now,
        },
      };
      var hostHistory = <String, Map<String, dynamic>>{
        'movie/10.mkv': {
          'url': 'movie/10.mkv',
          'title': 'Dune',
          'logo': '',
          'kind': 'movie',
          'pos': const Duration(minutes: 10).inMilliseconds,
          'dur': const Duration(hours: 2).inMilliseconds,
          'at': now,
        },
      };

      SyncMergeResult? hostCallbackResult;
      final server = LanSyncServer(
        account: _acc,
        deviceName: 'Linux PC',
        enableUdpBroadcast: false,
        onPeerSynced: (r) => hostCallbackResult = r,
        captureSnapshot: (_) async => SyncSnapshot(
          version: 1,
          accountHash: hash,
          deviceName: 'Linux PC',
          createdAtMs: now + 2000,
          library: {
            'favorites': hostFavorites.values.toList(),
            'removedFavorites': const <String, int>{},
            'history': hostHistory.values.toList(),
          },
          settings: const {'updatedMs': 0},
          recentSearches: const ['trt'],
        ),
        mergeSnapshot: (_, incoming) async {
          if (incoming.accountHash != hash) {
            throw const LanSyncException('Farklı hesap', statusCode: HttpStatus.conflict);
          }
          // Merge incoming into simulated host store.
          for (final f in (incoming.library['favorites'] as List).cast<Map<String, dynamic>>()) {
            final item = f['item'] as Map<String, dynamic>;
            hostFavorites[item['id'] as String] = f;
          }
          for (final h in (incoming.library['history'] as List).cast<Map<String, dynamic>>()) {
            final u = h['url'] as String;
            final existing = hostHistory[u];
            if (existing == null || (h['at'] as int) > (existing['at'] as int)) {
              hostHistory[u] = h;
            }
          }
          return SyncMergeResult(
            peerDeviceName: incoming.deviceName,
            libraryStats: LibraryMergeStats(
              totalFavorites: hostFavorites.length,
              totalHistory: hostHistory.length,
              favoritesChanged: 1,
              historyChanged: 1,
            ),
            settingsUpdated: false,
            recentSearchesCount: 2,
          );
        },
      );
      addTearDown(server.stop);

      final shareUrl = await server.start(
        bindAddress: InternetAddress.loopbackIPv4,
        advertisedAddress: '127.0.0.1',
      );
      expect(shareUrl, isNotNull);

      // Client (real Library.instance) has favorite movie 20 and NEWER position on movie 10 (42 min).
      final favMovie = Item(
        id: 'm20',
        name: 'Arrival',
        logo: '',
        group: 'Bilim Kurgu',
        kind: Kind.movie,
        url: '${_acc.host}/movie/${_acc.username}/${_acc.password}/20.mkv',
      );
      final duneUrl = '${_acc.host}/movie/${_acc.username}/${_acc.password}/10.mkv';
      await Library.instance.toggleFavorite(favMovie);
      await Library.instance.touch(url: duneUrl, title: 'Dune', logo: '', kind: Kind.movie);
      await Library.instance.savePosition(duneUrl, const Duration(minutes: 42), const Duration(hours: 2));

      // 1. Wrong PIN is rejected with 403.
      final wrongTarget = LanSyncClient.parseTarget('127.0.0.1:${server.port}', pin: '000000');
      if (server.pin != '000000') {
        await expectLater(
          LanSyncClient.syncWith(account: _acc, target: wrongTarget, deviceName: 'iPhone'),
          throwsA(isA<LanSyncException>().having((e) => e.statusCode, 'statusCode', HttpStatus.forbidden)),
        );
      }

      // 2. Correct PIN completes full two-way sync!
      final target = LanSyncClient.parseTarget('127.0.0.1:${server.port}', pin: formatSyncPin(server.pin));
      final clientRes = await LanSyncClient.syncWith(account: _acc, target: target, deviceName: 'iPhone');

      expect(clientRes.peerDeviceName, 'Linux PC');
      expect(hostCallbackResult, isNotNull);
      expect(hostCallbackResult!.peerDeviceName, 'iPhone');

      // Both host and client now have BOTH l1 (TRT 1) and m20 (Arrival)!
      expect(hostFavorites.keys.toSet(), {'l1', 'm20'});
      expect(Library.instance.favorites.map((e) => e.id).toSet(), {'l1', 'm20'});

      // Both host and client have the newer 42 min position for Dune!
      expect(hostHistory['movie/10.mkv']!['pos'], const Duration(minutes: 42).inMilliseconds);
      expect(Library.instance.positionFor(duneUrl), const Duration(minutes: 42));

      // 3. Browser helper page and export endpoint respond cleanly without credentials.
      final pageRes = await http.get(shareUrl!);
      expect(pageRes.statusCode, HttpStatus.ok);
      expect(pageRes.body, contains('IPTV Yerel Ağ Eşitleme'));

      final exportRes = await http.get(Uri.parse('$shareUrl/export.json'));
      expect(exportRes.statusCode, HttpStatus.ok);
      expect(exportRes.body, isNot(contains('VerySecretPassword999')));
      expect(jsonDecode(exportRes.body), isA<Map<String, dynamic>>());
    });
  });

  group('SettingsPage Eşitleme section & LanSyncDialog UI', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      _resetSettings();
      await Library.instance.use(_acc);
    });

    testWidgets('opens LAN sync dialog on desktop and switches between Host and Connect tabs without overflow', (tester) async {
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
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SideItem, 'Eşitleme'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-lan-sync')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open-lan-sync')));
      await tester.pumpAndSettle();
      expect(find.text('Yerel Ağ Eşitleme'), findsOneWidget);
      expect(find.byKey(const ValueKey('lan-sync-host-pin')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lan-sync-tab-connect')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lan-sync-address')), findsOneWidget);
      expect(find.byKey(const ValueKey('lan-sync-pin')), findsOneWidget);
      expect(find.byKey(const ValueKey('lan-sync-submit')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders LAN sync full screen cleanly on iPhone 15 portrait and landscape', (tester) async {
      // Portrait
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: SettingsPage(
            info: AccountInfo(status: 'Active', maxConnections: 1),
            account: _acc,
            client: XtreamClient(_acc),
            onLogout: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('open-lan-sync')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-lan-sync')));
      await tester.pumpAndSettle();
      expect(find.text('Yerel Ağ Eşitleme'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Landscape
      tester.view.physicalSize = const Size(852, 393);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lan-sync-tab-connect')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lan-sync-submit')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
