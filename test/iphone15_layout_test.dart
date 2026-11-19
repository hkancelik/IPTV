import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/accounts.dart';
import 'package:iptv_app/src/detail_page.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/login_page.dart';
import 'package:iptv_app/src/player_chrome.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/settings_page.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/controls.dart';
import 'package:iptv_app/src/ui/layout.dart';
import 'package:iptv_app/src/ui/shell.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

// iPhone 15 logical dimensions (393 × 852 pt @3x) and Dynamic Island / Home Indicator insets.
const _iphone15Portrait = Size(393, 852);
const _iphone15Landscape = Size(852, 393);
const _iphone15ProMaxPortrait = Size(430, 932);
const _portraitPadding = FakeViewPadding(top: 59, bottom: 34, left: 0, right: 0);
const _landscapePadding = FakeViewPadding(top: 0, bottom: 21, left: 59, right: 59);

final _acc = Account(name: 'Ev TV', host: 'http://demo.example:8080', username: 'u', password: 'p');
final _acc2 = Account(name: 'Çok Uzun Bir Hesap Adı İkinci Profil', host: 'http://second.example:8080', username: 'u2', password: 'p2');

class _FakeClient extends XtreamClient {
  _FakeClient() : super(_acc);

  @override
  Future<AccountInfo> authenticate() async => AccountInfo(status: 'Active', maxConnections: 2, activeConnections: 1);

  @override
  Future<List<Item>> live() async => [
        Item(id: 'l1', name: 'TRT 1 HD', logo: '', group: 'Ulusal', kind: Kind.live, url: 'http://demo.example/live/u/p/1.ts'),
        Item(id: 'l2', name: 'TRT Spor', logo: '', group: 'Spor', kind: Kind.live, url: 'http://demo.example/live/u/p/2.ts'),
        Item(id: 'l3', name: 'Çok Uzun Bir Canlı Kanal Adı Kesintisiz HD Yayın', logo: '', group: 'Haber', kind: Kind.live, url: 'http://demo.example/live/u/p/3.ts'),
      ];

  @override
  Future<List<Item>> movies() async => [
        Item(id: 'm1', name: 'Dune: Çöl Gezegeni Bölüm İki |2024| TR', logo: '', group: 'Bilim Kurgu', kind: Kind.movie, url: 'http://demo.example/movie/u/p/1.mkv'),
        Item(id: 'm2', name: 'Oppenheimer |2023| TR-EN', logo: '', group: 'Dram', kind: Kind.movie, url: 'http://demo.example/movie/u/p/2.mkv'),
        Item(id: 'm3', name: 'Kış Uykusu |2014| TR', logo: '', group: 'Dram', kind: Kind.movie, url: 'http://demo.example/movie/u/p/3.mkv'),
        Item(id: 'm4', name: 'Yıldızlararası |2014| TR', logo: '', group: 'Bilim Kurgu', kind: Kind.movie, url: 'http://demo.example/movie/u/p/4.mkv'),
      ];

  @override
  Future<List<Item>> series() async => [
        Item(id: 's1', name: 'Severance |2022| TR-EN', logo: '', group: 'Bilim Kurgu', kind: Kind.series, seriesId: 1),
        Item(id: 's2', name: 'Breaking Bad |2008| EN', logo: '', group: 'Dram', kind: Kind.series, seriesId: 2),
      ];

  @override
  Future<List<Programme>> shortEpg(int streamId) async {
    final now = DateTime.now();
    return [
      Programme(title: 'Ana Haber Bülteni', start: now.subtract(const Duration(minutes: 25)), end: now.add(const Duration(minutes: 35))),
      Programme(title: 'Gece Kuşağı', start: now.add(const Duration(minutes: 35)), end: now.add(const Duration(minutes: 95))),
    ];
  }

  @override
  Future<SeriesData> seriesData(int seriesId) async => SeriesData(
        Details(
          plot: 'Lumon Industries çalışanları, iş ve özel yaşam anılarını birbirinden tamamen ayıran cerrahi bir işlem geçirmiştir. Mark Scout ekibinin karanlık gerçeğini keşfeder.',
          cast: 'Adam Scott, Zach Cherry, Britt Lower, Tramell Tillman',
          director: 'Ben Stiller',
          rating: '8.7',
          year: '2022',
          genre: 'Bilim Kurgu · Gerilim',
        ),
        [
          Episode(season: 1, number: 1, title: 'İyi Haberler', url: 'http://demo.example/series/u/p/11.mkv', duration: '00:57:00'),
          Episode(season: 1, number: 2, title: 'Yarım Döngü', url: 'http://demo.example/series/u/p/12.mkv', duration: '00:52:00'),
          Episode(season: 1, number: 3, title: 'Sonsuza Dek', url: 'http://demo.example/series/u/p/13.mkv', duration: '00:49:00'),
          Episode(season: 2, number: 1, title: 'Merhaba Bayan Cobel', url: 'http://demo.example/series/u/p/21.mkv', duration: '00:55:00'),
        ],
      );

  @override
  Future<Details> vodDetails(int streamId) async => Details(
        plot: 'Paul Atreides, Chani ve Fremenler ile birleşerek ailesini yok edenlere karşı intikam yoluna girer.',
        cast: 'Timothée Chalamet, Zendaya, Rebecca Ferguson',
        director: 'Denis Villeneuve',
        rating: '8.6',
        year: '2024',
        duration: '02:46:00',
        genre: 'Bilim Kurgu · Macera',
      );
}

void _configureIphone(WidgetTester t, Size size, FakeViewPadding padding) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  t.view.padding = padding;
  t.view.viewPadding = padding;
  addTearDown(t.view.reset);
}

Future<void> _settle(WidgetTester t, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _seedLibrary() async {
  SharedPreferences.setMockInitialValues({});
  await Library.instance.use(_acc);
  await Library.instance.touch(url: 'http://demo.example/series/u/p/13.mkv', title: 'Severance S01E03', logo: '', kind: Kind.series);
  await Library.instance.savePosition('http://demo.example/series/u/p/13.mkv', const Duration(minutes: 22), const Duration(minutes: 49));
  await Library.instance.touch(url: 'http://demo.example/movie/u/p/1.mkv', title: 'Dune: Çöl Gezegeni Bölüm İki |2024| TR', logo: '', kind: Kind.movie);
  await Library.instance.savePosition('http://demo.example/movie/u/p/1.mkv', const Duration(hours: 1, minutes: 34), const Duration(hours: 2, minutes: 46));
  await Library.instance.toggleFavorite(Item(id: 'l1', name: 'TRT 1 HD', logo: '', group: 'Ulusal', kind: Kind.live, url: 'http://demo.example/live/u/p/1.ts'));
  await Library.instance.toggleFavorite(Item(id: 'm1', name: 'Dune: Çöl Gezegeni Bölüm İki |2024| TR', logo: '', group: 'Bilim Kurgu', kind: Kind.movie, url: 'http://demo.example/movie/u/p/1.mkv'));
}

Widget _iosApp(Widget home) => MaterialApp(
      theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
      home: home,
    );

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    AppSettings.instance
      ..tvMode = false
      ..uiScale = 1.0
      ..groupOrder = {}
      ..hiddenGroups = {};
    await _seedLibrary();
  });

  group('iPhone 15 layout classification', () {
    testWidgets('detects iPhone 15 portrait, landscape and iPhone 15 Pro Max', (t) async {
      late AppLayoutMode mode;
      Future<void> check(Size size, FakeViewPadding pad, AppLayoutMode expected) async {
        _configureIphone(t, size, pad);
        await t.pumpWidget(_iosApp(Builder(builder: (ctx) {
          mode = layoutModeOf(ctx);
          return const SizedBox.shrink();
        })));
        expect(mode, expected);
      }

      await check(_iphone15Portrait, _portraitPadding, AppLayoutMode.phonePortrait);
      await check(_iphone15Landscape, _landscapePadding, AppLayoutMode.phoneLandscape);
      await check(_iphone15ProMaxPortrait, _portraitPadding, AppLayoutMode.phonePortrait);
    });
  });

  group('iPhone 15 Portrait (393 × 852)', () {
    testWidgets('uses floating bottom bar and renders all tabs without overflow', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      await t.pumpWidget(_iosApp(HomePage(client: _FakeClient(), info: AccountInfo(status: 'Active', maxConnections: 2, activeConnections: 1), account: _acc)));
      await _settle(t);

      expect(find.byType(PhoneBottomBar), findsOneWidget);
      expect(find.byType(SideMenu), findsNothing);
      expect(find.byType(ClockPill), findsNothing);
      expect(find.text('Kaldığın yerden'), findsOneWidget);
      expect(t.takeException(), isNull);

      for (final key in ['nav-live', 'nav-movies', 'nav-series', 'nav-favorites', 'nav-settings']) {
        await t.tap(find.byKey(ValueKey(key)));
        await _settle(t);
        expect(t.takeException(), isNull, reason: 'overflow on $key');
      }
    });

    testWidgets('Live TV category chips, category sheet and sort sheet work cleanly', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      await t.pumpWidget(_iosApp(HomePage(client: _FakeClient(), info: AccountInfo(status: 'Active', maxConnections: 2), account: _acc)));
      await _settle(t);

      await t.tap(find.byKey(const ValueKey('nav-live')));
      await _settle(t);
      expect(find.text('TRT 1 HD'), findsOneWidget);
      expect(find.text('Spor'), findsWidgets);

      // Filter by tapping a category chip
      await t.tap(find.text('Spor').first);
      await _settle(t);
      expect(find.text('TRT Spor'), findsOneWidget);
      expect(find.text('TRT 1 HD'), findsNothing);

      // Open searchable categories bottom sheet
      await t.tap(find.byTooltip('Tüm kategoriler'));
      await _settle(t);
      expect(find.text('Kategoriler'), findsOneWidget);
      await t.tap(find.text('Tümü').last);
      await _settle(t);
      expect(find.text('TRT 1 HD'), findsOneWidget);

      // Switch to Movies and test Sort bottom sheet
      await t.tap(find.byKey(const ValueKey('nav-movies')));
      await _settle(t);
      await t.tap(find.byTooltip('Sırala'));
      await _settle(t);
      expect(find.text('A – Z'), findsOneWidget);
      await t.tap(find.text('A – Z'));
      await _settle(t);
      expect(t.takeException(), isNull);
    });

    testWidgets('DetailPage portrait renders series and movie without overflow', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      final client = _FakeClient();
      final seriesItem = (await client.series()).first;
      await t.pumpWidget(_iosApp(DetailPage(client: client, item: seriesItem)));
      await _settle(t);
      expect(find.text('Severance'), findsOneWidget);
      expect(find.text('1. sezon'), findsOneWidget);
      expect(find.text('İyi Haberler'), findsOneWidget);
      expect(t.takeException(), isNull);

      final movieItem = (await client.movies()).first;
      await t.pumpWidget(_iosApp(DetailPage(client: client, item: movieItem)));
      await _settle(t);
      expect(find.text('Dune: Çöl Gezegeni Bölüm İki'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('LoginPage portrait renders profile grid and add form without overflow', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      await t.runAsync(() async {
        await AccountStore.save([_acc, _acc2]);
        await AccountStore.saveLast(_acc.key);
      });
      await t.pumpWidget(_iosApp(LoginPage(autoLogin: false, clientFactory: (_) => _FakeClient())));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await _settle(t);
      expect(find.text('Kullanıcı seç'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.tap(find.text('Kullanıcı ekle'));
      await _settle(t);
      expect(find.text('Yeni kullanıcı ekle'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('SettingsPage portrait opens sheet picker without overflow', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      await t.pumpWidget(_iosApp(Scaffold(
        body: SettingsPage(info: AccountInfo(status: 'Active', maxConnections: 2, activeConnections: 1), account: _acc, client: _FakeClient(), onLogout: () {}),
      )));
      await _settle(t);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.byKey(const ValueKey('setting-cacheSecs')));
      await t.tap(find.byKey(const ValueKey('setting-cacheSecs')));
      await _settle(t);
      expect(find.text('60 sn'), findsOneWidget);
      await t.tap(find.text('60 sn'));
      await _settle(t);
      expect(AppSettings.instance.cacheSecs, 60);
      expect(t.takeException(), isNull);
    });

    testWidgets('PhonePlayerOverlay + PhonePlayerCompanion render in portrait without overflow', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      final now = DateTime(2026, 11, 19, 21, 30);
      final progs = [
        Programme(title: 'Ana Haber Bülteni', start: DateTime(2026, 11, 19, 21, 0), end: DateTime(2026, 11, 19, 22, 0)),
        Programme(title: 'Spor Gündemi', start: DateTime(2026, 11, 19, 22, 0), end: DateTime(2026, 11, 19, 23, 0)),
      ];
      await t.pumpWidget(_iosApp(Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: PhonePlayerOverlay(
                  landscape: false,
                  live: true,
                  playing: true,
                  title: 'TRT 1 HD',
                  subtitle: 'Ulusal',
                  onBack: () {},
                  onPlayPause: () {},
                  onToggleOrientation: () {},
                  onToggleFit: () {},
                  coverFit: false,
                  queued: true,
                  onPrev: () {},
                  onNext: () {},
                  liveChannelIndex: 0,
                  liveChannelName: 'TRT 1 HD',
                  programmes: progs,
                  now: () => now,
                ),
              ),
            ),
            Expanded(
              child: PhonePlayerCompanion(
                live: true,
                title: 'TRT 1 HD',
                subtitle: 'Ulusal',
                index: 0,
                programmes: progs,
                now: () => now,
                queueTitles: const ['TRT 1 HD', 'TRT Spor', 'NTV'],
                onSelectQueue: (_) {},
                audioLabel: 'Türkçe',
                subtitleLabel: 'Kapalı',
                coverFit: false,
                onPickAudio: () {},
                onPickSubtitle: () {},
                onToggleOrientation: () {},
                onToggleFit: () {},
              ),
            ),
          ],
        ),
      )));
      await _settle(t);
      expect(find.text('Ana Haber Bülteni'), findsOneWidget);
      expect(find.text('TRT Spor'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('iPhone 15 Landscape (852 × 393)', () {
    testWidgets('uses slim floating landscape rail and renders all tabs without overflow', (t) async {
      _configureIphone(t, _iphone15Landscape, _landscapePadding);
      await t.pumpWidget(_iosApp(HomePage(client: _FakeClient(), info: AccountInfo(status: 'Active', maxConnections: 2, activeConnections: 1), account: _acc)));
      await _settle(t);

      expect(find.byType(PhoneLandscapeRail), findsOneWidget);
      expect(find.byType(PhoneBottomBar), findsNothing);
      expect(find.byType(SideMenu), findsNothing);
      expect(find.text('Kaldığın yerden'), findsOneWidget);
      expect(find.text('Kanallarım'), findsOneWidget);
      expect(t.takeException(), isNull);

      for (final key in ['nav-live', 'nav-movies', 'nav-series', 'nav-favorites', 'nav-settings']) {
        await t.tap(find.byKey(ValueKey(key)));
        await _settle(t);
        expect(t.takeException(), isNull, reason: 'landscape overflow on $key');
      }
    });

    testWidgets('DetailPage landscape renders 2-column split cleanly for series and movie', (t) async {
      _configureIphone(t, _iphone15Landscape, _landscapePadding);
      final client = _FakeClient();
      final seriesItem = (await client.series()).first;
      await t.pumpWidget(_iosApp(DetailPage(client: client, item: seriesItem)));
      await _settle(t);
      expect(find.text('Severance'), findsOneWidget);
      expect(find.text('İyi Haberler'), findsOneWidget);
      expect(t.takeException(), isNull);

      final movieItem = (await client.movies()).first;
      await t.pumpWidget(_iosApp(DetailPage(client: client, item: movieItem)));
      await _settle(t);
      expect(find.text('Dune: Çöl Gezegeni Bölüm İki'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('LoginPage landscape renders horizontal profiles and 2-column form without overflow', (t) async {
      _configureIphone(t, _iphone15Landscape, _landscapePadding);
      await t.runAsync(() async {
        await AccountStore.save([_acc, _acc2]);
        await AccountStore.saveLast(_acc.key);
      });
      await t.pumpWidget(_iosApp(LoginPage(autoLogin: false, clientFactory: (_) => _FakeClient())));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await _settle(t);
      expect(find.text('Kullanıcı seç'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.tap(find.text('Kullanıcı ekle'));
      await _settle(t);
      expect(find.text('Yeni kullanıcı ekle'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('PhonePlayerOverlay landscape renders VOD and Live EPG without overflow', (t) async {
      _configureIphone(t, _iphone15Landscape, _landscapePadding);
      final now = DateTime(2026, 11, 19, 21, 30);
      final progs = [
        Programme(title: 'Ana Haber Bülteni', start: DateTime(2026, 11, 19, 21, 0), end: DateTime(2026, 11, 19, 22, 0)),
        Programme(title: 'Spor Gündemi', start: DateTime(2026, 11, 19, 22, 0), end: DateTime(2026, 11, 19, 23, 0)),
      ];

      // Live landscape player
      await t.pumpWidget(_iosApp(Scaffold(
        backgroundColor: Colors.black,
        body: PhonePlayerOverlay(
          landscape: true,
          live: true,
          playing: true,
          title: 'TRT 1 HD',
          subtitle: 'Ulusal',
          onBack: () {},
          onPlayPause: () {},
          onToggleOrientation: () {},
          onToggleFit: () {},
          coverFit: false,
          queued: true,
          onPrev: () {},
          onNext: () {},
          onPickAudio: () {},
          onPickSubtitle: () {},
          onOpenQueue: () {},
          audioLabel: 'Türkçe',
          subtitleLabel: 'Kapalı',
          liveChannelIndex: 0,
          liveChannelName: 'TRT 1 HD',
          programmes: progs,
          now: () => now,
        ),
      )));
      await _settle(t);
      expect(find.text('Ana Haber Bülteni'), findsOneWidget);
      expect(t.takeException(), isNull);

      // VOD landscape player
      await t.pumpWidget(_iosApp(Scaffold(
        backgroundColor: Colors.black,
        body: PhonePlayerOverlay(
          landscape: true,
          live: false,
          playing: true,
          title: 'Dune: Çöl Gezegeni Bölüm İki',
          subtitle: 'Bilim Kurgu · 2024',
          onBack: () {},
          onPlayPause: () {},
          onToggleOrientation: () {},
          onToggleFit: () {},
          coverFit: false,
          onSeekBack: () {},
          onSeekForward: () {},
          position: const Duration(hours: 1, minutes: 34),
          duration: const Duration(hours: 2, minutes: 46),
          buffer: const Duration(hours: 1, minutes: 50),
          onSeek: (_) {},
          onPickAudio: () {},
          onPickSubtitle: () {},
          onPickRate: () {},
          onGoTo: () {},
          audioLabel: 'Türkçe',
          subtitleLabel: 'Altyazı',
          rateLabel: '1x',
        ),
      )));
      await _settle(t);
      expect(find.text('1:34:00'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('rotating live between portrait and landscape switches shells seamlessly', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      await t.pumpWidget(_iosApp(HomePage(client: _FakeClient(), info: AccountInfo(status: 'Active', maxConnections: 2), account: _acc)));
      await _settle(t);
      expect(find.byType(PhoneBottomBar), findsOneWidget);

      // Rotate to landscape
      t.view.physicalSize = _iphone15Landscape;
      t.view.padding = _landscapePadding;
      t.view.viewPadding = _landscapePadding;
      await _settle(t);
      expect(find.byType(PhoneLandscapeRail), findsOneWidget);
      expect(find.byType(PhoneBottomBar), findsNothing);
      expect(t.takeException(), isNull);

      // Rotate back to portrait
      t.view.physicalSize = _iphone15Portrait;
      t.view.padding = _portraitPadding;
      t.view.viewPadding = _portraitPadding;
      await _settle(t);
      expect(find.byType(PhoneBottomBar), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
