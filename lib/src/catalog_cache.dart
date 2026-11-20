import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'xtream.dart';

/// A cached snapshot of one Xtream catalog ([Kind.live], [Kind.movie] or [Kind.series]).
class CatalogSnapshot {
  const CatalogSnapshot({required this.items, required this.savedAt});

  final List<Item> items;
  final DateTime savedAt;

  bool isFresh([Duration ttl = CatalogCache.defaultFreshTtl, DateTime? now]) {
    final current = now ?? DateTime.now();
    return current.difference(savedAt) < ttl;
  }
}

/// Summary of cached catalogs on disk for one account.
class CatalogCacheSummary {
  const CatalogCacheSummary({
    required this.totalBytes,
    required this.cachedKinds,
    this.oldestSavedAt,
    this.newestSavedAt,
  });

  final int totalBytes;
  final int cachedKinds;
  final DateTime? oldestSavedAt;
  final DateTime? newestSavedAt;
}

/// Disk cache for Xtream catalogs (live channels, movies, series).
///
/// Stores gzip-compressed compact JSON with a deduplicated category table and
/// credential-free portable stream paths (never writes passwords or host
/// credentials to disk). Heavy JSON/gzip work runs in a background isolate so
/// startup and scrolling stay smooth on 1 GB RAM TV sticks and phones.
class CatalogCache extends ChangeNotifier {
  CatalogCache._();
  static final CatalogCache instance = CatalogCache._();

  static const int _schemaVersion = 1;

  /// Catalogs newer than this open immediately without a background refresh.
  /// Older snapshots still open immediately and trigger a silent network refresh.
  static const Duration defaultFreshTtl = Duration(hours: 6);

  Directory? _overrideDirectory;
  bool? _overrideUseIsolate;

  /// Directs cache reads/writes to [directory] (intended for tests).
  ///
  /// Defaults [useIsolate] to `false` in tests so widget tests running under
  /// `FakeAsync` complete deterministically without spawning background VM
  /// isolates; set `useIsolate: true` to explicitly exercise the isolate path.
  @visibleForTesting
  void setTestDirectory(Directory? directory, {bool? useIsolate}) {
    _overrideDirectory = directory;
    _overrideUseIsolate = directory == null ? null : (useIsolate ?? false);
  }

  bool get _useIsolate => _overrideUseIsolate ?? !Platform.environment.containsKey('FLUTTER_TEST');

  /// Whether disk caching is active in the current process.
  ///
  /// Under `flutter test`, disk caching stays disabled unless a test explicitly
  /// configures [setTestDirectory], preventing state leakage across widget tests.
  bool get isEnabled {
    if (kIsWeb) return false;
    if (_overrideDirectory != null) return true;
    return !Platform.environment.containsKey('FLUTTER_TEST');
  }

  /// Resolves the platform-native cache directory without external plugins.
  Directory resolveDirectory() {
    if (_overrideDirectory != null) return _overrideDirectory!;
    final sep = Platform.pathSeparator;
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_CACHE_HOME'];
      if (xdg != null && xdg.trim().isNotEmpty) {
        return Directory('${xdg.trim()}${sep}iptv_app${sep}catalog');
      }
      if (home.isNotEmpty) {
        return Directory('$home$sep.cache${sep}iptv_app${sep}catalog');
      }
    } else if (Platform.isMacOS && home.isNotEmpty) {
      return Directory('$home${sep}Library${sep}Caches${sep}iptv_app${sep}catalog');
    } else if (Platform.isIOS && home.isNotEmpty) {
      // On iOS, HOME points to the app sandbox container root; Library/Caches is
      // Apple's official cache folder (excluded from iCloud backup & Files app).
      return Directory('$home${sep}Library${sep}Caches${sep}iptv_catalog');
    } else if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.trim().isNotEmpty) {
        return Directory('${localAppData.trim()}${sep}iptv_app${sep}cache${sep}catalog');
      }
    }
    // Android Flutter maps Directory.systemTemp to the app's private cache dir.
    return Directory('${Directory.systemTemp.path}${sep}iptv_catalog');
  }

  File _fileFor(Account account, Kind kind) {
    final dir = resolveDirectory();
    final hash = accountCacheKey(account);
    return File('${dir.path}${Platform.pathSeparator}${hash}_${kind.name}.json.gz');
  }

  /// Deterministic, credential-free filename key derived from `account.key`.
  static String accountCacheKey(Account account) => _hash64Hex(account.key);

  /// Reads the cached catalog for [account] and [kind], or null when missing/corrupt.
  Future<CatalogSnapshot?> read(Account account, Kind kind) async {
    if (!isEnabled) return null;
    final file = _fileFor(account, kind);
    try {
      if (!_useIsolate) {
        if (!file.existsSync()) return null;
        final bytes = file.readAsBytesSync();
        if (bytes.isEmpty) return null;
        final decoded = _decodePayload(bytes, account, kind);
        if (decoded == null) _deleteSyncQuietly(file);
        return decoded;
      }
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final decoded = await Isolate.run(() => _decodePayload(bytes, account, kind));
      if (decoded == null) {
        await _deleteQuietly(file);
      }
      return decoded;
    } catch (_) {
      if (!_useIsolate) {
        _deleteSyncQuietly(file);
      } else {
        await _deleteQuietly(file);
      }
      return null;
    }
  }

  /// Writes [items] atomically to disk as a compressed, credential-free snapshot.
  Future<void> write(Account account, Kind kind, List<Item> items, {DateTime? now}) async {
    if (!isEnabled) return;
    final savedAt = now ?? DateTime.now();
    try {
      final dir = resolveDirectory();
      final target = _fileFor(account, kind);
      final tmp = File('${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}');
      if (!_useIsolate) {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final encoded = _encodePayload(items, account, kind, savedAt.millisecondsSinceEpoch);
        tmp.writeAsBytesSync(encoded, flush: true);
        try {
          tmp.renameSync(target.path);
        } catch (_) {
          if (target.existsSync()) target.deleteSync();
          tmp.renameSync(target.path);
        }
        notifyListeners();
        return;
      }
      if (!await dir.exists()) await dir.create(recursive: true);
      final encoded = await Isolate.run(() => _encodePayload(items, account, kind, savedAt.millisecondsSinceEpoch));
      await tmp.writeAsBytes(encoded, flush: true);
      try {
        await tmp.rename(target.path);
      } catch (_) {
        // Windows rename onto an existing target can fail; replace explicitly.
        if (await target.exists()) await target.delete();
        await tmp.rename(target.path);
      }
      notifyListeners();
    } catch (_) {
      // Cache write failure must never break playback or listing.
    }
  }

  /// Returns total bytes, cached list count and timestamp bounds for [account].
  Future<CatalogCacheSummary> summaryFor(Account account) async {
    if (!isEnabled) {
      return const CatalogCacheSummary(totalBytes: 0, cachedKinds: 0);
    }
    var bytes = 0;
    var count = 0;
    DateTime? oldest;
    DateTime? newest;
    for (final kind in Kind.values) {
      final file = _fileFor(account, kind);
      try {
        if (!_useIsolate) {
          if (!file.existsSync()) continue;
          final stat = file.statSync();
          bytes += stat.size;
          count++;
          final m = stat.modified;
          if (oldest == null || m.isBefore(oldest)) oldest = m;
          if (newest == null || m.isAfter(newest)) newest = m;
          continue;
        }
        if (!await file.exists()) continue;
        final stat = await file.stat();
        bytes += stat.size;
        count++;
        final m = stat.modified;
        if (oldest == null || m.isBefore(oldest)) oldest = m;
        if (newest == null || m.isAfter(newest)) newest = m;
      } catch (_) {}
    }
    return CatalogCacheSummary(
      totalBytes: bytes,
      cachedKinds: count,
      oldestSavedAt: oldest,
      newestSavedAt: newest,
    );
  }

  /// Removes all cached catalogs for [account].
  Future<void> clearAccount(Account account) async {
    if (!isEnabled) return;
    var removed = false;
    for (final kind in Kind.values) {
      final file = _fileFor(account, kind);
      if (!_useIsolate) {
        if (_deleteSyncQuietly(file)) removed = true;
      } else if (await _deleteQuietly(file)) {
        removed = true;
      }
    }
    if (removed) notifyListeners();
  }

  /// Removes all cached catalogs across all accounts.
  Future<void> clearAll() async {
    if (!isEnabled) return;
    try {
      final dir = resolveDirectory();
      if (!await dir.exists()) return;
      var removed = false;
      await for (final entity in dir.list()) {
        if (entity is File && (entity.path.endsWith('.json.gz') || entity.path.contains('.json.gz.tmp.'))) {
          if (await _deleteQuietly(entity)) removed = true;
        }
      }
      if (removed) notifyListeners();
    } catch (_) {}
  }

  Future<bool> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }

  bool _deleteSyncQuietly(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
        return true;
      }
    } catch (_) {}
    return false;
  }
}

/// Formats a cache timestamp age in concise Turkish ("Az önce", "14 dk önce", "3 sa önce").
String formatCacheAge(DateTime savedAt, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(savedAt);
  if (diff.inSeconds < 60) return 'az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
  if (diff.inHours < 24) return '${diff.inHours} sa önce';
  return '${diff.inDays} gün önce';
}

/// Two independent 32-bit FNV-1a lanes combined into a 16-hex-char string.
String _hash64Hex(String input) {
  final bytes = utf8.encode(input);
  var h1 = 0x811c9dc5;
  var h2 = 0x01000193;
  for (final b in bytes) {
    h1 ^= b;
    h1 = (h1 * 0x01000193) & 0xffffffff;
    h2 ^= (b ^ 0x5a);
    h2 = (h2 * 0x85ebca6b) & 0xffffffff;
  }
  return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
}

List<int> _encodePayload(List<Item> items, Account account, Kind kind, int savedAtMs) {
  final groupIndex = <String, int>{};
  final groups = <String>[];
  final rows = <List<Object?>>[];
  for (final item in items) {
    final gIdx = groupIndex.putIfAbsent(item.group, () {
      groups.add(item.group);
      return groups.length - 1;
    });
    final portable = item.url == null ? null : account.portableUrl(item.url!);
    rows.add([
      item.id,
      item.name,
      item.logo,
      gIdx,
      portable,
      item.seriesId,
      item.added,
    ]);
  }
  final payload = {
    'v': CatalogCache._schemaVersion,
    'savedAtMs': savedAtMs,
    'kind': kind.name,
    'groups': groups,
    'items': rows,
  };
  return gzip.encode(utf8.encode(jsonEncode(payload)));
}

CatalogSnapshot? _decodePayload(List<int> compressed, Account account, Kind expectedKind) {
  final raw = utf8.decode(gzip.decode(compressed));
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) return null;
  if (decoded['v'] != CatalogCache._schemaVersion) return null;
  if (decoded['kind'] != expectedKind.name) return null;
  final savedAtMs = decoded['savedAtMs'];
  if (savedAtMs is! int) return null;
  final rawGroups = decoded['groups'];
  final rawItems = decoded['items'];
  if (rawGroups is! List || rawItems is! List) return null;
  final groups = [for (final g in rawGroups) '$g'];
  final items = <Item>[];
  for (final row in rawItems) {
    if (row is! List || row.length < 7) continue;
    final id = row[0];
    final name = row[1];
    final logo = row[2];
    final gIdx = row[3];
    final portable = row[4];
    final seriesId = row[5];
    final added = row[6];
    if (id is! String || name is! String || gIdx is! int || gIdx < 0 || gIdx >= groups.length) continue;
    final fullUrl = portable is String ? account.fullUrl(portable) : null;
    items.add(Item(
      id: id,
      name: name,
      logo: logo is String ? logo : '',
      group: groups[gIdx],
      kind: expectedKind,
      url: fullUrl,
      seriesId: seriesId is int ? seriesId : null,
      added: added is int ? added : 0,
    ));
  }
  return CatalogSnapshot(
    items: items,
    savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs),
  );
}
