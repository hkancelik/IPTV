import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'catalog_cache.dart';
import 'global_search_page.dart';
import 'library.dart';
import 'remote_entry.dart';
import 'settings.dart';
import 'xtream.dart';

/// Raised when LAN sync cannot complete (wrong PIN, account mismatch, network failure, etc.).
class LanSyncException implements Exception {
  const LanSyncException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Result of merging a remote [SyncSnapshot] into the local device.
class SyncMergeResult {
  const SyncMergeResult({
    required this.peerDeviceName,
    required this.libraryStats,
    required this.settingsUpdated,
    required this.recentSearchesCount,
  });

  final String peerDeviceName;
  final LibraryMergeStats libraryStats;
  final bool settingsUpdated;
  final int recentSearchesCount;

  String get summaryText {
    final parts = <String>[
      '${libraryStats.totalFavorites} favori',
      '${libraryStats.totalHistory} izleme kaydı',
      if (libraryStats.totalLogs > 0) '${libraryStats.totalLogs} günlük kaydı',
      if (settingsUpdated) 'tercihler ve kategori düzeni güncellendi',
    ];
    return parts.join(' · ');
  }
}

/// Credential-free snapshot exchanged between devices over LAN or offline JSON backup.
class SyncSnapshot {
  const SyncSnapshot({
    required this.version,
    required this.accountHash,
    required this.deviceName,
    required this.createdAtMs,
    required this.library,
    required this.settings,
    required this.recentSearches,
  });

  static const int currentVersion = 1;

  final int version;
  final String accountHash;
  final String deviceName;
  final int createdAtMs;
  final Map<String, dynamic> library;
  final Map<String, dynamic> settings;
  final List<String> recentSearches;

  Map<String, dynamic> toJson() => {
        'v': version,
        'accountHash': accountHash,
        'deviceName': deviceName,
        'createdAtMs': createdAtMs,
        'library': library,
        'settings': settings,
        'recentSearches': recentSearches,
      };

  String toJsonString({bool pretty = false}) =>
      pretty ? const JsonEncoder.withIndent('  ').convert(toJson()) : jsonEncode(toJson());

  factory SyncSnapshot.fromJson(Map<String, dynamic> json) {
    final v = json['v'];
    if (v != currentVersion) {
      throw const LanSyncException('Desteklenmeyen eşitleme sürümü');
    }
    final accountHash = json['accountHash'];
    if (accountHash is! String || accountHash.isEmpty) {
      throw const LanSyncException('Eşitleme verisi geçersiz (hesap özeti eksik)');
    }
    final lib = json['library'];
    final settings = json['settings'];
    if (lib is! Map<String, dynamic> || settings is! Map<String, dynamic>) {
      throw const LanSyncException('Eşitleme verisi bozuk');
    }
    final rawSearches = json['recentSearches'];
    final searches = rawSearches is List ? [for (final s in rawSearches) if (s is String) s] : const <String>[];
    return SyncSnapshot(
      version: v as int,
      accountHash: accountHash,
      deviceName: json['deviceName'] is String && (json['deviceName'] as String).trim().isNotEmpty
          ? (json['deviceName'] as String).trim()
          : 'Diğer cihaz',
      createdAtMs: json['createdAtMs'] is int ? json['createdAtMs'] as int : 0,
      library: lib,
      settings: settings,
      recentSearches: searches,
    );
  }

  static SyncSnapshot fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map<String, dynamic>) {
        throw const LanSyncException('Geçerli bir eşitleme JSON verisi değil');
      }
      return SyncSnapshot.fromJson(decoded);
    } on LanSyncException {
      rethrow;
    } catch (_) {
      throw const LanSyncException('Geçerli bir eşitleme JSON verisi değil');
    }
  }

  /// Captures the active account's credential-free favorites, watch history, preferences and recent searches.
  static Future<SyncSnapshot> capture(Account account, {String? deviceName}) async {
    final recents = await RecentSearchStore.load(account);
    return SyncSnapshot(
      version: currentVersion,
      accountHash: CatalogCache.accountCacheKey(account),
      deviceName: deviceName ?? defaultDeviceName(),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      library: Library.instance.exportSyncData(account),
      settings: AppSettings.instance.exportSyncSettings(),
      recentSearches: recents,
    );
  }

  /// Validates [accountHash] and merges [remote] into the local [Library], [AppSettings] and [RecentSearchStore].
  static Future<SyncMergeResult> applyAndMerge(Account account, SyncSnapshot remote) async {
    final localHash = CatalogCache.accountCacheKey(account);
    if (remote.accountHash != localHash) {
      throw const LanSyncException(
        'Farklı bir IPTV hesabı açık. Eşitleme için iki cihazda da aynı hesapla giriş yapılmış olmalı.',
        statusCode: HttpStatus.conflict,
      );
    }
    final libStats = await Library.instance.mergeSyncData(account, remote.library);
    final settingsUpdated = await AppSettings.instance.mergeSyncSettings(remote.settings);
    final mergedRecents = await RecentSearchStore.merge(account, remote.recentSearches);
    return SyncMergeResult(
      peerDeviceName: remote.deviceName,
      libraryStats: libStats,
      settingsUpdated: settingsUpdated,
      recentSearchesCount: mergedRecents.length,
    );
  }
}

/// Human-friendly label identifying this device on the local network.
String defaultDeviceName() {
  if (kIsWeb) return 'Tarayıcı';
  if (Platform.isIOS) return 'iPhone / iPad';
  if (Platform.isAndroid) return AppSettings.instance.tvMode ? 'Android TV' : 'Android';
  String host = '';
  try {
    host = Platform.localHostname.split('.').first.trim();
  } catch (_) {}
  final os = Platform.isLinux ? 'Linux PC' : (Platform.isMacOS ? 'Mac' : 'Windows PC');
  return host.isNotEmpty && host.toLowerCase() != 'localhost' ? '$os ($host)' : os;
}

/// A nearby IPTV instance announced over LAN UDP broadcast.
class LanSyncPeer {
  const LanSyncPeer({
    required this.name,
    required this.host,
    required this.port,
    required this.accountHash,
    required this.lastSeen,
  });

  final String name;
  final String host;
  final int port;
  final String accountHash;
  final DateTime lastSeen;

  String get id => '$host:$port';
  String get addressLabel => '$host:$port';
}

/// Parsed connection details accepted from either a QR sync URL or manual `IP:port` + PIN.
class ParsedSyncTarget {
  const ParsedSyncTarget({required this.endpoint, this.pin, this.token});

  final Uri endpoint;
  final String? pin;
  final String? token;
}

/// Generates a cryptographically secure 6-digit pairing PIN.
String generateSyncPin() {
  final r = Random.secure();
  return List.generate(6, (_) => '${r.nextInt(10)}').join();
}

/// Formats a 6-digit PIN as `123 456` for easy reading on TV/desktop.
String formatSyncPin(String pin) {
  final clean = normalizeSyncPin(pin);
  if (clean.length == 6) return '${clean.substring(0, 3)} ${clean.substring(3)}';
  return clean;
}

/// Strips spaces and dashes from a user-typed PIN.
String normalizeSyncPin(String raw) => raw.replaceAll(RegExp(r'[\s\-]+'), '').trim();

bool _constantTimeEquals(String a, String b) {
  final ab = utf8.encode(a);
  final bb = utf8.encode(b);
  if (ab.length != bb.length) return false;
  var diff = 0;
  for (var i = 0; i < ab.length; i++) {
    diff |= ab[i] ^ bb[i];
  }
  return diff == 0;
}

const int lanSyncDiscoveryPort = 45873;
const int _maxSyncPayloadBytes = 2 * 1024 * 1024; // 2 MiB

/// Temporary local-network HTTP server (+ best-effort UDP presence beacon) for two-way device sync.
class LanSyncServer {
  LanSyncServer({
    required this.account,
    this.deviceName,
    this.onPeerSynced,
    this.captureSnapshot,
    this.mergeSnapshot,
    this.enableUdpBroadcast = true,
  });

  final Account account;
  final String? deviceName;
  final void Function(SyncMergeResult result)? onPeerSynced;
  final Future<SyncSnapshot> Function(Account account)? captureSnapshot;
  final Future<SyncMergeResult> Function(Account account, SyncSnapshot remote)? mergeSnapshot;
  final bool enableUdpBroadcast;

  final String pin = generateSyncPin();
  final String token = RemoteEntryServer.newToken();

  HttpServer? _server;
  RawDatagramSocket? _beaconSocket;
  Timer? _beaconTimer;
  Uri? _shareUrl;
  String? _advertisedHost;

  bool get running => _server != null;
  int? get port => _server?.port;
  Uri? get shareUrl => _shareUrl;
  String? get advertisedHost => _advertisedHost;
  String get effectiveDeviceName => deviceName ?? defaultDeviceName();

  /// Starts the sync server and returns the QR/shareable URL (`http://<ip>:<port>/s/<token>`).
  ///
  /// Pass [bindAddress] / [advertisedAddress] in tests to bind purely to loopback (`127.0.0.1`).
  Future<Uri?> start({
    InternetAddress? bindAddress,
    String? advertisedAddress,
  }) async {
    final ip = advertisedAddress ?? await RemoteEntryServer.localAddress();
    if (ip == null) return null;
    final server = await HttpServer.bind(bindAddress ?? InternetAddress.anyIPv4, 0);
    _server = server;
    _advertisedHost = ip;
    _shareUrl = Uri(scheme: 'http', host: ip, port: server.port, path: '/s/$token');
    server.listen(_handle);

    if (enableUdpBroadcast) {
      unawaited(_startBeacon(ip, server.port));
    }
    return _shareUrl;
  }

  Future<void> _startBeacon(String ip, int port) async {
    try {
      final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      _beaconSocket = sock;
      final payload = utf8.encode(jsonEncode({
        'type': 'iptv_lan_sync_v1',
        'name': effectiveDeviceName,
        'host': ip,
        'port': port,
        'accountHash': CatalogCache.accountCacheKey(account),
      }));

      void send() {
        try {
          sock.send(payload, InternetAddress('255.255.255.255'), lanSyncDiscoveryPort);
        } catch (_) {}
      }

      send();
      _beaconTimer = Timer.periodic(const Duration(seconds: 2), (_) => send());
    } catch (_) {
      // Best-effort only: HTTP + QR + manual IP/PIN sync remains fully functional without UDP.
    }
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    try {
      _beaconSocket?.close();
    } catch (_) {}
    _beaconSocket = null;
    await _server?.close(force: true);
    _server = null;
    _shareUrl = null;
    _advertisedHost = null;
  }

  Future<SyncSnapshot> _capture() =>
      captureSnapshot != null ? captureSnapshot!(account) : SyncSnapshot.capture(account, deviceName: effectiveDeviceName);

  Future<SyncMergeResult> _merge(SyncSnapshot remote) =>
      mergeSnapshot != null ? mergeSnapshot!(account, remote) : SyncSnapshot.applyAndMerge(account, remote);

  bool _isAuthorized(HttpRequest req) {
    final providedPin = normalizeSyncPin(req.headers.value('x-sync-pin') ?? '');
    if (providedPin.isNotEmpty && _constantTimeEquals(providedPin, pin)) return true;
    final providedToken = (req.headers.value('x-sync-token') ?? req.uri.queryParameters['token'] ?? '').trim();
    if (providedToken.isNotEmpty && _constantTimeEquals(providedToken, token)) return true;
    return false;
  }

  Future<String> _readLimitedBody(HttpRequest req) async {
    final chunks = <int>[];
    await for (final chunk in req.timeout(const Duration(seconds: 10))) {
      chunks.addAll(chunk);
      if (chunks.length > _maxSyncPayloadBytes) {
        throw const LanSyncException('Eşitleme verisi çok büyük', statusCode: HttpStatus.requestEntityTooLarge);
      }
    }
    return utf8.decode(chunks);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = req.uri.path;
      if (req.method == 'POST' && path == '/api/sync') {
        if (!_isAuthorized(req)) {
          _jsonError(res, HttpStatus.forbidden, 'Eşitleme kodu hatalı veya süresi dolmuş');
          return;
        }
        final raw = await _readLimitedBody(req);
        final incoming = SyncSnapshot.fromJsonString(raw);
        final result = await _merge(incoming);
        final merged = await _capture();
        onPeerSynced?.call(result);
        res.statusCode = HttpStatus.ok;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'ok': true,
          'deviceName': effectiveDeviceName,
          'snapshot': merged.toJson(),
        }));
      } else if (req.method == 'GET' && (path == '/s/$token' || path == '/$token')) {
        res.statusCode = HttpStatus.ok;
        res.headers.contentType = ContentType.html;
        res.write(_webHelperPage(
          deviceName: effectiveDeviceName,
          shareUrl: _shareUrl?.toString() ?? '',
          formattedPin: formatSyncPin(pin),
          token: token,
        ));
      } else if (req.method == 'GET' && path == '/s/$token/export.json') {
        final snap = await _capture();
        res.statusCode = HttpStatus.ok;
        res.headers.contentType = ContentType.json;
        res.headers.set('Content-Disposition', 'attachment; filename="iptv-yedek.json"');
        res.write(snap.toJsonString(pretty: true));
      } else if (req.method == 'POST' && path == '/s/$token/import') {
        final raw = await _readLimitedBody(req);
        final incoming = SyncSnapshot.fromJsonString(raw);
        final result = await _merge(incoming);
        onPeerSynced?.call(result);
        res.statusCode = HttpStatus.ok;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'ok': true, 'summary': result.summaryText}));
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } on LanSyncException catch (e) {
      _jsonError(res, e.statusCode ?? HttpStatus.badRequest, e.message);
    } catch (_) {
      _jsonError(res, HttpStatus.badRequest, 'İstek işlenemedi');
    } finally {
      await res.close();
    }
  }

  void _jsonError(HttpResponse res, int code, String message) {
    res.statusCode = code;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode({'ok': false, 'error': message}));
  }
}

/// Best-effort UDP listener discovering nearby [LanSyncServer] peers on the same Wi-Fi & account.
class LanSyncDiscovery extends ChangeNotifier {
  LanSyncDiscovery({
    required this.account,
    this.ignoreHost,
    this.ignorePort,
  });

  final Account account;
  final String? ignoreHost;
  final int? ignorePort;

  RawDatagramSocket? _socket;
  Timer? _pruneTimer;
  final Map<String, LanSyncPeer> _peers = {};

  List<LanSyncPeer> get peers {
    final list = _peers.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<void> start() async {
    if (_socket != null) return;
    try {
      final sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        lanSyncDiscoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _socket = sock;
      final expectedHash = CatalogCache.accountCacheKey(account);
      sock.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = sock.receive();
        if (dg == null) return;
        try {
          final map = jsonDecode(utf8.decode(dg.data));
          if (map is! Map<String, dynamic> || map['type'] != 'iptv_lan_sync_v1') return;
          if (map['accountHash'] != expectedHash) return;
          final host = map['host'];
          final port = map['port'];
          final name = map['name'];
          if (host is! String || host.isEmpty || port is! int || port <= 0) return;
          if (host == ignoreHost && port == ignorePort) return;
          final peer = LanSyncPeer(
            name: name is String && name.trim().isNotEmpty ? name.trim() : host,
            host: host,
            port: port,
            accountHash: expectedHash,
            lastSeen: DateTime.now(),
          );
          final had = _peers.containsKey(peer.id);
          _peers[peer.id] = peer;
          if (!had) notifyListeners();
        } catch (_) {}
      });
      _pruneTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        final cutoff = DateTime.now().subtract(const Duration(seconds: 8));
        final before = _peers.length;
        _peers.removeWhere((_, p) => p.lastSeen.isBefore(cutoff));
        if (_peers.length != before) notifyListeners();
      });
    } catch (_) {
      // Best-effort: silently degrade to QR / manual IP entry if UDP port is busy or blocked.
    }
  }

  @override
  void dispose() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    super.dispose();
  }
}

/// Client that performs a single-round-trip two-way sync against a remote [LanSyncServer].
class LanSyncClient {
  /// Parses a full QR URL (`http://192.168.1.42:51234/s/<token>`) or a manual `IP:port` + optional PIN.
  static ParsedSyncTarget parseTarget(String rawAddress, {String? pin}) {
    var trimmed = rawAddress.trim();
    if (trimmed.isEmpty) {
      throw const LanSyncException('Bağlanılacak cihaz adresi boş');
    }
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      trimmed = 'http://$trimmed';
    }
    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      throw const LanSyncException('Cihaz adresi geçersiz');
    }
    if (uri.host.isEmpty || !uri.hasPort || uri.port <= 0) {
      throw const LanSyncException('Adres "IP:port" biçiminde olmalı (ör. 192.168.1.15:51234)');
    }

    String? token;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length >= 2 && segs[0] == 's') {
      token = segs[1];
    } else if (segs.length == 1 && segs[0] != 'api') {
      token = segs[0];
    }

    final cleanPin = pin == null ? '' : normalizeSyncPin(pin);
    if ((token == null || token.isEmpty) && cleanPin.isEmpty) {
      throw const LanSyncException('Eşitleme kodunu (6 haneli PIN) girin');
    }

    return ParsedSyncTarget(
      endpoint: Uri(scheme: uri.scheme, host: uri.host, port: uri.port, path: '/api/sync'),
      pin: cleanPin.isEmpty ? null : cleanPin,
      token: token,
    );
  }

  /// Sends local state to [target], receives the host's merged snapshot, and applies it locally.
  static Future<SyncMergeResult> syncWith({
    required Account account,
    required ParsedSyncTarget target,
    String? deviceName,
    http.Client? httpClient,
    Future<SyncSnapshot> Function(Account account)? captureSnapshot,
    Future<SyncMergeResult> Function(Account account, SyncSnapshot remote)? mergeSnapshot,
  }) async {
    final localSnap = captureSnapshot != null
        ? await captureSnapshot(account)
        : await SyncSnapshot.capture(account, deviceName: deviceName);
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        if (target.pin != null) 'X-Sync-Pin': target.pin!,
        if (target.token != null) 'X-Sync-Token': target.token!,
      };
      final http.Response res;
      try {
        res = await client
            .post(target.endpoint, headers: headers, body: localSnap.toJsonString())
            .timeout(const Duration(seconds: 12));
      } catch (e) {
        throw LanSyncException('Cihaza erişilemiyor (aynı Wi-Fi\'de misiniz?): $e');
      }

      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}

      if (res.statusCode != HttpStatus.ok) {
        final serverMsg = body?['error'];
        throw LanSyncException(
          serverMsg is String && serverMsg.isNotEmpty
              ? serverMsg
              : 'Eşitleme başarısız (HTTP ${res.statusCode})',
          statusCode: res.statusCode,
        );
      }

      final rawSnap = body?['snapshot'];
      if (rawSnap is! Map<String, dynamic>) {
        throw const LanSyncException('Sunucu geçersiz eşitleme yanıtı döndürdü');
      }
      final mergedFromHost = SyncSnapshot.fromJson(rawSnap);
      return mergeSnapshot != null
          ? await mergeSnapshot(account, mergedFromHost)
          : await SyncSnapshot.applyAndMerge(account, mergedFromHost);
    } finally {
      if (ownsClient) client.close();
    }
  }
}

String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _webHelperPage({
  required String deviceName,
  required String shareUrl,
  required String formattedPin,
  required String token,
}) =>
    '''<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>IPTV Eşitleme</title>
<style>
*{box-sizing:border-box}
body{font-family:system-ui,-apple-system,sans-serif;background:#16151a;color:#eee;margin:0;padding:22px;max-width:460px;margin:auto}
h1{font-size:20px;margin:4px 0 6px;color:#b9b0ff}
p{color:#b6b2c7;font-size:14px;line-height:1.45}
.card{background:#22202b;border:1px solid #343142;border-radius:16px;padding:16px;margin:14px 0}
.pin{font-size:28px;font-weight:700;letter-spacing:4px;text-align:center;color:#fff;margin:6px 0}
.url{font-family:ui-monospace,monospace;font-size:12px;word-break:break-all;background:#16151a;padding:10px;border-radius:10px;color:#d6d2ea}
button,a.btn{display:block;width:100%;text-align:center;text-decoration:none;padding:13px 14px;border-radius:12px;border:0;background:#6c5ce7;color:#fff;font-size:15px;font-weight:600;margin-top:10px;cursor:pointer}
button.sec,a.sec{background:#2e2b3b}
textarea{width:100%;min-height:90px;background:#16151a;color:#eee;border:1px solid #444;border-radius:10px;padding:10px;font-family:ui-monospace,monospace;font-size:12px;margin-top:8px}
#st{min-height:20px;margin-top:10px;font-size:13px;color:#a5f3c4;text-align:center}
</style></head><body>
<h1>IPTV Yerel Ağ Eşitleme</h1>
<p><strong>${_escapeHtml(deviceName)}</strong> eşitleme için hazır. Parolalar hiçbir zaman paylaşılmaz.</p>
<div class="card">
  <p style="margin:0 0 4px">Diğer cihazdaki IPTV uygulamasında <strong>Ayarlar → Eşitleme → Bağlan</strong> bölümüne bu adresi yapıştırabilir veya kodu girebilirsin:</p>
  <div class="pin">${_escapeHtml(formattedPin)}</div>
  <div class="url" id="u">${_escapeHtml(shareUrl)}</div>
  <button class="sec" onclick="cp()">Bağlantıyı kopyala</button>
</div>
<div class="card">
  <p style="margin:0 0 6px"><strong>Tarayıcıdan yedek al / yükle</strong></p>
  <a class="btn" href="/s/${_escapeHtml(token)}/export.json">JSON yedeği indir</a>
  <textarea id="j" placeholder="Başka cihazdan kopyaladığın JSON yedeğini buraya yapıştır..."></textarea>
  <button class="sec" onclick="imp()">Bu cihazla birleştir</button>
  <div id="st"></div>
</div>
<script>
function cp(){navigator.clipboard?.writeText(document.getElementById('u').textContent);document.getElementById('st').textContent='Bağlantı kopyalandı';}
async function imp(){
  const raw=document.getElementById('j').value.trim();if(!raw)return;
  const st=document.getElementById('st');st.textContent='Birleştiriliyor...';
  try{
    const r=await fetch('/s/${_escapeHtml(token)}/import',{method:'POST',headers:{'Content-Type':'application/json'},body:raw});
    const d=await r.json();
    st.style.color=r.ok?'#a5f3c4':'#ff9aa2';
    st.textContent=r.ok?('✓ Eşitlendi: '+d.summary):(d.error||'Hata');
  }catch(e){st.style.color='#ff9aa2';st.textContent='Bağlantı hatası';}
}
</script></body></html>''';
