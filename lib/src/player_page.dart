import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'library.dart';
import 'player_chrome.dart';
import 'settings.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/format.dart';
import 'ui/layout.dart';
import 'ui/tokens.dart';
import 'xtream.dart';

/// One playable thing: a channel, a movie or an episode.
class PlayerEntry {
  const PlayerEntry({required this.url, required this.title, this.logo = '', this.group, this.epg});

  final String url;
  final String title;
  final String logo;

  /// Category shown under "Canlı TV" in the title pill (live channels).
  final String? group;

  /// Loads now/next programmes (live channels only).
  final Future<List<Programme>> Function()? epg;
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.queue, this.index = 0, this.kind = Kind.movie, this.client});

  /// What can be reached with next/previous (channels of the list, episodes of the series). [index] is the one to start.
  final List<PlayerEntry> queue;
  final int index;
  final Kind kind;

  /// Used to tell "connection limit reached" apart from other failures.
  final XtreamClient? client;

  bool get live => kind == Kind.live;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  Timer? _saveTimer;
  final ValueNotifier<String?> _error = ValueNotifier(null);
  final List<StreamSubscription<dynamic>> _subs = [];
  int _retries = 0;
  int _gen = 0; // bumped on every channel/episode change so stale retries are dropped
  int _progress = 0; // bumped whenever the playback position moves
  int? _errorGen; // the [_gen] whose error is being handled right now
  String? _ignoredError; // an error after which playback went on
  bool _saveable = false; // the player's position is the one to remember (not while opening / before the resume seek)
  late int _index = widget.index;
  Future<List<Programme>>? _epg;
  late final ValueNotifier<PlayerEntry> _current = ValueNotifier(_entry);
  final ValueNotifier<int?> _countdown = ValueNotifier(null); // seconds until the next episode starts
  Timer? _countdownTimer;
  final ValueNotifier<String> _digits = ValueNotifier(''); // channel number being typed
  Timer? _digitsTimer;
  BoxFit _fit = BoxFit.contain;
  bool _immersive = false;

  PlayerEntry get _entry => widget.queue[_index];
  bool get _hasNext => _index < widget.queue.length - 1;
  bool get _hasPrev => _index > 0;

  @override
  void initState() {
    super.initState();
    _epg = _entry.epg?.call();
    // The lists behind the player hold decoded posters; release them while a video plays.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    _start();
  }

  Future<void> _start() async {
    final s = AppSettings.instance;
    // mpv options (media_kit exposes them on the native platform player)
    final native = _player.platform as dynamic;
    Future<void> set(String k, String v) async {
      try {
        await native.setProperty(k, v);
      } catch (_) {
        // property not supported on this platform: ignore
      }
    }

    await set('hwdec', s.hwdec ? 'auto-safe' : 'no');
    await set('cache-secs', '${s.cacheSecs}');
    await set('demuxer-readahead-secs', '${s.cacheSecs}');
    if (s.tvMode) {
      // TV sticks have ~1 GB RAM: mpv's default demuxer cache (150 MiB forward + 150 MiB back) makes
      // the system swap. Keep it small and seek to the nearest keyframe (much faster than exact seeks).
      await set('demuxer-max-bytes', '48MiB');
      await set('demuxer-max-back-bytes', '16MiB');
      await set('hr-seek', 'no');
    }
    if (s.alang.isNotEmpty) await set('alang', s.alang);
    if (s.slang.isNotEmpty) {
      await set('slang', s.slang);
      await set('sid', 'auto');
    }
    if (!mounted) return; // left again while the options were being set: the player is already disposed

    Library.instance.touch(url: _entry.url, title: _entry.title, logo: _entry.logo, kind: widget.kind);

    _subs.add(_player.stream.error.listen((message) => _onError(message)));
    // Only a moving position proves that the stream plays: media_kit reports playing=true as soon as open()
    // is called, before any data has arrived, so that must not reset the retry counter or hide the error.
    var last = Duration.zero;
    _subs.add(_player.stream.position.listen((position) {
      if (position == Duration.zero || position == last) return;
      last = position;
      _progress++;
      _retries = 0;
      if (_error.value != null) _error.value = null;
    }));
    if (widget.live) {
      // A live stream that "ends" has dropped: reconnect.
      _subs.add(_player.stream.completed.listen((done) {
        if (done) _onError('stream ended', stopped: true);
      }));
    } else {
      _subs.add(_player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }));
    }

    await _open();
    await _afterOpen();
  }

  Future<void> _afterOpen() async {
    if (widget.live) return;
    final gen = _gen;
    if (AppSettings.instance.resume) {
      final saved = Library.instance.positionFor(_entry.url);
      if (saved != null) {
        try {
          await _player.stream.duration.firstWhere((d) => d > Duration.zero);
        } catch (_) {
          return; // the player was closed before the video loaded
        }
        if (gen != _gen || !mounted) return;
        await _player.seek(saved);
        if (gen != _gen || !mounted) return;
      }
    }
    _saveable = true;
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
  }

  Future<void> _open() => _player.open(Media(_entry.url, httpHeaders: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'}));

  /// Moves to another channel/episode of the queue without leaving the player.
  Future<void> _switchTo(int i) async {
    if (i < 0 || i >= widget.queue.length || i == _index) return;
    _cancelCountdown();
    _saveTimer?.cancel();
    _save();
    _saveable = false;
    _gen++;
    _retries = 0;
    _error.value = null;
    _ignoredError = null;
    _index = i;
    final e = _entry;
    _epg = e.epg?.call();
    _current.value = e;
    Library.instance.touch(url: e.url, title: e.title, logo: e.logo, kind: widget.kind);
    await _open();
    if (mounted) await _afterOpen();
  }

  /// Digit keys on live TV: type a channel number (position in the list, 1-based), jump after a short pause.
  void _typeDigit(String d) {
    if (_digits.value.length >= 4) return;
    _digits.value += d;
    _digitsTimer?.cancel();
    _digitsTimer = Timer(const Duration(milliseconds: 1500), () {
      final n = int.tryParse(_digits.value);
      _digits.value = '';
      if (n != null && n >= 1 && n <= widget.queue.length) _switchTo(n - 1);
    });
  }

  void _next() => _switchTo(_index + 1);
  void _prev() => _switchTo(_index - 1);

  /// An episode ended: count down 10 s (like YouTube's autoplay) and then start the next one.
  void _onCompleted() {
    if (!mounted) return;
    _save();
    // mpv also reports a connection that died for good as the end of the file. If an error was let pass because
    // the buffered part still played, and this "end" is far from the real one, it was that connection.
    final ignored = _ignoredError;
    final state = _player.state;
    if (ignored != null && state.duration - state.position > const Duration(seconds: 60)) {
      _error.value = 'Yayın yarıda kesildi.\n\n$ignored';
      return;
    }
    if (!AppSettings.instance.autoNext || !_hasNext) return;
    _countdownTimer?.cancel();
    _countdown.value = 10;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (_countdown.value ?? 1) - 1;
      if (left <= 0) {
        _next();
      } else {
        _countdown.value = left;
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdown.value = null;
  }

  Future<AccountInfo?> _accountInfo() async {
    try {
      return await widget.client?.authenticate().timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  /// [stopped]: playback is known to have ended. Otherwise the error may be a passing decoder hiccup, which mpv
  /// reports the same way, so it only counts if the position stops moving.
  Future<void> _onError(String message, {bool stopped = false}) async {
    final gen = _gen;
    // mpv logs several lines for one failure: one recovery per channel/episode at a time.
    if (!mounted || _errorGen == gen) return;
    _errorGen = gen;
    try {
      if (!stopped) {
        final before = _progress;
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted || gen != _gen) return;
        if (_progress != before) {
          _ignoredError = message;
          return;
        }
      }
      // Is the account's connection limit used up (e.g. watching on the PC and the TV stick at once)?
      final info = await _accountInfo();
      if (!mounted || gen != _gen) return; // the user moved on to another channel/episode meanwhile
      if (info != null && info.limitReached) {
        final n = '${info.activeConnections}/${info.maxConnections}';
        if (widget.live && _retries < 3) {
          // The server may still count our own dropped connection for a few seconds: wait and retry.
          _retries++;
          _error.value = 'Bağlantı sınırı dolu ($n). Başka bir cihazda izleme açık olabilir ya da önceki bağlantın henüz kapanmadı. Yeniden deneniyor ($_retries/3)...';
          await Future<void>.delayed(Duration(seconds: 4 * _retries));
          if (mounted && gen == _gen) _open();
          return;
        }
        _error.value = 'Bağlantı sınırı dolu ($n).\n\nHesabın aynı anda en fazla ${info.maxConnections} cihazda izlemeye izin veriyor. '
            'Başka bir cihazda (TV, telefon, bilgisayar) açık yayını kapat, birkaç saniye bekle ve Tekrar dene.';
        return;
      }
      if (widget.live && _retries < 3) {
        _retries++;
        _error.value = 'Bağlantı koptu, yeniden deneniyor ($_retries/3)...';
        await Future<void>.delayed(Duration(seconds: 2 * _retries));
        if (mounted && gen == _gen) _open();
        return;
      }
      final refused = RegExp(r'(401|403|404|509|884|forbidden|unauthorized)', caseSensitive: false).hasMatch(message);
      _error.value = refused
          ? 'Yayın açılamadı. Sağlayıcı isteği reddetti (hesap süresi dolmuş ya da bağlantı sınırı olabilir).\n\n$message'
          : 'Yayın açılamadı.\n\n$message';
    } finally {
      if (_errorGen == gen) _errorGen = null;
    }
  }

  /// "Tekrar dene": opens the current channel/episode again (a movie continues from the saved position).
  Future<void> _retry() async {
    _gen++; // drops a recovery or a resume that still waits on the failed attempt
    _retries = 0;
    _error.value = null;
    _ignoredError = null;
    _saveTimer?.cancel();
    _saveable = false;
    await _open();
    if (mounted) await _afterOpen();
  }

  void _save() {
    if (widget.live || !_saveable) return;
    Library.instance.savePosition(_entry.url, _player.state.position, _player.state.duration);
  }

  void _toggleFit() {
    setState(() => _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain);
  }

  Future<void> _toggleOrientation(bool currentlyLandscape) async {
    if (currentlyLandscape) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      // Allow natural auto-rotation again shortly after rotating so physical turns still work.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) SystemChrome.setPreferredOrientations(const []);
      });
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) SystemChrome.setPreferredOrientations(const []);
      });
    }
  }

  void _setImmersive(bool on) {
    if (_immersive == on) return;
    _immersive = on;
    SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    if (_immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    SystemChrome.setPreferredOrientations(const []);
    _saveTimer?.cancel();
    _countdownTimer?.cancel();
    _digitsTimer?.cancel();
    _digits.dispose();
    for (final sub in _subs) {
      sub.cancel();
    }
    _save();
    _error.dispose();
    _current.dispose();
    _countdown.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The remote's Back key first cancels a running next-episode countdown, then leaves the player.
    return ValueListenableBuilder<int?>(
      valueListenable: _countdown,
      builder: (_, left, child) => PopScope(
        canPop: left == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _cancelCountdown();
        },
        child: child!,
      ),
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    final mode = layoutModeOf(context);
    if (mode == AppLayoutMode.desktop) {
      if (_immersive) _setImmersive(false);
      return Scaffold(
        backgroundColor: AppColors.video,
        body: Stack(children: [
          Positioned.fill(child: _video(mode)),
          Positioned(
            top: 92,
            right: 28,
            child: ValueListenableBuilder<String>(
              valueListenable: _digits,
              builder: (_, d, _) => d.isEmpty
                  ? const SizedBox.shrink()
                  : PlayerBox(padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14), child: Text(d, style: AppText.display(40))),
            ),
          ),
        ]),
      );
    }

    if (mode == AppLayoutMode.phoneLandscape) {
      return Scaffold(
        backgroundColor: AppColors.video,
        body: _video(mode),
      );
    }

    // Phone Portrait: 16:9 edge-to-edge video below Dynamic Island + rich interactive companion panel below.
    if (_immersive) _setImmersive(false);
    return Scaffold(
      backgroundColor: AppColors.video,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: AspectRatio(aspectRatio: 16 / 9, child: _video(mode)),
          ),
          Expanded(
            child: ValueListenableBuilder<PlayerEntry>(
              valueListenable: _current,
              builder: (_, entry, _) => _PhoneCompanionHost(
                player: _player,
                live: widget.live,
                entry: entry,
                index: _index,
                queue: widget.queue,
                epg: entry.epg == null ? null : _epg,
                coverFit: _fit == BoxFit.cover,
                onSelectQueue: _switchTo,
                onToggleFit: _toggleFit,
                onToggleOrientation: () => _toggleOrientation(false),
                onCancelCountdown: _cancelCountdown,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _video(AppLayoutMode mode) {
    return Video(
      key: _videoKey,
      controller: _controller,
      fit: _fit,
      subtitleViewConfiguration: SubtitleViewConfiguration(
        style: AppText.label(18, color: AppColors.ink).copyWith(
          shadows: const [Shadow(blurRadius: 6, color: Colors.black)],
        ),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      ),
      controls: (state) => ValueListenableBuilder<PlayerEntry>(
        valueListenable: _current,
        builder: (_, entry, _) => _Controls(
          state: state,
          player: _player,
          mode: mode,
          title: entry.title,
          logo: entry.logo,
          group: entry.group,
          index: _index,
          queue: widget.queue,
          live: widget.live,
          error: _error,
          onRetry: _retry,
          epg: entry.epg == null ? null : _epg,
          onPrev: _hasPrev ? _prev : null,
          onNext: _hasNext ? _next : null,
          onSelectQueue: _switchTo,
          queued: widget.queue.length > 1,
          countdown: _countdown,
          nextTitle: _hasNext ? widget.queue[_index + 1].title : null,
          prevTitle: _hasPrev ? widget.queue[_index - 1].title : null,
          onCancelCountdown: _cancelCountdown,
          onDigit: widget.live && widget.queue.length > 1 ? _typeDigit : null,
          coverFit: _fit == BoxFit.cover,
          onToggleFit: _toggleFit,
          onToggleOrientation: () => _toggleOrientation(mode == AppLayoutMode.phoneLandscape),
          onImmersiveChange: _setImmersive,
        ),
      ),
    );
  }
}

String? _digitOf(LogicalKeyboardKey k) {
  const keys = [
    LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
  ];
  const pad = [
    LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
  ];
  final i = keys.contains(k) ? keys.indexOf(k) : pad.indexOf(k);
  return i < 0 ? null : '$i';
}

String _fmt(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// The error message announces an automatic retry (no "Tekrar dene" button then).
bool _isRetrying(String message) => message.contains('Yeniden deneniyor') || message.startsWith('Bağlantı koptu');

String _trackLabel(String id, String? title, String? language) {
  if (id == 'auto') return 'Otomatik';
  if (id == 'no') return 'Kapalı';
  final parts = [if (title != null && title.isNotEmpty) title, if (language != null && language.isNotEmpty) language];
  return parts.isEmpty ? 'Parça $id' : parts.join(' · ');
}

class _Controls extends StatefulWidget {
  const _Controls({
    required this.state,
    required this.player,
    required this.mode,
    required this.title,
    required this.index,
    required this.queue,
    required this.live,
    required this.error,
    required this.onRetry,
    required this.countdown,
    required this.onCancelCountdown,
    required this.coverFit,
    required this.onToggleFit,
    required this.onToggleOrientation,
    required this.onImmersiveChange,
    this.onSelectQueue,
    this.epg,
    this.onPrev,
    this.onNext,
    this.queued = false,
    this.nextTitle,
    this.prevTitle,
    this.logo = '',
    this.group,
    this.onDigit,
  });

  final VideoState state;
  final Player player;
  final AppLayoutMode mode;
  final String title;
  final String logo;
  final String? group;
  final int index; // position in the queue
  final List<PlayerEntry> queue;
  final bool live;
  final ValueNotifier<String?> error;
  final VoidCallback onRetry;
  final Future<List<Programme>>? epg;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<int>? onSelectQueue;
  final bool queued; // more than one channel/episode to move between
  final ValueNotifier<int?> countdown;
  final String? nextTitle;
  final String? prevTitle;
  final void Function(String digit)? onDigit;
  final VoidCallback onCancelCountdown;
  final bool coverFit;
  final VoidCallback onToggleFit;
  final VoidCallback onToggleOrientation;
  final ValueChanged<bool> onImmersiveChange;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _visible = true;
  int _hideToken = 0;
  String? _osd;
  int _osdToken = 0;
  double _lastVolume = 100;
  final FocusNode _root = FocusNode(debugLabel: 'player-root');
  final FocusNode _playNode = FocusNode(debugLabel: 'player-play');
  bool _barFocused = false; // remote focus is on the control bar (TV mode)

  Player get p => widget.player;
  bool get _tv => AppSettings.instance.tvMode;
  bool get _phone => widget.mode != AppLayoutMode.desktop;
  bool get _phoneLandscape => widget.mode == AppLayoutMode.phoneLandscape;
  Duration get _skip => Duration(seconds: AppSettings.instance.skipSecs);

  void _syncImmersive(bool visible) {
    if (_phoneLandscape) {
      widget.onImmersiveChange(!visible);
    } else {
      widget.onImmersiveChange(false);
    }
  }

  void _poke() {
    if (!mounted) return;
    setState(() => _visible = true);
    _syncImmersive(true);
    final token = ++_hideToken;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && token == _hideToken && p.state.playing && !_barFocused) {
        setState(() => _visible = false);
        _syncImmersive(false);
      }
    });
  }

  void _toggleVisible() {
    if (_visible) {
      _hideToken++;
      setState(() => _visible = false);
      _syncImmersive(false);
    } else {
      _poke();
    }
  }

  void _flash(String text) {
    setState(() => _osd = text);
    final token = ++_osdToken;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && token == _osdToken) setState(() => _osd = null);
    });
  }

  @override
  void initState() {
    super.initState();
    _poke();
  }

  @override
  void dispose() {
    _commitTimer?.cancel();
    _pending.dispose();
    _root.dispose();
    _playNode.dispose();
    super.dispose();
  }

  // Remote-friendly seeking: each press moves a pending target (steps grow while the key is held or tapped
  // quickly), the real seek happens once the user pauses.
  final ValueNotifier<Duration?> _pending = ValueNotifier(null);
  Timer? _commitTimer;
  int _scrubStreak = 0;
  DateTime _lastScrub = DateTime.fromMillisecondsSinceEpoch(0);

  void _scrub(int dir) {
    if (widget.live) return;
    final now = DateTime.now();
    _scrubStreak = now.difference(_lastScrub) < const Duration(milliseconds: 900) ? _scrubStreak + 1 : 0;
    _lastScrub = now;
    final ladder = [_skip.inSeconds, _skip.inSeconds, _skip.inSeconds, 30, 30, 60, 60, 120, 120, 300, 300, 600];
    final step = ladder[_scrubStreak.clamp(0, ladder.length - 1)];
    final total = p.state.duration;
    var target = (_pending.value ?? p.state.position) + Duration(seconds: dir * step);
    if (target < Duration.zero) target = Duration.zero;
    if (total > Duration.zero && target > total) target = total;
    _pending.value = target;
    _flash('${_fmt(target)}${total > Duration.zero ? ' / ${_fmt(total)}' : ''}   (${dir > 0 ? '+' : '−'}${step >= 60 ? '${step ~/ 60} dk' : '$step sn'})');
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 700), _commitScrub);
    _poke();
  }

  void _commitScrub() {
    _commitTimer?.cancel();
    final t = _pending.value;
    _pending.value = null;
    if (t != null) p.seek(t);
  }

  void _enterBar() {
    _barFocused = true;
    _poke();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playNode.requestFocus();
    });
  }

  void _leaveBar() {
    _barFocused = false;
    _root.requestFocus();
    _poke();
  }

  Future<void> _goTo() async {
    if (widget.live) return;
    final total = p.state.duration;
    final picked = await showDialog<Duration>(
      context: context,
      builder: (_) => _GoToDialog(initial: p.state.position, total: total),
    );
    if (picked != null) {
      p.seek(picked);
      _flash('→ ${_fmt(picked)}');
    }
    _poke();
  }

  void _seekBy(Duration delta) {
    if (widget.live) return;
    final target = p.state.position + delta;
    p.seek(target < Duration.zero ? Duration.zero : target);
    _flash('${delta.isNegative ? '−' : '+'}${delta.inSeconds.abs()} sn');
  }

  void _setVolume(double v) {
    final vol = v.clamp(0, 100).toDouble();
    p.setVolume(vol);
    _flash('Ses ${vol.round()}%');
  }

  void _toggleMute() {
    if (p.state.volume > 0) {
      _lastVolume = p.state.volume;
      p.setVolume(0);
      _flash('Sessiz');
    } else {
      p.setVolume(_lastVolume == 0 ? 100 : _lastVolume);
      _flash('Ses açık');
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;

    // Media keys (remote controls, keyboards)
    if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.mediaPlay || k == LogicalKeyboardKey.mediaPause) {
      p.playOrPause();
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(_skip * 3);
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-_skip * 3);
      _poke();
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.mediaTrackNext || k == LogicalKeyboardKey.channelUp || k == LogicalKeyboardKey.pageDown) {
      if (widget.onNext == null) return KeyEventResult.ignored;
      widget.onNext!();
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackPrevious || k == LogicalKeyboardKey.channelDown || k == LogicalKeyboardKey.pageUp) {
      if (widget.onPrev == null) return KeyEventResult.ignored;
      widget.onPrev!();
      _poke();
      return KeyEventResult.handled;
    }
    final digit = widget.onDigit == null ? null : _digitOf(k);
    if (digit != null) {
      widget.onDigit!(digit);
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape && widget.countdown.value != null) {
      widget.onCancelCountdown();
      return KeyEventResult.handled;
    }

    final isSelect = k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter;

    // A failed stream: OK is "Tekrar dene" (like the countdown below, its button can't take focus from the video).
    final failure = widget.error.value;
    if (isSelect && failure != null && !_isRetrying(failure) && !_barFocused) {
      widget.onRetry();
      return KeyEventResult.handled;
    }

    // Next-episode countdown: OK starts it right away (the dialog's button can't take focus from the video).
    if (isSelect && widget.countdown.value != null && widget.onNext != null && !_barFocused) {
      widget.onNext!();
      return KeyEventResult.handled;
    }

    // Live TV has nothing to seek: Left/Right change the channel, so a plain D-pad remote (no channel keys) can zap.
    if (widget.live && !_barFocused && (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight)) {
      final go = k == LogicalKeyboardKey.arrowRight ? widget.onNext : widget.onPrev;
      if (go == null) return KeyEventResult.ignored;
      go();
      _poke();
      return KeyEventResult.handled;
    }

    if (_tv) {
      // Bar mode: the arrows move between the buttons, OK presses them, Up goes back to the video.
      if (_barFocused) {
        if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.arrowUp) {
          _leaveBar();
          return KeyEventResult.handled;
        }
        _poke();
        return KeyEventResult.ignored;
      }
      // Video mode: Up/Down open the control bar (it is not built while hidden, so focus it after the next frame).
      if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
        _enterBar();
        return KeyEventResult.handled;
      }
      if (isSelect) {
        if (_pending.value != null) {
          _commitScrub();
        } else {
          p.playOrPause();
        }
        _poke();
        return KeyEventResult.handled;
      }
      // Left/Right fall through to the scrubbing below.
    }

    if (k == LogicalKeyboardKey.space) {
      p.playOrPause();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _scrub(1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _scrub(-1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _setVolume(p.state.volume + 5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _setVolume(p.state.volume - 5);
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (k == LogicalKeyboardKey.keyF) {
      widget.state.toggleFullscreen();
    } else if (k == LogicalKeyboardKey.escape) {
      // (Android's Back key is handled by the system; handling it here as well popped several routes at once.)
      if (widget.state.isFullscreen()) {
        widget.state.exitFullscreen();
      } else {
        Navigator.of(context).maybePop();
      }
    } else {
      return KeyEventResult.ignored;
    }
    _poke();
    return KeyEventResult.handled;
  }

  Future<void> _pick<T>(String title, List<T> options, T current, String Function(T) label, void Function(T) set) async {
    if (_phone) {
      final choice = await showAppSheet<T>(
        context: context,
        title: title,
        builder: (ctx) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final t in options)
              SheetOptionTile(
                label: label(t),
                selected: t == current,
                onTap: () => Navigator.of(ctx).pop(t),
              ),
          ],
        ),
      );
      if (choice != null) set(choice);
      _poke();
      return;
    }
    final choice = await showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final t in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Row(children: [
                SizedBox(width: 30, child: t == current ? const Icon(Icons.check_rounded, size: 20, color: AppColors.accent) : null),
                Expanded(child: Text(label(t), style: AppText.label(15, color: t == current ? AppColors.accentInk : AppColors.ink))),
              ]),
            ),
        ],
      ),
    );
    if (choice != null) set(choice);
  }

  Future<void> _openQueueSheet() async {
    if (widget.onSelectQueue == null) return;
    await showAppSheet<void>(
      context: context,
      title: widget.live ? 'Kanallar' : 'Bölümler',
      subtitle: '${widget.queue.length} öğe',
      builder: (ctx) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.queue.length,
        itemBuilder: (_, i) {
          final e = widget.queue[i];
          final title = widget.live ? '${i + 1}. ${e.title}' : playerTitle(e.title).$1;
          final sub = widget.live ? e.group : episodeLabel(e.title);
          return SheetOptionTile(
            label: title,
            subtitle: sub,
            selected: i == widget.index,
            onTap: () {
              widget.onSelectQueue!(i);
              Navigator.of(ctx).pop();
            },
          );
        },
      ),
    );
    _poke();
  }

  void _onPhoneDoubleTap(TapDownDetails details, double width) {
    if (widget.live) {
      if (details.localPosition.dx < width * 0.45 && widget.onPrev != null) {
        AppHaptics.light(context);
        widget.onPrev!();
      } else if (details.localPosition.dx > width * 0.55 && widget.onNext != null) {
        AppHaptics.light(context);
        widget.onNext!();
      }
      return;
    }
    if (details.localPosition.dx < width * 0.45) {
      AppHaptics.light(context);
      _seekBy(-_skip);
    } else if (details.localPosition.dx > width * 0.55) {
      AppHaptics.light(context);
      _seekBy(_skip);
    } else {
      AppHaptics.light(context);
      p.playOrPause();
      _poke();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phone) return _buildPhoneControls(context);
    return Focus(
      focusNode: _root,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        onHover: (_) => _poke(),
        cursor: _visible ? MouseCursor.defer : SystemMouseCursors.none,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            p.playOrPause();
            _poke();
          },
          onDoubleTap: () => widget.state.toggleFullscreen(),
          child: Stack(children: [
            // buffering indicator
            Center(
              child: StreamBuilder<bool>(
                stream: p.stream.buffering,
                builder: (_, s) => (s.data ?? false)
                    ? Container(
                        width: 64,
                        height: 64,
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, boxShadow: AppShadows.overlay),
                        child: const CircularProgressIndicator(strokeWidth: 3),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: widget.error,
              builder: (_, msg, _) {
                if (msg == null) return const SizedBox.shrink();
                final retrying = _isRetrying(msg);
                return Center(
                  child: PlayerBox(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(msg, textAlign: TextAlign.center, style: AppText.label(15)),
                      if (!retrying) ...[
                        const SizedBox(height: 18),
                        AppButton(label: 'Tekrar dene', variant: AppButtonVariant.primary, autofocus: true, onPressed: widget.onRetry),
                      ],
                    ]),
                  ),
                );
              },
            ),
            if (_osd != null)
              Positioned(
                top: 92,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), boxShadow: AppShadows.overlay),
                    child: Text(_osd!, style: AppText.label(15).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ),
              ),
            // Not built at all while hidden, so position/volume streams don't rebuild an invisible UI.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _visible ? KeyedSubtree(key: const ValueKey('chrome'), child: _chrome(context)) : const SizedBox.expand(key: ValueKey('hidden')),
            ),
            ValueListenableBuilder<int?>(
              valueListenable: widget.countdown,
              builder: (_, left, _) {
                if (left == null) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 92, 28, 220),
                    child: PlayerBox(
                      maxWidth: 380,
                      padding: const EdgeInsets.all(22),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Sıradaki bölüm $left sn içinde başlıyor', style: AppText.title(15)),
                        if (widget.nextTitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(widget.nextTitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.meta(14)),
                          ),
                        const SizedBox(height: 14),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          AppButton(label: 'Şimdi oynat', variant: AppButtonVariant.primary, autofocus: true, onPressed: widget.onNext),
                          const SizedBox(width: 10),
                          AppButton(label: 'İptal', onPressed: widget.onCancelCountdown),
                        ]),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildPhoneControls(BuildContext context) {
    final (title, sub) = widget.live ? (widget.title, widget.group) : playerTitle(widget.title);
    TapDownDetails? lastDoubleTap;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleVisible,
        onDoubleTapDown: (d) => lastDoubleTap = d,
        onDoubleTap: () {
          if (lastDoubleTap != null) _onPhoneDoubleTap(lastDoubleTap!, constraints.maxWidth);
        },
        child: Stack(
          children: [
            // Buffering indicator
            Center(
              child: StreamBuilder<bool>(
                stream: p.stream.buffering,
                builder: (_, s) => (s.data ?? false)
                    ? Container(
                        width: 52,
                        height: 52,
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(color: AppColors.videoGlass, shape: BoxShape.circle),
                        child: const CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            // Error card
            ValueListenableBuilder<String?>(
              valueListenable: widget.error,
              builder: (_, msg, _) {
                if (msg == null) return const SizedBox.shrink();
                final retrying = _isRetrying(msg);
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: PlayerBox(
                      maxWidth: 360,
                      padding: const EdgeInsets.all(18),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(msg, textAlign: TextAlign.center, style: AppText.label(14)),
                        if (!retrying) ...[
                          const SizedBox(height: 14),
                          AppButton(label: 'Tekrar dene', variant: AppButtonVariant.primary, onPressed: widget.onRetry),
                        ],
                      ]),
                    ),
                  ),
                );
              },
            ),
            // OSD badge (seek feedback, speed, etc.)
            if (_osd != null)
              Positioned(
                top: _phoneLandscape ? 64 : 14,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.videoGlass,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Text(_osd!, style: AppText.label(13.5).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ),
              ),
            // Animated glass overlay
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _visible
                  ? KeyedSubtree(
                      key: const ValueKey('phone-chrome'),
                      child: StreamBuilder<bool>(
                        stream: p.stream.playing,
                        builder: (_, playingSnap) => StreamBuilder<Duration>(
                          stream: p.stream.position,
                          builder: (_, posSnap) => StreamBuilder<Duration>(
                            stream: p.stream.duration,
                            builder: (_, durSnap) => StreamBuilder<Duration>(
                              stream: p.stream.buffer,
                              builder: (_, bufSnap) => StreamBuilder<Tracks>(
                                stream: p.stream.tracks,
                                builder: (_, _) => StreamBuilder<double>(
                                  stream: p.stream.rate,
                                  builder: (_, rateSnap) => FutureBuilder<List<Programme>>(
                                    future: widget.epg,
                                    builder: (_, epgSnap) {
                                      final t = p.state.tracks;
                                      final cur = p.state.track;
                                      final rate = rateSnap.data ?? p.state.rate;
                                      String short(String s) => s.length <= 10 ? s : '${s.substring(0, 9)}…';
                                      final audioLbl = short(_trackLabel(cur.audio.id, cur.audio.title, cur.audio.language));
                                      final subLbl = cur.subtitle.id == 'no'
                                          ? 'Altyazı'
                                          : short(_trackLabel(cur.subtitle.id, cur.subtitle.title, cur.subtitle.language));
                                      return PhonePlayerOverlay(
                                        landscape: _phoneLandscape,
                                        live: widget.live,
                                        playing: playingSnap.data ?? p.state.playing,
                                        title: title,
                                        subtitle: sub,
                                        onBack: () => Navigator.of(context).maybePop(),
                                        onPlayPause: () {
                                          p.playOrPause();
                                          _poke();
                                        },
                                        onToggleOrientation: widget.onToggleOrientation,
                                        onToggleFit: () {
                                          widget.onToggleFit();
                                          _flash(widget.coverFit ? 'Ekrana sığdırıldı' : 'Ekranı doldur');
                                        },
                                        coverFit: widget.coverFit,
                                        skipSecs: _skip.inSeconds,
                                        onSeekBack: widget.live ? null : () => _seekBy(-_skip),
                                        onSeekForward: widget.live ? null : () => _seekBy(_skip),
                                        onPrev: widget.onPrev,
                                        onNext: widget.onNext,
                                        queued: widget.queued,
                                        position: _pending.value ?? posSnap.data ?? p.state.position,
                                        duration: durSnap.data ?? p.state.duration,
                                        buffer: bufSnap.data ?? p.state.buffer,
                                        pending: _pending.value != null,
                                        onSeek: (d) {
                                          p.seek(d);
                                          _poke();
                                        },
                                        audioLabel: audioLbl,
                                        subtitleLabel: subLbl,
                                        rateLabel: rate == 1.0 ? '1x' : '${rate}x',
                                        onPickAudio: () => _pick<AudioTrack>('Ses', t.audio, cur.audio, (a) => _trackLabel(a.id, a.title, a.language), p.setAudioTrack),
                                        onPickSubtitle: () => _pick<SubtitleTrack>('Altyazı', t.subtitle, cur.subtitle, (s) => _trackLabel(s.id, s.title, s.language), p.setSubtitleTrack),
                                        onPickRate: widget.live
                                            ? null
                                            : () => _pick<double>('Oynatma hızı', const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0], rate, (v) => v == 1.0 ? 'Normal' : '${v}x', p.setRate),
                                        onGoTo: widget.live ? null : _goTo,
                                        onOpenQueue: widget.queued ? _openQueueSheet : null,
                                        liveChannelIndex: widget.index,
                                        liveChannelName: widget.title,
                                        liveChannelLogo: widget.logo,
                                        programmes: epgSnap.data ?? const [],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.expand(key: ValueKey('phone-hidden')),
            ),
            // Next-episode countdown card
            ValueListenableBuilder<int?>(
              valueListenable: widget.countdown,
              builder: (_, left, _) {
                if (left == null) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, _phoneLandscape ? 64 : 14, _phoneLandscape ? 72 : 14),
                    child: PlayerBox(
                      maxWidth: 310,
                      padding: const EdgeInsets.all(14),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Sıradaki bölüm $left sn içinde başlıyor', style: AppText.title(14)),
                        if (widget.nextTitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(widget.nextTitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12.5)),
                          ),
                        const SizedBox(height: 10),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          AppButton(label: 'Şimdi oynat', height: 36, dense: true, variant: AppButtonVariant.primary, onPressed: widget.onNext),
                          const SizedBox(width: 8),
                          AppButton(label: 'İptal', height: 36, dense: true, onPressed: widget.onCancelCountdown),
                        ]),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Floating parts over the video: title pill, clock, and the white control card.
  Widget _chrome(BuildContext context) {
    final (title, sub) = widget.live ? ('Canlı TV', widget.group) : playerTitle(widget.title);
    return Stack(children: [
      Positioned(
        left: 28,
        top: 24,
        right: 160,
        child: Align(
          alignment: Alignment.centerLeft,
          child: PlayerTitlePill(onBack: () => Navigator.of(context).maybePop(), title: title, subtitle: sub),
        ),
      ),
      const Positioned(right: 28, top: 30, child: ClockPill()),
      Positioned(
        left: 28,
        right: 28,
        bottom: 24,
        child: PlayerCard(children: [
          if (widget.live)
            FutureBuilder<List<Programme>>(
              future: widget.epg,
              builder: (_, snap) => LiveInfo(
                index: widget.index,
                name: widget.title,
                logo: widget.logo,
                programmes: snap.data ?? const [],
                prevName: widget.prevTitle,
                nextName: widget.nextTitle,
              ),
            )
          else
            ExcludeFocus(excluding: _tv, child: _seekBar()),
          if (widget.live) const Padding(padding: EdgeInsets.only(top: 14), child: Divider(height: 1, thickness: 1, color: AppColors.line)),
          const SizedBox(height: 14),
          FocusScope(onFocusChange: (focused) => _barFocused = focused && _tv, child: _keys()),
        ]),
      ),
    ]);
  }

  /// The key row: sound on the left, playback in the middle, options on the right.
  Widget _keys() {
    Widget side(Alignment a, List<Widget> children) => Expanded(
          child: Align(
            alignment: a,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: a,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 8), children[i]],
              ]),
            ),
          ),
        );

    final sound = StreamBuilder<double>(
      stream: p.stream.volume,
      builder: (_, s) {
        final v = s.data ?? p.state.volume;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          AppButton(icon: v == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, tooltip: v == 0 ? 'Sesi aç' : 'Sessiz', onPressed: _toggleMute),
          // A slider eats the left/right keys, which would trap the remote's focus here. The TV has its own volume.
          if (!_tv) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: AppColors.ink,
                  inactiveTrackColor: AppColors.line,
                  thumbShape: SliderComponentShape.noThumb,
                  overlayShape: SliderComponentShape.noOverlay,
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(value: v.clamp(0, 100).toDouble(), max: 100, onChanged: p.setVolume),
              ),
            ),
          ],
        ]);
      },
    );

    final play = StreamBuilder<bool>(
      stream: p.stream.playing,
      builder: (_, s) => AppButton(
        focusNode: _playNode,
        variant: AppButtonVariant.primary,
        height: 60,
        icon: (s.data ?? p.state.playing) ? Icons.pause_rounded : Icons.play_arrow_rounded,
        tooltip: (s.data ?? p.state.playing) ? 'Duraklat' : 'Oynat',
        onPressed: p.playOrPause,
      ),
    );

    final tracks = StreamBuilder<Tracks>(
      stream: p.stream.tracks,
      builder: (_, _) {
        final t = p.state.tracks;
        final cur = p.state.track;
        String short(String s) => s.length <= 14 ? s : '${s.substring(0, 13)}…';
        final sub = cur.subtitle.id == 'no' ? 'Altyazı kapalı' : short(_trackLabel(cur.subtitle.id, cur.subtitle.title, cur.subtitle.language));
        return Row(mainAxisSize: MainAxisSize.min, children: [
          AppButton(
            label: short(_trackLabel(cur.audio.id, cur.audio.title, cur.audio.language)),
            tooltip: 'Ses parçası',
            onPressed: () => _pick<AudioTrack>('Ses', t.audio, cur.audio, (a) => _trackLabel(a.id, a.title, a.language), p.setAudioTrack),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: sub,
            tooltip: 'Altyazı',
            onPressed: () => _pick<SubtitleTrack>('Altyazı', t.subtitle, cur.subtitle, (s) => _trackLabel(s.id, s.title, s.language), p.setSubtitleTrack),
          ),
        ]);
      },
    );
    final fullscreen = AppButton(icon: Icons.fullscreen_rounded, tooltip: 'Tam ekran', onPressed: () => widget.state.toggleFullscreen());

    if (widget.live) {
      return Row(children: [
        side(Alignment.centerLeft, [sound]),
        const SizedBox(width: 16),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.queued) ...[
            AppButton(icon: Icons.skip_previous_rounded, label: 'Önceki kanal', height: 48, onPressed: widget.onPrev),
            const SizedBox(width: 10),
          ],
          play,
          if (widget.queued) ...[
            const SizedBox(width: 10),
            AppButton(trailingIcon: Icons.skip_next_rounded, label: 'Sonraki kanal', height: 48, onPressed: widget.onNext),
          ],
        ]),
        const SizedBox(width: 16),
        side(Alignment.centerRight, [tracks, fullscreen]),
      ]);
    }

    final secs = _skip.inSeconds;
    return Row(children: [
      side(Alignment.centerLeft, [sound, AppButton(icon: Icons.schedule_rounded, label: 'Zamana git', onPressed: _goTo)]),
      const SizedBox(width: 16),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (widget.queued) ...[AppButton(icon: Icons.skip_previous_rounded, tooltip: 'Önceki bölüm', onPressed: widget.onPrev), const SizedBox(width: 8)],
        AppButton(label: '-$secs', width: 56, tooltip: '$secs sn geri', onPressed: () => _seekBy(-_skip)),
        const SizedBox(width: 10),
        play,
        const SizedBox(width: 10),
        AppButton(label: '+$secs', width: 56, tooltip: '$secs sn ileri', onPressed: () => _seekBy(_skip)),
        if (widget.queued) ...[const SizedBox(width: 8), AppButton(icon: Icons.skip_next_rounded, tooltip: 'Sonraki bölüm', onPressed: widget.onNext)],
      ]),
      const SizedBox(width: 16),
      side(Alignment.centerRight, [
        if (widget.queued)
          ListenableBuilder(
            listenable: AppSettings.instance,
            builder: (_, _) {
              final on = AppSettings.instance.autoNext;
              return AppButton(
                tooltip: 'Sonraki bölümü otomatik oynat: ${on ? 'açık' : 'kapalı'}',
                onPressed: () {
                  AppSettings.instance.update(autoNext: !on);
                  if (on) widget.onCancelCountdown();
                  _flash('Otomatik sonraki bölüm: ${on ? 'kapalı' : 'açık'}');
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Otomatik sonraki'),
                  const SizedBox(width: 10),
                  AppSwitch(value: on, small: true, focusable: false, onChanged: null),
                ]),
              );
            },
          ),
        StreamBuilder<double>(
          stream: p.stream.rate,
          builder: (_, s) {
            final r = s.data ?? p.state.rate;
            return AppButton(
              label: r == 1.0 ? '1x' : '${r}x',
              tooltip: 'Oynatma hızı',
              onPressed: () => _pick<double>('Oynatma hızı', const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0], r, (v) => v == 1.0 ? 'Normal' : '${v}x', p.setRate),
            );
          },
        ),
        tracks,
        fullscreen,
      ]),
    ]);
  }

  Widget _seekBar() {
    return StreamBuilder<Duration>(
      stream: p.stream.position,
      builder: (_, pos) => StreamBuilder<Duration>(
        stream: p.stream.duration,
        builder: (_, dur) => StreamBuilder<Duration>(
          stream: p.stream.buffer,
          builder: (_, buf) => ValueListenableBuilder<Duration?>(
            valueListenable: _pending,
            builder: (_, pending, _) => VodTimeline(
              position: pending ?? pos.data ?? p.state.position,
              duration: dur.data ?? p.state.duration,
              buffer: buf.data ?? p.state.buffer,
              pending: pending != null,
              onSeek: p.seek,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Go to time" picker that works with a TV remote: ↑/↓ change the focused unit, ←/→ switch unit, OK confirms.
class _GoToDialog extends StatefulWidget {
  const _GoToDialog({required this.initial, required this.total});

  final Duration initial;
  final Duration total;

  @override
  State<_GoToDialog> createState() => _GoToDialogState();
}

class _GoToDialogState extends State<_GoToDialog> {
  late int _h = widget.initial.inHours;
  late int _m = widget.initial.inMinutes % 60;
  late int _s = widget.initial.inSeconds % 60;

  Duration get _value {
    final d = Duration(hours: _h, minutes: _m, seconds: _s);
    return widget.total > Duration.zero && d > widget.total ? widget.total : d;
  }

  Widget _unit(String label, int value, int max, void Function(int) set, {bool autofocus = false}) {
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (node, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.arrowUp) {
          setState(() => set(value >= max ? 0 : value + 1));
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown) {
          setState(() => set(value <= 0 ? max : value - 1));
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
          Navigator.pop(context, _value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        final compact = isPhoneLayout(context);
        return Container(
          width: compact ? 74 : 96,
          padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? AppSizes.itemRadius : AppSizes.tileRadius),
            border: Border.all(color: focused ? AppColors.ink : AppColors.line, width: focused ? AppSizes.ring : 1),
            color: focused ? AppColors.accentSoft : AppColors.surfaceAlt,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () => setState(() => set(value >= max ? 0 : value + 1)),
              child: const SizedBox(width: 44, height: 34, child: Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.ink2)),
            ),
            Text(value.toString().padLeft(2, '0'), style: AppText.display(compact ? 26 : 34).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            GestureDetector(
              onTap: () => setState(() => set(value <= 0 ? max : value - 1)),
              child: const SizedBox(width: 44, height: 34, child: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.ink2)),
            ),
            Text(label, style: AppText.meta(12)),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    final maxH = total > Duration.zero ? total.inHours : 99;
    return AlertDialog(
      title: const Text('Zamana git'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          _unit('saat', _h, maxH, (v) => _h = v),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: AppText.display(30))),
          _unit('dakika', _m, 59, (v) => _m = v, autofocus: true),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: AppText.display(30))),
          _unit('saniye', _s, 59, (v) => _s = v),
        ]),
        const SizedBox(height: 12),
        if (total > Duration.zero) Text('Toplam süre: ${_fmt(total)}', style: AppText.meta(13)),
        const SizedBox(height: 4),
        Text('↑↓ değiştir · ←→ alan seç · OK git', style: AppText.meta(13)),
      ]),
      actions: [
        AppButton(label: 'İptal', onPressed: () => Navigator.pop(context)),
        AppButton(label: 'Git', variant: AppButtonVariant.primary, onPressed: () => Navigator.pop(context, _value)),
      ],
    );
  }
}

/// Hosts [PhonePlayerCompanion] beneath the 16:9 video in iPhone portrait mode, wired to live mpv streams.
class _PhoneCompanionHost extends StatelessWidget {
  const _PhoneCompanionHost({
    required this.player,
    required this.live,
    required this.entry,
    required this.index,
    required this.queue,
    required this.epg,
    required this.coverFit,
    required this.onSelectQueue,
    required this.onToggleFit,
    required this.onToggleOrientation,
    required this.onCancelCountdown,
  });

  final Player player;
  final bool live;
  final PlayerEntry entry;
  final int index;
  final List<PlayerEntry> queue;
  final Future<List<Programme>>? epg;
  final bool coverFit;
  final ValueChanged<int> onSelectQueue;
  final VoidCallback onToggleFit;
  final VoidCallback onToggleOrientation;
  final VoidCallback onCancelCountdown;

  Future<void> _pickSheet<T>(BuildContext context, String title, List<T> options, T current, String Function(T) label, void Function(T) set) async {
    final choice = await showAppSheet<T>(
      context: context,
      title: title,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final t in options)
            SheetOptionTile(
              label: label(t),
              selected: t == current,
              onTap: () => Navigator.of(ctx).pop(t),
            ),
        ],
      ),
    );
    if (choice != null) set(choice);
  }

  Future<void> _goTo(BuildContext context) async {
    final picked = await showDialog<Duration>(
      context: context,
      builder: (_) => _GoToDialog(initial: player.state.position, total: player.state.duration),
    );
    if (picked != null) player.seek(picked);
  }

  @override
  Widget build(BuildContext context) {
    final (title, sub) = live ? (entry.title, entry.group) : playerTitle(entry.title);
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => StreamBuilder<Tracks>(
        stream: player.stream.tracks,
        builder: (_, _) => StreamBuilder<double>(
          stream: player.stream.rate,
          builder: (_, rateSnap) => FutureBuilder<List<Programme>>(
            future: epg,
            builder: (_, epgSnap) {
              final t = player.state.tracks;
              final cur = player.state.track;
              final rate = rateSnap.data ?? player.state.rate;
              String short(String s) => s.length <= 12 ? s : '${s.substring(0, 11)}…';
              final audioLabel = short(_trackLabel(cur.audio.id, cur.audio.title, cur.audio.language));
              final subLabel = cur.subtitle.id == 'no' ? 'Altyazı: Kapalı' : short(_trackLabel(cur.subtitle.id, cur.subtitle.title, cur.subtitle.language));
              final autoNext = AppSettings.instance.autoNext;
              return PhonePlayerCompanion(
                live: live,
                title: title,
                subtitle: sub,
                logo: entry.logo,
                index: index,
                programmes: epgSnap.data ?? const [],
                queueTitles: [for (final q in queue) q.title],
                queueLogos: [for (final q in queue) q.logo],
                onSelectQueue: queue.length > 1 ? onSelectQueue : null,
                audioLabel: audioLabel,
                subtitleLabel: subLabel,
                rateLabel: rate == 1.0 ? '1x' : '${rate}x',
                coverFit: coverFit,
                onPickAudio: () => _pickSheet<AudioTrack>(context, 'Ses parçası', t.audio, cur.audio, (a) => _trackLabel(a.id, a.title, a.language), player.setAudioTrack),
                onPickSubtitle: () => _pickSheet<SubtitleTrack>(context, 'Altyazı', t.subtitle, cur.subtitle, (s) => _trackLabel(s.id, s.title, s.language), player.setSubtitleTrack),
                onPickRate: live
                    ? null
                    : () => _pickSheet<double>(context, 'Oynatma hızı', const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0], rate, (v) => v == 1.0 ? 'Normal' : '${v}x', player.setRate),
                onGoTo: live ? null : () => _goTo(context),
                onToggleOrientation: onToggleOrientation,
                onToggleFit: onToggleFit,
                autoNext: !live && queue.length > 1 ? autoNext : null,
                onToggleAutoNext: !live && queue.length > 1
                    ? () {
                        AppSettings.instance.update(autoNext: !autoNext);
                        if (autoNext) onCancelCountdown();
                      }
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}
