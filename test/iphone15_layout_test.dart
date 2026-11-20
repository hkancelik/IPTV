import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/accounts.dart';
import 'package:iptv_app/src/detail_page.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/login_page.dart';
import 'package:iptv_app/src/player_chrome.dart';
import 'package:iptv_app/src/player_page.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/settings_page.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/controls.dart';
import 'package:iptv_app/src/ui/layout.dart';
import 'package:iptv_app/src/ui/liquid_glass.dart';
import 'package:iptv_app/src/ui/shell.dart';
import 'package:iptv_app/src/ui/tokens.dart';
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

    testWidgets('landscape rail sits on the right without brand play icon above home and content clears left safe area', (t) async {
      _configureIphone(t, _iphone15Landscape, _landscapePadding);
      await t.pumpWidget(_iosApp(HomePage(client: _FakeClient(), info: AccountInfo(status: 'Active', maxConnections: 2, activeConnections: 1), account: _acc)));
      await _settle(t);

      final railFinder = find.byType(PhoneLandscapeRail);
      expect(railFinder, findsOneWidget);

      // Rail sits on the right side of the landscape viewport.
      final railRect = t.getRect(railFinder);
      expect(railRect.left, greaterThan(_iphone15Landscape.width * 0.75));

      // No redundant play icon above the home icon inside the rail.
      expect(find.descendant(of: railFinder, matching: find.byIcon(Icons.play_arrow_rounded)), findsNothing);
      expect(find.descendant(of: railFinder, matching: find.byKey(const ValueKey('nav-home'))), findsOneWidget);

      // Home icon is the topmost nav item in the rail.
      final homeRect = t.getRect(find.byKey(const ValueKey('nav-home')));
      final liveRect = t.getRect(find.byKey(const ValueKey('nav-live')));
      expect(homeRect.top, lessThan(liveRect.top));

      // Top bar title clears the left Dynamic Island safe area and does not overlap the right rail.
      final titleRect = t.getRect(find.byType(PhoneTopBar));
      expect(titleRect.right, lessThanOrEqualTo(railRect.left));
      final continueRect = t.getRect(find.text('Kaldığın yerden'));
      expect(continueRect.left, greaterThanOrEqualTo(_landscapePadding.left));
      expect(continueRect.right, lessThanOrEqualTo(railRect.left));
    });
  });

  group('Player OSD non-overlap, orientation lock & native Liquid Glass tab bar', () {
    for (final (label, size, pad, landscape) in [
      ('iPhone 15 portrait', _iphone15Portrait, _portraitPadding, false),
      ('iPhone SE portrait', const Size(375, 667), const FakeViewPadding(top: 20, bottom: 0, left: 0, right: 0), false),
      ('iPhone 15 landscape', _iphone15Landscape, _landscapePadding, true),
    ]) {
      testWidgets('seek OSD badge never overlaps top bar, center controls or timeline on $label', (t) async {
        _configureIphone(t, size, pad);
        final overlay = PhonePlayerOverlay(
          landscape: landscape,
          live: false,
          playing: true,
          title: 'Aşk Tesadüfleri Sever 2',
          onBack: () {},
          onPlayPause: () {},
          onToggleOrientation: () {},
          onToggleFit: () {},
          coverFit: false,
          onSeekBack: () {},
          onSeekForward: () {},
          position: const Duration(minutes: 1, seconds: 12),
          duration: const Duration(hours: 2, seconds: 1),
          onSeek: (_) {},
          osdText: '+10 sn',
          menuItems: const [
            GlassMenuItem(id: 'fit', title: 'Ekranı doldur', sfSymbol: 'aspectratio', icon: Icons.aspect_ratio_rounded),
          ],
          onMenuSelected: (_) {},
        );
        await t.pumpWidget(_iosApp(Scaffold(
          backgroundColor: Colors.black,
          body: landscape
              ? overlay
              : SafeArea(bottom: false, child: AspectRatio(aspectRatio: 16 / 9, child: overlay)),
        )));
        await _settle(t);

        final topRect = t.getRect(find.byKey(const ValueKey('phone-player-top-bar')));
        final centerRect = t.getRect(find.byKey(const ValueKey('phone-player-center-controls')));
        final bottomRect = t.getRect(find.byKey(const ValueKey('phone-player-bottom-bar')));
        final osdRect = t.getRect(find.byKey(const ValueKey('phone-player-osd')));

        expect(osdRect.overlaps(topRect), isFalse, reason: 'OSD $osdRect overlapped top bar $topRect on $label');
        expect(osdRect.overlaps(centerRect), isFalse, reason: 'OSD $osdRect overlapped center controls $centerRect on $label');
        expect(osdRect.overlaps(bottomRect), isFalse, reason: 'OSD $osdRect overlapped bottom bar $bottomRect on $label');
        // Must be a compact shrink-wrapped pill, not a full-width banner.
        expect(osdRect.width, lessThan(topRect.width * 0.5));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('player orientation lock stays locked to landscape without auto-resetting after 2s', (t) async {
      final calls = <List<String>>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          calls.add(List<String>.from(call.arguments as List));
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await PlayerPage.applyOrientationLock(toLandscape: true);
      await t.pump(const Duration(seconds: 5));
      expect(calls, [
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
      ]);

      await PlayerPage.applyOrientationLock(toLandscape: false);
      await t.pump(const Duration(seconds: 5));
      expect(calls.last, ['DeviceOrientation.portraitUp']);
      expect(calls, hasLength(2));
    });

    testWidgets('PhoneBottomBar mounts native iOS 26 NativeGlassTabBar when supported and returns from Settings on reselect', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      debugUseNativeLiquidGlass = true;
      addTearDown(() => debugUseNativeLiquidGlass = null);

      final selectedTabs = <int>[];
      await t.pumpWidget(_iosApp(Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PhoneBottomBar(
            selected: 5, // Settings open from top bar
            lastMainTab: 1, // Came from Canlı TV
            onSelect: selectedTabs.add,
          ),
        ),
      )));
      await t.pump();

      final nativeBar = t.widget<NativeGlassTabBar>(find.byType(NativeGlassTabBar));
      expect(nativeBar.tabs, hasLength(5));
      expect(nativeBar.selectedId, 'nav-live');
      expect(nativeBar.isDark, isTrue);
      expect(nativeBar.tintColor, AppColors.accent);
      final kitView = t.widget<UiKitView>(find.byType(UiKitView));
      expect(kitView.viewType, 'iptv/liquid_glass_tab_bar');

      // Selecting another tab switches to it.
      nativeBar.onSelected('nav-movies');
      expect(selectedTabs, [2]);

      // Tapping the previously active tab while on Settings exits Settings back to that tab.
      nativeBar.onReselect?.call('nav-live');
      expect(selectedTabs, [2, 1]);
    });

    testWidgets('player ••• menu opens hierarchical options and reports lifecycle callbacks', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      var shown = 0;
      var hidden = 0;
      String? picked;

      await t.pumpWidget(_iosApp(Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PhonePlayerOverlay(
              landscape: false,
              live: false,
              playing: true,
              title: 'Aşk Tesadüfleri Sever 2',
              onBack: () {},
              onPlayPause: () {},
              onToggleOrientation: () {},
              onToggleFit: () {},
              coverFit: false,
              onSeekBack: () {},
              onSeekForward: () {},
              position: const Duration(minutes: 1, seconds: 12),
              duration: const Duration(hours: 2),
              onSeek: (_) {},
              menuItems: const [
                GlassMenuItem(
                  id: 'menu-rate',
                  title: 'Oynatma hızı',
                  sfSymbol: 'gauge.with.needle',
                  icon: Icons.speed_rounded,
                  children: [
                    GlassMenuItem(id: 'rate:1.0', title: 'Normal (1x)', selected: true),
                    GlassMenuItem(id: 'rate:1.5', title: '1.5x'),
                  ],
                ),
                GlassMenuItem(
                  id: 'menu-actions',
                  title: '',
                  inline: true,
                  children: [
                    GlassMenuItem(id: 'fit', title: 'Ekranı doldur', sfSymbol: 'aspectratio', icon: Icons.aspect_ratio_rounded),
                  ],
                ),
              ],
              onMenuSelected: (id) => picked = id,
              onMenuWillShow: () => shown++,
              onMenuDidHide: () => hidden++,
            ),
          ),
        ),
      )));
      await _settle(t);

      await t.tap(find.byKey(const ValueKey('phone-player-more-menu')));
      await _settle(t);
      expect(shown, 1);
      expect(find.text('Oynatma hızı'), findsOneWidget);
      expect(find.text('Ekranı doldur'), findsOneWidget);

      await t.tap(find.text('Oynatma hızı'));
      await _settle(t);
      expect(find.text('1.5x'), findsOneWidget);

      await t.tap(find.text('1.5x'));
      await _settle(t);
      expect(picked, 'rate:1.5');
      expect(hidden, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('native iOS 26 Liquid Glass mounts real UIKit surfaces, interactive buttons and ••• menu', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      debugUseNativeLiquidGlass = true;
      addTearDown(() => debugUseNativeLiquidGlass = null);

      await t.pumpWidget(_iosApp(Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PhonePlayerOverlay(
              landscape: false,
              live: false,
              playing: true,
              title: 'Aşk Tesadüfleri Sever 2',
              onBack: () {},
              onPlayPause: () {},
              onToggleOrientation: () {},
              onToggleFit: () {},
              coverFit: false,
              onSeekBack: () {},
              onSeekForward: () {},
              position: const Duration(minutes: 1, seconds: 12),
              duration: const Duration(hours: 2),
              onSeek: (_) {},
              osdText: '+10 sn',
              menuItems: const [
                GlassMenuItem(
                  id: 'menu-audio',
                  title: 'Ses parçası',
                  sfSymbol: 'speaker.wave.2',
                  children: [
                    GlassMenuItem(id: 'audio:0', title: 'Türkçe', selected: true),
                  ],
                ),
              ],
              onMenuSelected: (_) {},
            ),
          ),
        ),
      )));
      await t.pump();

      final views = t.widgetList<UiKitView>(find.byType(UiKitView)).toList();
      final types = views.map((v) => v.viewType).toList();
      expect(types, contains('iptv/liquid_glass_surface'));
      expect(types, contains('iptv/liquid_glass_button'));
      expect(types, contains('iptv/liquid_glass_menu'));

      final menuView = views.firstWhere((v) => v.viewType == 'iptv/liquid_glass_menu');
      final params = menuView.creationParams as Map<String, Object?>;
      expect(params['sfSymbol'], 'ellipsis');
      expect(params['style'], 'clearGlass');
      expect((params['items'] as List), hasLength(1));
      expect(t.takeException(), isNull);
    });

    testWidgets('native iOS 26 Liquid Glass upgrades HomePage sort menu and landscape rail', (t) async {
      _configureIphone(t, _iphone15Landscape, _landscapePadding);
      debugUseNativeLiquidGlass = true;
      addTearDown(() => debugUseNativeLiquidGlass = null);

      await t.pumpWidget(_iosApp(HomePage(client: _FakeClient(), info: AccountInfo(status: 'Active', maxConnections: 2), account: _acc)));
      await _settle(t);

      // Landscape rail uses native Liquid Glass surface.
      final homeViews = t.widgetList<UiKitView>(find.byType(UiKitView)).map((v) => v.viewType).toList();
      expect(homeViews, contains('iptv/liquid_glass_surface'));

      // Switch to Movies -> Sırala button becomes native Liquid Glass UIMenu!
      await t.tap(find.byKey(const ValueKey('nav-movies')));
      await _settle(t);
      final movieViews = t.widgetList<UiKitView>(find.byType(UiKitView)).toList();
      expect(movieViews.any((v) => v.viewType == 'iptv/liquid_glass_menu'), isTrue);
      expect(t.takeException(), isNull);
    });

    test('PlayerPage.subtitleConfigurationFor keeps subtitles legible without 1080p downscaling on iPhone', () {
      final portraitCfg = PlayerPage.subtitleConfigurationFor(
        mode: AppLayoutMode.phonePortrait,
        viewport: _iphone15Portrait,
        safePadding: const EdgeInsets.only(top: 59, bottom: 34),
      );
      expect(portraitCfg.textScaler, TextScaler.noScaling);
      expect(portraitCfg.style.fontSize, greaterThanOrEqualTo(15));
      expect(portraitCfg.style.shadows, isNotEmpty);

      final landscapeCfg = PlayerPage.subtitleConfigurationFor(
        mode: AppLayoutMode.phoneLandscape,
        viewport: _iphone15Landscape,
        safePadding: const EdgeInsets.only(left: 59, right: 59, bottom: 21),
      );
      expect(landscapeCfg.textScaler, TextScaler.noScaling);
      expect(landscapeCfg.style.fontSize, greaterThanOrEqualTo(20));
      expect(landscapeCfg.padding.bottom, greaterThanOrEqualTo(33));
      expect(landscapeCfg.padding.left, greaterThanOrEqualTo(71));

      final largeCfg = PlayerPage.subtitleConfigurationFor(
        mode: AppLayoutMode.phoneLandscape,
        viewport: _iphone15Landscape,
        safePadding: const EdgeInsets.only(left: 59, right: 59, bottom: 21),
        subtitleScale: 1.5,
      );
      expect(largeCfg.style.fontSize!, closeTo(landscapeCfg.style.fontSize! * 1.5, 0.01));

      final tvCfg = PlayerPage.subtitleConfigurationFor(
        mode: AppLayoutMode.desktop,
        viewport: const Size(1280, 720),
        safePadding: EdgeInsets.zero,
        tvMode: true,
      );
      expect(tvCfg.textScaler, TextScaler.noScaling);
      expect(tvCfg.style.fontSize, 32.0);
    });
  });
}
