import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/detail_page.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/player_chrome.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/liquid_glass.dart';
import 'package:iptv_app/src/ui/tokens.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _portraitSize = Size(393, 852);
const _landscapeSize = Size(852, 393);
const _portraitPad = FakeViewPadding(top: 59, bottom: 34, left: 0, right: 0);
const _landscapePad = FakeViewPadding(top: 0, bottom: 21, left: 59, right: 59);
const _dpr = 2.0;

final _acc = Account(name: 'Ev TV', host: 'http://demo.example:8080', username: 'u', password: 'p');

class _DemoClient extends XtreamClient {
  _DemoClient() : super(_acc);

  @override
  Future<AccountInfo> authenticate() async => AccountInfo(
        status: 'Active',
        expiry: DateTime(2027, 11, 19),
        maxConnections: 2,
        activeConnections: 1,
      );

  @override
  Future<List<Item>> live() async => [
        Item(id: 'l1', name: 'TRT 1 HD', logo: '', group: 'Ulusal', kind: Kind.live, url: 'http://demo.example/live/u/p/1.ts'),
        Item(id: 'l2', name: 'TRT Spor', logo: '', group: 'Spor', kind: Kind.live, url: 'http://demo.example/live/u/p/2.ts'),
        Item(id: 'l3', name: 'NTV', logo: '', group: 'Haber', kind: Kind.live, url: 'http://demo.example/live/u/p/3.ts'),
        Item(id: 'l4', name: 'beIN Sports 1', logo: '', group: 'Spor', kind: Kind.live, url: 'http://demo.example/live/u/p/4.ts'),
        Item(id: 'l5', name: 'TRT Belgesel', logo: '', group: 'Belgesel', kind: Kind.live, url: 'http://demo.example/live/u/p/5.ts'),
        Item(id: 'l6', name: 'CNN Türk', logo: '', group: 'Haber', kind: Kind.live, url: 'http://demo.example/live/u/p/6.ts'),
        Item(id: 'l7', name: 'TRT 2', logo: '', group: 'Kültür & Sanat', kind: Kind.live, url: 'http://demo.example/live/u/p/7.ts'),
        Item(id: 'l8', name: 'Tivibu Spor', logo: '', group: 'Spor', kind: Kind.live, url: 'http://demo.example/live/u/p/8.ts'),
      ];

  @override
  Future<List<Item>> movies() async => [
        Item(id: 'm1', name: 'Dune: Çöl Gezegeni Bölüm İki |2024| TR', logo: 'http://poster/dune', group: 'Bilim Kurgu', kind: Kind.movie, url: 'http://demo.example/movie/u/p/1.mkv'),
        Item(id: 'm2', name: 'Oppenheimer |2023| TR', logo: 'http://poster/opp', group: 'Dram', kind: Kind.movie, url: 'http://demo.example/movie/u/p/2.mkv'),
        Item(id: 'm3', name: 'Yıldızlararası |2014| TR', logo: 'http://poster/inter', group: 'Bilim Kurgu', kind: Kind.movie, url: 'http://demo.example/movie/u/p/3.mkv'),
        Item(id: 'm4', name: 'Başlangıç |2010| TR', logo: 'http://poster/incep', group: 'Aksiyon', kind: Kind.movie, url: 'http://demo.example/movie/u/p/4.mkv'),
        Item(id: 'm5', name: 'Kış Uykusu |2014| TR', logo: 'http://poster/winter', group: 'Dram', kind: Kind.movie, url: 'http://demo.example/movie/u/p/5.mkv'),
        Item(id: 'm6', name: 'Blade Runner 2049 |2017| EN', logo: 'http://poster/blade', group: 'Bilim Kurgu', kind: Kind.movie, url: 'http://demo.example/movie/u/p/6.mkv'),
        Item(id: 'm7', name: 'Parazit |2019| TR', logo: 'http://poster/para', group: 'Gerilim', kind: Kind.movie, url: 'http://demo.example/movie/u/p/7.mkv'),
        Item(id: 'm8', name: 'Geliş |2016| TR', logo: 'http://poster/arrival', group: 'Bilim Kurgu', kind: Kind.movie, url: 'http://demo.example/movie/u/p/8.mkv'),
        Item(id: 'm9', name: 'Ahlat Ağacı |2018| TR', logo: 'http://poster/tree', group: 'Dram', kind: Kind.movie, url: 'http://demo.example/movie/u/p/9.mkv'),
      ];

  @override
  Future<List<Item>> series() async => [
        Item(id: 's1', name: 'Severance |2022| TR-EN', logo: 'http://poster/sev', group: 'Bilim Kurgu', kind: Kind.series, seriesId: 1),
      ];

  @override
  Future<List<Programme>> shortEpg(int streamId) async {
    final now = DateTime.now();
    final map = <int, (String, String, int)>{
      1: ('Ana Haber Bülteni', 'Gece Kuşağı', 36),
      2: ('Spor Gündemi (Canlı)', 'Maç Özeti', 44),
      3: ('Gece Bülteni', 'Ekonomi Notları', 18),
      4: ('Süper Lig Özeti', 'Avrupa Futbolu', 28),
      5: ('Anadolu’nun Yaban Hayatı', 'Doğa Günlüğü', 32),
      6: ('Gündem Özel', 'Gece Görüşü', 24),
      7: ('Sinema Söyleşileri', 'Gece Filmi', 12),
    };
    final row = map[streamId];
    if (row == null) return [];
    return [
      Programme(title: row.$1, start: now.subtract(Duration(minutes: row.$3)), end: now.add(Duration(minutes: 60 - row.$3))),
      Programme(title: row.$2, start: now.add(Duration(minutes: 60 - row.$3)), end: now.add(Duration(minutes: 120 - row.$3))),
    ];
  }

  @override
  Future<SeriesData> seriesData(int seriesId) async => SeriesData(
        Details(
          plot: 'Lumon Industries çalışanları, iş ve özel yaşam anılarını birbirinden tamamen ayıran cerrahi bir işlem geçirmiştir. Mark Scout, ekibinin karanlık gerçeğini keşfetmesiyle iki dünya arasındaki dengeyi sorgulamaya başlar.',
          cast: 'Adam Scott, Zach Cherry, Britt Lower, Tramell Tillman, John Turturro',
          director: 'Ben Stiller, Aoife McArdle',
          rating: '8.7',
          year: '2022',
          genre: 'Bilim Kurgu · Gerilim · Dram',
          poster: 'http://poster/sev',
          backdrop: 'http://poster/sev',
        ),
        [
          Episode(season: 1, number: 1, title: 'İyi Haberler', url: 'http://demo.example/series/u/p/11.mkv', duration: '00:57:00', image: 'http://poster/sev'),
          Episode(season: 1, number: 2, title: 'Yarım Döngü', url: 'http://demo.example/series/u/p/12.mkv', duration: '00:52:00', image: 'http://poster/sev'),
          Episode(season: 1, number: 3, title: 'Sonsuza Dek', url: 'http://demo.example/series/u/p/13.mkv', duration: '00:49:00', image: 'http://poster/sev'),
          Episode(season: 1, number: 4, title: 'Sen Kimsin?', url: 'http://demo.example/series/u/p/14.mkv', duration: '00:49:00', image: 'http://poster/sev'),
          Episode(season: 2, number: 1, title: 'Merhaba Bayan Cobel', url: 'http://demo.example/series/u/p/21.mkv', duration: '00:55:00', image: 'http://poster/sev'),
        ],
      );
}

// ─── Minimal pure-Dart gradient PNG generator for offline crisp posters ───

final Map<String, (Color, Color)> _palettes = {
  'dune': (const Color(0xFFC25E26), const Color(0xFF21161C)),
  'opp': (const Color(0xFFB5222C), const Color(0xFF171326)),
  'inter': (const Color(0xFF0A6FA8), const Color(0xFF0A1424)),
  'incep': (const Color(0xFF7B33E0), const Color(0xFF1A112E)),
  'winter': (const Color(0xFF0D7D59), const Color(0xFF0B1C1B)),
  'blade': (const Color(0xFF3936B5), const Color(0xFF131126)),
  'para': (const Color(0xFFC94B14), const Color(0xFF241312)),
  'arrival': (const Color(0xFF127A7A), const Color(0xFF0A1F26)),
  'tree': (const Color(0xFFB86614), const Color(0xFF21170E)),
  'sev': (const Color(0xFF3528B8), const Color(0xFF121229)),
};

Uint8List _gradientPng(Color top, Color bottom, {int w = 96, int h = 144}) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0); // filter type 0
    final ty = y / (h - 1);
    for (var x = 0; x < w; x++) {
      final tx = x / (w - 1);
      final t = (ty * 0.8 + tx * 0.2).clamp(0.0, 1.0);
      final r = ((top.r * (1 - t) + bottom.r * t) * 255).round().clamp(0, 255);
      final g = ((top.g * (1 - t) + bottom.g * t) * 255).round().clamp(0, 255);
      final b = ((top.b * (1 - t) + bottom.b * t) * 255).round().clamp(0, 255);
      raw
        ..addByte(r)
        ..addByte(g)
        ..addByte(b);
    }
  }
  final idat = zlib.encode(raw.toBytes());

  int crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : (crc >>> 1);
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  void chunk(BytesBuilder out, String type, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length);
    out.add(len.buffer.asUint8List());
    final body = [...ascii.encode(type), ...data];
    out.add(body);
    final crc = ByteData(4)..setUint32(0, crc32(body));
    out.add(crc.buffer.asUint8List());
  }

  final png = BytesBuilder();
  png.add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // RGB
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  chunk(png, 'IHDR', ihdr.buffer.asUint8List());
  chunk(png, 'IDAT', idat);
  chunk(png, 'IEND', const []);
  return png.toBytes();
}

class _PosterHttpOverrides extends HttpOverrides {
  final Map<String, Uint8List> _cache = {};

  Uint8List _bytesFor(Uri uri) {
    final key = uri.pathSegments.isEmpty ? 'sev' : uri.pathSegments.first;
    return _cache.putIfAbsent(key, () {
      final (a, b) = _palettes[key] ?? (const Color(0xFF443388), const Color(0xFF151517));
      return _gradientPng(a, b);
    });
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient(_bytesFor);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._bytesFor);
  final Uint8List Function(Uri) _bytesFor;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(_bytesFor(url));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._bytes);
  final Uint8List _bytes;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this._bytes);
  final Uint8List _bytes;

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ─── iPhone 15 OLED Hardware Chrome Overlay (Dynamic Island + Status Bar + Home Indicator) ───

class _Iphone15Chrome extends StatelessWidget {
  const _Iphone15Chrome({required this.landscape, required this.child});

  final bool landscape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (!landscape) ...[
          // Top iOS status bar + Dynamic Island
          Positioned(
            left: 28,
            right: 26,
            top: 17,
            child: IgnorePointer(
              child: Row(
                children: [
                  Text(
                    '09:41',
                    style: AppText.label(14.5, color: AppColors.ink).copyWith(
                      decoration: TextDecoration.none,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.signal_cellular_alt_rounded, size: 15, color: AppColors.ink),
                  const SizedBox(width: 5),
                  const Icon(Icons.wifi_rounded, size: 15, color: AppColors.ink),
                  const SizedBox(width: 5),
                  const Icon(Icons.battery_full_rounded, size: 17, color: AppColors.ink),
                ],
              ),
            ),
          ),
          Positioned(
            top: 11,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 124,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1F1F24), width: 1),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 134,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0x73F4F4F5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ] else ...[
          // Left Dynamic Island pill in landscape
          Positioned(
            left: 11,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 36,
                  height: 124,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1F1F24), width: 1),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 7,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 210,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0x73F4F4F5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final bytes = await File(p).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Fraunces', ['assets/fonts/Fraunces-Variable.ttf', 'assets/fonts/Fraunces-Italic-Variable.ttf']);
  await load('HankenGrotesk', ['assets/fonts/HankenGrotesk-Variable.ttf', 'assets/fonts/HankenGrotesk-Italic-Variable.ttf']);
  const iconFont = '/home/hakan/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(iconFont).existsSync()) {
    await load('MaterialIcons', [iconFont]);
  }
}

Future<void> _capture(WidgetTester t, GlobalKey key, String filename) async {
  await t.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: _dpr);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('docs/screenshots/iphone15/$filename');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(data!.buffer.asUint8List());
  });
}

Future<void> _settle(WidgetTester t, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  testWidgets('render real iPhone 15 portrait and landscape screenshots', (t) async {
    debugDisableShadows = false;
    try {
    HttpOverrides.global = _PosterHttpOverrides();
    addTearDown(() => HttpOverrides.global = null);

    await t.runAsync(_loadFonts);

    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance
      ..tvMode = false
      ..uiScale = 1.0
      ..groupOrder = {}
      ..hiddenGroups = {};

    await Library.instance.use(_acc);
    await Library.instance.touch(url: 'http://demo.example/movie/u/p/1.mkv', title: 'Dune: Çöl Gezegeni Bölüm İki |2024| TR', logo: 'http://poster/dune', kind: Kind.movie);
    await Library.instance.savePosition('http://demo.example/movie/u/p/1.mkv', const Duration(hours: 1, minutes: 34), const Duration(hours: 2, minutes: 46));
    await Library.instance.touch(url: 'http://demo.example/series/u/p/13.mkv', title: 'Severance S01E03', logo: 'http://poster/sev', kind: Kind.series);
    await Library.instance.savePosition('http://demo.example/series/u/p/13.mkv', const Duration(minutes: 22), const Duration(minutes: 49));
    await Library.instance.touch(url: 'http://demo.example/movie/u/p/2.mkv', title: 'Oppenheimer |2023| TR', logo: 'http://poster/opp', kind: Kind.movie);
    await Library.instance.savePosition('http://demo.example/movie/u/p/2.mkv', const Duration(minutes: 45), const Duration(hours: 3));

    final client = _DemoClient();
    final liveItems = await client.live();
    final movieItems = await client.movies();
    final seriesItems = await client.series();
    for (final c in liveItems.take(4)) {
      await Library.instance.toggleFavorite(c);
    }
    await Library.instance.toggleFavorite(movieItems[0]);
    await Library.instance.toggleFavorite(movieItems[2]);
    final info = await client.authenticate();

    Future<void> renderShot(String name, Size size, FakeViewPadding pad, Widget child, {Future<void> Function()? afterPump}) async {
      final key = GlobalKey();
      final landscape = size.width > size.height;
      t.view.physicalSize = Size(size.width * _dpr, size.height * _dpr);
      t.view.devicePixelRatio = _dpr;
      t.view.padding = FakeViewPadding(top: pad.top * _dpr, bottom: pad.bottom * _dpr, left: pad.left * _dpr, right: pad.right * _dpr);
      t.view.viewPadding = t.view.padding;

      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
          home: _Iphone15Chrome(landscape: landscape, child: child),
        ),
      ));
      await _settle(t, 12);
      if (afterPump != null) {
        await afterPump();
        await _settle(t, 12);
      }
      // Let PosterImage's ResizeImage(NetworkImage) decode every visible poster asynchronously.
      for (var round = 0; round < 3; round++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
        await _settle(t, 4);
      }
      expect(t.takeException(), isNull, reason: 'clean layout for $name');
      await _capture(t, key, name);
    }

    // ─── PORTRAIT SHOTS (393 × 852) ───
    await renderShot('portrait_home.png', _portraitSize, _portraitPad, HomePage(client: client, info: info, account: _acc));
    await renderShot(
      'portrait_live.png',
      _portraitSize,
      _portraitPad,
      HomePage(client: client, info: info, account: _acc),
      afterPump: () => t.tap(find.byKey(const ValueKey('nav-live'))),
    );
    await renderShot(
      'portrait_movies.png',
      _portraitSize,
      _portraitPad,
      HomePage(client: client, info: info, account: _acc),
      afterPump: () => t.tap(find.byKey(const ValueKey('nav-movies'))),
    );
    await renderShot('portrait_detail.png', _portraitSize, _portraitPad, DetailPage(client: client, item: seriesItems.first));
    await renderShot(
      'portrait_settings.png',
      _portraitSize,
      _portraitPad,
      HomePage(client: client, info: info, account: _acc),
      afterPump: () => t.tap(find.byKey(const ValueKey('nav-settings'))),
    );

    final now = DateTime(2026, 11, 19, 23, 3);
    final liveProgs = [
      Programme(title: 'Ana Haber Bülteni', start: DateTime(2026, 11, 19, 22, 38), end: DateTime(2026, 11, 19, 23, 38)),
      Programme(title: 'Gece Kuşağı', start: DateTime(2026, 11, 19, 23, 38), end: DateTime(2026, 11, 20, 0, 38)),
    ];
    await renderShot(
      'portrait_player_live.png',
      _portraitSize,
      _portraitPad,
      Scaffold(
        backgroundColor: AppColors.video,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(center: Alignment(0.15, -0.1), radius: 1.0, colors: [Color(0xFF33235C), Color(0xFF100C1E), Colors.black]),
                  ),
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
                    programmes: liveProgs,
                    now: () => now,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PhonePlayerCompanion(
                live: true,
                title: 'TRT 1 HD',
                subtitle: 'Ulusal',
                index: 0,
                programmes: liveProgs,
                now: () => now,
                queueTitles: [for (final c in liveItems) c.name],
                onSelectQueue: (_) {},
                audioLabel: 'Türkçe',
                subtitleLabel: 'Altyazı: Kapalı',
                coverFit: false,
                onPickAudio: () {},
                onPickSubtitle: () {},
                onToggleOrientation: () {},
                onToggleFit: () {},
              ),
            ),
          ],
        ),
      ),
    );

    const sampleMenu = [
      GlassMenuItem(
        id: 'menu-audio',
        title: 'Ses parçası',
        subtitle: 'Türkçe',
        sfSymbol: 'speaker.wave.2',
        icon: Icons.audiotrack_rounded,
        children: [GlassMenuItem(id: 'audio:0', title: 'Türkçe', selected: true)],
      ),
      GlassMenuItem(
        id: 'menu-sub',
        title: 'Altyazı',
        subtitle: 'Kapalı',
        sfSymbol: 'captions.bubble',
        icon: Icons.subtitles_rounded,
        children: [GlassMenuItem(id: 'sub:0', title: 'Kapalı', selected: true)],
      ),
      GlassMenuItem(
        id: 'menu-rate',
        title: 'Oynatma hızı',
        subtitle: 'Normal',
        sfSymbol: 'gauge.with.needle',
        icon: Icons.speed_rounded,
        children: [GlassMenuItem(id: 'rate:1.0', title: 'Normal (1x)', selected: true)],
      ),
    ];

    await renderShot(
      'portrait_player_vod.png',
      _portraitSize,
      _portraitPad,
      Scaffold(
        backgroundColor: AppColors.video,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(center: Alignment(0.1, -0.1), radius: 1.0, colors: [Color(0xFF3E4A35), Color(0xFF1A2218), Colors.black]),
                  ),
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
                    duration: const Duration(hours: 2, seconds: 1),
                    buffer: const Duration(minutes: 10),
                    onSeek: (_) {},
                    osdText: '+10 sn',
                    menuItems: sampleMenu,
                    onMenuSelected: (_) {},
                  ),
                ),
              ),
            ),
            Expanded(
              child: PhonePlayerCompanion(
                live: false,
                title: 'Aşk Tesadüfleri Sever 2',
                index: 0,
                queueTitles: const ['Aşk Tesadüfleri Sever 2'],
                audioLabel: 'Otomatik',
                subtitleLabel: 'Altyazı: Kapalı',
                rateLabel: '1x',
                coverFit: false,
                onPickAudio: () {},
                onPickSubtitle: () {},
                onPickRate: () {},
                onGoTo: () {},
                onToggleOrientation: () {},
                onToggleFit: () {},
              ),
            ),
          ],
        ),
      ),
    );

    // ─── LANDSCAPE SHOTS (852 × 393) ───
    await renderShot('landscape_home.png', _landscapeSize, _landscapePad, HomePage(client: client, info: info, account: _acc));
    await renderShot(
      'landscape_live.png',
      _landscapeSize,
      _landscapePad,
      HomePage(client: client, info: info, account: _acc),
      afterPump: () => t.tap(find.byKey(const ValueKey('nav-live'))),
    );
    await renderShot(
      'landscape_movies.png',
      _landscapeSize,
      _landscapePad,
      HomePage(client: client, info: info, account: _acc),
      afterPump: () => t.tap(find.byKey(const ValueKey('nav-movies'))),
    );
    await renderShot('landscape_detail.png', _landscapeSize, _landscapePad, DetailPage(client: client, item: seriesItems.first));
    await renderShot(
      'landscape_player_live.png',
      _landscapeSize,
      _landscapePad,
      Scaffold(
        backgroundColor: AppColors.video,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(0.15, -0.05), radius: 0.95, colors: [Color(0xFF33235C), Color(0xFF100C1E), Colors.black]),
          ),
          child: PhonePlayerOverlay(
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
            programmes: liveProgs,
            now: () => now,
          ),
        ),
      ),
    );
    await renderShot(
      'landscape_player_vod.png',
      _landscapeSize,
      _landscapePad,
      Scaffold(
        backgroundColor: AppColors.video,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(0.05, -0.08), radius: 0.95, colors: [Color(0xFF422238), Color(0xFF150E1E), Colors.black]),
          ),
          child: PhonePlayerOverlay(
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
            position: const Duration(hours: 1, minutes: 34, seconds: 12),
            duration: const Duration(hours: 2, minutes: 46),
            buffer: const Duration(hours: 1, minutes: 55),
            onSeek: (_) {},
            menuItems: sampleMenu,
            onMenuSelected: (_) {},
            onPickAudio: () {},
            onPickSubtitle: () {},
            onPickRate: () {},
            onGoTo: () {},
            audioLabel: 'Türkçe',
            subtitleLabel: 'Altyazı',
            rateLabel: '1x',
          ),
        ),
      ),
    );
    await renderShot(
      'landscape_player_vod_scrub.png',
      _landscapeSize,
      _landscapePad,
      Scaffold(
        backgroundColor: AppColors.video,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(0.05, -0.08), radius: 0.95, colors: [Color(0xFF422238), Color(0xFF150E1E), Colors.black]),
          ),
          child: PhonePlayerOverlay(
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
            position: const Duration(hours: 1, minutes: 34, seconds: 18),
            duration: const Duration(hours: 2, minutes: 46),
            buffer: const Duration(hours: 1, minutes: 55),
            pending: true,
            onSeek: (_) {},
            osdText: '1:34:18  (+6 sn) · Hassas · 1 sn',
            menuItems: sampleMenu,
            onMenuSelected: (_) {},
            onPickAudio: () {},
            onPickSubtitle: () {},
            onPickRate: () {},
            onGoTo: () {},
            audioLabel: 'Türkçe',
            subtitleLabel: 'Altyazı',
            rateLabel: '1x',
          ),
        ),
      ),
    );

    addTearDown(t.view.reset);
    } finally {
      debugDisableShadows = true;
    }
  });
}
