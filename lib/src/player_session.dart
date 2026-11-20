import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'downloads.dart';
import 'library.dart';
import 'settings.dart';
import 'system_pip.dart';
import 'xtream.dart';

/// One playable thing: a channel, a movie or an episode.
class PlayerEntry {
  const PlayerEntry({required this.url, required this.title, this.logo = '', this.group, this.epg, this.item, this.localPath});

  final String url;
  final String title;
  final String logo;

  /// Category shown under "Canlı TV" in the title pill (live channels).
  final String? group;

  /// Loads now/next programmes (live channels only).
  final Future<List<Programme>> Function()? epg;

  /// Backing catalog item (movie or parent series) for navigating to [DetailPage].
  final Item? item;

  /// Optional explicit local file path for offline playback; even when omitted,
  /// [PlayerSession] automatically plays from disk if [url] is already downloaded.
  final String? localPath;
}

/// Persistent playback session that stays alive across Full Player, the iPhone
/// in-app Mini Player bar, and native iOS System Picture-in-Picture.
class PlayerSession extends ChangeNotifier with WidgetsBindingObserver {
  PlayerSession._();
  static final PlayerSession instance = PlayerSession._();

  static const _userAgent = 'VLC/3.0.20 LibVLC/3.0.20';

  Player? _player;
  VideoController? _controller;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _saveTimer;
  Timer? _countdownTimer;
  Timer? _pipSyncTimer;
  bool _observersAttached = false;

  List<PlayerEntry> _queue = const [];
  int _index = 0;
  Kind _kind = Kind.movie;
  XtreamClient? _client;
  Item? _resolvedItem;
  Future<List<Programme>>? _epg;
  List<Programme> _resolvedProgrammes = const [];
  BoxFit _fit = BoxFit.contain;

  bool _active = false;
  bool _minimized = false;
  bool _systemPipActive = false;
  bool _playingLocal = false;
  bool _debugPreview = false;
  bool _debugPlaying = true;
  Duration _debugPosition = Duration.zero;
  Duration _debugDuration = Duration.zero;

  int _retries = 0;
  int _gen = 0;
  int _progress = 0;
  int? _errorGen;
  String? _ignoredError;
  bool _saveable = false;

  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<PlayerEntry?> current = ValueNotifier(null);
  final ValueNotifier<int?> countdown = ValueNotifier(null);

  /// Called by [SystemPip] when the user taps Restore (`⤢`) on the iOS PiP window
  /// while the in-app player is minimized, so the app opens the full player.
  VoidCallback? onRequestExpandFromPip;

  Player? get player => _player;
  VideoController? get controller => _controller;
  List<PlayerEntry> get queue => _queue;
  int get index => _index;
  Kind get kind => _kind;
  XtreamClient? get client => _client;
  bool get live => _kind == Kind.live;
  bool get active => _active;
  bool get minimized => _minimized;
  bool get systemPipActive => _systemPipActive;
  bool get isPlayingLocal => _playingLocal;
  bool get isMiniVisible => _active && _minimized && !_systemPipActive;
  BoxFit get fit => _fit;
  Future<List<Programme>>? get epg => _epg;
  List<Programme> get programmes => _resolvedProgrammes;

  PlayerEntry? get entry => _active && _index >= 0 && _index < _queue.length ? _queue[_index] : null;
  Item? get detailItem => entry?.item ?? _resolvedItem;
  void cacheDetailItem(Item item) {
    _resolvedItem = item;
  }
  bool get hasNext => _active && _index < _queue.length - 1;
  bool get hasPrev => _active && _index > 0;
  bool get isPlaying => _debugPreview ? _debugPlaying : (_player?.state.playing ?? false);
  Duration get position => _debugPreview ? _debugPosition : (_player?.state.position ?? Duration.zero);
  Duration get duration => _debugPreview ? _debugDuration : (_player?.state.duration ?? Duration.zero);

  void _ensureObservers() {
    if (_observersAttached) return;
    _observersAttached = true;
    WidgetsBinding.instance.addObserver(this);
    AppSettings.instance.addListener(_onSettingsChanged);
    SystemPip.instance.ensureInitialized();
    SystemPip.instance.onWillStart = _onPipWillStart;
    SystemPip.instance.onDidStart = _onPipDidStart;
    SystemPip.instance.onDidStop = _onPipDidStop;
    SystemPip.instance.onFailed = _onPipFailed;
  }

  void _onSettingsChanged() {
    if (!_active) return;
    SystemPip.instance.setAutoStart(AppSettings.instance.autoPipOnLeave);
  }

  /// Starts playing [queue] at [index], reusing the underlying [Player] if alive.
  Future<void> open({
    required List<PlayerEntry> queue,
    int index = 0,
    Kind kind = Kind.movie,
    XtreamClient? client,
  }) async {
    assert(queue.isNotEmpty);
    _ensureObservers();
    _debugPreview = false;

    if (_systemPipActive) {
      await SystemPip.instance.stop();
      _systemPipActive = false;
    }

    _cancelCountdown();
    _saveTimer?.cancel();
    _save();
    _saveable = false;

    _gen++;
    _retries = 0;
    _errorGen = null;
    _ignoredError = null;
    error.value = null;

    _queue = List<PlayerEntry>.unmodifiable(queue);
    _index = index.clamp(0, _queue.length - 1);
    _kind = kind;
    _client = client;
    _resolvedItem = null;
    _active = true;
    _minimized = false;
    _fit = BoxFit.contain;

    final e = entry!;
    current.value = e;
    _loadEpg(e);

    // Release cached posters before allocating hardware video buffers.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();

    final created = _ensurePlayer();
    if (created) {
      await _applyMpvOptions();
    }
    if (!_active) return;

    Library.instance.touch(url: e.url, title: e.title, logo: e.logo, kind: _kind, item: e.item);
    notifyListeners();

    await _openCurrent();
    if (!_active) return;
    _syncSystemPip(playingOverride: true);
    await _afterOpen();
  }

  bool _ensurePlayer() {
    if (_player != null && _controller != null) return false;
    final p = Player();
    _player = p;
    _controller = VideoController(p);

    _subs.add(p.stream.error.listen(_onError));
    var last = Duration.zero;
    _subs.add(p.stream.position.listen((pos) {
      if (pos == Duration.zero || pos == last) return;
      last = pos;
      _progress++;
      _retries = 0;
      if (error.value != null) error.value = null;
    }));
    _subs.add(p.stream.playing.listen((playing) {
      if (_active && !_systemPipActive) {
        _syncSystemPip(playingOverride: playing);
        notifyListeners();
      }
    }));
    _subs.add(p.stream.completed.listen((done) {
      if (!done || !_active || _systemPipActive) return;
      if (live) {
        _onError('stream ended', stopped: true);
      } else {
        _onCompleted();
      }
    }));

    _pipSyncTimer?.cancel();
    _pipSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_active && !_systemPipActive && !live && isPlaying) {
        _syncSystemPip();
      }
    });
    return true;
  }

  Future<void> _applyMpvOptions() async {
    final p = _player;
    if (p == null) return;
    final s = AppSettings.instance;
    final native = p.platform as dynamic;
    Future<void> set(String k, String v) async {
      try {
        await native.setProperty(k, v);
      } catch (_) {}
    }

    await set('hwdec', s.hwdec ? 'auto-safe' : 'no');
    await set('cache-secs', '${s.cacheSecs}');
    await set('demuxer-readahead-secs', '${s.cacheSecs}');
    if (s.tvMode) {
      await set('demuxer-max-bytes', '48MiB');
      await set('demuxer-max-back-bytes', '16MiB');
      await set('hr-seek', 'no');
    }
    if (s.alang.isNotEmpty) await set('alang', s.alang);
    if (s.slang.isNotEmpty) {
      await set('slang', s.slang);
      await set('sid', 'auto');
    }
  }

  void _loadEpg(PlayerEntry e) {
    _resolvedProgrammes = const [];
    final f = e.epg?.call();
    _epg = f;
    if (f != null) {
      final gen = _gen;
      f.then((list) {
        if (_active && gen == _gen) {
          _resolvedProgrammes = list;
          notifyListeners();
        }
      }).catchError((_) {});
    }
  }

  String? _resolveLocalPath(PlayerEntry e) {
    final explicit = e.localPath;
    if (explicit != null && explicit.isNotEmpty) {
      try {
        if (File(explicit).existsSync()) return explicit;
      } catch (_) {}
    }
    return DownloadManager.instance.localPathForUrl(e.url, account: _client?.acc);
  }

  Future<void> _openCurrent() async {
    final p = _player;
    final e = entry;
    if (p == null || e == null) return;
    final local = _resolveLocalPath(e);
    _playingLocal = local != null;
    if (local != null) {
      await p.open(Media(local));
    } else {
      await p.open(Media(e.url, httpHeaders: const {'User-Agent': _userAgent}));
    }
  }

  Future<void> _afterOpen({Duration? resumeOverride}) async {
    if (live) return;
    final p = _player;
    final e = entry;
    if (p == null || e == null) return;
    final gen = _gen;
    final target = resumeOverride ?? (AppSettings.instance.resume ? Library.instance.positionFor(e.url) : null);
    if (target != null && target > Duration.zero) {
      try {
        await p.stream.duration.firstWhere((d) => d > Duration.zero);
      } catch (_) {
        return;
      }
      if (gen != _gen || !_active) return;
      await p.seek(target);
      if (gen != _gen || !_active) return;
    }
    _saveable = true;
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    _syncSystemPip();
  }

  /// Switches to another channel or episode without leaving the player session.
  Future<void> switchTo(int i) async {
    if (!_active || i < 0 || i >= _queue.length || i == _index) return;
    _cancelCountdown();
    _saveTimer?.cancel();
    _save();
    _saveable = false;
    _gen++;
    _retries = 0;
    _errorGen = null;
    error.value = null;
    _ignoredError = null;
    _index = i;
    _resolvedItem = null;
    final e = entry!;
    current.value = e;
    _loadEpg(e);
    Library.instance.touch(url: e.url, title: e.title, logo: e.logo, kind: _kind, item: e.item);
    notifyListeners();
    await _openCurrent();
    if (!_active) return;
    _syncSystemPip(playingOverride: true);
    await _afterOpen();
  }

  void next() => switchTo(_index + 1);
  void prev() => switchTo(_index - 1);

  Future<void> retry() async {
    if (!_active) return;
    _gen++;
    _retries = 0;
    error.value = null;
    _ignoredError = null;
    _saveTimer?.cancel();
    _saveable = false;
    await _openCurrent();
    if (!_active) return;
    _syncSystemPip(playingOverride: true);
    await _afterOpen();
  }

  void toggleFit() {
    _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
    notifyListeners();
  }

  Future<void> playOrPause() async {
    if (_debugPreview) {
      _debugPlaying = !_debugPlaying;
      notifyListeners();
      return;
    }
    await _player?.playOrPause();
  }

  void cancelCountdown() => _cancelCountdown();

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    countdown.value = null;
  }

  void _onCompleted() {
    if (!_active) return;
    _save();
    final p = _player;
    if (p == null) return;
    final ignored = _ignoredError;
    final state = p.state;
    if (ignored != null && state.duration - state.position > const Duration(seconds: 60)) {
      error.value = 'Yayın yarıda kesildi.\n\n$ignored';
      return;
    }
    if (!AppSettings.instance.autoNext || !hasNext) return;
    _countdownTimer?.cancel();
    countdown.value = 10;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = (countdown.value ?? 1) - 1;
      if (left <= 0) {
        next();
      } else {
        countdown.value = left;
      }
    });
  }

  Future<AccountInfo?> _accountInfo() async {
    try {
      return await _client?.authenticate().timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  Future<void> _onError(String message, {bool stopped = false}) async {
    final gen = _gen;
    if (!_active || _systemPipActive || _errorGen == gen) return;
    _errorGen = gen;
    try {
      if (!stopped) {
        final before = _progress;
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!_active || _systemPipActive || gen != _gen) return;
        if (_progress != before) {
          _ignoredError = message;
          return;
        }
      }
      if (_playingLocal) {
        error.value = 'İndirilen dosya açılamadı.\n\n$message';
        return;
      }
      final info = await _accountInfo();
      if (!_active || _systemPipActive || gen != _gen) return;
      if (info != null && info.limitReached) {
        final n = '${info.activeConnections}/${info.maxConnections}';
        if (live && _retries < 3) {
          _retries++;
          error.value = 'Bağlantı sınırı dolu ($n). Başka bir cihazda izleme açık olabilir ya da önceki bağlantın henüz kapanmadı. Yeniden deneniyor ($_retries/3)...';
          await Future<void>.delayed(Duration(seconds: 4 * _retries));
          if (_active && !_systemPipActive && gen == _gen) await _openCurrent();
          return;
        }
        error.value = 'Bağlantı sınırı dolu ($n).\n\nHesabın aynı anda en fazla ${info.maxConnections} cihazda izlemeye izin veriyor. '
            'Başka bir cihazda (TV, telefon, bilgisayar) açık yayını kapat, birkaç saniye bekle ve Tekrar dene.';
        return;
      }
      if (live && _retries < 3) {
        _retries++;
        error.value = 'Bağlantı koptu, yeniden deneniyor ($_retries/3)...';
        await Future<void>.delayed(Duration(seconds: 2 * _retries));
        if (_active && !_systemPipActive && gen == _gen) await _openCurrent();
        return;
      }
      final refused = RegExp(r'(401|403|404|509|884|forbidden|unauthorized)', caseSensitive: false).hasMatch(message);
      error.value = refused
          ? 'Yayın açılamadı. Sağlayıcı isteği reddetti (hesap süresi dolmuş ya da bağlantı sınırı olabilir).\n\n$message'
          : 'Yayın açılamadı.\n\n$message';
    } finally {
      if (_errorGen == gen) _errorGen = null;
    }
  }

  void _save() {
    if (live || !_saveable) return;
    final p = _player;
    final e = entry;
    if (p == null || e == null) return;
    Library.instance.savePosition(e.url, p.state.position, p.state.duration);
  }

  /// Minimizes the full player into the in-app Mini Player bar without stopping playback.
  void minimize() {
    if (!_active || _minimized) return;
    _minimized = true;
    notifyListeners();
  }

  /// Marks the full player UI as visible again (hiding the in-app Mini Player bar).
  void markExpanded() {
    if (!_active || !_minimized) return;
    _minimized = false;
    notifyListeners();
  }

  /// Requests native iOS System PiP immediately (manual trigger from player chrome).
  Future<bool> startSystemPip() async {
    if (!_active || !SystemPip.instance.isSupported) return false;
    _syncSystemPip(playingOverride: true);
    return SystemPip.instance.start();
  }

  /// Stops playback completely, clears iOS System PiP, and releases native resources.
  Future<void> close() async {
    _cancelCountdown();
    _saveTimer?.cancel();
    _saveTimer = null;
    _pipSyncTimer?.cancel();
    _pipSyncTimer = null;
    _save();
    _saveable = false;
    _gen++;

    _active = false;
    _minimized = false;
    _systemPipActive = false;
    _playingLocal = false;
    _debugPreview = false;
    _queue = const [];
    _index = 0;
    _resolvedItem = null;
    _epg = null;
    _resolvedProgrammes = const [];
    error.value = null;
    current.value = null;

    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();

    final p = _player;
    _player = null;
    _controller = null;
    await p?.dispose();
    await SystemPip.instance.clear();
    notifyListeners();
  }

  void _syncSystemPip({bool? playingOverride}) {
    if (!_active || _debugPreview || !SystemPip.instance.isSupported) return;
    final e = entry;
    if (e == null) return;
    final local = _resolveLocalPath(e);
    final playing = playingOverride ?? isPlaying;
    SystemPip.instance.configure(
      url: local != null ? Uri.file(local).toString() : e.url,
      title: e.title,
      live: live,
      playing: playing,
      position: position,
      duration: duration,
      autoStart: AppSettings.instance.autoPipOnLeave,
      userAgent: _userAgent,
    );
  }

  void _onPipWillStart() {
    if (!_active) return;
    _systemPipActive = true;
    _save();
    _saveTimer?.cancel();
    _saveable = false;
    // Stop mpv immediately to release the single IPTV connection slot and avoid
    // OpenGL ES calls while backgrounded.
    _player?.stop();
    notifyListeners();
  }

  void _onPipDidStart() {
    if (!_active) return;
    _systemPipActive = true;
    notifyListeners();
  }

  Future<void> _onPipDidStop(SystemPipStopEvent event) async {
    if (!_active) return;
    _systemPipActive = false;
    final e = entry;
    final resumePos = event.positionMs > 0 ? Duration(milliseconds: event.positionMs) : null;
    if (!live && e != null && resumePos != null) {
      Library.instance.savePosition(e.url, resumePos, duration);
    }

    if (event.restoreUi) {
      notifyListeners();
      if (_minimized) {
        onRequestExpandFromPip?.call();
      }
      await _openCurrent();
      if (!_active) return;
      await _afterOpen(resumeOverride: resumePos);
      if (!event.wasPlaying) {
        await _player?.pause();
      }
      _syncSystemPip(playingOverride: event.wasPlaying);
    } else {
      // User dismissed the floating System PiP window with its close button.
      await close();
    }
  }

  Future<void> _onPipFailed(String reason) async {
    final wasPip = _systemPipActive;
    _systemPipActive = false;
    notifyListeners();
    if (wasPip && _active && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await _openCurrent();
      if (_active) await _afterOpen();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active || _debugPreview) return;
    if (state == AppLifecycleState.inactive) {
      _save();
      _syncSystemPip();
    } else if (state == AppLifecycleState.paused) {
      _save();
      // When auto-PiP is disabled (or PiP did not start), pause mpv on iOS so
      // playback stops cleanly instead of running silently in background.
      if (SystemPip.instance.isSupported && !_systemPipActive && isPlaying) {
        _player?.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      _syncSystemPip();
    }
  }

  /// Lightweight state injection for widget tests (avoids native libmpv initialization).
  @visibleForTesting
  void debugSetMiniPreview({
    required PlayerEntry entry,
    Kind kind = Kind.live,
    bool playing = true,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    List<Programme> programmes = const [],
  }) {
    _debugPreview = true;
    _debugPlaying = playing;
    _debugPosition = position;
    _debugDuration = duration;
    _queue = [entry];
    _index = 0;
    _kind = kind;
    _active = true;
    _minimized = true;
    _systemPipActive = false;
    _resolvedProgrammes = programmes;
    current.value = entry;
    notifyListeners();
  }

  /// Resets test preview state cleanly without touching native channels.
  @visibleForTesting
  void debugReset() {
    _active = false;
    _minimized = false;
    _systemPipActive = false;
    _playingLocal = false;
    _debugPreview = false;
    _queue = const [];
    _index = 0;
    _resolvedItem = null;
    _resolvedProgrammes = const [];
    current.value = null;
    error.value = null;
    countdown.value = null;
    notifyListeners();
  }
}
