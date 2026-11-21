import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Sorted, coalesced half-open `[start, end)` byte intervals safely written to `<dest>.part`.
class DownloadRangeMap {
  DownloadRangeMap([Iterable<({int start, int end})>? initial]) {
    if (initial != null) {
      for (final r in initial) {
        add(r.start, r.end);
      }
    }
  }

  final List<({int start, int end})> _ranges = [];

  List<({int start, int end})> get ranges => List.unmodifiable(_ranges);

  bool get isEmpty => _ranges.isEmpty;

  int get completedBytes {
    var sum = 0;
    for (final r in _ranges) {
      sum += r.end - r.start;
    }
    return sum;
  }

  int get maxEnd => _ranges.isEmpty ? 0 : _ranges.last.end;

  void clear() => _ranges.clear();

  /// Records half-open `[start, end)` as safely written to disk, merging adjacent/overlapping intervals.
  void add(int start, int end) {
    if (end <= start || start < 0) return;
    var s = start;
    var e = end;
    final next = <({int start, int end})>[];
    var inserted = false;
    for (final r in _ranges) {
      if (r.end < s) {
        next.add(r);
      } else if (e < r.start) {
        if (!inserted) {
          next.add((start: s, end: e));
          inserted = true;
        }
        next.add(r);
      } else {
        s = math.min(s, r.start);
        e = math.max(e, r.end);
      }
    }
    if (!inserted) {
      next.add((start: s, end: e));
    }
    _ranges
      ..clear()
      ..addAll(next);
  }

  /// Drops or trims any interval beyond [maxLength] (e.g. if `.part` was externally truncated).
  void clampToLength(int maxLength) {
    if (maxLength <= 0) {
      _ranges.clear();
      return;
    }
    final next = <({int start, int end})>[];
    for (final r in _ranges) {
      if (r.start >= maxLength) break;
      final clampedEnd = math.min(r.end, maxLength);
      if (clampedEnd > r.start) {
        next.add((start: r.start, end: clampedEnd));
      }
    }
    _ranges
      ..clear()
      ..addAll(next);
  }

  bool isComplete(int totalBytes) =>
      totalBytes > 0 && _ranges.length == 1 && _ranges.first.start == 0 && _ranges.first.end >= totalBytes;

  /// Complement of [_ranges] within `[0, totalBytes)`.
  List<({int start, int end})> missingRanges(int totalBytes) {
    if (totalBytes <= 0) return const [];
    final gaps = <({int start, int end})>[];
    var cursor = 0;
    for (final r in _ranges) {
      if (r.start >= totalBytes) break;
      if (r.start > cursor) {
        gaps.add((start: cursor, end: math.min(r.start, totalBytes)));
      }
      if (r.end > cursor) cursor = r.end;
      if (cursor >= totalBytes) break;
    }
    if (cursor < totalBytes) {
      gaps.add((start: cursor, end: totalBytes));
    }
    return gaps;
  }

  /// True when every byte in `[start, end)` is outside [_ranges].
  bool isCompletelyMissing(int start, int end) {
    if (end <= start) return false;
    for (final r in _ranges) {
      if (r.end <= start) continue;
      if (r.start >= end) break;
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson(int totalBytes) => {
        'v': 1,
        'totalBytes': totalBytes,
        'ranges': [
          for (final r in _ranges) [r.start, r.end],
        ],
      };

  static ({DownloadRangeMap map, int totalBytes})? tryLoadMeta(File partFile, File metaFile) {
    try {
      if (!partFile.existsSync() || !metaFile.existsSync()) return null;
      final decoded = jsonDecode(metaFile.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return null;
      final totalBytes = (decoded['totalBytes'] as num?)?.toInt() ?? 0;
      final rawRanges = decoded['ranges'];
      if (totalBytes <= 0 || rawRanges is! List) return null;
      final map = DownloadRangeMap();
      for (final item in rawRanges) {
        if (item is List && item.length >= 2) {
          final s = (item[0] as num?)?.toInt();
          final e = (item[1] as num?)?.toInt();
          if (s != null && e != null && s >= 0 && e > s) {
            map.add(s, math.min(e, totalBytes));
          }
        }
      }
      final partLen = partFile.lengthSync();
      map.clampToLength(partLen);
      return (map: map, totalBytes: totalBytes);
    } catch (_) {
      return null;
    }
  }

  void saveMeta(File metaFile, int totalBytes) {
    if (totalBytes <= 0) return;
    try {
      metaFile.writeAsStringSync(jsonEncode(toJson(totalBytes)), flush: false);
    } catch (_) {}
  }
}

/// Returns the true persisted downloaded byte count for [destinationPath],
/// preferring `<dest>.part.meta` (segmented range sum) over raw `.part` file length.
int readPersistedDownloadedBytes(String destinationPath) {
  if (destinationPath.isEmpty) return 0;
  final part = File('$destinationPath.part');
  if (!part.existsSync()) return 0;
  final meta = File('$destinationPath.part.meta');
  final loaded = DownloadRangeMap.tryLoadMeta(part, meta);
  if (loaded != null) return loaded.map.completedBytes;
  try {
    return part.lengthSync();
  } catch (_) {
    return 0;
  }
}

/// Sliding-window throughput meter for smooth, accurate speed reporting across parallel workers.
class DownloadSpeedMeter {
  DownloadSpeedMeter({this.windowMs = 1500});

  final int windowMs;
  final List<({int timeMs, int bytes})> _samples = [];
  int _windowBytes = 0;

  void addBytes(int bytes, int nowMs) {
    if (bytes <= 0) return;
    _samples.add((timeMs: nowMs, bytes: bytes));
    _windowBytes += bytes;
    _prune(nowMs);
  }

  int bytesPerSecond(int nowMs) {
    _prune(nowMs);
    if (_samples.isEmpty || _windowBytes <= 0) return 0;
    final spanMs = math.max(250, nowMs - _samples.first.timeMs);
    return (_windowBytes * 1000 / spanMs).round().clamp(0, 1 << 62);
  }

  void reset() {
    _samples.clear();
    _windowBytes = 0;
  }

  void _prune(int nowMs) {
    final cutoff = nowMs - windowMs;
    var removeCount = 0;
    while (removeCount < _samples.length && _samples[removeCount].timeMs < cutoff) {
      _windowBytes -= _samples[removeCount].bytes;
      removeCount++;
    }
    if (removeCount > 0) {
      _samples.removeRange(0, removeCount);
    }
    if (_windowBytes < 0) _windowBytes = 0;
  }
}

/// Configuration passed into the background download [Isolate].
class DownloadWorkerArgs {
  const DownloadWorkerArgs({
    required this.replyPort,
    required this.url,
    required this.destinationPath,
    required this.userAgent,
    required this.maxConnections,
    required this.minSegmentedBytes,
    this.chunkSizeOverride,
    this.retryDelayMs,
  });

  final SendPort replyPort;
  final String url;
  final String destinationPath;
  final String userAgent;
  final int maxConnections;
  final int minSegmentedBytes;
  final int? chunkSizeOverride;
  final int? retryDelayMs;
}

/// Entrypoint for [Isolate.spawn] running high-throughput adaptive segmented HTTP downloads.
Future<void> runDownloadWorkerIsolate(DownloadWorkerArgs args) async {
  final controlPort = ReceivePort();
  args.replyPort.send({'type': 'ready', 'controlPort': controlPort.sendPort});

  final runner = _SegmentedDownloadRunner(args);
  controlPort.listen((msg) {
    if (msg == 'pause') {
      runner.requestPause();
    } else if (msg == 'cancel') {
      runner.requestCancel();
    }
  });

  try {
    await runner.run();
  } finally {
    controlPort.close();
  }
}

class _WorkerSpan {
  _WorkerSpan({required this.workerId, required this.start, required this.end, required this.openEnded})
      : cursor = start;

  final int workerId;
  final int start;
  int cursor;
  int end; // exclusive
  final bool openEnded;

  int get remaining => math.max(0, end - cursor);
}

class _FatalHttpException implements Exception {
  const _FatalHttpException(this.message);
  final String message;
}

class _RecoverableNetworkException implements Exception {
  const _RecoverableNetworkException(this.message);
  final String message;
}

class _RangeRejectedException implements Exception {
  const _RangeRejectedException(this.statusCode);
  final int statusCode;
}

class _ServerIgnoredRangeException implements Exception {
  const _ServerIgnoredRangeException();
}

class _BurstRotateException implements Exception {
  const _BurstRotateException(this.peakBps, this.slowBps);
  final int peakBps;
  final int slowBps;
}

class _SegmentedDownloadRunner {
  _SegmentedDownloadRunner(this.args)
      : _partFile = File('${args.destinationPath}.part'),
        _metaFile = File('${args.destinationPath}.part.meta'),
        _finalFile = File(args.destinationPath),
        _desiredMaxWorkers = args.maxConnections.clamp(1, 8);

  static const _maxNetworkRetries = 3;
  static const _writeBufferBytes = 512 * 1024; // 512 KiB write coalescing
  static const _minStealBytes = 512 * 1024;

  final DownloadWorkerArgs args;
  final File _partFile;
  final File _metaFile;
  final File _finalFile;
  final int _desiredMaxWorkers;

  final DownloadRangeMap _rangeMap = DownloadRangeMap();
  final DownloadSpeedMeter _speedMeter = DownloadSpeedMeter();
  final Map<int, _WorkerSpan> _activeSpans = {};
  final Set<HttpClient> _activeClients = {};
  final Set<StreamSubscription<List<int>>> _activeSubs = {};
  final Set<int> _streamingWorkerIds = {};

  RandomAccessFile? _raf;
  Uri? _originalUri;
  Uri? _resolvedUri;
  bool _resolvedUriReusable = true;

  int _totalBytes = 0;
  int _chunkSize = 4 * 1024 * 1024;
  bool _supportsRange = true;
  int _effectiveMaxWorkers = 1;
  bool _probeStarted = false;
  bool _probeSucceeded = false;
  int _lastScaleUpMs = 0;
  bool _singleConnKickDetected = false;

  // Smart Nginx limit_rate_after burst detector (only used if capped to 1 worker).
  bool _burstRotationTested = false;
  bool _burstRotationEnabled = false;
  int _burstChunkBytes = 4 * 1024 * 1024;

  bool _paused = false;
  bool _cancelled = false;
  int _lastProgressEmitMs = 0;
  int _lastMetaSaveMs = 0;
  bool _receivedAnyBytesThisAttempt = false;
  int _nextWorkerId = 1;

  void requestPause() {
    if (_paused || _cancelled) return;
    _paused = true;
    _abortActiveNetwork();
  }

  void requestCancel() {
    if (_cancelled) return;
    _cancelled = true;
    _abortActiveNetwork();
  }

  void _abortActiveNetwork() {
    for (final sub in _activeSubs.toList()) {
      try {
        sub.cancel();
      } catch (_) {}
    }
    _activeSubs.clear();
    for (final c in _activeClients.toList()) {
      try {
        c.close(force: true);
      } catch (_) {}
    }
    _activeClients.clear();
  }

  HttpClient _createClient({int? maxConnectionsPerHost}) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 30)
      ..autoUncompress = false;
    if (maxConnectionsPerHost != null) {
      client.maxConnectionsPerHost = maxConnectionsPerHost;
    }
    _activeClients.add(client);
    return client;
  }

  void _disposeClient(HttpClient? client, {bool force = true}) {
    if (client == null) return;
    _activeClients.remove(client);
    try {
      client.close(force: force);
    } catch (_) {}
  }

  Future<void> run() async {
    final parsedUri = Uri.tryParse(args.url);
    if (parsedUri == null || (parsedUri.scheme != 'http' && parsedUri.scheme != 'https')) {
      args.replyPort.send({'type': 'failed', 'error': 'Geçersiz indirme adresi'});
      return;
    }
    _originalUri = parsedUri;
    _effectiveMaxWorkers = _desiredMaxWorkers;

    var retries = 0;

    while (!_paused && !_cancelled) {
      HttpClient? poolClient;
      _receivedAnyBytesThisAttempt = false;
      _activeSpans.clear();
      _streamingWorkerIds.clear();
      _probeStarted = false;
      _probeSucceeded = false;
      _speedMeter.reset();

      try {
        await _finalFile.parent.create(recursive: true);
        _loadExistingPartState();

        // Already complete on disk from a previous run!
        if (_totalBytes > 0 && _rangeMap.isComplete(_totalBytes)) {
          await _finalizeAndNotify();
          return;
        }

        if (!_partFile.existsSync()) {
          _partFile.createSync(recursive: true);
        }
        _raf = _partFile.openSync(mode: FileMode.append);
        poolClient = _createClient(maxConnectionsPerHost: _effectiveMaxWorkers + 4);

        final workerFutures = <Future<void>>[];

        void spawnExtraWorkersIfAllowed() {
          if (_paused || _cancelled || !_supportsRange || _totalBytes < args.minSegmentedBytes) return;
          final target = _probeSucceeded ? _effectiveMaxWorkers : math.min(2, _effectiveMaxWorkers);
          while (_activeSpans.length < target && !_paused && !_cancelled) {
            final wid = _nextWorkerId++;
            final span = _claimNextSpan(wid);
            if (span == null) break;
            if (!_probeStarted && wid > 0) _probeStarted = true;
            _lastScaleUpMs = DateTime.now().millisecondsSinceEpoch;
            final fut = _runExtraWorker(
              poolClient!,
              wid,
              span,
              onProbeConfirmed: () {
                if (!_probeSucceeded && !_singleConnKickDetected) {
                  _probeSucceeded = true;
                  spawnExtraWorkersIfAllowed();
                }
              },
              onNeedMoreWork: () => spawnExtraWorkersIfAllowed(),
            );
            workerFutures.add(fut);
          }
        }

        // Launch primary worker 0.
        final primaryFuture = _runPrimaryWorker(
          poolClient,
          onMetadataReady: () {
            if (_effectiveMaxWorkers > 1 && _supportsRange && _totalBytes >= args.minSegmentedBytes) {
              spawnExtraWorkersIfAllowed();
            }
          },
          onPrimaryDoneContinuePool: () {
            // Once Worker 0 finishes its initial open-ended/resume span, it joins the bounded pool!
            if (!_paused && !_cancelled && _supportsRange && _totalBytes > 0 && !_rangeMap.isComplete(_totalBytes)) {
              final wid = _nextWorkerId++;
              final span = _claimNextSpan(wid);
              if (span != null) {
                workerFutures.add(
                  _runExtraWorker(
                    poolClient!,
                    wid,
                    span,
                    isPrimaryContinuation: true,
                    onProbeConfirmed: () {
                      if (!_probeSucceeded && !_singleConnKickDetected) {
                        _probeSucceeded = true;
                        spawnExtraWorkersIfAllowed();
                      }
                    },
                    onNeedMoreWork: () => spawnExtraWorkersIfAllowed(),
                  ),
                );
              }
            }
          },
        );
        workerFutures.add(primaryFuture);

        // Wait until all currently spawned (and dynamically added) workers finish.
        var idx = 0;
        Object? fatalError;
        Object? recoverableError;
        while (idx < workerFutures.length) {
          final current = workerFutures[idx++];
          try {
            await current;
          } catch (e) {
            if (e is _FatalHttpException || e is FormatException) {
              fatalError ??= e;
              _abortActiveNetwork();
            } else {
              recoverableError ??= e;
            }
          }
        }

        _closeRafAndSaveMeta();
        _disposeClient(poolClient, force: true);
        poolClient = null;

        if (_cancelled) {
          _deletePartFiles();
          return;
        }
        if (_paused) {
          args.replyPort.send({'type': 'paused'});
          return;
        }
        if (fatalError != null) {
          throw fatalError;
        }

        // Verify completion.
        if (_totalBytes > 0 && !_rangeMap.isComplete(_totalBytes)) {
          if (_receivedAnyBytesThisAttempt) retries = 0;
          throw recoverableError ?? const _RecoverableNetworkException('Bağlantı indirme bitmeden kesildi');
        }
        if (_totalBytes == 0 && recoverableError != null) {
          throw recoverableError;
        }

        await _finalizeAndNotify();
        return;
      } catch (e) {
        _closeRafAndSaveMeta();
        _disposeClient(poolClient, force: true);
        poolClient = null;

        if (_cancelled) {
          _deletePartFiles();
          return;
        }
        if (_paused) {
          args.replyPort.send({'type': 'paused'});
          return;
        }

        if (e is _RestartCleanException) {
          _deletePartFiles();
          _rangeMap.clear();
          _totalBytes = 0;
          _resolvedUri = null;
          continue;
        }

        final recoverable = e is _RecoverableNetworkException ||
            e is _BurstRotateException ||
            e is SocketException ||
            e is HandshakeException ||
            e is TimeoutException ||
            e is HttpException;
        if (recoverable && (e is _BurstRotateException || retries < _maxNetworkRetries)) {
          if (e is! _BurstRotateException) {
            retries++;
            final delayMs = args.retryDelayMs ?? (retries * 2000);
            await Future<void>.delayed(Duration(milliseconds: delayMs));
          }
          if (_cancelled) {
            _deletePartFiles();
            return;
          }
          if (_paused) {
            args.replyPort.send({'type': 'paused'});
            return;
          }
          continue;
        }

        final msg = e is _FatalHttpException
            ? e.message
            : (e is _RecoverableNetworkException
                ? e.message
                : (e is HttpException
                    ? e.message
                    : (e is FormatException ? e.message : 'İndirme başarısız: $e')));
        args.replyPort.send({'type': 'failed', 'error': msg});
        return;
      }
    }
  }

  void _loadExistingPartState() {
    _rangeMap.clear();
    _totalBytes = 0;
    if (!_partFile.existsSync()) {
      try {
        if (_metaFile.existsSync()) _metaFile.deleteSync();
      } catch (_) {}
      return;
    }

    final meta = DownloadRangeMap.tryLoadMeta(_partFile, _metaFile);
    if (meta != null) {
      for (final r in meta.map.ranges) {
        _rangeMap.add(r.start, r.end);
      }
      _totalBytes = meta.totalBytes;
      _chunkSize = _computeChunkSize(_totalBytes);
      return;
    }

    // Legacy sequential .part file without .part.meta.
    final len = _partFile.lengthSync();
    if (len > 0) {
      _rangeMap.add(0, len);
    }
  }

  int _computeChunkSize(int totalBytes) {
    if (args.chunkSizeOverride != null && args.chunkSizeOverride! > 0) {
      return args.chunkSizeOverride!;
    }
    if (_burstRotationEnabled && _effectiveMaxWorkers == 1) {
      return _burstChunkBytes;
    }
    if (totalBytes >= 16 * 1024 * 1024) return 4 * 1024 * 1024;
    if (totalBytes >= 4 * 1024 * 1024) return 1 * 1024 * 1024;
    return 512 * 1024;
  }

  void _closeRafAndSaveMeta() {
    try {
      _raf?.flushSync();
      _raf?.closeSync();
    } catch (_) {}
    _raf = null;
    if (!_cancelled && _totalBytes > 0 && !_rangeMap.isEmpty) {
      _rangeMap.saveMeta(_metaFile, _totalBytes);
    }
  }

  void _deletePartFiles() {
    for (final f in [_partFile, _metaFile]) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _finalizeAndNotify() async {
    try {
      if (_metaFile.existsSync()) _metaFile.deleteSync();
    } catch (_) {}
    if (await _finalFile.exists()) {
      await _finalFile.delete();
    }
    try {
      await _partFile.rename(_finalFile.path);
    } on FileSystemException {
      await _partFile.copy(_finalFile.path);
      if (await _partFile.exists()) await _partFile.delete();
    }
    final finalSize = await _finalFile.length();
    args.replyPort.send({'type': 'completed', 'filePath': _finalFile.path, 'totalBytes': finalSize});
  }

  /// Opens [uri] following up to 8 HTTP redirects manually while preserving
  /// `User-Agent`, `Accept-Encoding: identity`, and `Range` headers across CDNs.
  Future<({HttpClientResponse response, Uri resolvedUri})> _getFollowingRedirects(
    HttpClient client,
    Uri uri, {
    String? rangeHeader,
    bool forceClose = false,
  }) async {
    var current = uri;
    for (var hops = 0; hops < 8; hops++) {
      final req = await client.getUrl(current);
      req.followRedirects = false;
      req.persistentConnection = !forceClose;
      req.headers.set(HttpHeaders.userAgentHeader, args.userAgent);
      req.headers.set(HttpHeaders.acceptHeader, '*/*');
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (rangeHeader != null && rangeHeader.isNotEmpty) {
        req.headers.set(HttpHeaders.rangeHeader, rangeHeader);
      }
      final res = await req.close();
      final isRedirect = res.statusCode == HttpStatus.movedPermanently ||
          res.statusCode == HttpStatus.found ||
          res.statusCode == HttpStatus.seeOther ||
          res.statusCode == HttpStatus.temporaryRedirect ||
          res.statusCode == HttpStatus.permanentRedirect;
      final loc = res.headers.value(HttpHeaders.locationHeader);
      if (isRedirect && loc != null && loc.isNotEmpty) {
        await res.drain<void>().catchError((_) {});
        current = current.resolve(loc);
        continue;
      }
      return (response: res, resolvedUri: current);
    }
    throw const _FatalHttpException('Çok fazla yönlendirme (redirect) alındı');
  }

  /// Primary bootstrap worker (workerId = 0):
  /// - Fresh download: plain GET (no Range header) for 100% server compatibility.
  /// - Legacy .part resume: `Range: bytes=existing-`.
  /// - Segmented `.part.meta` resume: bounded `Range: bytes=s-e` on the first gap.
  Future<void> _runPrimaryWorker(
    HttpClient client, {
    required void Function() onMetadataReady,
    required void Function() onPrimaryDoneContinuePool,
  }) async {
    const workerId = 0;
    final hasMeta = _totalBytes > 0 && !_rangeMap.isEmpty;
    String? rangeHeader;
    var requestedStart = 0;
    int? requestedEnd; // exclusive

    if (hasMeta) {
      final gaps = _rangeMap.missingRanges(_totalBytes);
      if (gaps.isEmpty) return;
      final firstGap = gaps.first;
      requestedStart = firstGap.start;
      final shouldSegment = _supportsRange && _effectiveMaxWorkers > 1 && _totalBytes >= args.minSegmentedBytes;
      if (shouldSegment) {
        final spanEnd = math.min(firstGap.end, firstGap.start + _chunkSize);
        requestedEnd = spanEnd;
        rangeHeader = 'bytes=$requestedStart-${spanEnd - 1}';
      } else if (firstGap.end >= _totalBytes) {
        // Single-stream open-ended resume to EOF (maximally compatible with picky servers).
        requestedEnd = null;
        rangeHeader = 'bytes=$requestedStart-';
      } else {
        requestedEnd = firstGap.end;
        rangeHeader = 'bytes=$requestedStart-${firstGap.end - 1}';
      }
    } else if (!_rangeMap.isEmpty) {
      // Legacy sequential .part file.
      requestedStart = _rangeMap.maxEnd;
      rangeHeader = 'bytes=$requestedStart-';
    }

    final result = await _getFollowingRedirects(
      client,
      _originalUri!,
      rangeHeader: rangeHeader,
      forceClose: _burstRotationEnabled && _effectiveMaxWorkers == 1,
    );
    if (_paused || _cancelled) {
      await result.response.drain<void>().catchError((_) {});
      return;
    }

    final res = result.response;
    _resolvedUri = result.resolvedUri;

    if (res.statusCode == HttpStatus.requestedRangeNotSatisfiable && requestedStart > 0) {
      final parsedTotal = _parseContentRangeTotal(res.headers.value(HttpHeaders.contentRangeHeader));
      await res.drain<void>().catchError((_) {});
      if (parsedTotal != null && parsedTotal > 0 && _rangeMap.completedBytes >= parsedTotal) {
        _totalBytes = parsedTotal;
        _rangeMap.add(0, parsedTotal);
        return;
      }
      throw const _RestartCleanException();
    }

    final isPartial = res.statusCode == HttpStatus.partialContent;
    if (res.statusCode != HttpStatus.ok && !isPartial) {
      await res.drain<void>().catchError((_) {});
      final msg = switch (res.statusCode) {
        401 || 403 || 509 =>
          'Sunucu indirmeyi reddetti (HTTP ${res.statusCode} — bağlantı sınırı dolu veya hesap yetkisiz olabilir)',
        404 => 'Dosya sunucuda bulunamadı (HTTP 404)',
        _ => 'Sunucu HTTP ${res.statusCode} döndürdü',
      };
      throw _FatalHttpException(msg);
    }

    final acceptRanges = (res.headers.value(HttpHeaders.acceptRangesHeader) ?? '').toLowerCase();
    if (acceptRanges == 'none') {
      _supportsRange = false;
      _effectiveMaxWorkers = 1;
    }

    int startOffset;
    if (isPartial) {
      startOffset = requestedStart;
      final parsedTotal = _parseContentRangeTotal(res.headers.value(HttpHeaders.contentRangeHeader));
      if (parsedTotal != null && parsedTotal > 0) {
        if (_totalBytes > 0 && _totalBytes != parsedTotal) {
          // Server file size changed since last pause: restart cleanly from byte 0.
          await res.drain<void>().catchError((_) {});
          throw const _RestartCleanException();
        }
        _totalBytes = parsedTotal;
      } else if (res.contentLength > 0 && _totalBytes == 0) {
        _totalBytes = requestedStart + res.contentLength;
      }
    } else {
      // 200 OK: fresh download OR server ignored our Range header.
      if (requestedStart > 0) {
        _supportsRange = false;
        _effectiveMaxWorkers = 1;
        _rangeMap.clear();
        _raf?.truncateSync(0);
      }
      startOffset = 0;
      if (res.contentLength > 0) {
        _totalBytes = res.contentLength;
      }
    }

    if (_totalBytes > 0) {
      _chunkSize = _computeChunkSize(_totalBytes);
    }

    final openEnded = requestedEnd == null;
    final initialEnd = requestedEnd ??
        (_totalBytes > 0
            ? (_supportsRange && _effectiveMaxWorkers > 1 && _totalBytes >= args.minSegmentedBytes
                ? math.min(startOffset + _chunkSize, _totalBytes)
                : _totalBytes)
            : (1 << 62));

    final span = _WorkerSpan(
      workerId: workerId,
      start: startOffset,
      end: initialEnd,
      openEnded: openEnded,
    );
    _activeSpans[workerId] = span;
    _streamingWorkerIds.add(workerId);
    _emitProgress(force: true);

    onMetadataReady();

    try {
      await _consumeResponseIntoSpan(
        res,
        span,
        canExtendOpenEnded: openEnded && _totalBytes > 0,
        detectBurstThrottle: true,
      );
    } catch (e) {
      // Detect strict 1-connection IPTV server kicking Worker 0 right after Probe Worker 1 connects!
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final recentlyScaledUp = _lastScaleUpMs > 0 && (nowMs - _lastScaleUpMs) <= 3500;
      if (!_paused && !_cancelled && recentlyScaledUp && _effectiveMaxWorkers > 1 && e is! _BurstRotateException) {
        _singleConnKickDetected = true;
        _effectiveMaxWorkers = 1;
        _probeSucceeded = false;
        return;
      }
      rethrow;
    } finally {
      _activeSpans.remove(workerId);
      _streamingWorkerIds.remove(workerId);
    }

    onPrimaryDoneContinuePool();
  }

  /// Bounded-Range pool worker (workerId >= 1) pulling chunks until the file is 100% complete.
  Future<void> _runExtraWorker(
    HttpClient client,
    int workerId,
    _WorkerSpan initialSpan, {
    bool isPrimaryContinuation = false,
    required void Function() onProbeConfirmed,
    required void Function() onNeedMoreWork,
  }) async {
    _WorkerSpan? span = initialSpan;
    var consecutiveErrors = 0;

    while (span != null && !_paused && !_cancelled) {
      // If concurrency was capped below our slot, yield cleanly (unless we are the sole remaining worker).
      if (!isPrimaryContinuation && _activeSpans.length > _effectiveMaxWorkers) {
        _activeSpans.remove(workerId);
        return;
      }

      _activeSpans[workerId] = span;
      var triedOriginalFallback = false;

      try {
        final rangeHeader = 'bytes=${span.cursor}-${span.end - 1}';
        var targetUri = (_resolvedUriReusable && _resolvedUri != null) ? _resolvedUri! : _originalUri!;

        ({HttpClientResponse response, Uri resolvedUri}) resPair;
        try {
          resPair = await _getFollowingRedirects(
            client,
            targetUri,
            rangeHeader: rangeHeader,
            forceClose: _burstRotationEnabled && _effectiveMaxWorkers == 1,
          );
        } catch (e) {
          rethrow;
        }

        if (_paused || _cancelled) {
          await resPair.response.drain<void>().catchError((_) {});
          return;
        }

        var res = resPair.response;
        // If post-redirect token URL was single-use/expired, retry once against the original URL.
        if ((res.statusCode == 401 || res.statusCode == 403 || res.statusCode == 404 || res.statusCode == 410) &&
            targetUri != _originalUri &&
            !triedOriginalFallback) {
          triedOriginalFallback = true;
          _resolvedUriReusable = false;
          await res.drain<void>().catchError((_) {});
          resPair = await _getFollowingRedirects(
            client,
            _originalUri!,
            rangeHeader: rangeHeader,
            forceClose: _burstRotationEnabled && _effectiveMaxWorkers == 1,
          );
          if (_paused || _cancelled) {
            await resPair.response.drain<void>().catchError((_) {});
            return;
          }
          res = resPair.response;
        }

        if (res.statusCode == HttpStatus.ok) {
          // Server ignored Range header!
          await res.drain<void>().catchError((_) {});
          throw const _ServerIgnoredRangeException();
        }
        if (res.statusCode != HttpStatus.partialContent) {
          final code = res.statusCode;
          await res.drain<void>().catchError((_) {});
          throw _RangeRejectedException(code);
        }

        consecutiveErrors = 0;
        _streamingWorkerIds.add(workerId);
        await _consumeResponseIntoSpan(
          res,
          span,
          canExtendOpenEnded: false,
          detectBurstThrottle: _effectiveMaxWorkers == 1,
          onFirstBytes: () {
            if (!isPrimaryContinuation) {
              onProbeConfirmed();
            }
          },
        );
        _streamingWorkerIds.remove(workerId);
        _activeSpans.remove(workerId);

        if (_paused || _cancelled) return;
        if (!isPrimaryContinuation && _activeSpans.length >= _effectiveMaxWorkers) return;

        span = _claimNextSpan(workerId);
        if (span != null) {
          onNeedMoreWork();
        }
      } on _ServerIgnoredRangeException {
        _streamingWorkerIds.remove(workerId);
        _activeSpans.remove(workerId);
        _supportsRange = false;
        _effectiveMaxWorkers = 1;
        return;
      } on _RangeRejectedException catch (e) {
        _streamingWorkerIds.remove(workerId);
        _activeSpans.remove(workerId);
        final isConnectionLimit =
            e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 429 || e.statusCode == 503 || e.statusCode == 509;
        if (isConnectionLimit && (!isPrimaryContinuation || _activeSpans.isNotEmpty)) {
          // Server enforces a lower connection cap: gracefully clamp concurrency without failing!
          _effectiveMaxWorkers = math.max(1, _activeSpans.length);
          return;
        }
        if (isPrimaryContinuation && _activeSpans.isEmpty) {
          final msg = switch (e.statusCode) {
            401 || 403 || 509 =>
              'Sunucu indirmeyi reddetti (HTTP ${e.statusCode} — bağlantı sınırı dolu veya hesap yetkisiz olabilir)',
            404 => 'Dosya sunucuda bulunamadı (HTTP 404)',
            _ => 'Sunucu HTTP ${e.statusCode} döndürdü',
          };
          throw _FatalHttpException(msg);
        }
        return;
      } on _BurstRotateException {
        _streamingWorkerIds.remove(workerId);
        _activeSpans.remove(workerId);
        // Grab next gap on a fresh socket immediately.
        span = _claimNextSpan(workerId);
      } catch (e) {
        _streamingWorkerIds.remove(workerId);
        _activeSpans.remove(workerId);
        if (_paused || _cancelled) return;

        // If another worker is healthy and we hit a transient error on an extra worker,
        // release our remaining range and shrink concurrency slightly or retry once.
        consecutiveErrors++;
        if (!isPrimaryContinuation && _activeSpans.isNotEmpty) {
          if (consecutiveErrors >= 2) {
            _effectiveMaxWorkers = math.max(1, _activeSpans.length);
            return;
          }
          await Future<void>.delayed(Duration(milliseconds: args.retryDelayMs ?? 400));
          if (_paused || _cancelled) return;
          span = _claimNextSpan(workerId);
          continue;
        }
        rethrow;
      }
    }
  }

  /// Streams bytes from [res] into [span], coalescing 512 KiB disk writes via [RandomAccessFile].
  Future<void> _consumeResponseIntoSpan(
    HttpClientResponse res,
    _WorkerSpan span, {
    required bool canExtendOpenEnded,
    required bool detectBurstThrottle,
    void Function()? onFirstBytes,
  }) async {
    final buffer = BytesBuilder(copy: false);
    var writePos = span.cursor;
    var firstBytesFired = false;

    // Local burst-throttle tracker (for Nginx limit_rate_after on strict 1-connection servers).
    final reqStartMs = DateTime.now().millisecondsSinceEpoch;
    var reqBytes = 0;
    var initialPeakBps = 0;
    var slowWindowStartMs = 0;
    var slowWindowBytes = 0;
    var burstRotateTriggered = false;

    void flushBuffer() {
      if (_cancelled || buffer.isEmpty || _raf == null) return;
      final bytes = buffer.takeBytes();
      _raf!.setPositionSync(writePos);
      _raf!.writeFromSync(bytes);
      _rangeMap.add(writePos, writePos + bytes.length);
      writePos += bytes.length;
    }

    final completer = Completer<void>();
    late final StreamSubscription<List<int>> sub;

    sub = res.listen(
      (chunk) {
        if (_paused || _cancelled) {
          sub.cancel();
          if (!completer.isCompleted) completer.complete();
          return;
        }
        if (chunk.isEmpty) return;

        // If open-ended worker reached its current chunk boundary, try extending seamlessly
        // if nobody else claimed the following bytes; otherwise stop cleanly!
        var remaining = span.end - span.cursor;
        if (remaining <= 0 && canExtendOpenEnded) {
          _tryExtendOpenEndedSpan(span);
          remaining = span.end - span.cursor;
        }
        if (remaining <= 0) {
          sub.cancel();
          if (!completer.isCompleted) completer.complete();
          return;
        }

        final takeLen = chunk.length <= remaining ? chunk.length : remaining;
        if (takeLen == chunk.length) {
          buffer.add(chunk);
        } else {
          buffer.add(chunk is Uint8List ? Uint8List.sublistView(chunk, 0, takeLen) : chunk.sublist(0, takeLen));
        }
        span.cursor += takeLen;
        reqBytes += takeLen;
        _receivedAnyBytesThisAttempt = true;

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        _speedMeter.addBytes(takeLen, nowMs);

        if (!firstBytesFired && reqBytes >= 8 * 1024) {
          firstBytesFired = true;
          onFirstBytes?.call();
        }

        if (buffer.length >= _writeBufferBytes) {
          flushBuffer();
        }

        // Check for Nginx limit_rate_after signature when capped to 1 worker.
        if (detectBurstThrottle && _effectiveMaxWorkers == 1 && _supportsRange && _totalBytes >= args.minSegmentedBytes) {
          final elapsedMs = nowMs - reqStartMs;
          if (reqBytes <= 3 * 1024 * 1024 && elapsedMs >= 200) {
            final curBps = (reqBytes * 1000 / elapsedMs).round();
            if (curBps > initialPeakBps) initialPeakBps = curBps;
          } else if (reqBytes > 4 * 1024 * 1024 && initialPeakBps >= 3 * 1024 * 1024) {
            if (slowWindowStartMs == 0) {
              slowWindowStartMs = nowMs;
              slowWindowBytes = takeLen;
            } else {
              slowWindowBytes += takeLen;
              final slowDt = nowMs - slowWindowStartMs;
              if (slowDt >= 2000) {
                final slowBps = (slowWindowBytes * 1000 / slowDt).round();
                if (slowBps < initialPeakBps * 0.35 && slowBps < 1500 * 1024) {
                  if (!_burstRotationTested) {
                    _burstRotationTested = true;
                    _burstRotationEnabled = true;
                    _burstChunkBytes = math.max(2 * 1024 * 1024, math.min(reqBytes - slowWindowBytes, 8 * 1024 * 1024));
                    _chunkSize = _burstChunkBytes;
                    burstRotateTriggered = true;
                    sub.cancel();
                    if (!completer.isCompleted) {
                      completer.completeError(_BurstRotateException(initialPeakBps, slowBps));
                    }
                    return;
                  }
                } else if (_burstRotationEnabled) {
                  // Fresh socket didn't stay fast or wasn't throttled; reset window.
                  slowWindowStartMs = nowMs;
                  slowWindowBytes = 0;
                }
              }
            }
          }
        }

        // Persist meta periodically (~1.5s) and emit UI progress (~250ms).
        if (nowMs - _lastMetaSaveMs >= 1500 && _totalBytes > 0) {
          _lastMetaSaveMs = nowMs;
          if (buffer.isNotEmpty) flushBuffer();
          _rangeMap.saveMeta(_metaFile, _totalBytes);
        }
        _emitProgress();

        // Check if we finished our span right on this chunk.
        if (span.cursor >= span.end) {
          if (canExtendOpenEnded && _tryExtendOpenEndedSpan(span)) {
            return;
          }
          sub.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object err, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(err, st);
      },
      cancelOnError: true,
    );
    _activeSubs.add(sub);

    try {
      await completer.future;
    } finally {
      _activeSubs.remove(sub);
      if (!burstRotateTriggered) {
        try {
          await sub.cancel();
        } catch (_) {}
      }
      flushBuffer();
      if (!_cancelled && _totalBytes > 0) {
        _rangeMap.saveMeta(_metaFile, _totalBytes);
      }
      _emitProgress(force: true);
    }

    if (!_paused && !_cancelled && !firstBytesFired && reqBytes > 0) {
      onFirstBytes?.call();
    }

    // If server closed the stream prematurely before reaching span.end (when totalBytes is known),
    // treat as recoverable so primary kick-detection and retry logic handle it cleanly.
    if (!_paused && !_cancelled && _totalBytes > 0 && span.cursor < span.end) {
      throw const _RecoverableNetworkException('Parça bağlantısı erken kesildi');
    }
  }

  /// Attempts to extend an open-ended Worker 0 span into the next contiguous chunk
  /// if no other worker has claimed or completed those bytes.
  bool _tryExtendOpenEndedSpan(_WorkerSpan span) {
    if (_totalBytes <= 0 || span.end >= _totalBytes) return false;
    final nextStart = span.end;
    final nextEnd = math.min(nextStart + _chunkSize, _totalBytes);
    if (!_rangeMap.isCompletelyMissing(nextStart, nextEnd)) return false;
    for (final other in _activeSpans.values) {
      if (other.workerId == span.workerId) continue;
      if (other.cursor < nextEnd && other.end > nextStart) return false;
    }
    span.end = nextEnd;
    return true;
  }

  /// Claims the next unclaimed byte span (or steals half of the largest remaining active span).
  _WorkerSpan? _claimNextSpan(int workerId) {
    if (_totalBytes <= 0) return null;

    // Build a temporary map of everything already completed OR currently claimed by active workers.
    final covered = DownloadRangeMap(_rangeMap.ranges);
    for (final s in _activeSpans.values) {
      if (s.cursor < s.end) {
        covered.add(s.cursor, s.end);
      }
    }

    final unclaimed = covered.missingRanges(_totalBytes);
    if (unclaimed.isNotEmpty) {
      final gap = unclaimed.first;
      final end = math.min(gap.start + _chunkSize, gap.end);
      final span = _WorkerSpan(workerId: workerId, start: gap.start, end: end, openEnded: false);
      _activeSpans[workerId] = span;
      return span;
    }

    // Tail work-stealing: split the largest remaining active span in half so slow stragglers don't stall at 98%.
    _WorkerSpan? victim;
    for (final s in _activeSpans.values) {
      if (s.remaining >= _minStealBytes * 2) {
        if (victim == null || s.remaining > victim.remaining) {
          victim = s;
        }
      }
    }
    if (victim != null) {
      final mid = victim.cursor + (victim.remaining ~/ 2);
      final stolenEnd = victim.end;
      victim.end = mid;
      final span = _WorkerSpan(workerId: workerId, start: mid, end: stolenEnd, openEnded: false);
      _activeSpans[workerId] = span;
      return span;
    }
    return null;
  }

  void _emitProgress({bool force = false}) {
    if (_paused || _cancelled) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force && nowMs - _lastProgressEmitMs < 250) return;
    _lastProgressEmitMs = nowMs;

    // Include unflushed in-flight cursor progress so the progress bar moves smoothly every 250ms.
    final liveMap = DownloadRangeMap(_rangeMap.ranges);
    for (final s in _activeSpans.values) {
      if (s.cursor > s.start) {
        liveMap.add(s.start, s.cursor);
      }
    }
    final downloaded = liveMap.completedBytes;
    final speed = _speedMeter.bytesPerSecond(nowMs);
    final activeConns = math.max(1, _streamingWorkerIds.length);
    args.replyPort.send({
      'type': 'progress',
      'downloaded': downloaded,
      'total': _totalBytes,
      'speed': speed,
      'connections': activeConns,
    });
  }

  static int? _parseContentRangeTotal(String? header) {
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return null;
    return int.tryParse(header.substring(slash + 1).trim());
  }
}

class _RestartCleanException implements Exception {
  const _RestartCleanException();
}
