import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/accounts.dart';
import 'package:iptv_app/src/detail_page.dart';
import 'package:iptv_app/src/downloads.dart';
import 'package:iptv_app/src/downloads_page.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/login_page.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/settings_page.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeClient extends XtreamClient {
  _FakeClient(super.acc);

  @override
  Future<AccountInfo> authenticate() async => AccountInfo(status: 'Active', maxConnections: 1);

  @override
  Future<List<Item>> live() async => const [];

  @override
  Future<List<Item>> movies() async => const [];

  @override
  Future<List<Item>> series() async => const [];

  @override
  Future<Details> vodDetails(int streamId) async => Details(
        plot: 'Çevrimdışı indirme testi.',
        year: '2024',
        duration: '02:00:00',
        genre: 'Bilim Kurgu',
      );

  @override
  Future<SeriesData> seriesData(int seriesId) async => SeriesData(
        Details(plot: 'Dizi açıklaması', year: '2024'),
        [
          Episode(season: 1, number: 1, title: 'Başlangıç', url: '${acc.host}/series/${acc.username}/${acc.password}/101.mkv'),
          Episode(season: 1, number: 2, title: 'Devam', url: '${acc.host}/series/${acc.username}/${acc.password}/102.mkv'),
        ],
      );
}

class _NoopEngine implements DownloadEngine {
  DownloadEngineCallbacks? cb;
  final List<String> startedIds = [];
  final List<String> pausedIds = [];

  @override
  void bind(DownloadEngineCallbacks callbacks) => cb = callbacks;

  @override
  Future<String?> defaultBaseDirectory() async => '/tmp/iptv_noop_dl';

  @override
  Future<void> start({required String id, required String url, required String destinationPath, required String userAgent, int totalBytes = 0, int maxConnections = 6}) async {
    startedIds.add(id);
  }

  @override
  Future<void> pause({required String id, required String destinationPath}) async {
    pausedIds.add(id);
    cb?.onPaused(id);
  }

  @override
  Future<void> cancel({required String id, required String destinationPath}) async {}

  @override
  Future<List<NativeTaskSnapshot>> syncTasks() async => const [];

  @override
  void dispose() {}
}

Future<void> _waitUntil(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not satisfied within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  group('Download helpers', () {
    test('portableKeyOfUrl strips host and credentials', () {
      final acc = Account(name: 'Ev', host: 'http://tv.example:8080', username: 'alice', password: 'secret');
      expect(portableKeyOfUrl('http://tv.example:8080/movie/alice/secret/42.mkv', account: acc), 'movie/42.mkv');
      expect(portableKeyOfUrl('http://other.example/series/bob/pw/99.mp4'), 'series/99.mp4');
      expect(portableKeyOfUrl('movie/42.mkv'), 'movie/42.mkv');
    });

    test('isHlsPlaylistUrl detects .m3u8 streams', () {
      expect(isHlsPlaylistUrl('http://x/live/u/p/1.m3u8'), isTrue);
      expect(isHlsPlaylistUrl('http://x/movie/u/p/1.mkv'), isFalse);
      expect(isHlsPlaylistUrl('http://x/movie/u/p/1.mp4?token=abc'), isFalse);
    });

    test('sanitizeFileName removes illegal filesystem chars and keeps Turkish letters', () {
      expect(sanitizeFileName('Dune: Çöl/Gezegeni? *2024*.'), 'Dune Çöl Gezegeni 2024');
      expect(sanitizeFileName('   '), 'video');
    });

    test('formatBytes uses Turkish decimal comma formatting', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512 * 1024), '512 KB');
      expect(formatBytes((1.5 * 1024 * 1024).round()), '1,5 MB');
      expect(formatBytes((2.25 * 1024 * 1024 * 1024).round()), '2,25 GB');
    });

    test('DownloadRangeMap coalesces overlapping ranges, computes gaps, and persists meta', () async {
      final map = DownloadRangeMap();
      map.add(0, 100);
      map.add(200, 300);
      map.add(100, 200);
      expect(map.ranges.length, 1);
      expect(map.ranges.first, (start: 0, end: 300));
      expect(map.completedBytes, 300);
      expect(map.isComplete(300), isTrue);
      expect(map.missingRanges(500), [(start: 300, end: 500)]);

      final dir = await Directory.systemTemp.createTemp('iptv_rangemap_');
      try {
        final part = File('${dir.path}/f.part')..writeAsBytesSync(List<int>.filled(400, 0));
        final meta = File('${dir.path}/f.part.meta');
        final m2 = DownloadRangeMap()
          ..add(0, 100)
          ..add(250, 400);
        m2.saveMeta(meta, 500);
        final loaded = DownloadRangeMap.tryLoadMeta(part, meta);
        expect(loaded, isNotNull);
        expect(loaded!.totalBytes, 500);
        expect(loaded.map.completedBytes, 250);
        expect(loaded.map.missingRanges(500), [(start: 100, end: 250), (start: 400, end: 500)]);
        expect(readPersistedDownloadedBytes('${dir.path}/f'), 250);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('DownloadManager + DartDownloadEngine (real local HttpServer)', () {
    late Directory tempDir;
    late HttpServer server;
    late Account account;
    HttpOverrides? prevOverrides;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      prevOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      DownloadManager.instance.resetForTest();
      tempDir = await Directory.systemTemp.createTemp('iptv_dl_test_');
      DownloadManager.instance.debugBaseDir = tempDir.path;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      account = Account(
        name: 'Test',
        host: 'http://127.0.0.1:${server.port}',
        username: 'user1',
        password: 'super_secret_password',
      );
    });

    tearDown(() async {
      DownloadManager.instance.resetForTest();
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      HttpOverrides.global = prevOverrides;
    });

    test('downloads a movie, verifies bytes, never persists password, and resolves local path', () async {
      final payload = List<int>.generate(64 * 1024, (i) => i % 251);
      server.listen((req) async {
        req.response.statusCode = HttpStatus.ok;
        req.response.contentLength = payload.length;
        req.response.add(payload);
        await req.response.close();
      });

      final movie = Item(
        id: 'm42',
        name: 'Dune: Çöl Gezegeni |2024| TR',
        logo: '',
        group: 'Bilim Kurgu',
        kind: Kind.movie,
        url: '${account.host}/movie/${account.username}/${account.password}/42.mkv',
      );

      final res = await DownloadManager.instance.enqueueMovie(movie, account);
      expect(res.added, 1);

      await _waitUntil(() => DownloadManager.instance.completedCount == 1);

      final entry = DownloadManager.instance.entryForUrl(movie.url!, account: account);
      expect(entry, isNotNull);
      expect(entry!.isCompleted, isTrue);
      expect(entry.fileName, 'Dune Çöl Gezegeni (2024).mkv');
      expect(File(entry.filePath).readAsBytesSync(), payload);
      expect(File('${entry.filePath}.part').existsSync(), isFalse);

      // Local path resolves both from full URL and from portable URL.
      expect(DownloadManager.instance.localPathForUrl(movie.url!, account: account), entry.filePath);
      expect(DownloadManager.instance.localPathForUrl('movie/42.mkv'), entry.filePath);

      // Password must never appear in SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('downloads_v1') ?? '';
      expect(raw, isNotEmpty);
      expect(raw.contains('super_secret_password'), isFalse);

      // Reloading from disk restores the completed entry.
      final savedPath = entry.filePath;
      DownloadManager.instance.resetForTest();
      DownloadManager.instance.debugBaseDir = tempDir.path;
      await DownloadManager.instance.load();
      expect(DownloadManager.instance.completedCount, 1);
      expect(DownloadManager.instance.localPathForUrl('movie/42.mkv'), savedPath);
    });

    test('pauses and resumes cleanly via HTTP 206 Range without data corruption', () async {
      final payload = List<int>.generate(120 * 1024, (i) => (i * 7) % 256);
      final receivedRanges = <String?>[];
      final firstChunkSent = Completer<void>();

      server.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        receivedRanges.add(range);
        if (range != null && range.startsWith('bytes=')) {
          final start = int.parse(range.substring(6, range.indexOf('-')));
          final rest = payload.sublist(start);
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-${payload.length - 1}/${payload.length}');
          req.response.contentLength = rest.length;
          req.response.add(rest);
          await req.response.close();
          return;
        }
        // First request: trickle slowly so the test can pause mid-stream.
        req.response.statusCode = HttpStatus.ok;
        req.response.contentLength = payload.length;
        req.response.add(payload.sublist(0, 32 * 1024));
        await req.response.flush();
        if (!firstChunkSent.isCompleted) firstChunkSent.complete();
        await Future<void>.delayed(const Duration(seconds: 3));
        try {
          req.response.add(payload.sublist(32 * 1024));
          await req.response.close();
        } catch (_) {}
      });

      final movie = Item(
        id: 'm99',
        name: 'Range Test Film',
        logo: '',
        group: 'Test',
        kind: Kind.movie,
        url: '${account.host}/movie/${account.username}/${account.password}/99.mp4',
      );

      await DownloadManager.instance.enqueueMovie(movie, account);
      await firstChunkSent.future;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final entry = DownloadManager.instance.entries.first;
      await DownloadManager.instance.pause(entry.id);
      await _waitUntil(() => entry.isPaused);
      expect(File('${entry.filePath}.part').existsSync(), isTrue);
      expect(File('${entry.filePath}.part').lengthSync(), greaterThan(0));

      await DownloadManager.instance.resume(entry.id, account: account);
      await _waitUntil(() => entry.isCompleted);

      expect(receivedRanges.length, 2);
      expect(receivedRanges.first, isNull);
      expect(receivedRanges.last, startsWith('bytes='));
      expect(File(entry.filePath).readAsBytesSync(), payload);
    });

    test('queues season episodes sequentially and handles retry after HTTP 509', () async {
      final ep1Payload = List<int>.filled(8 * 1024, 1);
      final ep2Payload = List<int>.filled(10 * 1024, 2);
      var ep1Attempts = 0;

      server.listen((req) async {
        if (req.uri.path.endsWith('/101.mkv')) {
          ep1Attempts++;
          if (ep1Attempts == 1) {
            req.response.statusCode = 509;
            await req.response.close();
            return;
          }
          req.response.statusCode = HttpStatus.ok;
          req.response.contentLength = ep1Payload.length;
          req.response.add(ep1Payload);
          await req.response.close();
        } else {
          req.response.statusCode = HttpStatus.ok;
          req.response.contentLength = ep2Payload.length;
          req.response.add(ep2Payload);
          await req.response.close();
        }
      });

      final series = Item(id: 's1', name: 'Severance |2022|', logo: '', group: 'Dram', kind: Kind.series, seriesId: 1);
      final episodes = [
        Episode(season: 1, number: 1, title: 'İyi Haberler', url: '${account.host}/series/${account.username}/${account.password}/101.mkv'),
        Episode(season: 1, number: 2, title: 'Yarım Döngü', url: '${account.host}/series/${account.username}/${account.password}/102.mkv'),
      ];

      final res = await DownloadManager.instance.enqueueSeason(series, episodes, account);
      expect(res.added, 2);

      // Episode 1 fails with 509, then Episode 2 automatically runs and completes.
      await _waitUntil(() =>
          DownloadManager.instance.completedCount == 1 &&
          DownloadManager.instance.entries.any((e) => e.isFailed));

      final failedEp = DownloadManager.instance.entries.firstWhere((e) => e.isFailed);
      expect(failedEp.error, contains('509'));

      await DownloadManager.instance.retry(failedEp.id, account: account);
      await _waitUntil(() => DownloadManager.instance.completedCount == 2);

      // Delete removes file from disk and entry from manager.
      final doomed = DownloadManager.instance.completedEntries.first;
      final doomedPath = doomed.filePath;
      expect(File(doomedPath).existsSync(), isTrue);
      await DownloadManager.instance.delete(doomed.id);
      expect(File(doomedPath).existsSync(), isFalse);
      expect(DownloadManager.instance.completedCount, 1);
    });

    test('rejects HLS .m3u8 URLs with a clear error message', () async {
      final hlsItem = Item(
        id: 'm7',
        name: 'HLS Film',
        logo: '',
        group: 'Test',
        kind: Kind.movie,
        url: '${account.host}/movie/${account.username}/${account.password}/7.m3u8',
      );
      final res = await DownloadManager.instance.enqueueMovie(hlsItem, account);
      expect(res.added, 0);
      expect(res.error, contains('.m3u8'));
    });

    test('automatically recovers from mid-stream drop across 302 redirect using HTTP Range', () async {
      final engine = DartDownloadEngine()..debugRetryDelay = const Duration(milliseconds: 20);
      DownloadManager.instance.debugEngine = engine;
      final payload = List<int>.generate(96 * 1024, (i) => (i * 13) % 256);
      final cdnRanges = <String?>[];
      var cdnHits = 0;

      server.listen((req) async {
        // Simulate IPTV panel 302 redirect to a fresh CDN token URL on every request.
        if (req.uri.path.startsWith('/movie/')) {
          cdnHits++;
          req.response.statusCode = HttpStatus.found;
          req.response.headers.set(HttpHeaders.locationHeader, '/cdn/token_$cdnHits/55.mkv');
          await req.response.close();
          return;
        }
        final range = req.headers.value(HttpHeaders.rangeHeader);
        cdnRanges.add(range);
        if (range == null) {
          // Drop TCP socket abruptly halfway through (simulates Wi-Fi -> Cellular switch).
          final socket = await req.response.detachSocket(writeHeaders: false);
          socket.write(
            'HTTP/1.1 200 OK\r\n'
            'Content-Length: ${payload.length}\r\n'
            'Connection: close\r\n\r\n',
          );
          socket.add(payload.sublist(0, 40 * 1024));
          await socket.flush();
          socket.destroy();
          return;
        }
        final start = int.parse(range.substring(6, range.indexOf('-')));
        final rest = payload.sublist(start);
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-${payload.length - 1}/${payload.length}');
        req.response.contentLength = rest.length;
        req.response.add(rest);
        await req.response.close();
      });

      final movie = Item(
        id: 'm55',
        name: 'Redirect Drop Film',
        logo: '',
        group: 'Test',
        kind: Kind.movie,
        url: '${account.host}/movie/${account.username}/${account.password}/55.mkv',
      );

      await DownloadManager.instance.enqueueMovie(movie, account);
      await _waitUntil(() => DownloadManager.instance.completedCount == 1);

      final entry = DownloadManager.instance.entries.first;
      expect(cdnRanges.length, 2);
      expect(cdnRanges.first, isNull);
      expect(cdnRanges.last, 'bytes=${40 * 1024}-');
      expect(File(entry.filePath).readAsBytesSync(), payload);
    });

    test('downloads in parallel across multiple Range connections and accelerates per-connection throttled servers', () async {
      final engine = DartDownloadEngine()
        ..debugMinSegmentedBytes = 64 * 1024
        ..debugChunkSize = 32 * 1024;
      DownloadManager.instance.debugEngine = engine;
      AppSettings.instance.downloadConnections = 6;

      final payload = List<int>.generate(256 * 1024, (i) => (i * 19 + 7) % 256);
      var concurrent = 0;
      var peakConcurrent = 0;
      var rangeRequests = 0;

      server.listen((req) async {
        concurrent++;
        if (concurrent > peakConcurrent) peakConcurrent = concurrent;
        try {
          final range = req.headers.value(HttpHeaders.rangeHeader);
          if (range != null && range.startsWith('bytes=')) {
            rangeRequests++;
            final spec = range.substring(6).split('-');
            final start = int.parse(spec[0]);
            final end = spec[1].isEmpty ? payload.length - 1 : int.parse(spec[1]);
            final slice = payload.sublist(start, end + 1);
            req.response.statusCode = HttpStatus.partialContent;
            req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${payload.length}');
            req.response.contentLength = slice.length;
            // Simulate per-connection rate limit (~160 KB/s per connection).
            for (var off = 0; off < slice.length; off += 8192) {
              final chunkEnd = off + 8192 > slice.length ? slice.length : off + 8192;
              req.response.add(slice.sublist(off, chunkEnd));
              await req.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
            await req.response.close();
            return;
          }
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          req.response.contentLength = payload.length;
          for (var off = 0; off < payload.length; off += 8192) {
            final chunkEnd = off + 8192 > payload.length ? payload.length : off + 8192;
            req.response.add(payload.sublist(off, chunkEnd));
            await req.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
          await req.response.close();
        } catch (_) {
          // Client closed open-ended initial stream after chunk 0 — expected.
        } finally {
          concurrent--;
        }
      });

      final movie = Item(
        id: 'm200',
        name: 'Fiber Multi Range Film',
        logo: '',
        group: 'Test',
        kind: Kind.movie,
        url: '${account.host}/movie/${account.username}/${account.password}/200.mkv',
      );

      final sw = Stopwatch()..start();
      await DownloadManager.instance.enqueueMovie(movie, account);
      await _waitUntil(() => DownloadManager.instance.completedCount == 1, timeout: const Duration(seconds: 10));
      sw.stop();

      final entry = DownloadManager.instance.entries.first;
      expect(peakConcurrent, greaterThanOrEqualTo(3));
      expect(rangeRequests, greaterThanOrEqualTo(4));
      expect(File(entry.filePath).readAsBytesSync(), payload);
      expect(File('${entry.filePath}.part').existsSync(), isFalse);
      expect(File('${entry.filePath}.part.meta').existsSync(), isFalse);
      // Single-connection throttled time would be ~800ms+; parallel should finish much faster.
      expect(sw.elapsedMilliseconds, lessThan(2500));
    });

    test('gracefully falls back to 1 connection when strict IPTV server rejects extra connections with HTTP 509', () async {
      final engine = DartDownloadEngine()
        ..debugMinSegmentedBytes = 32 * 1024
        ..debugChunkSize = 32 * 1024
        ..debugRetryDelay = const Duration(milliseconds: 20);
      DownloadManager.instance.debugEngine = engine;
      AppSettings.instance.downloadConnections = 6;

      final payload = List<int>.generate(128 * 1024, (i) => (i * 11) % 256);
      var activeConns = 0;
      var rejected509Count = 0;

      server.listen((req) async {
        if (activeConns >= 1) {
          rejected509Count++;
          req.response.statusCode = 509;
          await req.response.close();
          return;
        }
        activeConns++;
        try {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          req.response.contentLength = payload.length;
          for (var off = 0; off < payload.length; off += 16 * 1024) {
            final chunkEnd = off + 16 * 1024 > payload.length ? payload.length : off + 16 * 1024;
            req.response.add(payload.sublist(off, chunkEnd));
            await req.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 15));
          }
          await req.response.close();
        } finally {
          activeConns--;
        }
      });

      final movie = Item(
        id: 'm201',
        name: 'Strict Single Connection Film',
        logo: '',
        group: 'Test',
        kind: Kind.movie,
        url: '${account.host}/movie/${account.username}/${account.password}/201.mkv',
      );

      await DownloadManager.instance.enqueueMovie(movie, account);
      await _waitUntil(() => DownloadManager.instance.completedCount == 1, timeout: const Duration(seconds: 8));

      final entry = DownloadManager.instance.entries.first;
      expect(entry.isCompleted, isTrue);
      expect(rejected509Count, greaterThanOrEqualTo(1));
      expect(File(entry.filePath).readAsBytesSync(), payload);
    });

    test('gracefully recovers and caps to 1 connection when server kicks primary connection on 2nd connection', () async {
      final engine = DartDownloadEngine()
        ..debugMinSegmentedBytes = 32 * 1024
        ..debugChunkSize = 32 * 1024
        ..debugRetryDelay = const Duration(milliseconds: 20);
      DownloadManager.instance.debugEngine = engine;
      AppSettings.instance.downloadConnections = 4;

      final payload = List<int>.generate(128 * 1024, (i) => (i * 23) % 256);
      Socket? currentSocket;
      var kickCount = 0;

      server.listen((req) async {
        // Simulate Xtream panel kicking the previous active stream whenever a 2nd connection arrives!
        if (currentSocket != null) {
          kickCount++;
          try {
            currentSocket!.destroy();
          } catch (_) {}
          currentSocket = null;
        }
        final range = req.headers.value(HttpHeaders.rangeHeader);
        var start = 0;
        var end = payload.length - 1;
        var status = '200 OK';
        var extraHeader = '';
        if (range != null && range.startsWith('bytes=')) {
          final spec = range.substring(6).split('-');
          start = int.parse(spec[0]);
          end = spec[1].isEmpty ? payload.length - 1 : int.parse(spec[1]);
          status = '206 Partial Content';
          extraHeader = 'Content-Range: bytes $start-$end/${payload.length}\r\n';
        }
        final slice = payload.sublist(start, end + 1);
        final socket = await req.response.detachSocket(writeHeaders: false);
        currentSocket = socket;
        try {
          socket.write(
            'HTTP/1.1 $status\r\n'
            'Accept-Ranges: bytes\r\n'
            '$extraHeader'
            'Content-Length: ${slice.length}\r\n'
            'Connection: close\r\n\r\n',
          );
          for (var off = 0; off < slice.length; off += 16 * 1024) {
            final chunkEnd = off + 16 * 1024 > slice.length ? slice.length : off + 16 * 1024;
            socket.add(slice.sublist(off, chunkEnd));
            await socket.flush();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await socket.close();
        } catch (_) {
          // Kicked socket write error expected.
        } finally {
          if (identical(currentSocket, socket)) currentSocket = null;
        }
      });

      final movie = Item(
        id: 'm202',
        name: 'Kick Detection Film',
        logo: '',
        group: 'Test',
        kind: Kind.movie,
        url: '${account.host}/movie/${account.username}/${account.password}/202.mkv',
      );

      await DownloadManager.instance.enqueueMovie(movie, account);
      await _waitUntil(() => DownloadManager.instance.completedCount == 1, timeout: const Duration(seconds: 10));

      final entry = DownloadManager.instance.entries.first;
      expect(entry.isCompleted, isTrue);
      expect(kickCount, greaterThanOrEqualTo(1));
      expect(File(entry.filePath).readAsBytesSync(), payload);
    });

    test('pauses mid-segmented download, persists .part.meta, and resumes without corruption', () async {
      final engine = DartDownloadEngine()
        ..debugMinSegmentedBytes = 64 * 1024
        ..debugChunkSize = 32 * 1024;
      DownloadManager.instance.debugEngine = engine;
      AppSettings.instance.downloadConnections = 4;

      final payload = List<int>.generate(256 * 1024, (i) => (i * 29 + 3) % 256);
      final probeReceived = Completer<void>();

      server.listen((req) async {
        try {
          final range = req.headers.value(HttpHeaders.rangeHeader);
          if (range != null && range.startsWith('bytes=')) {
            final spec = range.substring(6).split('-');
            final start = int.parse(spec[0]);
            final end = spec[1].isEmpty ? payload.length - 1 : int.parse(spec[1]);
            final slice = payload.sublist(start, end + 1);
            req.response.statusCode = HttpStatus.partialContent;
            req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${payload.length}');
            req.response.contentLength = slice.length;
            req.response.add(slice.sublist(0, slice.length ~/ 2));
            await req.response.flush();
            if (!probeReceived.isCompleted) probeReceived.complete();
            await Future<void>.delayed(const Duration(milliseconds: 120));
            req.response.add(slice.sublist(slice.length ~/ 2));
            await req.response.close();
            return;
          }
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          req.response.contentLength = payload.length;
          for (var off = 0; off < payload.length; off += 16 * 1024) {
            final chunkEnd = off + 16 * 1024 > payload.length ? payload.length : off + 16 * 1024;
            req.response.add(payload.sublist(off, chunkEnd));
            await req.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 80));
          }
          await req.response.close();
        } catch (_) {}
      });

      final movie = Item(
        id: 'm203',
        name: 'Segmented Resume Film',
        logo: '',
        group: 'Test',
        kind: Kind.movie,
        url: '${account.host}/movie/${account.username}/${account.password}/203.mkv',
      );

      await DownloadManager.instance.enqueueMovie(movie, account);
      await probeReceived.future;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final entry = DownloadManager.instance.entries.first;
      await DownloadManager.instance.pause(entry.id);
      await _waitUntil(() => entry.isPaused);
      expect(File('${entry.filePath}.part').existsSync(), isTrue);
      expect(File('${entry.filePath}.part.meta').existsSync(), isTrue);
      expect(readPersistedDownloadedBytes(entry.filePath), greaterThan(0));

      await DownloadManager.instance.resume(entry.id, account: account);
      await _waitUntil(() => entry.isCompleted, timeout: const Duration(seconds: 10));
      expect(File(entry.filePath).readAsBytesSync(), payload);
      expect(File('${entry.filePath}.part.meta').existsSync(), isFalse);
    });
  });

  group('Downloads UI (Desktop & iPhone 15 Portrait / Landscape)', () {
    late Directory tempDir;
    late Account account;
    late _NoopEngine noopEngine;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      DownloadManager.instance.resetForTest();
      tempDir = await Directory.systemTemp.createTemp('iptv_dl_ui_');
      noopEngine = _NoopEngine();
      DownloadManager.instance
        ..debugBaseDir = tempDir.path
        ..debugEngine = noopEngine;
      await DownloadManager.instance.load();
      account = Account(name: 'Demo', host: 'http://demo.example:8080', username: 'u', password: 'p');
      AppSettings.instance
        ..tvMode = false
        ..uiScale = 1.0
        ..downloadDir = '';
    });

    tearDown(() async {
      DownloadManager.instance.resetForTest();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> seedSampleDownloads() async {
      final movie = Item(
        id: 'm1',
        name: 'Dune: Çöl Gezegeni |2024| TR',
        logo: '',
        group: 'Bilim Kurgu',
        kind: Kind.movie,
        url: '${account.host}/movie/u/p/1.mkv',
      );
      await DownloadManager.instance.enqueueMovie(movie, account);
      final mEntry = DownloadManager.instance.entries.first;
      final mFile = File(mEntry.filePath);
      await mFile.parent.create(recursive: true);
      await mFile.writeAsBytes(List<int>.filled(4096, 1));
      noopEngine.cb!.onCompleted(mEntry.id, mFile.path, 4096);

      final series = Item(id: 's1', name: 'Severance |2022|', logo: '', group: 'Dram', kind: Kind.series, seriesId: 1);
      final ep1 = Episode(season: 1, number: 1, title: 'İyi Haberler', url: '${account.host}/series/u/p/101.mkv');
      final ep2 = Episode(season: 1, number: 2, title: 'Yarım Döngü', url: '${account.host}/series/u/p/102.mkv');
      await DownloadManager.instance.enqueueEpisode(series, ep1, account);
      final e1 = DownloadManager.instance.entryForUrl(ep1.url, account: account)!;
      final e1File = File(e1.filePath);
      await e1File.parent.create(recursive: true);
      await e1File.writeAsBytes(List<int>.filled(2048, 2));
      noopEngine.cb!.onCompleted(e1.id, e1File.path, 2048);

      await DownloadManager.instance.enqueueEpisode(series, ep2, account);
      final e2 = DownloadManager.instance.entryForUrl(ep2.url, account: account)!;
      noopEngine.cb!.onProgress(e2.id, 1024, 4096, 512 * 1024);
    }

    testWidgets('DetailPage movie and series expose download controls and enqueue items', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final client = _FakeClient(account);
      final movie = Item(id: 'm1', name: 'Interstellar |2014|', logo: '', group: 'Bilim Kurgu', kind: Kind.movie, url: '${account.host}/movie/u/p/1.mkv');
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: DetailPage(client: client, item: movie)));
      await _settle(tester);

      expect(find.byKey(const ValueKey('detail-download-movie')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('detail-download-movie')));
      await _settle(tester);
      expect(DownloadManager.instance.entries.length, 1);
      expect(noopEngine.startedIds.length, 1);

      final series = Item(id: 's1', name: 'Severance |2022|', logo: '', group: 'Dram', kind: Kind.series, seriesId: 1);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: DetailPage(client: client, item: series)));
      await _settle(tester);

      expect(find.byKey(const ValueKey('detail-download-season')), findsOneWidget);
      expect(find.byKey(const ValueKey('episode-download-1-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('detail-download-season')));
      await _settle(tester);
      expect(DownloadManager.instance.entries.length, 3); // 1 movie + 2 episodes
      expect(tester.takeException(), isNull);
    });

    testWidgets('DownloadsPage renders cleanly on Desktop, iPhone Portrait and iPhone Landscape', (tester) async {
      await tester.runAsync(seedSampleDownloads);

      for (final size in [const Size(1400, 900), const Size(393, 852), const Size(852, 393)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: DownloadsPage.offline(account: account),
        ));
        await _settle(tester);

        expect(find.text('İndirilenler'), findsOneWidget);
        expect(find.text('Devam edenler'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Dune: Çöl Gezegeni'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Dune: Çöl Gezegeni'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Severance'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Severance'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('LoginPage opens offline DownloadsPage without network authentication', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await AccountStore.save([account]);
        await AccountStore.saveLast(account.key);
        await seedSampleDownloads();
      });

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: LoginPage(autoLogin: false, clientFactory: _FakeClient.new),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await _settle(tester);

      final btn = find.byKey(const ValueKey('login-offline-downloads'));
      expect(btn, findsOneWidget);
      expect(find.text('İndirilenler (2)'), findsOneWidget);

      await tester.tap(btn);
      await _settle(tester);

      expect(find.text('Çevrimdışı izleme'), findsOneWidget);
      expect(find.text('Dune: Çöl Gezegeni'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HomePage opens Downloads tab on desktop and iPhone portrait', (tester) async {
      await tester.runAsync(seedSampleDownloads);
      final client = _FakeClient(account);

      // Desktop SideMenu
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(client: client, info: AccountInfo(status: 'Active', maxConnections: 1), account: account),
      ));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('nav-downloads')));
      await _settle(tester);
      expect(find.text('Çevrimdışı depolama · 2 hazır · 1 kuyrukta · 6 KB'), findsOneWidget);

      // iPhone portrait top bar icon
      tester.view.physicalSize = const Size(393, 852);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(key: const ValueKey('home-phone'), client: client, info: AccountInfo(status: 'Active', maxConnections: 1), account: account),
      ));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('nav-downloads')));
      await _settle(tester);
      expect(find.text('Çevrimdışı depolama'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SettingsPage shows Downloads section on PC and iOS', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsPage(
            info: AccountInfo(status: 'Active', maxConnections: 1),
            account: account,
            client: _FakeClient(account),
            onLogout: () {},
          ),
        ),
      ));
      await _settle(tester);
      expect(find.text('İndirmeler'), findsWidgets);
      expect(find.byKey(const ValueKey('setting-downloadConnections')), findsOneWidget);
      expect(find.byKey(const ValueKey('setting-downloadDir')), findsOneWidget);

      // iOS variant shows Files app path instead of PC folder picker.
      tester.view.physicalSize = const Size(393, 852);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: SettingsPage(
            info: AccountInfo(status: 'Active', maxConnections: 1),
            account: account,
            client: _FakeClient(account),
            onLogout: () {},
          ),
        ),
      ));
      await _settle(tester);
      expect(find.byKey(const ValueKey('setting-downloadDir')), findsNothing);
      expect(find.textContaining('Dosyalar (Files)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
