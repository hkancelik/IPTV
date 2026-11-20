import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'downloads.dart';
import 'library.dart';
import 'player_comfort.dart';
import 'settings.dart';
import 'system_media_controls.dart';
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
  Timer? _mediaSyncTimer;
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
  bool _pipPlaying = true;
  Duration _pipPosition = Duration.zero;
  Duration _pipDuration = Duration.zero;
  bool _backgroundAudioOnly = false;
  bool _pausedByInterruption = false;
  bool _playingLocal = false;
  bool _debugPreview = false;
  bool _debugEmitMediaControls = false;
  bool _debugPlaying = true;
  Duration _debugPosition = Duration.zero;
  Duration _debugDuration = Duration.zero;
  double _debugRate = 1.0;
  double _debugVolume = 100.0;

  Duration? _lastMediaPos;
  DateTime? _lastMediaPosAt;
  Duration _lastMediaDuration = Duration.zero;
  String? _lastLiveEpgTitle;

  int _retries = 0;
  int _gen = 0;
  int _progress = 0;
  int? _errorGen;
  String? _ignoredError;
  bool _saveable = false;

  TrackPref? _pendingAudioPref;
  TrackPref? _pendingSubtitlePref;
  bool _userPickedAudio = false;
  bool _userPickedSubtitle = false;
  bool _appliedSavedAudio = false;
  bool _appliedSavedSubtitle = false;

  int _subDelayMs = 0;
  int _audioDelayMs = 0;
  String? _appliedDeinterlace;
  bool _tempSpeedHoldActive = false;
  double? _rateBeforeHold;
  Timer? _sleepTickTimer;
  DateTime? _sleepTargetAt;
  DateTime Function()? _sleepClock;

  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<PlayerEntry?> current = ValueNotifier(null);
  final ValueNotifier<int?> countdown = ValueNotifier(null);
  final ValueNotifier<SleepTimerState> sleepTimer = ValueNotifier(const SleepTimerState.off());
  final ValueNotifier<String?> comfortNotice = ValueNotifier(null);

  /// Optional test sink observing mpv property writes (`sub-delay`, `audio-delay`, `deinterlace`).
  @visibleForTesting
  Future<void> Function(String key, String value)? debugMpvPropertySink;

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
  bool get isPlaying => _systemPipActive ? _pipPlaying : (_debugPreview ? _debugPlaying : (_player?.state.playing ?? false));
  Duration get position => _systemPipActive ? _pipPosition : (_debugPreview ? _debugPosition : (_player?.state.position ?? Duration.zero));
  Duration get duration => _systemPipActive ? _pipDuration : (_debugPreview ? _debugDuration : (_player?.state.duration ?? Duration.zero));
  double get rate => _debugPreview ? _debugRate : (_player?.state.rate ?? 1.0);
  double get volume => _debugPreview ? _debugVolume : (_player?.state.volume ?? 100.0);
  int get subDelayMs => _subDelayMs;
  int get audioDelayMs => _audioDelayMs;
  bool get hasDelayOffset => _subDelayMs != 0 || _audioDelayMs != 0;
  String get deinterlace => AppSettings.normalizeDeinterlace(AppSettings.instance.deinterlace);
  bool get isTempSpeedHolding => _tempSpeedHoldActive;

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
    SystemPip.instance.onPlaybackState = _onPipPlaybackState;
    SystemMediaControls.instance.ensureInitialized();
    SystemMediaControls.instance.onCommand = _onMediaCommand;
  }

  void _onSettingsChanged() {
    if (!_active) return;
    SystemPip.instance.setAutoStart(AppSettings.instance.autoPipOnLeave);
    final desiredDeint = deinterlace;
    if (_appliedDeinterlace != desiredDeint) {
      _applyDeinterlace(desiredDeint);
    }
    _syncSystemMedia();
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
    _backgroundAudioOnly = false;
    _pausedByInterruption = false;
    _tempSpeedHoldActive = false;
    _rateBeforeHold = null;
    _subDelayMs = 0;
    _audioDelayMs = 0;
    comfortNotice.value = null;
    if (kind == Kind.live && sleepTimer.value.mode == SleepTimerMode.endOfCurrent) {
      cancelSleepTimer();
    }
    _lastMediaPos = null;
    _lastMediaPosAt = null;
    _lastMediaDuration = Duration.zero;
    _lastLiveEpgTitle = null;

    final e = entry!;
    current.value = e;
    _loadEpg(e);
    _resetPendingTracks(e);

    // Release cached posters before allocating hardware video buffers.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();

    final created = _ensurePlayer();
    if (created) {
      await _applyMpvOptions();
    } else {
      await _exitBackgroundAudioOnly();
    }
    await _applyTrackMpvOptions();
    await _applyComfortMpvOptions();
    if (!_active) return;

    Library.instance.touch(url: e.url, title: e.title, logo: e.logo, kind: _kind, item: e.item);
    notifyListeners();

    await _openCurrent();
    if (!_active) return;
    _syncSystemPip(playingOverride: true);
    _syncSystemMedia(playingOverride: true);
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

      if (_active && !_systemPipActive && !live) {
        final now = DateTime.now();
        final prevPos = _lastMediaPos;
        final prevAt = _lastMediaPosAt;
        _lastMediaPos = pos;
        _lastMediaPosAt = now;
        if (prevPos != null && prevAt != null) {
          final elapsedMs = now.difference(prevAt).inMilliseconds;
          final expectedMs = isPlaying
              ? prevPos.inMilliseconds + (elapsedMs * rate).round()
              : prevPos.inMilliseconds;
          if ((pos.inMilliseconds - expectedMs).abs() > 1800) {
            _syncSystemMedia(seeked: true);
          }
        }
      }
    }));
    _subs.add(p.stream.playing.listen((playing) {
      if (_active && !_systemPipActive) {
        _syncSystemPip(playingOverride: playing);
        _syncSystemMedia(playingOverride: playing);
        notifyListeners();
      }
    }));
    _subs.add(p.stream.duration.listen((dur) {
      if (!_active || _systemPipActive || live || dur <= Duration.zero) return;
      if ((dur - _lastMediaDuration).abs() >= const Duration(seconds: 1)) {
        _lastMediaDuration = dur;
        _syncSystemMedia();
      }
    }));
    _subs.add(p.stream.rate.listen((_) {
      if (_active && !_systemPipActive) {
        _syncSystemMedia();
      }
    }));
    _subs.add(p.stream.volume.listen((_) {
      if (_active && !_systemPipActive) {
        _syncSystemMedia();
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
    _subs.add(p.stream.tracks.listen((t) {
      if (!_active || _systemPipActive) return;
      _applyPendingTracks(t);
    }));

    _pipSyncTimer?.cancel();
    _pipSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_active && !_systemPipActive && !live && isPlaying) {
        _syncSystemPip();
      }
    });
    _mediaSyncTimer?.cancel();
    _mediaSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_active || _systemPipActive) return;
      if (live) {
        final currentTitle = activeEpgProgramme(_resolvedProgrammes)?.title;
        if (currentTitle != _lastLiveEpgTitle) {
          _syncSystemMedia();
        }
      } else if (isPlaying) {
        _syncSystemMedia();
      }
    });
    return true;
  }

  void _resetPendingTracks(PlayerEntry e) {
    final prefs = Library.instance.trackPreferencesFor(e.url, item: e.item ?? _resolvedItem);
    _pendingAudioPref = prefs.audio;
    _pendingSubtitlePref = prefs.subtitle;
    _userPickedAudio = false;
    _userPickedSubtitle = false;
    _appliedSavedAudio = false;
    _appliedSavedSubtitle = false;
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
    final deint = deinterlace;
    await _setMpvProperty('deinterlace', deint);
    _appliedDeinterlace = deint;
    await set('cache-secs', '${s.cacheSecs}');
    await set('demuxer-readahead-secs', '${s.cacheSecs}');
    if (s.tvMode) {
      await set('demuxer-max-bytes', '48MiB');
      await set('demuxer-max-back-bytes', '16MiB');
      await set('hr-seek', 'no');
    }
  }

  Future<void> _applyTrackMpvOptions() async {
    final p = _player;
    if (p == null) return;
    final s = AppSettings.instance;
    final audioPref = _pendingAudioPref;
    final subPref = _pendingSubtitlePref;

    if (audioPref != null) {
      if (audioPref.id == 'no') {
        await _setMpvProperty('alang', '');
        await _setMpvProperty('aid', 'no');
      } else if (audioPref.id == 'auto') {
        await _setMpvProperty('alang', s.alang);
        await _setMpvProperty('aid', 'auto');
      } else {
        final lang = mpvLangList(audioPref.language);
        await _setMpvProperty('alang', lang.isNotEmpty ? lang : s.alang);
        await _setMpvProperty('aid', 'auto');
      }
    } else {
      await _setMpvProperty('alang', s.alang);
      await _setMpvProperty('aid', 'auto');
    }

    if (subPref != null) {
      if (subPref.id == 'no') {
        await _setMpvProperty('slang', '');
        await _setMpvProperty('sid', 'no');
      } else if (subPref.id == 'auto') {
        await _setMpvProperty('slang', s.slang);
        await _setMpvProperty('sid', s.slang.isNotEmpty ? 'auto' : 'no');
      } else {
        final lang = mpvLangList(subPref.language);
        await _setMpvProperty('slang', lang.isNotEmpty ? lang : s.slang);
        await _setMpvProperty('sid', 'auto');
      }
    } else if (s.slang.isNotEmpty) {
      await _setMpvProperty('slang', s.slang);
      await _setMpvProperty('sid', 'auto');
    } else {
      await _setMpvProperty('slang', '');
      await _setMpvProperty('sid', 'no');
    }
  }

  void _applyPendingTracks(Tracks t) {
    final p = _player;
    if (p == null) return;
    final audioPref = _pendingAudioPref;
    if (!_userPickedAudio && !_appliedSavedAudio && audioPref != null) {
      if (audioPref.id == 'no') {
        _appliedSavedAudio = true;
        if (p.state.track.audio.id != 'no') p.setAudioTrack(AudioTrack.no());
      } else if (audioPref.id == 'auto') {
        _appliedSavedAudio = true;
        if (p.state.track.audio.id != 'auto') p.setAudioTrack(AudioTrack.auto());
      } else if (t.audio.any((a) => a.id != 'auto' && a.id != 'no')) {
        _appliedSavedAudio = true;
        final matched = matchSavedTrack<AudioTrack>(
          t.audio,
          audioPref,
          idOf: (a) => a.id,
          languageOf: (a) => a.language,
          titleOf: (a) => a.title,
        );
        if (matched != null && p.state.track.audio != matched) {
          p.setAudioTrack(matched);
        }
      }
    }

    final subPref = _pendingSubtitlePref;
    if (!_userPickedSubtitle && !_appliedSavedSubtitle && subPref != null) {
      if (subPref.id == 'no') {
        _appliedSavedSubtitle = true;
        if (p.state.track.subtitle.id != 'no') p.setSubtitleTrack(SubtitleTrack.no());
      } else if (subPref.id == 'auto') {
        _appliedSavedSubtitle = true;
        if (p.state.track.subtitle.id != 'auto') p.setSubtitleTrack(SubtitleTrack.auto());
      } else if (t.subtitle.any((sub) => sub.id != 'auto' && sub.id != 'no')) {
        _appliedSavedSubtitle = true;
        final matched = matchSavedTrack<SubtitleTrack>(
          t.subtitle,
          subPref,
          idOf: (sub) => sub.id,
          languageOf: (sub) => sub.language,
          titleOf: (sub) => sub.title,
        );
        if (matched != null && p.state.track.subtitle != matched) {
          p.setSubtitleTrack(matched);
        }
      }
    }
  }

  /// Selects [track] on the player and persists the choice for the current item/series.
  Future<void> setAudioTrack(AudioTrack track) async {
    _userPickedAudio = true;
    _appliedSavedAudio = true;
    await _player?.setAudioTrack(track);
    final e = entry;
    if (e != null) {
      await Library.instance.saveTracks(
        e.url,
        audio: TrackPref(id: track.id, language: track.language, title: track.title),
        item: e.item ?? _resolvedItem,
      );
    }
  }

  /// Selects [track] on the player and persists the choice for the current item/series.
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    _userPickedSubtitle = true;
    _appliedSavedSubtitle = true;
    await _player?.setSubtitleTrack(track);
    final e = entry;
    if (e != null) {
      await Library.instance.saveTracks(
        e.url,
        subtitle: TrackPref(id: track.id, language: track.language, title: track.title),
        item: e.item ?? _resolvedItem,
      );
    }
  }

  Future<void> _setMpvProperty(String key, String value) async {
    final sink = debugMpvPropertySink;
    if (sink != null) {
      await sink(key, value);
    }
    final p = _player;
    if (p == null) return;
    try {
      await (p.platform as dynamic).setProperty(key, value);
    } catch (_) {}
  }

  Future<void> _applyDeinterlace(String mode) async {
    final norm = AppSettings.normalizeDeinterlace(mode);
    _appliedDeinterlace = norm;
    await _setMpvProperty('deinterlace', norm);
  }

  Future<void> _applyComfortMpvOptions() async {
    await _applyDeinterlace(deinterlace);
    await _setMpvProperty('sub-delay', mpvDelaySeconds(_subDelayMs));
    await _setMpvProperty('audio-delay', mpvDelaySeconds(_audioDelayMs));
  }

  /// Sets subtitle synchronization delay in milliseconds (clamped to ±30 s) and applies it live to mpv.
  Future<void> setSubDelayMs(int ms) async {
    final clamped = clampSubDelayMs(ms);
    _subDelayMs = clamped;
    await _setMpvProperty('sub-delay', mpvDelaySeconds(clamped));
    notifyListeners();
  }

  Future<void> adjustSubDelayMs(int deltaMs) => setSubDelayMs(_subDelayMs + deltaMs);

  /// Sets audio synchronization delay in milliseconds (clamped to ±10 s) and applies it live to mpv.
  Future<void> setAudioDelayMs(int ms) async {
    final clamped = clampAudioDelayMs(ms);
    _audioDelayMs = clamped;
    await _setMpvProperty('audio-delay', mpvDelaySeconds(clamped));
    notifyListeners();
  }

  Future<void> adjustAudioDelayMs(int deltaMs) => setAudioDelayMs(_audioDelayMs + deltaMs);

  /// Resets both subtitle and audio delays back to 0 ms.
  Future<void> resetDelays() async {
    _subDelayMs = 0;
    _audioDelayMs = 0;
    await _setMpvProperty('sub-delay', mpvDelaySeconds(0));
    await _setMpvProperty('audio-delay', mpvDelaySeconds(0));
    notifyListeners();
  }

  /// Updates persisted deinterlace mode (`no` | `auto` | `yes`) and applies it immediately to mpv.
  Future<void> setDeinterlace(String mode) async {
    final norm = AppSettings.normalizeDeinterlace(mode);
    await AppSettings.instance.update(deinterlace: norm);
    await _applyDeinterlace(norm);
    notifyListeners();
  }

  /// Temporarily boosts VOD playback speed (default 2×) while the user holds the screen.
  Future<bool> beginTempSpeedHold({double targetRate = holdBoostRate}) async {
    if (!_active || live || _tempSpeedHoldActive) return false;
    _rateBeforeHold = rate;
    _tempSpeedHoldActive = true;
    final clamped = targetRate.clamp(0.25, 4.0).toDouble();
    if (_debugPreview) {
      _debugRate = clamped;
      _syncSystemMedia();
    } else {
      await _player?.setRate(clamped);
    }
    notifyListeners();
    return true;
  }

  /// Restores the playback speed that was active before [beginTempSpeedHold].
  Future<void> endTempSpeedHold() async {
    if (!_tempSpeedHoldActive) return;
    final restore = (_rateBeforeHold ?? 1.0).clamp(0.25, 4.0).toDouble();
    _tempSpeedHoldActive = false;
    _rateBeforeHold = null;
    if (_debugPreview) {
      _debugRate = restore;
      _syncSystemMedia();
    } else if (_active) {
      await _player?.setRate(restore);
    }
    notifyListeners();
  }

  /// Starts a wall-clock countdown sleep timer that persists across rotation, Mini Player, and System PiP.
  void setSleepTimer(Duration duration, {DateTime Function()? now}) {
    if (!_active) return;
    if (duration <= Duration.zero) {
      cancelSleepTimer();
      return;
    }
    final clock = now ?? DateTime.now;
    _sleepClock = clock;
    _sleepTickTimer?.cancel();
    _sleepTargetAt = clock().add(duration);
    sleepTimer.value = SleepTimerState.countdown(duration);
    _sleepTickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickSleepTimer());
    notifyListeners();
  }

  /// Adds [extra] time to an active countdown sleep timer, or starts a new timer if none is running.
  void extendSleepTimer(Duration extra, {DateTime Function()? now}) {
    if (!_active || extra <= Duration.zero) return;
    if (sleepTimer.value.mode == SleepTimerMode.countdown && _sleepTargetAt != null) {
      final clock = now ?? _sleepClock ?? DateTime.now;
      _sleepClock = clock;
      _sleepTargetAt = _sleepTargetAt!.add(extra);
      final rem = _sleepTargetAt!.difference(clock());
      sleepTimer.value = SleepTimerState.countdown(rem.isNegative ? Duration.zero : rem);
      notifyListeners();
      return;
    }
    setSleepTimer(extra, now: now);
  }

  /// Configures the sleep timer to stop playback when the current movie or episode finishes.
  void setSleepAtEndOfCurrent() {
    if (!_active || live) return;
    _sleepTickTimer?.cancel();
    _sleepTickTimer = null;
    _sleepTargetAt = null;
    _sleepClock = null;
    sleepTimer.value = const SleepTimerState.endOfCurrent();
    notifyListeners();
  }

  /// Cancels any active sleep timer.
  void cancelSleepTimer() {
    _sleepTickTimer?.cancel();
    _sleepTickTimer = null;
    _sleepTargetAt = null;
    _sleepClock = null;
    if (sleepTimer.value.isActive) {
      sleepTimer.value = const SleepTimerState.off();
      notifyListeners();
    }
  }

  void _tickSleepTimer() {
    if (!_active || _sleepTargetAt == null) {
      cancelSleepTimer();
      return;
    }
    final clock = _sleepClock ?? DateTime.now;
    final rem = _sleepTargetAt!.difference(clock());
    if (rem <= Duration.zero) {
      _triggerSleepTimer();
    } else {
      sleepTimer.value = SleepTimerState.countdown(rem);
    }
  }

  Future<void> _triggerSleepTimer() async {
    _sleepTickTimer?.cancel();
    _sleepTickTimer = null;
    _sleepTargetAt = null;
    _sleepClock = null;
    sleepTimer.value = const SleepTimerState.off();
    if (!_active) return;

    await endTempSpeedHold();
    _cancelCountdown();
    _save();

    if (live) {
      // Closing live TV releases the Xtream connection slot, System PiP, and wakelock cleanly.
      await close();
      return;
    }

    await pause();
    comfortNotice.value = 'Uyku zamanlayıcısı doldu · Duraklatıldı';
    notifyListeners();
  }

  Future<void> _enterBackgroundAudioOnly() async {
    if (_backgroundAudioOnly) return;
    _backgroundAudioOnly = true;
    await _setMpvProperty('vid', 'no');
  }

  Future<void> _exitBackgroundAudioOnly() async {
    if (!_backgroundAudioOnly) return;
    _backgroundAudioOnly = false;
    await _setMpvProperty('vid', 'auto');
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
          _syncSystemMedia();
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
    var resumed = false;
    if (target != null && target > Duration.zero) {
      try {
        await p.stream.duration.firstWhere((d) => d > Duration.zero);
      } catch (_) {
        return;
      }
      if (gen != _gen || !_active) return;
      await p.seek(target);
      if (gen != _gen || !_active) return;
      _lastMediaPos = target;
      _lastMediaPosAt = DateTime.now();
      resumed = true;
    }
    _saveable = true;
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    _syncSystemPip();
    _syncSystemMedia(seeked: resumed);
  }

  /// Switches to another channel or episode without leaving the player session.
  Future<void> switchTo(int i) async {
    if (!_active || i < 0 || i >= _queue.length || i == _index) return;
    await endTempSpeedHold();
    _cancelCountdown();
    _saveTimer?.cancel();
    _save();
    _saveable = false;
    _subDelayMs = 0;
    _audioDelayMs = 0;
    _gen++;
    _retries = 0;
    _errorGen = null;
    error.value = null;
    _ignoredError = null;
    _lastMediaPos = null;
    _lastMediaPosAt = null;
    _lastMediaDuration = Duration.zero;
    _lastLiveEpgTitle = null;
    _index = i;
    _resolvedItem = null;
    final e = entry!;
    current.value = e;
    _loadEpg(e);
    _resetPendingTracks(e);
    Library.instance.touch(url: e.url, title: e.title, logo: e.logo, kind: _kind, item: e.item);
    notifyListeners();

    if (_systemPipActive) {
      final local = _resolveLocalPath(e);
      _pipPlaying = true;
      _pipPosition = Duration.zero;
      _pipDuration = Duration.zero;
      await SystemPip.instance.switchStream(
        url: local != null ? Uri.file(local).toString() : e.url,
        title: e.title,
        live: live,
        userAgent: _userAgent,
      );
      _syncSystemMedia(playingOverride: true);
      return;
    }

    if (_debugPreview) {
      _debugPosition = Duration.zero;
      await _applyComfortMpvOptions();
      _syncSystemMedia();
      return;
    }

    await _applyTrackMpvOptions();
    await _applyComfortMpvOptions();
    if (!_active) return;
    await _openCurrent();
    if (!_active) return;
    _syncSystemPip(playingOverride: true);
    _syncSystemMedia(playingOverride: true);
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
    final e = entry;
    if (e != null) _resetPendingTracks(e);
    await _applyTrackMpvOptions();
    await _applyComfortMpvOptions();
    if (!_active) return;
    await _openCurrent();
    if (!_active) return;
    _syncSystemPip(playingOverride: true);
    _syncSystemMedia(playingOverride: true);
    await _afterOpen();
  }

  void toggleFit() {
    _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
    notifyListeners();
  }

  Future<void> play() async {
    if (!_active) return;
    _pausedByInterruption = false;
    if (_systemPipActive) {
      _pipPlaying = true;
      await SystemPip.instance.setPlaying(true);
      _syncSystemMedia(playingOverride: true);
      notifyListeners();
      return;
    }
    if (_debugPreview) {
      _debugPlaying = true;
      _syncSystemMedia(playingOverride: true);
      notifyListeners();
      return;
    }
    if (!kIsWeb && Platform.isIOS && WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      // Explicit Lock Screen / AirPods play while screen is locked: disable video decoding
      // before starting mpv so iOS never triggers background GPU rendering.
      await _enterBackgroundAudioOnly();
    }
    await _player?.play();
  }

  Future<void> pause() async {
    if (!_active) return;
    _pausedByInterruption = false;
    if (_systemPipActive) {
      _pipPlaying = false;
      await SystemPip.instance.setPlaying(false);
      _syncSystemMedia(playingOverride: false);
      notifyListeners();
      return;
    }
    if (_debugPreview) {
      _debugPlaying = false;
      _syncSystemMedia(playingOverride: false);
      notifyListeners();
      return;
    }
    await _player?.pause();
  }

  Future<void> playOrPause() async {
    if (!_active) return;
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Seeks VOD playback to [target] and immediately informs OS media controls.
  Future<void> seekTo(Duration target) async {
    if (!_active || live) return;
    var clamped = target < Duration.zero ? Duration.zero : target;
    final dur = duration;
    if (dur > Duration.zero && clamped > dur) {
      clamped = dur;
    }
    if (_systemPipActive) {
      _pipPosition = clamped;
      await SystemPip.instance.seekTo(clamped);
      await SystemMediaControls.instance.notifySeeked(clamped);
      notifyListeners();
      return;
    }
    if (_debugPreview) {
      _debugPosition = clamped;
      notifyListeners();
      await SystemMediaControls.instance.notifySeeked(clamped);
      return;
    }
    await _player?.seek(clamped);
    notifyUserSeek(clamped);
  }

  /// Relative VOD seek used by AirPods/Lock Screen skip buttons and MPRIS2 `Seek`.
  Future<void> seekBy(Duration offset) async {
    if (!_active || live) return;
    if (_systemPipActive) {
      await SystemPip.instance.skipBy(offset);
      return;
    }
    await seekTo(position + offset);
  }

  /// Informs OS media controls immediately when the player UI performs a seek directly on `Player`.
  void notifyUserSeek(Duration target) {
    if (!_active || live) return;
    final clamped = target < Duration.zero ? Duration.zero : target;
    _lastMediaPos = clamped;
    _lastMediaPosAt = DateTime.now();
    SystemMediaControls.instance.notifySeeked(clamped);
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
    if (p != null) {
      final ignored = _ignoredError;
      final state = p.state;
      if (ignored != null && state.duration - state.position > const Duration(seconds: 60)) {
        error.value = 'Yayın yarıda kesildi.\n\n$ignored';
        return;
      }
    } else if (!_debugPreview) {
      return;
    }
    if (sleepTimer.value.mode == SleepTimerMode.endOfCurrent) {
      cancelSleepTimer();
      if (_debugPreview) _debugPlaying = false;
      comfortNotice.value = _kind == Kind.series
          ? 'Uyku zamanlayıcısı · Bölüm bitti'
          : 'Uyku zamanlayıcısı · İçerik bitti';
      notifyListeners();
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

  /// Stops playback completely, clears iOS System PiP & OS media controls, and releases native resources.
  Future<void> close() async {
    final shouldClearMedia = !_debugPreview || _debugEmitMediaControls;
    _cancelCountdown();
    cancelSleepTimer();
    _saveTimer?.cancel();
    _saveTimer = null;
    _pipSyncTimer?.cancel();
    _pipSyncTimer = null;
    _mediaSyncTimer?.cancel();
    _mediaSyncTimer = null;
    _save();
    _saveable = false;
    _gen++;

    _active = false;
    _minimized = false;
    _systemPipActive = false;
    _pipPlaying = true;
    _pipPosition = Duration.zero;
    _pipDuration = Duration.zero;
    _backgroundAudioOnly = false;
    _pausedByInterruption = false;
    _playingLocal = false;
    _subDelayMs = 0;
    _audioDelayMs = 0;
    _appliedDeinterlace = null;
    _tempSpeedHoldActive = false;
    _rateBeforeHold = null;
    comfortNotice.value = null;
    _debugPreview = false;
    _debugEmitMediaControls = false;
    _lastMediaPos = null;
    _lastMediaPosAt = null;
    _lastMediaDuration = Duration.zero;
    _lastLiveEpgTitle = null;
    _queue = const [];
    _index = 0;
    _resolvedItem = null;
    _epg = null;
    _resolvedProgrammes = const [];
    error.value = null;
    current.value = null;

    final subs = List<StreamSubscription<dynamic>>.of(_subs);
    _subs.clear();
    final p = _player;
    _player = null;
    _controller = null;

    notifyListeners();

    for (final sub in subs) {
      await sub.cancel();
    }
    await p?.dispose();
    await SystemPip.instance.clear();
    if (shouldClearMedia) {
      await SystemMediaControls.instance.clear();
    }
  }

  void _syncSystemMedia({bool? playingOverride, bool seeked = false}) {
    if (!_active || !SystemMediaControls.instance.isSupported) return;
    if (_debugPreview && !_debugEmitMediaControls) return;
    final e = entry;
    if (e == null) return;
    final local = _playingLocal ? _resolveLocalPath(e) : null;
    final state = buildSystemMediaState(
      trackId: '/dev/nailhakan/iptv/track/t_${_gen}_$_index',
      rawTitle: e.title,
      kind: _kind,
      playing: playingOverride ?? isPlaying,
      position: position,
      duration: duration,
      canGoNext: hasNext,
      canGoPrevious: hasPrev,
      logo: e.logo,
      group: e.group,
      item: detailItem,
      programmes: _resolvedProgrammes,
      localPath: local,
      rate: rate,
      volumePercent: volume,
      skipSeconds: AppSettings.instance.skipSecs,
      userAgent: _userAgent,
    );
    _lastLiveEpgTitle = live ? activeEpgProgramme(_resolvedProgrammes)?.title : null;
    SystemMediaControls.instance.update(state, seeked: seeked);
  }

  Future<void> _onMediaCommand(SystemMediaCommand cmd) async {
    if (!_active) return;
    switch (cmd.action) {
      case SystemMediaAction.play:
        await play();
      case SystemMediaAction.pause:
        await pause();
      case SystemMediaAction.playPause:
        await playOrPause();
      case SystemMediaAction.stop:
        await close();
      case SystemMediaAction.next:
        if (hasNext) await switchTo(_index + 1);
      case SystemMediaAction.previous:
        if (hasPrev) await switchTo(_index - 1);
      case SystemMediaAction.seek:
        if (cmd.position != null) await seekTo(cmd.position!);
      case SystemMediaAction.seekBy:
        if (cmd.offset != null) await seekBy(cmd.offset!);
      case SystemMediaAction.setVolume:
        final vol = cmd.volume;
        if (vol != null) {
          final pct = (vol.clamp(0.0, 1.0) * 100.0).toDouble();
          if (_debugPreview) {
            _debugVolume = pct;
            _syncSystemMedia();
            notifyListeners();
          } else {
            await _player?.setVolume(pct);
            _syncSystemMedia();
          }
        }
      case SystemMediaAction.setRate:
        final r = cmd.rate;
        if (!live && r != null) {
          final clamped = r.clamp(0.25, 4.0).toDouble();
          if (_debugPreview) {
            _debugRate = clamped;
            _syncSystemMedia();
            notifyListeners();
          } else {
            await _player?.setRate(clamped);
            _syncSystemMedia();
          }
        }
      case SystemMediaAction.audioInterruptionBegan:
        if (isPlaying) {
          _pausedByInterruption = true;
          if (_systemPipActive) {
            _pipPlaying = false;
            await SystemPip.instance.setPlaying(false);
            _syncSystemMedia(playingOverride: false);
            notifyListeners();
          } else if (_debugPreview) {
            _debugPlaying = false;
            _syncSystemMedia(playingOverride: false);
            notifyListeners();
          } else {
            await _player?.pause();
          }
        }
      case SystemMediaAction.audioInterruptionEnded:
        final shouldResume = _pausedByInterruption && cmd.shouldResume;
        _pausedByInterruption = false;
        if (shouldResume) {
          await play();
        }
      case SystemMediaAction.audioBecomingNoisy:
        if (isPlaying) {
          await pause();
        }
    }
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
    if (_tempSpeedHoldActive) {
      endTempSpeedHold();
    }
    _systemPipActive = true;
    _pipPlaying = true;
    _pipPosition = _player?.state.position ?? _debugPosition;
    _pipDuration = _player?.state.duration ?? _debugDuration;
    _save();
    _saveTimer?.cancel();
    _saveable = false;
    // Stop mpv immediately to release the single IPTV connection slot and avoid
    // OpenGL ES calls while backgrounded.
    _player?.stop();
    _syncSystemMedia(playingOverride: true);
    notifyListeners();
  }

  void _onPipDidStart() {
    if (!_active) return;
    _systemPipActive = true;
    _syncSystemMedia(playingOverride: _pipPlaying);
    notifyListeners();
  }

  void _onPipPlaybackState(SystemPipPlaybackState state) {
    if (!_active || !_systemPipActive) return;
    _pipPlaying = state.playing;
    _pipPosition = Duration(milliseconds: state.positionMs);
    if (state.durationMs > 0) {
      _pipDuration = Duration(milliseconds: state.durationMs);
    }
    _syncSystemMedia(playingOverride: state.playing);
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
      await _exitBackgroundAudioOnly();
      await _applyComfortMpvOptions();
      await _openCurrent();
      if (!_active) return;
      await _afterOpen(resumeOverride: resumePos);
      if (!event.wasPlaying) {
        await _player?.pause();
      }
      _syncSystemPip(playingOverride: event.wasPlaying);
      _syncSystemMedia(playingOverride: event.wasPlaying);
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
      if (_active) {
        await _afterOpen();
        _syncSystemMedia();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active || _debugPreview) return;
    if (state == AppLifecycleState.inactive) {
      _save();
      _syncSystemPip();
      _syncSystemMedia();
    } else if (state == AppLifecycleState.paused) {
      _save();
      // When auto-PiP is disabled (or PiP did not start), pause mpv on iOS so
      // playback stops cleanly instead of running silently in background.
      if (SystemPip.instance.isSupported && !_systemPipActive && isPlaying && !_backgroundAudioOnly) {
        _player?.pause();
        _syncSystemMedia(playingOverride: false);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_sleepTargetAt != null) {
        final clock = _sleepClock ?? DateTime.now;
        if (!clock().isBefore(_sleepTargetAt!)) {
          _triggerSleepTimer();
          return;
        }
      }
      if (_backgroundAudioOnly) {
        _exitBackgroundAudioOnly();
      }
      _syncSystemPip();
      _syncSystemMedia();
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
    debugSetQueuePreview(
      queue: [entry],
      index: 0,
      kind: kind,
      playing: playing,
      position: position,
      duration: duration,
      programmes: programmes,
      minimized: true,
    );
  }

  /// Injects a multi-item queue preview for unit/widget tests without initializing libmpv.
  @visibleForTesting
  void debugSetQueuePreview({
    required List<PlayerEntry> queue,
    int index = 0,
    Kind kind = Kind.live,
    bool playing = true,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    double rate = 1.0,
    double volume = 100.0,
    List<Programme> programmes = const [],
    bool minimized = false,
    bool systemPipActive = false,
    bool emitMediaControls = false,
  }) {
    assert(queue.isNotEmpty);
    _debugPreview = true;
    _debugEmitMediaControls = emitMediaControls;
    _debugPlaying = playing;
    _debugPosition = position;
    _debugDuration = duration;
    _debugRate = rate;
    _debugVolume = volume;
    _queue = List<PlayerEntry>.unmodifiable(queue);
    _index = index.clamp(0, _queue.length - 1);
    _kind = kind;
    _active = true;
    _minimized = minimized;
    _systemPipActive = systemPipActive;
    _pipPlaying = playing;
    _pipPosition = position;
    _pipDuration = duration;
    _resolvedProgrammes = programmes;
    current.value = _queue[_index];
    _syncSystemMedia();
    notifyListeners();
  }

  /// Exercises incoming OS media commands in tests without requiring libmpv.
  @visibleForTesting
  Future<void> debugHandleMediaCommand(SystemMediaCommand cmd) => _onMediaCommand(cmd);

  /// Exercises stream completion handling (e.g. sleep timer end-of-current) in tests without libmpv.
  @visibleForTesting
  void debugHandleCompleted() => _onCompleted();

  /// Resets test preview state cleanly without touching native channels.
  @visibleForTesting
  void debugReset() {
    _cancelCountdown();
    cancelSleepTimer();
    _saveTimer?.cancel();
    _saveTimer = null;
    _pipSyncTimer?.cancel();
    _pipSyncTimer = null;
    _mediaSyncTimer?.cancel();
    _mediaSyncTimer = null;
    _active = false;
    _minimized = false;
    _systemPipActive = false;
    _pipPlaying = true;
    _pipPosition = Duration.zero;
    _pipDuration = Duration.zero;
    _backgroundAudioOnly = false;
    _pausedByInterruption = false;
    _playingLocal = false;
    _debugPreview = false;
    _debugEmitMediaControls = false;
    _debugRate = 1.0;
    _debugVolume = 100.0;
    _subDelayMs = 0;
    _audioDelayMs = 0;
    _appliedDeinterlace = null;
    _tempSpeedHoldActive = false;
    _rateBeforeHold = null;
    debugMpvPropertySink = null;
    _lastMediaPos = null;
    _lastMediaPosAt = null;
    _lastMediaDuration = Duration.zero;
    _lastLiveEpgTitle = null;
    _queue = const [];
    _index = 0;
    _resolvedItem = null;
    _resolvedProgrammes = const [];
    _pendingAudioPref = null;
    _pendingSubtitlePref = null;
    _userPickedAudio = false;
    _userPickedSubtitle = false;
    _appliedSavedAudio = false;
    _appliedSavedSubtitle = false;
    current.value = null;
    error.value = null;
    countdown.value = null;
    comfortNotice.value = null;
    notifyListeners();
  }
}

/// Normalizes common ISO 639-1 / 639-2 track language tags (e.g. `tur` -> `tr`).
String normalizeTrackLang(String? raw) {
  final v = raw?.trim().toLowerCase() ?? '';
  if (v.isEmpty) return '';
  final base = v.split(RegExp(r'[-_]')).first;
  return switch (base) {
    'tur' || 'trk' => 'tr',
    'eng' => 'en',
    'deu' || 'ger' => 'de',
    'fra' || 'fre' => 'fr',
    'spa' || 'esl' => 'es',
    'ita' => 'it',
    'rus' => 'ru',
    'ara' => 'ar',
    'jpn' => 'ja',
    'zho' || 'chi' => 'zh',
    'kor' => 'ko',
    'por' => 'pt',
    'nld' || 'dut' => 'nl',
    _ => base,
  };
}

/// Builds a comma-separated mpv `alang`/`slang` preference string for [lang].
String mpvLangList(String? lang) {
  final raw = lang?.trim().toLowerCase() ?? '';
  if (raw.isEmpty) return '';
  final norm = normalizeTrackLang(raw);
  return switch (norm) {
    'tr' => 'tr,tur',
    'en' => 'en,eng',
    _ when norm != raw => '$raw,$norm',
    _ => raw,
  };
}

/// Finds the best matching track in [tracks] for a saved [pref].
T? matchSavedTrack<T>(
  List<T> tracks,
  TrackPref pref, {
  required String Function(T) idOf,
  required String? Function(T) languageOf,
  required String? Function(T) titleOf,
}) {
  final real = [
    for (final t in tracks)
      if (idOf(t) != 'auto' && idOf(t) != 'no') t,
  ];
  if (real.isEmpty) return null;

  String normText(String? s) => s?.trim().toLowerCase() ?? '';
  final pLang = normalizeTrackLang(pref.language);
  final pTitle = normText(pref.title);

  if (pref.id != 'auto' && pref.id != 'no') {
    for (final t in real) {
      if (idOf(t) == pref.id && normalizeTrackLang(languageOf(t)) == pLang && normText(titleOf(t)) == pTitle) {
        return t;
      }
    }
  }
  if (pLang.isNotEmpty && pTitle.isNotEmpty) {
    for (final t in real) {
      if (normalizeTrackLang(languageOf(t)) == pLang && normText(titleOf(t)) == pTitle) {
        return t;
      }
    }
  }
  if (pLang.isNotEmpty) {
    for (final t in real) {
      if (normalizeTrackLang(languageOf(t)) == pLang) return t;
    }
  }
  if (pTitle.isNotEmpty) {
    for (final t in real) {
      if (normText(titleOf(t)) == pTitle) return t;
    }
  }
  if (pLang.isEmpty && pTitle.isEmpty && pref.id != 'auto' && pref.id != 'no') {
    for (final t in real) {
      if (idOf(t) == pref.id) return t;
    }
  }
  return null;
}
