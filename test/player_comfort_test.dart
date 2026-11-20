import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/mini_player.dart';
import 'package:iptv_app/src/player_chrome.dart';
import 'package:iptv_app/src/player_comfort.dart';
import 'package:iptv_app/src/player_device_controls.dart';
import 'package:iptv_app/src/player_page.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/settings_page.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _iphone15Portrait = Size(393, 852);
const _iphone15Landscape = Size(852, 393);
const _portraitPadding = FakeViewPadding(top: 59, bottom: 34, left: 0, right: 0);
const _landscapePadding = FakeViewPadding(top: 0, bottom: 21, left: 59, right: 59);

final _acc = Account(name: 'Demo', host: 'http://demo.example', username: 'u', password: 'p');

void _configureView(WidgetTester t, Size size, FakeViewPadding pad) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  t.view.padding = pad;
  t.view.viewPadding = pad;
  addTearDown(t.view.reset);
}

Widget _iosApp(Widget home) => MaterialApp(
      theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
      home: home,
    );

Widget _desktopApp(Widget home) => MaterialApp(
      theme: buildAppTheme().copyWith(platform: TargetPlatform.linux),
      home: home,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance
      ..tvMode = false
      ..uiScale = 1.0
      ..autoNext = true
      ..deinterlace = 'auto';
    PlayerSession.instance.debugReset();
    PlayerDeviceControls.debugBrightnessSupportedOverride = null;
    PlayerDeviceControls.debugSystemVolumeSupportedOverride = null;
  });

  tearDown(() {
    PlayerSession.instance.debugReset();
    PlayerDeviceControls.debugBrightnessSupportedOverride = null;
    PlayerDeviceControls.debugSystemVolumeSupportedOverride = null;
  });

  group('player_comfort pure helpers', () {
    test('formatDelayMs formats zero, milliseconds, tenths, and hundredths cleanly', () {
      expect(formatDelayMs(0), '0 ms');
      expect(formatDelayMs(50), '+50 ms');
      expect(formatDelayMs(-200), '−200 ms');
      expect(formatDelayMs(1000), '+1.0 sn');
      expect(formatDelayMs(-1500), '−1.5 sn');
      expect(formatDelayMs(1250), '+1.25 sn');
      expect(mpvDelaySeconds(-250), '-0.250');
      expect(mpvDelaySeconds(1500), '1.500');
      expect(clampSubDelayMs(99999), maxSubDelayMs);
      expect(clampSubDelayMs(-99999), minSubDelayMs);
      expect(clampAudioDelayMs(99999), maxAudioDelayMs);
      expect(clampAudioDelayMs(-99999), minAudioDelayMs);
    });

    test('SleepTimerState produces compact short labels and minute-stable menu subtitles', () {
      const off = SleepTimerState.off();
      expect(off.isActive, isFalse);
      expect(off.shortLabel(), 'Kapalı');
      expect(off.menuSubtitle(), 'Kapalı');

      const halfHour = SleepTimerState.countdown(Duration(minutes: 29, seconds: 45));
      expect(halfHour.isActive, isTrue);
      expect(halfHour.shortLabel(), '29:45');
      expect(halfHour.menuSubtitle(), '30 dk kaldı');

      const underMinute = SleepTimerState.countdown(Duration(seconds: 32));
      expect(underMinute.shortLabel(), '00:32');
      expect(underMinute.menuSubtitle(), '< 1 dk kaldı');

      const overHour = SleepTimerState.countdown(Duration(hours: 1, minutes: 15));
      expect(overHour.shortLabel(), '1:15:00');
      expect(overHour.menuSubtitle(), '1 sa 15 dk kaldı');

      const end = SleepTimerState.endOfCurrent();
      expect(end.shortLabel(isSeries: true), 'Bölüm sonu');
      expect(end.shortLabel(isSeries: false), 'İçerik sonu');
      expect(end.menuSubtitle(isSeries: true), 'Bu bölüm bitince');
      expect(end.detailLabel(isSeries: true), 'Bu bölüm bitince durdurulacak');
    });

    test('classifyPhoneVerticalGesture separates brightness, volume, minimize, and edge guards', () {
      // Landscape (852 × 393)
      const land = Size(852, 393);
      expect(classifyPhoneVerticalGesture(localPosition: const Offset(120, 180), size: land, landscape: true), PhoneVerticalGesture.brightness);
      expect(classifyPhoneVerticalGesture(localPosition: const Offset(720, 180), size: land, landscape: true), PhoneVerticalGesture.volume);
      expect(classifyPhoneVerticalGesture(localPosition: const Offset(426, 180), size: land, landscape: true), PhoneVerticalGesture.none);
      // iOS top/bottom/side system margins ignored
      expect(classifyPhoneVerticalGesture(localPosition: const Offset(120, 18), size: land, landscape: true), PhoneVerticalGesture.none);
      expect(classifyPhoneVerticalGesture(localPosition: const Offset(720, 380), size: land, landscape: true), PhoneVerticalGesture.none);
      expect(classifyPhoneVerticalGesture(localPosition: const Offset(8, 180), size: land, landscape: true), PhoneVerticalGesture.none);
      // Visible VOD timeline bottom exclusion
      expect(
        classifyPhoneVerticalGesture(localPosition: const Offset(720, 350), size: land, landscape: true, controlsVisible: true, live: false),
        PhoneVerticalGesture.none,
      );
      // Brightness disabled on non-iOS devices
      expect(
        classifyPhoneVerticalGesture(localPosition: const Offset(120, 180), size: land, landscape: true, brightnessEnabled: false),
        PhoneVerticalGesture.none,
      );

      // Portrait 16:9 (393 × 221)
      const port = Size(393, 221);
      expect(classifyPhoneVerticalGesture(localPosition: const Offset(40, 110), size: port, landscape: false), PhoneVerticalGesture.brightness);
      expect(classifyPhoneVerticalGesture(localPosition: const Offset(196, 110), size: port, landscape: false), PhoneVerticalGesture.minimize);
      expect(classifyPhoneVerticalGesture(localPosition: const Offset(350, 110), size: port, landscape: false), PhoneVerticalGesture.volume);
      // Without hardware brightness, left zone falls back to minimize
      expect(
        classifyPhoneVerticalGesture(localPosition: const Offset(40, 110), size: port, landscape: false, brightnessEnabled: false),
        PhoneVerticalGesture.minimize,
      );
    });

    test('applyVerticalDragDelta maps upward drags to increases and clamps to [0, 1]', () {
      final raised = applyVerticalDragDelta(currentValue: 0.5, deltaDy: -100, viewportHeight: 393);
      expect(raised, greaterThan(0.8));
      expect(applyVerticalDragDelta(currentValue: 0.9, deltaDy: -200, viewportHeight: 393), 1.0);
      expect(applyVerticalDragDelta(currentValue: 0.1, deltaDy: 200, viewportHeight: 393), 0.0);
    });
  });

  group('PlayerDeviceControls MethodChannel bridge', () {
    test('bridges brightness and system volume over iptv/device_controls channel', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      PlayerDeviceControls.debugBrightnessSupportedOverride = true;
      PlayerDeviceControls.debugSystemVolumeSupportedOverride = true;

      final calls = <MethodCall>[];
      const ch = MethodChannel('iptv/device_controls');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
        calls.add(call);
        return switch (call.method) {
          'getBrightness' => 0.42,
          'getVolume' => 0.65,
          'setVolume' => true,
          _ => null,
        };
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));

      expect(await PlayerDeviceControls.instance.getBrightness(), closeTo(0.42, 0.001));
      await PlayerDeviceControls.instance.setBrightness(1.5);
      expect(await PlayerDeviceControls.instance.getVolume(fallbackPlayerVolume: 100), closeTo(0.65, 0.001));
      expect(await PlayerDeviceControls.instance.setVolume(-0.2), isTrue);
      await PlayerDeviceControls.instance.endVolumeGesture();

      expect(calls.map((c) => c.method).toList(), ['getBrightness', 'setBrightness', 'getVolume', 'setVolume', 'endVolumeGesture']);
      expect((calls[1].arguments as Map)['value'], 1.0);
      expect((calls[3].arguments as Map)['value'], 0.0);
    });

    test('falls back safely when device controls are unsupported', () async {
      PlayerDeviceControls.debugBrightnessSupportedOverride = false;
      PlayerDeviceControls.debugSystemVolumeSupportedOverride = false;

      expect(await PlayerDeviceControls.instance.getBrightness(fallback: 0.7), closeTo(0.7, 0.001));
      expect(await PlayerDeviceControls.instance.getVolume(fallbackPlayerVolume: 45), closeTo(0.45, 0.001));
      expect(await PlayerDeviceControls.instance.setVolume(0.8), isFalse);
    });
  });

  group('PlayerSession comfort state (delays, deinterlace, 2x hold, sleep timer)', () {
    test('sub-delay, audio-delay, and deinterlace write mpv properties and delays reset on switchTo', () async {
      final writes = <(String, String)>[];
      PlayerSession.instance.debugMpvPropertySink = (k, v) async => writes.add((k, v));
      PlayerSession.instance.debugSetQueuePreview(
        queue: const [
          PlayerEntry(url: 'http://demo/ep1.mkv', title: 'Dizi S01E01'),
          PlayerEntry(url: 'http://demo/ep2.mkv', title: 'Dizi S01E02'),
        ],
        kind: Kind.series,
      );

      await PlayerSession.instance.adjustSubDelayMs(500);
      await PlayerSession.instance.adjustSubDelayMs(-100);
      expect(PlayerSession.instance.subDelayMs, 400);
      expect(PlayerSession.instance.hasDelayOffset, isTrue);

      await PlayerSession.instance.adjustAudioDelayMs(-150);
      expect(PlayerSession.instance.audioDelayMs, -150);

      await PlayerSession.instance.setDeinterlace('yes');
      expect(AppSettings.instance.deinterlace, 'yes');
      expect(writes, contains(('sub-delay', '0.400')));
      expect(writes, contains(('audio-delay', '-0.150')));
      expect(writes, contains(('deinterlace', 'yes')));

      // Switching episodes resets per-stream delays while keeping deinterlace setting.
      writes.clear();
      await PlayerSession.instance.switchTo(1);
      expect(PlayerSession.instance.subDelayMs, 0);
      expect(PlayerSession.instance.audioDelayMs, 0);
      expect(PlayerSession.instance.hasDelayOffset, isFalse);
      expect(writes, contains(('sub-delay', '0.000')));
      expect(writes, contains(('audio-delay', '0.000')));
      expect(writes, contains(('deinterlace', 'yes')));
    });

    test('2x temporary speed hold boosts VOD, restores original rate, and refuses Live TV', () async {
      // VOD movie at custom 1.25x rate
      PlayerSession.instance.debugSetQueuePreview(
        queue: const [PlayerEntry(url: 'http://demo/movie.mkv', title: 'Film')],
        kind: Kind.movie,
        rate: 1.25,
      );

      expect(await PlayerSession.instance.beginTempSpeedHold(), isTrue);
      expect(PlayerSession.instance.isTempSpeedHolding, isTrue);
      expect(PlayerSession.instance.rate, 2.0);

      await PlayerSession.instance.endTempSpeedHold();
      expect(PlayerSession.instance.isTempSpeedHolding, isFalse);
      expect(PlayerSession.instance.rate, 1.25);

      // Live TV rejects temporary 2x hold
      PlayerSession.instance.debugSetQueuePreview(
        queue: const [PlayerEntry(url: 'http://demo/live/1.ts', title: 'TRT 1')],
        kind: Kind.live,
        rate: 1.0,
      );
      expect(await PlayerSession.instance.beginTempSpeedHold(), isFalse);
      expect(PlayerSession.instance.isTempSpeedHolding, isFalse);
      expect(PlayerSession.instance.rate, 1.0);
    });

    test('sleep timer pauses VOD on expiry and extends cleanly', () async {
      var fakeNow = DateTime(2026, 11, 20, 23, 0, 0);
      PlayerSession.instance.debugSetQueuePreview(
        queue: const [PlayerEntry(url: 'http://demo/movie.mkv', title: 'Film')],
        kind: Kind.movie,
        playing: true,
      );

      PlayerSession.instance.setSleepTimer(const Duration(seconds: 2), now: () => fakeNow);
      expect(PlayerSession.instance.sleepTimer.value.mode, SleepTimerMode.countdown);
      expect(PlayerSession.instance.sleepTimer.value.remaining, const Duration(seconds: 2));

      PlayerSession.instance.extendSleepTimer(const Duration(minutes: 15), now: () => fakeNow);
      expect(PlayerSession.instance.sleepTimer.value.remaining!.inSeconds, 15 * 60 + 2);

      // Reset to 1 second and let wall clock + timer fire.
      PlayerSession.instance.setSleepTimer(const Duration(seconds: 1), now: () => fakeNow);
      fakeNow = fakeNow.add(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 1150));

      expect(PlayerSession.instance.sleepTimer.value.isActive, isFalse);
      expect(PlayerSession.instance.active, isTrue);
      expect(PlayerSession.instance.isPlaying, isFalse);
      expect(PlayerSession.instance.comfortNotice.value, contains('Uyku zamanlayıcısı'));
    });

    test('sleep timer closes Live TV session on expiry to release IPTV connection slot', () async {
      var fakeNow = DateTime(2026, 11, 20, 23, 0, 0);
      PlayerSession.instance.debugSetQueuePreview(
        queue: const [
          PlayerEntry(url: 'http://demo/live/1.ts', title: 'TRT 1'),
          PlayerEntry(url: 'http://demo/live/2.ts', title: 'NTV'),
        ],
        kind: Kind.live,
        playing: true,
      );

      PlayerSession.instance.setSleepTimer(const Duration(seconds: 1), now: () => fakeNow);
      // Channel zap preserves active countdown timer!
      await PlayerSession.instance.switchTo(1);
      expect(PlayerSession.instance.sleepTimer.value.isActive, isTrue);

      fakeNow = fakeNow.add(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 1150));

      expect(PlayerSession.instance.active, isFalse);
      expect(PlayerSession.instance.sleepTimer.value.isActive, isFalse);
    });

    test('sleep timer endOfCurrent intercepts series completion before autoNext', () {
      PlayerSession.instance.debugSetQueuePreview(
        queue: const [
          PlayerEntry(url: 'http://demo/ep1.mkv', title: 'Dizi S01E01'),
          PlayerEntry(url: 'http://demo/ep2.mkv', title: 'Dizi S01E02'),
        ],
        kind: Kind.series,
        playing: true,
      );

      PlayerSession.instance.setSleepAtEndOfCurrent();
      expect(PlayerSession.instance.sleepTimer.value.mode, SleepTimerMode.endOfCurrent);

      PlayerSession.instance.debugHandleCompleted();
      expect(PlayerSession.instance.countdown.value, isNull);
      expect(PlayerSession.instance.sleepTimer.value.isActive, isFalse);
      expect(PlayerSession.instance.isPlaying, isFalse);
      expect(PlayerSession.instance.comfortNotice.value, contains('Bölüm bitti'));
    });
  });

  group('PhoneVideoGestureSurface (iPhone brightness/volume gestures + 2x hold)', () {
    testWidgets('landscape left drag changes brightness, right drag changes volume, and HUD shows cleanly', (t) async {
      _configureView(t, _iphone15Landscape, _landscapePadding);
      var brightness = 0.5;
      var volume = 0.4;
      var volumeEnded = 0;

      await t.pumpWidget(_iosApp(Scaffold(
        backgroundColor: Colors.black,
        body: PhoneVideoGestureSurface(
          landscape: true,
          live: false,
          controlsVisible: false,
          enabled: true,
          brightnessEnabled: true,
          onTap: () {},
          onDoubleTapZone: (_, _) {},
          onSpeedHoldStart: () async => true,
          onSpeedHoldEnd: () async {},
          readBrightness: () async => brightness,
          writeBrightness: (v) async => brightness = v,
          readVolume: () async => volume,
          writeVolume: (v) async => volume = v,
          onVolumeGestureEnd: () => volumeEnded++,
          child: const SizedBox.expand(),
        ),
      )));

      // Left-side upward drag increases brightness and renders PhoneGestureHud.
      final leftGesture = await t.startGesture(const Offset(160, 260));
      for (var i = 0; i < 6; i++) {
        await leftGesture.moveBy(const Offset(0, -20));
        await t.pump();
      }
      expect(brightness, greaterThan(0.75));
      expect(find.byKey(const ValueKey('phone-gesture-hud')), findsOneWidget);
      await leftGesture.up();
      await t.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('phone-gesture-hud')), findsNothing);

      // Right-side downward drag decreases volume and calls onVolumeGestureEnd.
      final rightGesture = await t.startGesture(const Offset(700, 140));
      for (var i = 0; i < 6; i++) {
        await rightGesture.moveBy(const Offset(0, 20));
        await t.pump();
      }
      expect(volume, lessThan(0.25));
      expect(find.byKey(const ValueKey('phone-gesture-hud')), findsOneWidget);
      await rightGesture.up();
      await t.pump();
      expect(volumeEnded, 1);
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
    });

    testWidgets('portrait separates left brightness, center minimize swipe, and right volume', (t) async {
      _configureView(t, _iphone15Portrait, _portraitPadding);
      var brightness = 0.5;
      var volume = 0.5;
      var minimized = 0;

      await t.pumpWidget(_iosApp(Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PhoneVideoGestureSurface(
              landscape: false,
              live: false,
              controlsVisible: false,
              enabled: true,
              brightnessEnabled: true,
              onTap: () {},
              onDoubleTapZone: (_, _) {},
              onMinimizeSwipe: () => minimized++,
              onSpeedHoldStart: () async => true,
              onSpeedHoldEnd: () async {},
              readBrightness: () async => brightness,
              writeBrightness: (v) async => brightness = v,
              readVolume: () async => volume,
              writeVolume: (v) async => volume = v,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      )));

      final surfaceRect = t.getRect(find.byKey(const ValueKey('phone-video-gesture-surface')));

      // Center downward swipe triggers minimize without touching brightness or volume.
      await t.flingFrom(
        Offset(surfaceRect.left + surfaceRect.width * 0.5, surfaceRect.top + 40),
        const Offset(0, 110),
        700,
      );
      await t.pump();
      expect(minimized, 1);
      expect(brightness, 0.5);
      expect(volume, 0.5);

      // Left third drag adjusts brightness without minimizing.
      final leftG = await t.startGesture(Offset(surfaceRect.left + 40, surfaceRect.top + 160));
      for (var i = 0; i < 5; i++) {
        await leftG.moveBy(const Offset(0, -18));
        await t.pump();
      }
      await leftG.up();
      await t.pump(const Duration(seconds: 1));
      expect(brightness, greaterThan(0.7));
      expect(minimized, 1);
    });

    testWidgets('long-press activates 2x hold badge on VOD and restores speed on release, ignored on Live TV', (t) async {
      _configureView(t, _iphone15Landscape, _landscapePadding);
      var started = 0;
      var ended = 0;

      Widget buildSurface({required bool live}) => _iosApp(Scaffold(
            backgroundColor: Colors.black,
            body: PhoneVideoGestureSurface(
              landscape: true,
              live: live,
              controlsVisible: false,
              enabled: true,
              brightnessEnabled: true,
              onTap: () {},
              onDoubleTapZone: (_, _) {},
              onSpeedHoldStart: () async {
                started++;
                return true;
              },
              onSpeedHoldEnd: () async => ended++,
              readBrightness: () async => 0.5,
              writeBrightness: (_) async {},
              readVolume: () async => 0.5,
              writeVolume: (_) async {},
              child: const SizedBox.expand(),
            ),
          ));

      await t.pumpWidget(buildSurface(live: false));
      final hold = await t.startGesture(const Offset(420, 200));
      await t.pump(const Duration(milliseconds: 650));
      expect(started, 1);
      expect(find.byKey(const ValueKey('speed-hold-badge')), findsOneWidget);
      expect(find.text('2× Hızlı oynatma'), findsOneWidget);

      await hold.up();
      await t.pump();
      expect(ended, 1);
      expect(find.byKey(const ValueKey('speed-hold-badge')), findsNothing);

      // Live TV ignores 2x hold
      await t.pumpWidget(buildSurface(live: true));
      final liveHold = await t.startGesture(const Offset(420, 200));
      await t.pump(const Duration(milliseconds: 650));
      expect(started, 1);
      expect(find.byKey(const ValueKey('speed-hold-badge')), findsNothing);
      await liveHold.up();
      await t.pump();
    });
  });

  group('Sync, Deinterlace, and Sleep Timer UI widgets & SettingsPage', () {
    testWidgets('showPlayerSyncModal adjusts sub-delay, audio-delay, and deinterlace live on iPhone & Desktop', (t) async {
      final writes = <(String, String)>[];
      PlayerSession.instance.debugMpvPropertySink = (k, v) async => writes.add((k, v));
      PlayerSession.instance.debugSetQueuePreview(
        queue: const [PlayerEntry(url: 'http://demo/movie.mkv', title: 'Film')],
        kind: Kind.movie,
      );

      _configureView(t, _iphone15Portrait, _portraitPadding);
      await t.pumpWidget(_iosApp(Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showPlayerSyncModal(ctx, useSheet: true),
              child: const Text('Open Sync'),
            ),
          ),
        ),
      )));

      await t.tap(find.text('Open Sync'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Senkron ve görüntü'), findsOneWidget);

      await t.tap(find.text('+0.5 sn'));
      await t.pump();
      expect(PlayerSession.instance.subDelayMs, 500);
      expect(find.descendant(of: find.byKey(const ValueKey('sync-sub-delay-value')), matching: find.text('+500 ms')), findsOneWidget);

      await t.tap(find.text('−50 ms'));
      await t.pump();
      expect(PlayerSession.instance.audioDelayMs, -50);
      expect(find.descendant(of: find.byKey(const ValueKey('sync-audio-delay-value')), matching: find.text('−50 ms')), findsOneWidget);

      await t.tap(find.descendant(of: find.byKey(const ValueKey('sync-deinterlace')), matching: find.text('Açık')));
      await t.pump();
      expect(AppSettings.instance.deinterlace, 'yes');
      expect(writes, contains(('deinterlace', 'yes')));

      await t.tap(find.byKey(const ValueKey('sync-sub-delay-reset')));
      await t.pump();
      expect(PlayerSession.instance.subDelayMs, 0);
      expect(t.takeException(), isNull);
    });

    testWidgets('showSleepTimerModal selects presets, shows active banner, extends, and cancels cleanly', (t) async {
      PlayerSession.instance.debugSetQueuePreview(
        queue: const [PlayerEntry(url: 'http://demo/ep1.mkv', title: 'Dizi S01E01')],
        kind: Kind.series,
      );

      _configureView(t, _iphone15Portrait, _portraitPadding);
      await t.pumpWidget(_iosApp(Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showSleepTimerModal(ctx, useSheet: true, live: false, isSeries: true),
              child: const Text('Open Sleep'),
            ),
          ),
        ),
      )));

      await t.tap(find.text('Open Sleep'));
      await t.pumpAndSettle();
      expect(find.text('30 dakika'), findsOneWidget);
      expect(find.text('Bu bölüm bitince'), findsOneWidget);

      await t.tap(find.text('30 dakika'));
      await t.pumpAndSettle();
      expect(PlayerSession.instance.sleepTimer.value.mode, SleepTimerMode.countdown);

      // Reopen: shows active banner with +15 dk uzat and İptal et
      await t.tap(find.text('Open Sleep'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('sleep-timer-active-banner')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('sleep-timer-extend')));
      await t.pump();
      expect(PlayerSession.instance.sleepTimer.value.remaining!.inMinutes, greaterThanOrEqualTo(44));

      await t.tap(find.byKey(const ValueKey('sleep-timer-cancel')));
      await t.pumpAndSettle();
      expect(PlayerSession.instance.sleepTimer.value.isActive, isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets('PhonePlayerOverlay, PhonePlayerCompanion, and PhoneMiniPlayerSlot display active comfort indicators cleanly', (t) async {
      _configureView(t, _iphone15Landscape, _landscapePadding);
      var sleepTapped = 0;
      await t.pumpWidget(_iosApp(Scaffold(
        backgroundColor: Colors.black,
        body: PhonePlayerOverlay(
          landscape: true,
          live: false,
          playing: true,
          title: 'Dune',
          onPlayPause: () {},
          onToggleOrientation: () {},
          onToggleFit: () {},
          coverFit: false,
          sleepTimerLabel: '29:45',
          onOpenSleepTimer: () => sleepTapped++,
        ),
      )));
      await t.pump();
      expect(find.byKey(const ValueKey('phone-player-sleep-chip')), findsOneWidget);
      expect(find.text('29:45'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('phone-player-sleep-chip')));
      expect(sleepTapped, 1);
      expect(t.takeException(), isNull);

      // Portrait companion quick strip shows Senkron and active Uyku button
      _configureView(t, _iphone15Portrait, _portraitPadding);
      await t.pumpWidget(_iosApp(Scaffold(
        body: PhonePlayerCompanion(
          live: false,
          title: 'Dune',
          index: 0,
          queueTitles: const ['Dune'],
          audioLabel: 'Türkçe',
          subtitleLabel: 'Kapalı',
          coverFit: false,
          onPickAudio: () {},
          onPickSubtitle: () {},
          onToggleOrientation: () {},
          onToggleFit: () {},
          hasDelayOffset: true,
          onOpenSync: () {},
          sleepTimerLabel: '29:45',
          onOpenSleepTimer: () {},
        ),
      )));
      await t.pump();
      final horizontalScrollable = find.descendant(
        of: find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal),
        matching: find.byType(Scrollable),
      );
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('phone-companion-sync')),
        180,
        scrollable: horizontalScrollable,
      );
      expect(find.byKey(const ValueKey('phone-companion-sync')), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('phone-companion-sleep')),
        180,
        scrollable: horizontalScrollable,
      );
      expect(find.byKey(const ValueKey('phone-companion-sleep')), findsOneWidget);
      expect(t.takeException(), isNull);

      // Minimized Mini Player shows active sleep countdown in subtitle
      PlayerSession.instance.debugSetMiniPreview(
        entry: const PlayerEntry(url: 'http://demo/live/1.ts', title: 'TRT 1 HD', group: 'Ulusal'),
        kind: Kind.live,
      );
      PlayerSession.instance.setSleepTimer(const Duration(minutes: 25));
      await t.pumpWidget(_iosApp(Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PhoneMiniPlayerSlot(onExpand: () {}),
        ),
      )));
      await t.pump();
      expect(find.textContaining('☾ 25:00'), findsOneWidget);
      expect(t.takeException(), isNull);
      PlayerSession.instance.cancelSleepTimer();
    });

    testWidgets('Desktop Sync & Sleep Timer dialogs render without overflow and Live TV omits end-of-current option', (t) async {
      PlayerSession.instance.debugSetQueuePreview(
        queue: const [PlayerEntry(url: 'http://demo/live/1.ts', title: 'TRT 1 HD')],
        kind: Kind.live,
      );
      _configureView(t, const Size(1280, 720), FakeViewPadding.zero);
      await t.pumpWidget(_desktopApp(Scaffold(
        body: Builder(
          builder: (ctx) => Row(
            children: [
              ElevatedButton(
                onPressed: () => showPlayerSyncModal(ctx, useSheet: false),
                child: const Text('Sync Dialog'),
              ),
              ElevatedButton(
                onPressed: () => showSleepTimerModal(ctx, useSheet: false, live: true, isSeries: false),
                child: const Text('Sleep Dialog'),
              ),
            ],
          ),
        ),
      )));

      await t.tap(find.text('Sync Dialog'));
      await t.pumpAndSettle();
      expect(find.text('Altyazı gecikmesi'), findsOneWidget);
      expect(find.text('Ses gecikmesi'), findsOneWidget);
      expect(find.text('Tarama giderme (Deinterlace)'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Kapat'));
      await t.pumpAndSettle();

      await t.tap(find.text('Sleep Dialog'));
      await t.pumpAndSettle();
      expect(find.text('15 dakika'), findsOneWidget);
      expect(find.text('Bu film bitince'), findsNothing);
      expect(find.text('Bu bölüm bitince'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('PhoneGestureHud never overlaps visible PhonePlayerOverlay top bar or center controls on iPhone SE/15', (t) async {
      for (final (size, pad, landscape) in [
        (const Size(375, 667), const FakeViewPadding(top: 20, bottom: 0, left: 0, right: 0), false),
        (_iphone15Portrait, _portraitPadding, false),
        (_iphone15Landscape, _landscapePadding, true),
      ]) {
        _configureView(t, size, pad);
        final surface = PhoneVideoGestureSurface(
          landscape: landscape,
          live: false,
          controlsVisible: true,
          enabled: true,
          brightnessEnabled: true,
          onTap: () {},
          onDoubleTapZone: (_, _) {},
          onSpeedHoldStart: () async => true,
          onSpeedHoldEnd: () async {},
          readBrightness: () async => 0.5,
          writeBrightness: (_) async {},
          readVolume: () async => 0.5,
          writeVolume: (_) async {},
          child: PhonePlayerOverlay(
            landscape: landscape,
            live: false,
            playing: true,
            title: 'Dune',
            onPlayPause: () {},
            onToggleOrientation: () {},
            onToggleFit: () {},
            coverFit: false,
          ),
        );
        await t.pumpWidget(_iosApp(Scaffold(
          backgroundColor: Colors.black,
          body: landscape ? surface : SafeArea(bottom: false, child: AspectRatio(aspectRatio: 16 / 9, child: surface)),
        )));
        await t.pump();

        final box = t.getRect(find.byKey(const ValueKey('phone-video-gesture-surface')));
        final drag = await t.startGesture(Offset(box.left + 32, box.top + box.height * 0.5));
        for (var i = 0; i < 4; i++) {
          await drag.moveBy(const Offset(0, -15));
          await t.pump();
        }
        final topRect = t.getRect(find.byKey(const ValueKey('phone-player-top-bar')));
        final centerRect = t.getRect(find.byKey(const ValueKey('phone-player-center-controls')));
        final hudRect = t.getRect(find.byKey(const ValueKey('phone-gesture-hud')));

        expect(hudRect.overlaps(topRect), isFalse);
        expect(hudRect.overlaps(centerRect), isFalse);
        await drag.up();
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
      }
    });

    testWidgets('SettingsPage shows deinterlace control and desktop comfort shortcuts', (t) async {
      _configureView(t, const Size(1500, 900), FakeViewPadding.zero);
      await t.pumpWidget(_desktopApp(Scaffold(
        body: SettingsPage(
          info: AccountInfo(status: 'Active', maxConnections: 1),
          account: _acc,
          client: XtreamClient(_acc),
          onLogout: () {},
        ),
      )));
      await t.pump();

      final deint = find.byKey(const ValueKey('setting-deinterlace'));
      await t.ensureVisible(deint);
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: deint, matching: find.text('Kapalı')));
      await t.pump();
      expect(AppSettings.instance.deinterlace, 'no');

      // Verify new keyboard shortcuts are documented on desktop
      final shortcutsKey = find.text('Z / X');
      await t.ensureVisible(shortcutsKey);
      await t.pumpAndSettle();
      expect(find.text('Z / X'), findsOneWidget);
      expect(find.text('J / K'), findsOneWidget);
      expect(find.text('Tarama giderme (Deinterlace)'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  });
}
