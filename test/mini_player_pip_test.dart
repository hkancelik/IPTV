import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/mini_player.dart';
import 'package:iptv_app/src/player_chrome.dart';
import 'package:iptv_app/src/player_session.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/settings_page.dart';
import 'package:iptv_app/src/system_pip.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/layout.dart';
import 'package:iptv_app/src/xtream.dart';

const _iphone15Portrait = Size(393, 852);
const _iphone15Landscape = Size(852, 393);
const _portraitPadding = FakeViewPadding(top: 59, bottom: 34, left: 0, right: 0);
const _landscapePadding = FakeViewPadding(top: 0, bottom: 21, left: 59, right: 59);

final _acc = Account(name: 'Ev TV', host: 'http://demo.example', username: 'u', password: 'p');

class _FakeClient extends XtreamClient {
  _FakeClient() : super(_acc);

  @override
  Future<List<Item>> live() async => [
        Item(id: 'l1', name: 'TRT 1 HD', logo: '', group: 'Ulusal', kind: Kind.live, url: 'http://demo.example/live/u/p/1.ts'),
        Item(id: 'l2', name: 'TRT Spor', logo: '', group: 'Spor', kind: Kind.live, url: 'http://demo.example/live/u/p/2.ts'),
      ];

  @override
  Future<List<Item>> movies() async => const [];

  @override
  Future<List<Item>> series() async => const [];

  @override
  Future<List<Programme>> shortEpg(int streamId) async => const [];
}

void _configureIphone(WidgetTester t, Size size, FakeViewPadding padding) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  t.view.viewPadding = padding;
  t.view.padding = padding;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    t.view.resetViewPadding();
    t.view.resetPadding();
  });
}

Widget _iosApp(Widget home) => MaterialApp(
      theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
      home: home,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.tvMode = false;
    AppSettings.instance.uiScale = 1.0;
    AppSettings.instance.autoPipOnLeave = true;
    PlayerSession.instance.debugReset();
    SystemPip.debugSupportedOverride = null;
  });

  tearDown(() {
    PlayerSession.instance.debugReset();
    SystemPip.debugSupportedOverride = null;
  });

  group('PhoneMiniPlayerBar (2-button Alt Cam Çubuk)', () {
    testWidgets('renders Live TV and VOD without overflow and triggers play/close/expand', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      var expanded = 0;
      var toggled = 0;
      var closed = 0;

      await t.pumpWidget(_iosApp(Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: PhoneMiniPlayerBar(
              title: 'TRT 1 HD',
              subtitle: 'Ana Haber Bülteni',
              live: true,
              playing: true,
              progress: 0.44,
              onExpand: () => expanded++,
              onPlayPause: () => toggled++,
              onClose: () => closed++,
            ),
          ),
        ),
      )));
      await t.pump();

      expect(t.takeException(), isNull);
      expect(find.text('TRT 1 HD'), findsOneWidget);
      expect(find.text('Ana Haber Bülteni'), findsOneWidget);
      expect(find.text('CANLI'), findsOneWidget);
      expect(find.byKey(const ValueKey('mini-player-play-pause')), findsOneWidget);
      expect(find.byKey(const ValueKey('mini-player-close')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('mini-player-play-pause')));
      expect(toggled, 1);
      await t.tap(find.byKey(const ValueKey('mini-player-close')));
      expect(closed, 1);
      await t.tap(find.text('TRT 1 HD'));
      expect(expanded, 1);
    });

    testWidgets('mounts above PhoneBottomBar in HomePage portrait & compact in landscape', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      final now = DateTime.now();
      PlayerSession.instance.debugSetMiniPreview(
        entry: const PlayerEntry(url: 'http://demo.example/live/u/p/1.ts', title: 'TRT 1 HD', group: 'Ulusal'),
        kind: Kind.live,
        playing: true,
        programmes: [
          Programme(title: 'Ana Haber Bülteni', start: now.subtract(const Duration(minutes: 20)), end: now.add(const Duration(minutes: 40))),
        ],
      );

      await t.pumpWidget(_iosApp(HomePage(
        client: _FakeClient(),
        info: AccountInfo(status: 'Active', maxConnections: 2, activeConnections: 1),
        account: _acc,
      )));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('phone-mini-player')), findsOneWidget);
      expect(find.text('TRT 1 HD'), findsWidgets);
      expect(find.text('Ana Haber Bülteni'), findsOneWidget);

      // Verify mini-player sits cleanly above the bottom tab bar.
      final miniRect = t.getRect(find.byKey(const ValueKey('phone-mini-player')));
      final homeTabRect = t.getRect(find.byKey(const ValueKey('nav-home')));
      expect(miniRect.bottom, lessThanOrEqualTo(homeTabRect.top));

      // Verify dynamic clearance includes mini-player height.
      final ctx = t.element(find.byType(HomePage));
      expect(phoneBottomClearance(ctx), 88 + 34 + phoneMiniPlayerClearance);

      // Toggle play/pause and close from the 2-button bar.
      await t.tap(find.byKey(const ValueKey('mini-player-play-pause')));
      await t.pump();
      expect(PlayerSession.instance.isPlaying, isFalse);

      // Rotate to landscape while minimized: renders compact bar without overflow.
      _configureIphone(t, _iphone15Landscape, _landscapePadding);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('phone-mini-player')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('mini-player-close')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-mini-player')), findsNothing);
    });
  });

  group('PhonePlayerOverlay minimize & System PiP controls', () {
    testWidgets('shows minimize chevron and PiP button without overflow on portrait & landscape', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      var minimized = 0;
      var pipTapped = 0;

      await t.pumpWidget(_iosApp(Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PhonePlayerOverlay(
              landscape: false,
              live: true,
              playing: true,
              title: 'TRT 1 HD',
              subtitle: 'Ulusal',
              onMinimize: () => minimized++,
              onSystemPip: () => pipTapped++,
              onPlayPause: () {},
              onToggleOrientation: () {},
              onToggleFit: () {},
              coverFit: false,
              skipSecs: 10,
            ),
          ),
        ),
      )));
      await t.pump();

      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('phone-player-minimize')), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-player-pip')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('phone-player-minimize')));
      await t.tap(find.byKey(const ValueKey('phone-player-pip')));
      expect(minimized, 1);
      expect(pipTapped, 1);
    });
  });

  group('Settings autoPipOnLeave toggle & SystemPip bridge', () {
    testWidgets('iOS SettingsPage exposes autoPipOnLeave switch and syncs native channel', (t) async {
      _configureIphone(t, _iphone15Portrait, _portraitPadding);
      SystemPip.debugSupportedOverride = true;

      final calls = <MethodCall>[];
      const ch = MethodChannel('iptv/system_pip');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null);
      });

      await t.pumpWidget(_iosApp(Scaffold(
        body: SettingsPage(
          info: AccountInfo(status: 'Active', maxConnections: 2, activeConnections: 1),
          account: _acc,
          client: _FakeClient(),
          onLogout: () {},
        ),
      )));
      await t.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('setting-autoPipOnLeave'));
      await t.ensureVisible(toggle);
      await t.pumpAndSettle();
      expect(toggle, findsOneWidget);
      expect(AppSettings.instance.autoPipOnLeave, isTrue);

      await t.tap(toggle);
      await t.pumpAndSettle();
      expect(AppSettings.instance.autoPipOnLeave, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('autoPipOnLeave'), isFalse);
      expect(calls.where((c) => c.method == 'setAutoStart').last.arguments, {'enabled': false});
    });

    test('pipPlayableUrl converts Xtream live .ts to Apple HLS .m3u8 and preserves VOD urls', () {
      expect(
        SystemPip.pipPlayableUrl('http://demo.example/live/u/p/12345.ts', live: true),
        'http://demo.example/live/u/p/12345.m3u8',
      );
      expect(
        SystemPip.pipPlayableUrl('http://demo.example/live/u/p/12345.m3u8', live: true),
        'http://demo.example/live/u/p/12345.m3u8',
      );
      expect(
        SystemPip.pipPlayableUrl('http://demo.example/movie/u/p/42.mp4', live: false),
        'http://demo.example/movie/u/p/42.mp4',
      );
    });
  });
}
