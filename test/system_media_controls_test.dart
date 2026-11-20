import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iptv_app/src/player_session.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/system_media_controls.dart';
import 'package:iptv_app/src/system_pip.dart';
import 'package:iptv_app/src/xtream.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mediaChannel = MethodChannel('iptv/system_media_controls');
  const pipChannel = MethodChannel('iptv/system_pip');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.skipSecs = 10;
    PlayerSession.instance.debugReset();
    SystemMediaControls.instance.debugReset();
    SystemMediaControls.debugSupportedOverride = null;
    SystemPip.debugSupportedOverride = null;
  });

  tearDown(() {
    PlayerSession.instance.debugReset();
    SystemMediaControls.instance.debugReset();
    SystemMediaControls.debugSupportedOverride = null;
    SystemPip.debugSupportedOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mediaChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pipChannel, null);
  });

  group('buildSystemMediaState', () {
    test('formats Live TV with active EPG programme and disables seek', () {
      final now = DateTime(2026, 11, 20, 20, 15);
      final state = buildSystemMediaState(
        trackId: '/dev/nailhakan/iptv/track/t_1_0',
        rawTitle: 'TRT 1 HD',
        kind: Kind.live,
        playing: true,
        position: const Duration(seconds: 999),
        duration: const Duration(seconds: 1200),
        canGoNext: true,
        canGoPrevious: false,
        logo: 'https://cdn.example/trt1.png',
        group: 'TR/Ulusal ⚡ Ulusal Kanallar',
        programmes: [
          Programme(
            title: 'Ana Haber Bülteni',
            start: DateTime(2026, 11, 20, 20, 0),
            end: DateTime(2026, 11, 20, 21, 0),
          ),
        ],
        now: now,
      );

      expect(state.title, 'TRT 1 HD');
      expect(state.subtitle, 'Ana Haber Bülteni');
      expect(state.album, 'Ulusal Kanallar');
      expect(state.artUrl, 'https://cdn.example/trt1.png');
      expect(state.localUrl, isEmpty);
      expect(state.live, isTrue);
      expect(state.playing, isTrue);
      expect(state.canSeek, isFalse);
      expect(state.canGoNext, isTrue);
      expect(state.canGoPrevious, isFalse);
      expect(state.durationMs, const Duration(hours: 1).inMilliseconds);
      expect(state.positionMs, const Duration(minutes: 15).inMilliseconds);
      expect(state.rate, 1.0);
    });

    test('formats Live TV without EPG gracefully with zero duration', () {
      final state = buildSystemMediaState(
        trackId: '/dev/nailhakan/iptv/track/t_2_0',
        rawTitle: 'NTV',
        kind: Kind.live,
        playing: true,
        position: Duration.zero,
        duration: Duration.zero,
        canGoNext: false,
        canGoPrevious: true,
        group: 'Haber',
      );

      expect(state.title, 'NTV');
      expect(state.subtitle, 'Haber');
      expect(state.album, 'Canlı TV');
      expect(state.canSeek, isFalse);
      expect(state.durationMs, 0);
      expect(state.positionMs, 0);
    });

    test('formats VOD movie with parsed title, year, category, and local file URL only when offline', () {
      final movie = Item(
        id: 'm1',
        name: 'Dune |2024| TR-EN',
        logo: 'https://img.example/dune.jpg',
        group: 'TR/Film ⚡ Bilim Kurgu',
        kind: Kind.movie,
        url: 'http://secret.panel/movie/user/pass/42.mp4',
      );

      final streamed = buildSystemMediaState(
        trackId: '/dev/nailhakan/iptv/track/t_3_0',
        rawTitle: movie.name,
        kind: Kind.movie,
        playing: true,
        position: const Duration(minutes: 42),
        duration: const Duration(hours: 2, minutes: 46),
        canGoNext: false,
        canGoPrevious: false,
        item: movie,
        rate: 1.25,
        volumePercent: 75,
        skipSeconds: 15,
      );

      expect(streamed.title, 'Dune');
      expect(streamed.subtitle, '2024 · Bilim Kurgu');
      expect(streamed.album, isEmpty);
      expect(streamed.artUrl, 'https://img.example/dune.jpg');
      expect(streamed.localUrl, isEmpty); // Never leaks Xtream credentials
      expect(streamed.live, isFalse);
      expect(streamed.canSeek, isTrue);
      expect(streamed.positionMs, const Duration(minutes: 42).inMilliseconds);
      expect(streamed.durationMs, const Duration(hours: 2, minutes: 46).inMilliseconds);
      expect(streamed.rate, 1.25);
      expect(streamed.volume, closeTo(0.75, 0.001));
      expect(streamed.skipSeconds, 15);

      final offline = buildSystemMediaState(
        trackId: '/dev/nailhakan/iptv/track/t_3_0',
        rawTitle: movie.name,
        kind: Kind.movie,
        playing: true,
        position: const Duration(minutes: 10),
        duration: const Duration(hours: 2),
        canGoNext: false,
        canGoPrevious: false,
        item: movie,
        localPath: '/home/hakan/Downloads/IPTV/Dune.mp4',
      );
      expect(offline.localUrl, 'file:///home/hakan/Downloads/IPTV/Dune.mp4');
    });

    test('formats Series episode with clean title and Turkish season/episode subtitle', () {
      final state = buildSystemMediaState(
        trackId: '/dev/nailhakan/iptv/track/t_4_2',
        rawTitle: 'Breaking Bad S01E03',
        kind: Kind.series,
        playing: false,
        position: const Duration(minutes: 18),
        duration: const Duration(minutes: 48),
        canGoNext: true,
        canGoPrevious: true,
        logo: 'https://img.example/bb.jpg',
        group: 'Yabancı Diziler',
      );

      expect(state.title, 'Breaking Bad');
      expect(state.subtitle, '1. sezon 3. bölüm');
      expect(state.album, 'Yabancı Diziler');
      expect(state.live, isFalse);
      expect(state.playing, isFalse);
      expect(state.canSeek, isTrue);
      expect(state.canGoNext, isTrue);
      expect(state.canGoPrevious, isTrue);
    });

    test('sanitizeArtworkUrl accepts http/https/file and rejects unsafe schemes', () {
      expect(sanitizeArtworkUrl(' https://cdn.example/a.png '), 'https://cdn.example/a.png');
      expect(sanitizeArtworkUrl('http://cdn.example/a.png'), 'http://cdn.example/a.png');
      expect(sanitizeArtworkUrl('file:///tmp/cover.jpg'), 'file:///tmp/cover.jpg');
      expect(sanitizeArtworkUrl('javascript:alert(1)'), isEmpty);
      expect(sanitizeArtworkUrl('not-a-url'), isEmpty);
      expect(sanitizeArtworkUrl(''), isEmpty);
    });
  });

  group('SystemMediaControls MethodChannel bridge', () {
    test('dispatches incoming native commands to onCommand callback', () async {
      SystemMediaControls.debugSupportedOverride = true;
      final received = <SystemMediaCommand>[];
      SystemMediaControls.instance.onCommand = received.add;
      SystemMediaControls.instance.ensureInitialized();

      Future<void> simulateNative(String method, [Object? args]) async {
        const codec = StandardMethodCodec();
        final data = codec.encodeMethodCall(MethodCall(method, args));
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(mediaChannel.name, data, (_) {});
      }

      await simulateNative('play');
      await simulateNative('pause');
      await simulateNative('playPause');
      await simulateNative('stop');
      await simulateNative('next');
      await simulateNative('previous');
      await simulateNative('seek', {'positionMs': 95000});
      await simulateNative('seekBy', {'offsetMs': -15000});
      await simulateNative('setVolume', {'volume': 0.45});
      await simulateNative('setRate', {'rate': 1.5});
      await simulateNative('audioInterruptionBegan');
      await simulateNative('audioInterruptionEnded', {'shouldResume': true});
      await simulateNative('audioBecomingNoisy');

      expect(received.map((c) => c.action).toList(), [
        SystemMediaAction.play,
        SystemMediaAction.pause,
        SystemMediaAction.playPause,
        SystemMediaAction.stop,
        SystemMediaAction.next,
        SystemMediaAction.previous,
        SystemMediaAction.seek,
        SystemMediaAction.seekBy,
        SystemMediaAction.setVolume,
        SystemMediaAction.setRate,
        SystemMediaAction.audioInterruptionBegan,
        SystemMediaAction.audioInterruptionEnded,
        SystemMediaAction.audioBecomingNoisy,
      ]);
      expect(received[6].position, const Duration(seconds: 95));
      expect(received[7].offset, const Duration(seconds: -15));
      expect(received[8].volume, closeTo(0.45, 0.0001));
      expect(received[9].rate, closeTo(1.5, 0.0001));
      expect(received[11].shouldResume, isTrue);
    });
  });

  group('PlayerSession + SystemMediaControls integration', () {
    test('syncs metadata, handles transport/seek/volume/rate/interruptions, and clears on stop', () async {
      SystemMediaControls.debugSupportedOverride = true;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mediaChannel, (call) async {
        calls.add(call);
        return null;
      });

      final session = PlayerSession.instance;
      session.debugSetQueuePreview(
        queue: const [
          PlayerEntry(url: 'http://demo.example/s/1.mp4', title: 'Breaking Bad S01E01', logo: 'https://img.example/1.jpg'),
          PlayerEntry(url: 'http://demo.example/s/2.mp4', title: 'Breaking Bad S01E02', logo: 'https://img.example/2.jpg'),
        ],
        index: 0,
        kind: Kind.series,
        playing: true,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 50),
        emitMediaControls: true,
      );

      expect(calls.where((c) => c.method == 'update'), isNotEmpty);
      final initial = (calls.last.arguments as Map).cast<String, dynamic>();
      expect(initial['title'], 'Breaking Bad');
      expect(initial['subtitle'], '1. sezon 1. bölüm');
      expect(initial['playing'], isTrue);
      expect(initial['canGoNext'], isTrue);
      expect(initial['canGoPrevious'], isFalse);
      expect(initial['canSeek'], isTrue);

      // Pause & resume via remote commands
      await session.debugHandleMediaCommand(const SystemMediaCommand(SystemMediaAction.playPause));
      expect(session.isPlaying, isFalse);
      expect((calls.last.arguments as Map)['playing'], isFalse);

      await session.debugHandleMediaCommand(const SystemMediaCommand(SystemMediaAction.play));
      expect(session.isPlaying, isTrue);
      expect((calls.last.arguments as Map)['playing'], isTrue);

      // Seek & SeekBy with clamping
      await session.debugHandleMediaCommand(
        const SystemMediaCommand(SystemMediaAction.seek, position: Duration(minutes: 20)),
      );
      expect(session.position, const Duration(minutes: 20));
      expect(calls.last.method, 'seeked');
      expect((calls.last.arguments as Map)['positionMs'], const Duration(minutes: 20).inMilliseconds);

      await session.debugHandleMediaCommand(
        const SystemMediaCommand(SystemMediaAction.seekBy, offset: Duration(minutes: 100)),
      );
      expect(session.position, const Duration(minutes: 50)); // clamped to duration

      // Volume & Rate
      await session.debugHandleMediaCommand(
        const SystemMediaCommand(SystemMediaAction.setVolume, volume: 0.6),
      );
      expect(session.volume, closeTo(60.0, 0.01));
      await session.debugHandleMediaCommand(
        const SystemMediaCommand(SystemMediaAction.setRate, rate: 1.5),
      );
      expect(session.rate, closeTo(1.5, 0.01));

      // Next episode switches trackId and updates capabilities
      final prevTrackId = initial['trackId'];
      await session.debugHandleMediaCommand(const SystemMediaCommand(SystemMediaAction.next));
      expect(session.index, 1);
      final afterNext = (calls.last.arguments as Map).cast<String, dynamic>();
      expect(afterNext['subtitle'], '1. sezon 2. bölüm');
      expect(afterNext['canGoNext'], isFalse);
      expect(afterNext['canGoPrevious'], isTrue);
      expect(afterNext['trackId'], isNot(prevTrackId));

      // Audio interruption pauses and resumes when shouldResume == true
      await session.debugHandleMediaCommand(const SystemMediaCommand(SystemMediaAction.audioInterruptionBegan));
      expect(session.isPlaying, isFalse);
      await session.debugHandleMediaCommand(
        const SystemMediaCommand(SystemMediaAction.audioInterruptionEnded, shouldResume: true),
      );
      expect(session.isPlaying, isTrue);

      // AirPods unplugged (becoming noisy) pauses playback
      await session.debugHandleMediaCommand(const SystemMediaCommand(SystemMediaAction.audioBecomingNoisy));
      expect(session.isPlaying, isFalse);

      // Stop closes session and clears OS media controls
      await session.debugHandleMediaCommand(const SystemMediaCommand(SystemMediaAction.stop));
      expect(session.active, isFalse);
      expect(calls.last.method, 'clear');
    });

    test('Live TV rejects seek and setRate commands while supporting Next/Previous channel switching', () async {
      SystemMediaControls.debugSupportedOverride = true;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mediaChannel, (call) async {
        calls.add(call);
        return null;
      });

      final session = PlayerSession.instance;
      session.debugSetQueuePreview(
        queue: const [
          PlayerEntry(url: 'http://demo.example/live/1.ts', title: 'TRT 1 HD', group: 'Ulusal'),
          PlayerEntry(url: 'http://demo.example/live/2.ts', title: 'TRT Spor', group: 'Spor'),
        ],
        index: 0,
        kind: Kind.live,
        playing: true,
        emitMediaControls: true,
      );

      final countBefore = calls.length;
      await session.debugHandleMediaCommand(
        const SystemMediaCommand(SystemMediaAction.seek, position: Duration(seconds: 30)),
      );
      await session.debugHandleMediaCommand(
        const SystemMediaCommand(SystemMediaAction.seekBy, offset: Duration(seconds: 10)),
      );
      await session.debugHandleMediaCommand(
        const SystemMediaCommand(SystemMediaAction.setRate, rate: 2.0),
      );
      expect(calls.length, countBefore);
      expect(session.rate, 1.0);

      await session.debugHandleMediaCommand(const SystemMediaCommand(SystemMediaAction.next));
      expect(session.index, 1);
      expect((calls.last.arguments as Map)['title'], 'TRT Spor');

      await session.debugHandleMediaCommand(const SystemMediaCommand(SystemMediaAction.previous));
      expect(session.index, 0);
      expect((calls.last.arguments as Map)['title'], 'TRT 1 HD');
    });

    test('routes Lock Screen / AirPods commands to native iOS SystemPip when PiP is active', () async {
      SystemMediaControls.debugSupportedOverride = true;
      SystemPip.debugSupportedOverride = true;
      final mediaCalls = <MethodCall>[];
      final pipCalls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mediaChannel, (call) async {
        mediaCalls.add(call);
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pipChannel, (call) async {
        pipCalls.add(call);
        return null;
      });

      final session = PlayerSession.instance;
      session.debugSetQueuePreview(
        queue: const [
          PlayerEntry(url: 'http://demo.example/movie/1.mp4', title: 'Inception |2010|', logo: ''),
          PlayerEntry(url: 'http://demo.example/movie/2.mp4', title: 'Interstellar |2014|', logo: ''),
        ],
        index: 0,
        kind: Kind.movie,
        playing: true,
        position: const Duration(minutes: 12),
        duration: const Duration(hours: 2),
        systemPipActive: true,
        emitMediaControls: true,
      );

      await session.debugHandleMediaCommand(const SystemMediaCommand(SystemMediaAction.pause));
      expect(pipCalls.last.method, 'setPlaying');
      expect((pipCalls.last.arguments as Map)['playing'], isFalse);
      expect(session.isPlaying, isFalse);

      await session.debugHandleMediaCommand(
        const SystemMediaCommand(SystemMediaAction.seek, position: Duration(minutes: 30)),
      );
      expect(pipCalls.last.method, 'seekTo');
      expect((pipCalls.last.arguments as Map)['positionMs'], const Duration(minutes: 30).inMilliseconds);

      await session.debugHandleMediaCommand(
        const SystemMediaCommand(SystemMediaAction.seekBy, offset: Duration(seconds: 15)),
      );
      expect(pipCalls.last.method, 'skipBy');
      expect((pipCalls.last.arguments as Map)['offsetMs'], 15000);

      await session.debugHandleMediaCommand(const SystemMediaCommand(SystemMediaAction.next));
      expect(pipCalls.last.method, 'switchStream');
      expect((pipCalls.last.arguments as Map)['url'], 'http://demo.example/movie/2.mp4');
      expect((mediaCalls.last.arguments as Map)['title'], 'Interstellar');
    });
  });
}
