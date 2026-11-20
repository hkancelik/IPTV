import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';
import 'title_utils.dart';
import 'xtream.dart';

const _userAgent = 'VLC/3.0.20 LibVLC/3.0.20';

enum DownloadStatus { queued, downloading, paused, completed, failed }

/// One downloadable movie or series episode managed by [DownloadManager].
class DownloadEntry {
  DownloadEntry({
    required this.id,
    required this.accountKey,
    required this.portableUrl,
    required this.kind,
    required this.title,
    this.seriesTitle = '',
    this.season,
    this.episodeNumber,
    this.episodeTitle = '',
    this.logo = '',
    this.item,
    required this.fileName,
    required this.relativePath,
    required this.filePath,
    this.status = DownloadStatus.queued,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.error,
    required this.createdMs,
    required this.updatedMs,
  });

  final String id;
  final String accountKey;

  /// Stream path without host/credentials (e.g. "movie/42.mkv" or "series/99.mkv").
  final String portableUrl;
  final Kind kind;
  final String title;
  final String seriesTitle;
  final int? season;
  final int? episodeNumber;
  final String episodeTitle;
  final String logo;
  final Item? item;
  final String fileName;

  /// Path relative to the download root (e.g. "Filmler/Dune.mkv"), kept so iOS
  /// sandbox container UUID changes across updates still locate the file.
  final String relativePath;
  String filePath;
  DownloadStatus status;
  int downloadedBytes;
  int totalBytes;
  int speedBytesPerSec; // transient, not persisted
  String? error;
  final int createdMs;
  int updatedMs;

  bool get isCompleted => status == DownloadStatus.completed;
  bool get isDownloading => status == DownloadStatus.downloading;
  bool get isQueued => status == DownloadStatus.queued;
  bool get isPaused => status == DownloadStatus.paused;
  bool get isFailed => status == DownloadStatus.failed;
  bool get isActive => status == DownloadStatus.queued || status == DownloadStatus.downloading;

  double get progress {
    if (status == DownloadStatus.completed) return 1.0;
    if (totalBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
  }

  /// Effective size on disk for storage reporting.
  int get effectiveBytes => totalBytes > 0 ? totalBytes : downloadedBytes;

  bool fileExistsSync() {
    if (filePath.isEmpty) return false;
    try {
      return File(filePath).existsSync();
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountKey': accountKey,
        'portableUrl': portableUrl,
        'kind': kind.name,
        'title': title,
        'seriesTitle': seriesTitle,
        if (season != null) 'season': season,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
        'episodeTitle': episodeTitle,
        'logo': logo,
        if (item != null)
          'item': {
            ...item!.toJson(),
            // Never persist credentials in SharedPreferences.
            'url': item!.url == null ? null : portableKeyOfUrl(item!.url!),
          },
        'fileName': fileName,
        'relativePath': relativePath,
        'filePath': filePath,
        'status': status.name,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        if (error != null) 'error': error,
        'createdMs': createdMs,
        'updatedMs': updatedMs,
      };

  factory DownloadEntry.fromJson(Map<String, dynamic> j) {
    Item? item;
    final rawItem = j['item'];
    if (rawItem is Map<String, dynamic>) {
      try {
        item = Item.fromJson(rawItem);
      } catch (_) {}
    }
    return DownloadEntry(
      id: j['id'] as String,
      accountKey: (j['accountKey'] ?? '') as String,
      portableUrl: j['portableUrl'] as String,
      kind: Kind.values.byName(j['kind'] as String),
      title: j['title'] as String,
      seriesTitle: (j['seriesTitle'] ?? '') as String,
      season: (j['season'] as num?)?.toInt(),
      episodeNumber: (j['episodeNumber'] as num?)?.toInt(),
      episodeTitle: (j['episodeTitle'] ?? '') as String,
      logo: (j['logo'] ?? '') as String,
      item: item,
      fileName: (j['fileName'] ?? '') as String,
      relativePath: (j['relativePath'] ?? '') as String,
      filePath: (j['filePath'] ?? '') as String,
      status: DownloadStatus.values.byName((j['status'] ?? 'paused') as String),
      downloadedBytes: (j['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
      error: j['error'] as String?,
      createdMs: (j['createdMs'] as num?)?.toInt() ?? 0,
      updatedMs: (j['updatedMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Extracts a credential-free key such as `"movie/42.mkv"` or `"series/99.mkv"`
/// from either a full Xtream stream URL or an already-portable path.
String portableKeyOfUrl(String url, {Account? account}) {
  if (account != null) {
    final p = account.portableUrl(url);
    if (p != url) return p;
  }
  final uri = Uri.tryParse(url);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length >= 4 && (segs[0] == 'movie' || segs[0] == 'series' || segs[0] == 'live')) {
      return [segs[0], ...segs.skip(3)].join('/');
    }
  }
  return url;
}

/// Returns true when [url] points to an HLS playlist that cannot be saved as a single file.
bool isHlsPlaylistUrl(String url) {
  final uri = Uri.tryParse(url);
  final path = (uri?.path ?? url).toLowerCase();
  return path.endsWith('.m3u8');
}

/// Extracts a clean lowercase video extension (e.g. `.mkv`, `.mp4`), defaulting to `.mp4`.
String extensionFromUrl(String url) {
  final uri = Uri.tryParse(url);
  final path = uri?.path ?? url;
  final dot = path.lastIndexOf('.');
  if (dot >= 0 && dot < path.length - 1) {
    final ext = path.substring(dot).toLowerCase();
    if (RegExp(r'^\.[a-z0-9]{2,5}$').hasMatch(ext) && ext != '.m3u8') {
      return ext;
    }
  }
  return '.mp4';
}

/// Produces a filesystem-safe file or folder name across Linux, macOS, Windows and iOS.
String sanitizeFileName(String raw, {String fallback = 'video'}) {
  var cleaned = raw
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Avoid trailing dots/spaces (invalid on Windows / awkward on macOS).
  cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
  if (cleaned.isEmpty) return fallback;
  if (cleaned.length > 110) cleaned = cleaned.substring(0, 110).trim();
  return cleaned;
}

/// Human-readable Turkish byte formatting: `420 MB`, `1,4 GB`, `850 KB`.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const kb = 1024;
  const mb = 1024 * 1024;
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) {
    final v = (bytes / gb).toStringAsFixed(bytes >= 10 * gb ? 1 : 2).replaceAll('.', ',');
    return '$v GB';
  }
  if (bytes >= mb) {
    final v = (bytes / mb).toStringAsFixed(bytes >= 100 * mb ? 0 : 1).replaceAll('.', ',');
    return '$v MB';
  }
  if (bytes >= kb) {
    return '${(bytes / kb).round()} KB';
  }
  return '$bytes B';
}

String formatSpeed(int bytesPerSec) {
  if (bytesPerSec <= 0) return '';
  return '${formatBytes(bytesPerSec)}/sn';
}

/// Callbacks emitted by a [DownloadEngine] back to [DownloadManager].
class DownloadEngineCallbacks {
  const DownloadEngineCallbacks({
    required this.onProgress,
    required this.onCompleted,
    required this.onPaused,
    required this.onFailed,
  });

  final void Function(String id, int downloadedBytes, int totalBytes, int speedBytesPerSec) onProgress;
  final void Function(String id, String filePath, int totalBytes) onCompleted;
  final void Function(String id) onPaused;
  final void Function(String id, String error) onFailed;
}

/// Snapshot of a task still running natively (e.g. iOS background URLSession).
class NativeTaskSnapshot {
  const NativeTaskSnapshot({
    required this.id,
    required this.destination,
    required this.state,
    required this.downloadedBytes,
    required this.totalBytes,
  });

  final String id;
  final String destination;
  final String state; // downloading | paused | completed | canceling
  final int downloadedBytes;
  final int totalBytes;
}

/// Abstraction over platform download engines (pure Dart HTTP on PC, URLSession on iOS).
abstract class DownloadEngine {
  void bind(DownloadEngineCallbacks callbacks);

  Future<String?> defaultBaseDirectory();

  Future<void> start({
    required String id,
    required String url,
    required String destinationPath,
    required String userAgent,
  });

  Future<void> pause({required String id, required String destinationPath});

  Future<void> cancel({required String id, required String destinationPath});

  Future<List<NativeTaskSnapshot>> syncTasks() async => const [];

  void dispose() {}
}

/// Pure Dart HTTP download engine for Linux, macOS, Windows and Android.
///
/// Writes to `<destination>.part`, supports HTTP `Range` resume when paused or
/// interrupted, and atomically moves the completed file into place.
class DartDownloadEngine implements DownloadEngine {
  DownloadEngineCallbacks? _cb;
  final Map<String, _DartActiveTask> _tasks = {};

  @override
  void bind(DownloadEngineCallbacks callbacks) {
    _cb = callbacks;
  }

  @override
  Future<String?> defaultBaseDirectory() async {
    return resolveDesktopDownloadDirectory();
  }

  @override
  Future<void> start({
    required String id,
    required String url,
    required String destinationPath,
    required String userAgent,
  }) async {
    if (_tasks.containsKey(id)) return;
    final task = _DartActiveTask(id: id, destinationPath: destinationPath);
    _tasks[id] = task;
    unawaited(_run(task, url, userAgent));
  }

  Future<void> _run(_DartActiveTask task, String url, String userAgent) async {
    final partFile = File('${task.destinationPath}.part');
    final finalFile = File(task.destinationPath);
    IOSink? sink;
    HttpClient? client;
    try {
      await finalFile.parent.create(recursive: true);
      var existingBytes = 0;
      if (await partFile.exists()) {
        existingBytes = await partFile.length();
      }

      final uri = Uri.tryParse(url);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw const FormatException('Geçersiz indirme adresi');
      }

      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..idleTimeout = const Duration(seconds: 30);
      task.client = client;

      final req = await client.getUrl(uri);
      req.followRedirects = true;
      req.maxRedirects = 8;
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
      if (existingBytes > 0) {
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }

      final res = await req.close();
      if (task.paused || task.cancelled) return;

      if (res.statusCode == HttpStatus.requestedRangeNotSatisfiable && existingBytes > 0) {
        // File might already be completely downloaded or changed on server; restart cleanly.
        existingBytes = 0;
        if (await partFile.exists()) await partFile.delete();
        client.close(force: true);
        _tasks.remove(task.id);
        await start(id: task.id, url: url, destinationPath: task.destinationPath, userAgent: userAgent);
        return;
      }

      final isPartial = res.statusCode == HttpStatus.partialContent;
      if (res.statusCode != HttpStatus.ok && !isPartial) {
        final msg = switch (res.statusCode) {
          401 || 403 || 509 => 'Sunucu indirmeyi reddetti (HTTP ${res.statusCode} — bağlantı sınırı dolu veya hesap yetkisiz olabilir)',
          404 => 'Dosya sunucuda bulunamadı (HTTP 404)',
          _ => 'Sunucu HTTP ${res.statusCode} döndürdü',
        };
        throw HttpException(msg);
      }

      int totalBytes = 0;
      int downloaded = 0;
      if (isPartial) {
        downloaded = existingBytes;
        final contentRange = res.headers.value(HttpHeaders.contentRangeHeader);
        final parsedTotal = _parseContentRangeTotal(contentRange);
        if (parsedTotal != null && parsedTotal > 0) {
          totalBytes = parsedTotal;
        } else if (res.contentLength > 0) {
          totalBytes = existingBytes + res.contentLength;
        }
        sink = partFile.openWrite(mode: FileMode.append);
      } else {
        // Server ignored Range header and sent full content.
        downloaded = 0;
        totalBytes = res.contentLength > 0 ? res.contentLength : 0;
        sink = partFile.openWrite(mode: FileMode.write);
      }

      var lastEmit = DateTime.now();
      var lastBytes = downloaded;
      _cb?.onProgress(task.id, downloaded, totalBytes, 0);

      final completer = Completer<void>();
      late final StreamSubscription<List<int>> sub;
      sub = res.listen(
        (chunk) {
          if (task.paused || task.cancelled) {
            sub.cancel();
            if (!completer.isCompleted) completer.complete();
            return;
          }
          sink!.add(chunk);
          downloaded += chunk.length;
          final now = DateTime.now();
          final dtMs = now.difference(lastEmit).inMilliseconds;
          if (dtMs >= 250) {
            final speed = ((downloaded - lastBytes) * 1000 / dtMs).round().clamp(0, 1 << 62);
            lastEmit = now;
            lastBytes = downloaded;
            _cb?.onProgress(task.id, downloaded, totalBytes, speed);
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
      task.subscription = sub;

      await completer.future;
      await sink.flush();
      await sink.close();
      sink = null;

      if (task.cancelled) {
        if (await partFile.exists()) await partFile.delete();
        return;
      }
      if (task.paused) {
        _cb?.onPaused(task.id);
        return;
      }

      if (totalBytes > 0 && downloaded < totalBytes) {
        throw const HttpException('Bağlantı indirme bitmeden kesildi');
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      try {
        await partFile.rename(finalFile.path);
      } on FileSystemException {
        await partFile.copy(finalFile.path);
        if (await partFile.exists()) await partFile.delete();
      }
      final finalSize = await finalFile.length();
      _tasks.remove(task.id);
      _cb?.onCompleted(task.id, finalFile.path, finalSize);
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      _tasks.remove(task.id);
      if (task.cancelled) {
        try {
          if (await partFile.exists()) await partFile.delete();
        } catch (_) {}
        return;
      }
      if (task.paused) {
        _cb?.onPaused(task.id);
        return;
      }
      final msg = e is HttpException ? e.message : (e is FormatException ? e.message : 'İndirme başarısız: $e');
      _cb?.onFailed(task.id, msg);
    } finally {
      _tasks.remove(task.id);
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }

  static int? _parseContentRangeTotal(String? header) {
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return null;
    return int.tryParse(header.substring(slash + 1).trim());
  }

  @override
  Future<void> pause({required String id, required String destinationPath}) async {
    final task = _tasks[id];
    if (task == null) {
      _cb?.onPaused(id);
      return;
    }
    task.paused = true;
    await task.subscription?.cancel();
    task.client?.close(force: true);
    _tasks.remove(id);
    _cb?.onPaused(id);
  }

  @override
  Future<void> cancel({required String id, required String destinationPath}) async {
    final task = _tasks.remove(id);
    if (task != null) {
      task.cancelled = true;
      await task.subscription?.cancel();
      task.client?.close(force: true);
    }
    try {
      final part = File('$destinationPath.part');
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }

  @override
  Future<List<NativeTaskSnapshot>> syncTasks() async => const [];

  @override
  void dispose() {
    for (final t in _tasks.values.toList()) {
      t.paused = true;
      t.subscription?.cancel();
      t.client?.close(force: true);
    }
    _tasks.clear();
  }
}

class _DartActiveTask {
  _DartActiveTask({required this.id, required this.destinationPath});

  final String id;
  final String destinationPath;
  HttpClient? client;
  StreamSubscription<List<int>>? subscription;
  bool paused = false;
  bool cancelled = false;
}

/// iOS native `URLSessionConfiguration.background` engine backed by `BackgroundDownloadPlugin.swift`.
class IosBackgroundDownloadEngine implements DownloadEngine {
  static const MethodChannel _channel = MethodChannel('iptv/background_downloads');

  DownloadEngineCallbacks? _cb;
  bool _handlerBound = false;

  @override
  void bind(DownloadEngineCallbacks callbacks) {
    _cb = callbacks;
    if (_handlerBound) return;
    _handlerBound = true;
    _channel.setMethodCallHandler(_onNativeEvent);
  }

  Future<dynamic> _onNativeEvent(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final id = args['id'] as String?;
    if (id == null) return;
    switch (call.method) {
      case 'progress':
        _cb?.onProgress(
          id,
          (args['downloadedBytes'] as num?)?.toInt() ?? 0,
          (args['totalBytes'] as num?)?.toInt() ?? 0,
          (args['speedBytesPerSec'] as num?)?.toInt() ?? 0,
        );
      case 'completed':
        _cb?.onCompleted(
          id,
          (args['filePath'] as String?) ?? '',
          (args['totalBytes'] as num?)?.toInt() ?? 0,
        );
      case 'paused':
        _cb?.onPaused(id);
      case 'failed':
        _cb?.onFailed(id, (args['error'] as String?) ?? 'İndirme başarısız');
    }
  }

  @override
  Future<String?> defaultBaseDirectory() async {
    try {
      return await _channel.invokeMethod<String>('getDownloadDirectory');
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> start({
    required String id,
    required String url,
    required String destinationPath,
    required String userAgent,
  }) async {
    try {
      await _channel.invokeMethod<void>('start', {
        'id': id,
        'url': url,
        'destination': destinationPath,
        'userAgent': userAgent,
      });
    } on MissingPluginException {
      _cb?.onFailed(id, 'iOS arka plan indirme eklentisi kullanılamıyor');
    } catch (e) {
      _cb?.onFailed(id, 'İndirme başlatılamadı: $e');
    }
  }

  @override
  Future<void> pause({required String id, required String destinationPath}) async {
    try {
      await _channel.invokeMethod<void>('pause', {'id': id, 'destination': destinationPath});
    } catch (_) {}
  }

  @override
  Future<void> cancel({required String id, required String destinationPath}) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id, 'destination': destinationPath});
    } catch (_) {}
  }

  @override
  Future<List<NativeTaskSnapshot>> syncTasks() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('syncTasks');
      if (raw == null) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            NativeTaskSnapshot(
              id: '${item['id'] ?? ''}',
              destination: '${item['destination'] ?? ''}',
              state: '${item['state'] ?? 'downloading'}',
              downloadedBytes: (item['downloadedBytes'] as num?)?.toInt() ?? 0,
              totalBytes: (item['totalBytes'] as num?)?.toInt() ?? 0,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
  @override
  void dispose() {}
}

/// Resolves the default download folder for desktop/Android platforms.
String resolveDesktopDownloadDirectory() {
  if (kIsWeb) return '';
  final sep = Platform.pathSeparator;
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (Platform.isLinux && home.isNotEmpty) {
    final xdg = _readXdgDownloadDir(home);
    if (xdg != null && xdg.isNotEmpty) return '$xdg${sep}IPTV';
    final trDir = Directory('$home$sepİndirilenler');
    final enDir = Directory('$home${sep}Downloads');
    if (trDir.existsSync() && !enDir.existsSync()) return '${trDir.path}${sep}IPTV';
    return '${enDir.path}${sep}IPTV';
  }
  if (Platform.isMacOS && home.isNotEmpty) {
    return '$home${sep}Downloads${sep}IPTV';
  }
  if (Platform.isWindows && home.isNotEmpty) {
    return '$home${sep}Downloads${sep}IPTV';
  }
  if (Platform.isAndroid) {
    return '/storage/emulated/0/Download/IPTV';
  }
  return '${Directory.systemTemp.path}${sep}iptv_downloads';
}

String? _readXdgDownloadDir(String home) {
  final envDir = Platform.environment['XDG_DOWNLOAD_DIR'];
  if (envDir != null && envDir.trim().isNotEmpty) {
    return envDir.trim().replaceFirst(r'$HOME', home);
  }
  try {
    final cfg = File('$home/.config/user-dirs.dirs');
    if (!cfg.existsSync()) return null;
    for (final line in cfg.readAsLinesSync()) {
      final t = line.trim();
      if (t.startsWith('XDG_DOWNLOAD_DIR=')) {
        var val = t.substring('XDG_DOWNLOAD_DIR='.length).trim();
        if (val.startsWith('"') && val.endsWith('"') && val.length >= 2) {
          val = val.substring(1, val.length - 1);
        }
        val = val.replaceFirst(r'$HOME', home);
        if (val.isNotEmpty) return val;
      }
    }
  } catch (_) {}
  return null;
}

/// Result returned when enqueueing one or more items for download.
class EnqueueResult {
  const EnqueueResult({required this.added, this.skipped = 0, this.error});

  final int added;
  final int skipped;
  final String? error;
}

/// Central download queue, metadata store and local-file resolver for movies and series.
///
/// Downloads run sequentially (1 active transfer at a time) so single-connection IPTV
/// accounts stay safe from provider connection-limit kicks.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const _prefsKey = 'downloads_v1';

  final List<DownloadEntry> _entries = [];
  final Map<String, String> _runtimeUrls = {}; // entry.id -> full HTTP URL (in-memory only)

  DownloadEngine? _engine;
  String _baseDir = '';
  bool _loaded = false;
  Account? _currentAccount;
  Timer? _persistTimer;

  @visibleForTesting
  String? debugBaseDir;

  @visibleForTesting
  DownloadEngine? debugEngine;

  List<DownloadEntry> get entries => List.unmodifiable(_entries);
  List<DownloadEntry> get completedEntries => _entries.where((e) => e.isCompleted).toList();
  List<DownloadEntry> get activeEntries => _entries.where((e) => !e.isCompleted).toList();
  int get completedCount => _entries.where((e) => e.isCompleted).length;
  int get activeCount => _entries.where((e) => e.isActive).length;
  bool get hasDownloading => _entries.any((e) => e.isDownloading);
  bool get hasAny => _entries.isNotEmpty;
  String get baseDir => _effectiveBaseDir();

  int get totalStorageBytes {
    var sum = 0;
    for (final e in _entries) {
      if (e.isCompleted) {
        sum += e.effectiveBytes;
      }
    }
    return sum;
  }

  DownloadEngine _ensureEngine() {
    final override = debugEngine;
    if (override != null) {
      if (!identical(_engine, override)) {
        _engine = override;
        _bindEngine(override);
      }
      return override;
    }
    if (_engine != null) return _engine!;
    final eng = (!kIsWeb && Platform.isIOS) ? IosBackgroundDownloadEngine() : DartDownloadEngine();
    _engine = eng;
    _bindEngine(eng);
    return eng;
  }

  void _bindEngine(DownloadEngine engine) {
    engine.bind(
      DownloadEngineCallbacks(
        onProgress: _onProgress,
        onCompleted: _onCompleted,
        onPaused: _onPaused,
        onFailed: _onFailed,
      ),
    );
  }

  String _effectiveBaseDir() {
    if (debugBaseDir != null && debugBaseDir!.isNotEmpty) return debugBaseDir!;
    if (!kIsWeb && !Platform.isIOS) {
      final custom = AppSettings.instance.downloadDir.trim();
      if (custom.isNotEmpty) return custom;
    }
    if (_baseDir.isNotEmpty) return _baseDir;
    return resolveDesktopDownloadDirectory();
  }

  /// Associates the currently signed-in account so paused/queued entries can
  /// reconstruct authenticated URLs on demand without storing passwords on disk.
  void setAccount(Account? account) {
    _currentAccount = account;
  }

  /// Loads persisted download metadata, refreshes platform paths, and syncs any
  /// background iOS tasks that finished while the app was suspended.
  Future<void> load() async {
    final eng = _ensureEngine();
    if (debugBaseDir != null && debugBaseDir!.isNotEmpty) {
      _baseDir = debugBaseDir!;
    } else {
      _baseDir = (await eng.defaultBaseDirectory()) ?? resolveDesktopDownloadDirectory();
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _entries.clear();
    var dirty = false;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          if (item is! Map<String, dynamic>) continue;
          try {
            final e = DownloadEntry.fromJson(item);
            // Re-resolve path from relativePath when iOS container path shifts.
            if (!e.fileExistsSync() && e.relativePath.isNotEmpty && _baseDir.isNotEmpty) {
              final candidate = '$_baseDir${Platform.pathSeparator}${e.relativePath}';
              if (File(candidate).existsSync()) {
                e.filePath = candidate;
                dirty = true;
              }
            }
            // Refresh actual file size on completed entries.
            if (e.isCompleted) {
              if (e.fileExistsSync()) {
                try {
                  final len = File(e.filePath).lengthSync();
                  if (len > 0 && len != e.totalBytes) {
                    e.totalBytes = len;
                    e.downloadedBytes = len;
                    dirty = true;
                  }
                } catch (_) {}
              } else {
                // File was removed externally (e.g. from Files app or file manager).
                dirty = true;
                continue;
              }
            } else if (e.isDownloading) {
              // If the process restarted, mark in-flight downloads paused until
              // syncTasks confirms a live iOS background task.
              e.status = DownloadStatus.paused;
              e.speedBytesPerSec = 0;
              // Refresh partial size if .part exists on PC.
              final part = File('${e.filePath}.part');
              if (part.existsSync()) {
                e.downloadedBytes = part.lengthSync();
              }
              dirty = true;
            }
            _entries.add(e);
          } catch (_) {
            dirty = true;
          }
        }
      } catch (_) {
        dirty = true;
      }
    }

    // Reconcile native background tasks on iOS.
    final nativeTasks = await eng.syncTasks();
    final nativeById = {for (final t in nativeTasks) t.id: t};
    for (final e in _entries) {
      final snap = nativeById[e.id];
      if (snap != null) {
        if (snap.state == 'downloading') {
          e.status = DownloadStatus.downloading;
          e.downloadedBytes = snap.downloadedBytes;
          if (snap.totalBytes > 0) e.totalBytes = snap.totalBytes;
          dirty = true;
        }
      } else if (!e.isCompleted && e.fileExistsSync()) {
        // Background download finished while Flutter engine was terminated.
        final len = File(e.filePath).lengthSync();
        if (len > 0) {
          e.status = DownloadStatus.completed;
          e.downloadedBytes = len;
          e.totalBytes = len;
          e.speedBytesPerSec = 0;
          e.error = null;
          dirty = true;
        }
      }
    }

    _loaded = true;
    notifyListeners();
    if (dirty) await _persistNow();
  }

  /// Finds the download entry matching [url] (full or portable).
  DownloadEntry? entryForUrl(String url, {Account? account}) {
    if (url.isEmpty) return null;
    final key = portableKeyOfUrl(url, account: account ?? _currentAccount);
    for (final e in _entries) {
      if (e.portableUrl == key || e.filePath == url) return e;
    }
    return null;
  }

  DownloadEntry? entryById(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Returns the verified local file path if [url] has finished downloading and
  /// the file still exists on disk; otherwise null.
  String? localPathForUrl(String url, {Account? account}) {
    final e = entryForUrl(url, account: account);
    if (e == null || !e.isCompleted) return null;
    return e.fileExistsSync() ? e.filePath : null;
  }

  /// Enqueues a single movie for download.
  Future<EnqueueResult> enqueueMovie(Item item, Account account) async {
    if (!_loaded) await load();
    setAccount(account);
    final url = item.url;
    if (url == null || url.isEmpty) {
      return const EnqueueResult(added: 0, error: 'Film adresi bulunamadı');
    }
    if (isHlsPlaylistUrl(url)) {
      return const EnqueueResult(added: 0, error: 'Bu yayın (.m3u8) doğrudan indirmeyi desteklemiyor');
    }
    final portable = portableKeyOfUrl(url, account: account);
    final existing = entryForUrl(portable, account: account);
    if (existing != null) {
      if (existing.isCompleted && existing.fileExistsSync()) {
        return const EnqueueResult(added: 0, skipped: 1);
      }
      if (existing.isPaused || existing.isFailed) {
        _runtimeUrls[existing.id] = url;
        await resume(existing.id, account: account);
        return const EnqueueResult(added: 1);
      }
      return const EnqueueResult(added: 0, skipped: 1);
    }

    final parsed = parsedTitleOf(item);
    final cleanTitle = parsed.year != null && parsed.year!.isNotEmpty
        ? '${parsed.title} (${parsed.year})'
        : parsed.title;
    final ext = extensionFromUrl(url);
    final baseName = sanitizeFileName(cleanTitle, fallback: 'film_${item.streamId ?? item.id}');
    final sep = Platform.pathSeparator;
    final relPath = _uniqueRelativePath('Filmler$sep$baseName$ext');
    final fileName = relPath.split(sep).last;
    final fullPath = '${_effectiveBaseDir()}$sep$relPath';
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _entryId(account.key, portable);

    final entry = DownloadEntry(
      id: id,
      accountKey: account.key,
      portableUrl: portable,
      kind: Kind.movie,
      title: parsed.title,
      logo: item.logo,
      item: item,
      fileName: fileName,
      relativePath: relPath,
      filePath: fullPath,
      status: DownloadStatus.queued,
      createdMs: now,
      updatedMs: now,
    );
    _entries.insert(0, entry);
    _runtimeUrls[id] = url;
    notifyListeners();
    await _persistNow();
    await _pumpQueue();
    return const EnqueueResult(added: 1);
  }

  /// Enqueues a single series episode for download.
  Future<EnqueueResult> enqueueEpisode(Item series, Episode episode, Account account) async {
    if (!_loaded) await load();
    setAccount(account);
    final url = episode.url;
    if (url.isEmpty) {
      return const EnqueueResult(added: 0, error: 'Bölüm adresi bulunamadı');
    }
    if (isHlsPlaylistUrl(url)) {
      return const EnqueueResult(added: 0, error: 'Bu yayın (.m3u8) doğrudan indirmeyi desteklemiyor');
    }
    final portable = portableKeyOfUrl(url, account: account);
    final existing = entryForUrl(portable, account: account);
    if (existing != null) {
      if (existing.isCompleted && existing.fileExistsSync()) {
        return const EnqueueResult(added: 0, skipped: 1);
      }
      if (existing.isPaused || existing.isFailed) {
        _runtimeUrls[existing.id] = url;
        await resume(existing.id, account: account);
        return const EnqueueResult(added: 1);
      }
      return const EnqueueResult(added: 0, skipped: 1);
    }

    final seriesTitle = parsedTitleOf(series).title;
    final sCode = 'S${episode.season.toString().padLeft(2, '0')}E${episode.number.toString().padLeft(2, '0')}';
    final displayTitle = '$seriesTitle $sCode';
    final ext = extensionFromUrl(url);
    final folder = sanitizeFileName(seriesTitle, fallback: 'Dizi');
    final epPart = episode.title.trim().isNotEmpty ? ' - ${episode.title.trim()}' : '';
    final baseName = sanitizeFileName('$seriesTitle - $sCode$epPart', fallback: sCode);
    final sep = Platform.pathSeparator;
    final relPath = _uniqueRelativePath('Diziler$sep$folder$sep$baseName$ext');
    final fileName = relPath.split(sep).last;
    final fullPath = '${_effectiveBaseDir()}$sep$relPath';
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _entryId(account.key, portable);

    final entry = DownloadEntry(
      id: id,
      accountKey: account.key,
      portableUrl: portable,
      kind: Kind.series,
      title: displayTitle,
      seriesTitle: seriesTitle,
      season: episode.season,
      episodeNumber: episode.number,
      episodeTitle: episode.title,
      logo: episode.image.isNotEmpty ? episode.image : series.logo,
      item: series,
      fileName: fileName,
      relativePath: relPath,
      filePath: fullPath,
      status: DownloadStatus.queued,
      createdMs: now,
      updatedMs: now,
    );
    _entries.insert(0, entry);
    _runtimeUrls[id] = url;
    notifyListeners();
    await _persistNow();
    await _pumpQueue();
    return const EnqueueResult(added: 1);
  }

  /// Enqueues every un-downloaded episode in [episodes] sequentially.
  Future<EnqueueResult> enqueueSeason(Item series, List<Episode> episodes, Account account) async {
    if (!_loaded) await load();
    setAccount(account);
    var added = 0;
    var skipped = 0;
    String? lastError;
    for (final ep in episodes) {
      final res = await enqueueEpisode(series, ep, account);
      added += res.added;
      skipped += res.skipped;
      if (res.error != null) lastError = res.error;
    }
    return EnqueueResult(added: added, skipped: skipped, error: added == 0 ? lastError : null);
  }

  Future<void> pause(String id) async {
    final e = entryById(id);
    if (e == null) return;
    if (e.isQueued) {
      e.status = DownloadStatus.paused;
      e.speedBytesPerSec = 0;
      e.updatedMs = DateTime.now().millisecondsSinceEpoch;
      notifyListeners();
      await _persistNow();
      return;
    }
    if (!e.isDownloading) return;
    e.status = DownloadStatus.paused;
    e.speedBytesPerSec = 0;
    e.updatedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _persistNow();
    await _ensureEngine().pause(id: e.id, destinationPath: e.filePath);
    await _pumpQueue();
  }

  Future<void> resume(String id, {Account? account}) async {
    final e = entryById(id);
    if (e == null || e.isCompleted) return;
    final acc = account ?? _currentAccount;
    if (acc != null) {
      _runtimeUrls[e.id] = acc.fullUrl(e.portableUrl);
    }
    if (!_runtimeUrls.containsKey(e.id)) {
      e.status = DownloadStatus.failed;
      e.error = 'Devam etmek için hesaba giriş yapmalısın';
      notifyListeners();
      await _persistNow();
      return;
    }
    e.status = DownloadStatus.queued;
    e.error = null;
    e.speedBytesPerSec = 0;
    e.updatedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _persistNow();
    await _pumpQueue();
  }

  Future<void> retry(String id, {Account? account}) => resume(id, account: account);

  Future<void> cancel(String id) async {
    final e = entryById(id);
    if (e == null) return;
    final wasDownloading = e.isDownloading;
    _entries.removeWhere((x) => x.id == id);
    _runtimeUrls.remove(id);
    notifyListeners();
    await _ensureEngine().cancel(id: id, destinationPath: e.filePath);
    await _deleteFilesOf(e);
    await _persistNow();
    if (wasDownloading) await _pumpQueue();
  }

  /// Deletes a completed or partial download and removes its files from disk.
  Future<void> delete(String id) => cancel(id);

  /// Deletes every downloaded and active entry along with files on disk.
  Future<void> deleteAll() async {
    final copy = [..._entries];
    _entries.clear();
    _runtimeUrls.clear();
    notifyListeners();
    for (final e in copy) {
      await _ensureEngine().cancel(id: e.id, destinationPath: e.filePath);
      await _deleteFilesOf(e);
    }
    await _persistNow();
  }

  Future<void> _deleteFilesOf(DownloadEntry e) async {
    for (final p in [e.filePath, '${e.filePath}.part', '${e.filePath}.resume']) {
      if (p.isEmpty) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _pumpQueue() async {
    if (_entries.any((e) => e.isDownloading)) return;
    // Pick the oldest queued entry so season downloads proceed in order (E01, E02, ...).
    DownloadEntry? next;
    for (final e in _entries.reversed) {
      if (e.isQueued) {
        next = e;
        break;
      }
    }
    if (next == null) return;

    var url = _runtimeUrls[next.id];
    if (url == null && _currentAccount != null) {
      url = _currentAccount!.fullUrl(next.portableUrl);
      _runtimeUrls[next.id] = url;
    }
    if (url == null || url.isEmpty) {
      next.status = DownloadStatus.paused;
      next.error = 'İndirmeyi sürdürmek için hesaba giriş yapmalısın';
      notifyListeners();
      await _persistNow();
      return;
    }

    next.status = DownloadStatus.downloading;
    next.error = null;
    next.updatedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    await _persistNow();

    await _ensureEngine().start(
      id: next.id,
      url: url,
      destinationPath: next.filePath,
      userAgent: _userAgent,
    );
  }

  void _onProgress(String id, int downloadedBytes, int totalBytes, int speedBytesPerSec) {
    final e = entryById(id);
    if (e == null || e.isCompleted) return;
    e.status = DownloadStatus.downloading;
    e.downloadedBytes = downloadedBytes;
    if (totalBytes > 0) e.totalBytes = totalBytes;
    e.speedBytesPerSec = speedBytesPerSec;
    e.updatedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    _schedulePersist();
  }

  void _onCompleted(String id, String filePath, int totalBytes) {
    final e = entryById(id);
    if (e == null) return;
    if (filePath.isNotEmpty) e.filePath = filePath;
    e.status = DownloadStatus.completed;
    if (totalBytes > 0) {
      e.totalBytes = totalBytes;
      e.downloadedBytes = totalBytes;
    }
    e.speedBytesPerSec = 0;
    e.error = null;
    e.updatedMs = DateTime.now().millisecondsSinceEpoch;
    _runtimeUrls.remove(id);
    notifyListeners();
    unawaited(_persistNow());
    unawaited(_pumpQueue());
  }

  void _onPaused(String id) {
    final e = entryById(id);
    if (e == null || e.isCompleted) return;
    e.status = DownloadStatus.paused;
    e.speedBytesPerSec = 0;
    e.updatedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    unawaited(_persistNow());
    unawaited(_pumpQueue());
  }

  void _onFailed(String id, String error) {
    final e = entryById(id);
    if (e == null || e.isCompleted) return;
    e.status = DownloadStatus.failed;
    e.speedBytesPerSec = 0;
    e.error = error;
    e.updatedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    unawaited(_persistNow());
    unawaited(_pumpQueue());
  }

  /// Opens the download directory in the desktop OS file manager.
  Future<bool> openDownloadFolder() async {
    if (kIsWeb || Platform.isIOS || Platform.isAndroid) return false;
    final dir = Directory(_effectiveBaseDir());
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      if (Platform.isLinux) {
        await Process.start('xdg-open', [dir.path], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [dir.path], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isWindows) {
        await Process.start('explorer', [dir.path], mode: ProcessStartMode.detached);
        return true;
      }
    } catch (_) {}
    return false;
  }

  String _entryId(String accountKey, String portableUrl) => '${accountKey.hashCode.toRadixString(16)}:$portableUrl';

  String _uniqueRelativePath(String desired) {
    final used = {for (final e in _entries) e.relativePath.toLowerCase()};
    if (!used.contains(desired.toLowerCase())) return desired;
    final dot = desired.lastIndexOf('.');
    final stem = dot > 0 ? desired.substring(0, dot) : desired;
    final ext = dot > 0 ? desired.substring(dot) : '';
    var i = 2;
    while (used.contains('$stem ($i)$ext'.toLowerCase())) {
      i++;
    }
    return '$stem ($i)$ext';
  }

  void _schedulePersist() {
    if (_persistTimer?.isActive ?? false) return;
    _persistTimer = Timer(const Duration(seconds: 2), () {
      _persistTimer = null;
      unawaited(_persistNow());
    });
  }

  Future<void> _persistNow() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode([for (final e in _entries) e.toJson()]);
      await prefs.setString(_prefsKey, json);
    } catch (_) {}
  }

  /// Resets in-memory state for deterministic unit/widget tests.
  @visibleForTesting
  void resetForTest() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _engine?.dispose();
    _engine = null;
    debugEngine = null;
    debugBaseDir = null;
    _baseDir = '';
    _entries.clear();
    _runtimeUrls.clear();
    _currentAccount = null;
    _loaded = false;
    notifyListeners();
  }
}
