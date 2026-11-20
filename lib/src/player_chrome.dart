import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'player_comfort.dart';
import 'settings.dart';
import 'title_utils.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/focus_ring.dart';
import 'ui/format.dart';
import 'ui/layout.dart';
import 'ui/liquid_glass.dart';
import 'ui/shell.dart';
import 'ui/tokens.dart';
import 'xtream.dart';

/// Player title and the line under it: "Breaking Bad S01E03" → ("Breaking Bad", "1. sezon 3. bölüm").
(String, String?) playerTitle(String raw) {
  final season = episodeLabel(raw);
  final clean = raw.replaceAll(RegExp(r'\s*S\d+\s*E\d+', caseSensitive: false), '').trim();
  return (parseTitle(clean).title, season);
}

/// White pill in the top left corner: back key, title, a line under it.
class PlayerTitlePill extends StatelessWidget {
  const PlayerTitlePill({super.key, required this.onBack, required this.title, this.subtitle, this.onTitleTap});

  final VoidCallback onBack;
  final String title;
  final String? subtitle;

  /// Optional tap action on the title/subtitle area (used for series to jump to the series detail page).
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    final labels = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(16))),
      if (subtitle != null) ...[
        const SizedBox(width: 12),
        Flexible(child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(14))),
      ],
      if (onTitleTap != null) ...[
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink2),
      ],
    ]);

    return Container(
      height: 56,
      padding: EdgeInsets.fromLTRB(6, 0, onTitleTap != null ? 10 : 20, 0),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(28), boxShadow: AppShadows.overlay),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppButton(icon: Icons.chevron_left_rounded, tooltip: 'Geri', onPressed: onBack),
        SizedBox(width: onTitleTap != null ? 4 : 12),
        Flexible(
          child: onTitleTap == null
              ? labels
              : FocusRing(
                  key: const ValueKey('player-title-link'),
                  radius: 20,
                  lift: false,
                  hoverColor: AppColors.surfaceAlt,
                  tooltip: 'Dizi sayfasına git',
                  semanticLabel: '$title, dizi sayfasına git',
                  onTap: onTitleTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: labels,
                  ),
                ),
        ),
      ]),
    );
  }
}

/// The floating white card that holds the player's controls.
class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppSizes.panelRadius), boxShadow: AppShadows.overlay),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// White card used for the player's messages (error, next episode, typed channel number).
class PlayerBox extends StatelessWidget {
  const PlayerBox({super.key, required this.child, this.maxWidth = 460, this.padding = const EdgeInsets.all(24)});

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: padding,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppSizes.panelRadius), boxShadow: AppShadows.overlay),
        child: child,
      );
}

/// Precision gear active while touch-scrubbing [VodTimeline].
enum ScrubPrecision {
  normal,
  half,
  quarter,
  fine,
}

/// Computes how many seconds of media one horizontal logical pixel of drag
/// moves during touch precision scrubbing.
///
/// Slow drags move smoothly at ~1 second per 3 pt even on 2+ hour movies;
/// faster swipes accelerate up to the full track scale so long jumps stay
/// effortless, and sliding vertically away from the bar locks finer gears
/// (Apple AVPlayerViewController style).
(double secondsPerPt, ScrubPrecision precision) scrubRateFor({
  required double durationSeconds,
  required double trackWidth,
  required double speedPxPerSec,
  required double verticalOffsetPx,
}) {
  final linear = durationSeconds / math.max(trackWidth, 1.0);
  if (linear <= 0) return (0, ScrubPrecision.normal);

  final absDy = verticalOffsetPx.abs();
  if (absDy >= 85) {
    return (math.min(linear, 0.15), ScrubPrecision.fine);
  }
  if (absDy >= 48) {
    return (math.min(linear * 0.12, 0.45), ScrubPrecision.quarter);
  }
  if (absDy >= 24) {
    return (math.min(linear * 0.30, 1.5), ScrubPrecision.half);
  }

  final fineRate = math.min(linear, 0.35);
  final midRate = math.max(fineRate, math.min(linear * 0.35, 3.5));
  final fastRate = math.max(midRate, linear * 1.1);
  final v = speedPxPerSec.abs();

  if (v <= 55) return (fineRate, ScrubPrecision.normal);
  if (v <= 220) {
    final t = (v - 55) / (220 - 55);
    return (fineRate + (midRate - fineRate) * t * t, ScrubPrecision.normal);
  }
  final t = ((v - 220) / (520 - 220)).clamp(0.0, 1.0);
  return (midRate + (fastRate - midRate) * t, ScrubPrecision.normal);
}

String? scrubPrecisionLabel(ScrubPrecision precision) => switch (precision) {
      ScrubPrecision.normal => null,
      ScrubPrecision.half => 'Yarım hız',
      ScrubPrecision.quarter => 'Çeyrek hız',
      ScrubPrecision.fine => 'Hassas · 1 sn',
    };

/// Elapsed time, position bar (buffered part lighter) and time left.
///
/// When [precisionScrub] is true (phone touch controls), horizontal dragging
/// scrubs relatively from the current position with second-by-second slow
/// precision and vertical fine gears instead of snapping abruptly on touch.
/// The final position is committed once on release via [onScrubEnd] / [onSeek].
class VodTimeline extends StatefulWidget {
  const VodTimeline({
    super.key,
    required this.position,
    required this.duration,
    this.buffer = Duration.zero,
    this.pending = false,
    this.precisionScrub = false,
    this.onSeek,
    this.onScrubStart,
    this.onScrubUpdate,
    this.onScrubEnd,
    this.onScrubCancel,
    this.onInteract,
  });

  final Duration position;
  final Duration duration;
  final Duration buffer;

  /// The position is a target being chosen with the remote, not the playing one.
  final bool pending;

  /// Enables relative velocity-adaptive second-by-second touch scrubbing.
  final bool precisionScrub;

  /// Called when a seek target is committed (or immediately on click in desktop mode).
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onScrubStart;
  final void Function(Duration target, Duration delta, ScrubPrecision precision)? onScrubUpdate;
  final ValueChanged<Duration>? onScrubEnd;
  final VoidCallback? onScrubCancel;
  final VoidCallback? onInteract;

  @override
  State<VodTimeline> createState() => _VodTimelineState();
}

class _VodTimelineState extends State<VodTimeline> {
  bool _dragging = false;
  double _scrubSeconds = 0;
  double _startSeconds = 0;
  double _startY = 0;
  double _emaSpeed = 0;
  Duration? _lastStamp;
  ScrubPrecision _precision = ScrubPrecision.normal;

  bool get _known => widget.duration > Duration.zero;
  bool get _enabled => _known && (widget.onSeek != null || widget.onScrubEnd != null);

  Duration get _shownPosition {
    if (!_known) return widget.position;
    if (_dragging) {
      final clamped = _scrubSeconds.clamp(0.0, widget.duration.inSeconds.toDouble());
      return Duration(seconds: clamped.round());
    }
    final ms = widget.position.inMilliseconds.clamp(0, widget.duration.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  double _fractionForDx(double dx, double width) {
    if (width <= 0) return 0;
    return (dx / width).clamp(0.0, 1.0);
  }

  void _beginDrag(DragStartDetails details, double trackWidth) {
    if (!_enabled) return;
    final durSec = widget.duration.inMilliseconds / 1000.0;
    final curSec = (widget.position.inMilliseconds / 1000.0).clamp(0.0, durSec);
    final initial = widget.precisionScrub ? curSec : _fractionForDx(details.localPosition.dx, trackWidth) * durSec;
    setState(() {
      _dragging = true;
      _startSeconds = curSec;
      _scrubSeconds = initial;
      _startY = details.globalPosition.dy;
      _emaSpeed = 0;
      _lastStamp = details.sourceTimeStamp;
      _precision = ScrubPrecision.normal;
    });
    AppHaptics.selection(context);
    widget.onScrubStart?.call();
    _emitUpdate();
  }

  void _updateDrag(DragUpdateDetails details, double trackWidth) {
    if (!_dragging || !_known) return;
    final durSec = widget.duration.inMilliseconds / 1000.0;
    if (widget.precisionScrub) {
      final dx = details.delta.dx;
      final stamp = details.sourceTimeStamp;
      var dt = 0.016;
      if (stamp != null && _lastStamp != null) {
        final diff = (stamp - _lastStamp!).inMicroseconds / 1000000.0;
        if (diff > 0) dt = diff.clamp(0.008, 0.08);
      }
      _lastStamp = stamp;
      final instantSpeed = dx.abs() / dt;
      _emaSpeed = _emaSpeed * 0.65 + instantSpeed * 0.35;
      final dy = (details.globalPosition.dy - _startY).abs();
      final (rate, gear) = scrubRateFor(
        durationSeconds: durSec,
        trackWidth: trackWidth,
        speedPxPerSec: _emaSpeed,
        verticalOffsetPx: dy,
      );
      if (gear != _precision) {
        AppHaptics.selection(context);
      }
      setState(() {
        _precision = gear;
        _scrubSeconds = (_scrubSeconds + dx * rate).clamp(0.0, durSec);
      });
    } else {
      final next = _fractionForDx(details.localPosition.dx, trackWidth) * durSec;
      setState(() => _scrubSeconds = next);
    }
    _emitUpdate();
  }

  void _endDrag() {
    if (!_dragging) return;
    final target = _shownPosition;
    setState(() {
      _dragging = false;
      _precision = ScrubPrecision.normal;
    });
    if (widget.onScrubEnd != null) {
      widget.onScrubEnd!(target);
    } else {
      widget.onSeek?.call(target);
    }
  }

  void _cancelDrag() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _precision = ScrubPrecision.normal;
    });
    widget.onScrubCancel?.call();
  }

  void _handleTapUp(TapUpDetails details, double trackWidth) {
    widget.onInteract?.call();
    if (!_enabled) return;
    // In touch precision mode, single taps on the timeline do not snap abruptly
    // across minutes (matching native iOS AVPlayerViewController).
    if (widget.precisionScrub) return;
    final target = Duration(milliseconds: (_fractionForDx(details.localPosition.dx, trackWidth) * widget.duration.inMilliseconds).round());
    if (widget.onScrubEnd != null) {
      widget.onScrubEnd!(target);
    } else {
      widget.onSeek?.call(target);
    }
  }

  void _emitUpdate() {
    final target = _shownPosition;
    final delta = Duration(seconds: (target.inSeconds - _startSeconds.round()));
    widget.onScrubUpdate?.call(target, delta, _precision);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shownPosition;
    final active = _dragging || widget.pending;
    final fraction = _known
        ? (shown.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final bufferedFraction = _known
        ? (widget.buffer.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = _known ? widget.duration - shown : Duration.zero;
    final safeRemaining = remaining.isNegative ? Duration.zero : remaining;

    return Row(children: [
      Text(
        clockTime(shown),
        style: AppText.label(13.5, color: active ? AppColors.accentInk : AppColors.ink)
            .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            Widget track = GestureDetector(
              key: const ValueKey('vod-timeline-track'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => widget.onInteract?.call(),
              onTapUp: _enabled ? (d) => _handleTapUp(d, trackWidth) : null,
              onHorizontalDragStart: _enabled ? (d) => _beginDrag(d, trackWidth) : null,
              onHorizontalDragUpdate: _enabled ? (d) => _updateDrag(d, trackWidth) : null,
              onHorizontalDragEnd: _enabled ? (_) => _endDrag() : null,
              onHorizontalDragCancel: _enabled ? _cancelDrag : null,
              child: SizedBox(
                height: 36,
                child: CustomPaint(
                  painter: _TimelineTrackPainter(
                    value: fraction,
                    buffered: bufferedFraction,
                    enabled: _enabled,
                    dragging: _dragging,
                  ),
                  size: Size(trackWidth, 36),
                ),
              ),
            );
            if (widget.precisionScrub) {
              // Lower touch slop so tiny 5-15 pt thumb nudges scrub smoothly by seconds
              // instead of getting swallowed by Flutter's default 18 pt dead zone.
              track = MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  gestureSettings: const DeviceGestureSettings(touchSlop: 4.0),
                ),
                child: track,
              );
            }
            return Semantics(
              slider: true,
              enabled: _enabled,
              value: clockTime(shown),
              child: track,
            );
          },
        ),
      ),
      const SizedBox(width: 12),
      Text(
        _known ? '-${clockTime(safeRemaining)}' : '--:--',
        style: AppText.meta(13.5),
      ),
    ]);
  }
}

class _TimelineTrackPainter extends CustomPainter {
  const _TimelineTrackPainter({
    required this.value,
    required this.buffered,
    required this.enabled,
    required this.dragging,
  });

  final double value;
  final double buffered;
  final bool enabled;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final thumbRadius = dragging ? 10.5 : 8.5;
    final trackHeight = dragging ? 8.5 : 6.0;
    final startX = thumbRadius;
    final endX = math.max(startX, size.width - thumbRadius);
    final usable = endX - startX;
    final r = Radius.circular(trackHeight / 2);

    // Base track
    final bgRect = RRect.fromLTRBR(startX, cy - trackHeight / 2, endX, cy + trackHeight / 2, r);
    canvas.drawRRect(bgRect, Paint()..color = AppColors.line);

    if (!enabled) return;

    // Buffered range
    if (buffered > 0) {
      final bx = startX + usable * buffered.clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromLTRBR(startX, cy - trackHeight / 2, bx, cy + trackHeight / 2, r),
        Paint()..color = AppColors.buffered,
      );
    }

    // Played range
    final px = startX + usable * value.clamp(0.0, 1.0);
    if (px > startX) {
      canvas.drawRRect(
        RRect.fromLTRBR(startX, cy - trackHeight / 2, px, cy + trackHeight / 2, r),
        Paint()..color = AppColors.accent,
      );
    }

    // Thumb shadow + ring
    final center = Offset(px, cy);
    canvas.drawCircle(
      center.translate(0, 1.5),
      thumbRadius + 1,
      Paint()
        ..color = AppColors.onImageTrack.withValues(alpha: dragging ? 0.45 : 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, thumbRadius, Paint()..color = AppColors.surface);
    canvas.drawCircle(center, thumbRadius - 2.5, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_TimelineTrackPainter old) =>
      old.value != value || old.buffered != buffered || old.enabled != enabled || old.dragging != dragging;
}

/// Compact shrink-wrapped pill for transient seek, scrub, and fit feedback over video.
class PhoneOsdBadge extends StatelessWidget {
  const PhoneOsdBadge({super.key, required this.text, this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final innerH = compact ? 24.0 : 30.0;
    return IgnorePointer(
      child: GlassSurface(
        radius: (innerH + 2) / 2,
        nativeClear: true,
        nativeShape: NativeGlassShape.capsule,
        color: AppColors.videoGlass,
        shadows: const [],
        padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 14),
        child: SizedBox(
          height: innerH,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(compact ? 12 : 13.5).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live channel block of the player card: badge, number, name, "Canlı"; the programme now with its time range,
/// bar and the next one; the channels before and after.
class LiveInfo extends StatelessWidget {
  const LiveInfo({super.key, required this.index, required this.name, this.logo = '', this.programmes = const [], this.prevName, this.nextName, this.now});

  final int index; // position in the queue, 0-based
  final String name;
  final String logo;
  final List<Programme> programmes;
  final String? prevName;
  final String? nextName;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final t = (now ?? DateTime.now)();
    final current = programmes.where((p) => !t.isBefore(p.start) && t.isBefore(p.end)).firstOrNull;
    final next = programmes.where((p) => p.start.isAfter(t)).firstOrNull;
    double progress(Programme p) {
      final total = p.end.difference(p.start).inSeconds;
      return total <= 0 ? 0 : t.difference(p.start).inSeconds / total;
    }

    Widget neighbour(IconData icon, int number, String title) => Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppSizes.smallRadius)),
          child: Row(children: [
            Icon(icon, size: 16, color: AppColors.ink3),
            const SizedBox(width: 8),
            Text('$number', style: AppText.title(13, color: AppColors.ink2)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(14))),
          ]),
        );

    return Row(children: [
      ChannelBadge(name: name, logo: logo, size: 72),
      const SizedBox(width: 18),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 160, maxWidth: 280),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${index + 1}', style: AppText.title(14, color: AppColors.ink2)),
            const SizedBox(width: 10),
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(24))),
          ]),
          const SizedBox(height: 6),
          const Pill('Canlı', tone: PillTone.live, height: 26, leading: LiveDot(size: 8)),
        ]),
      ),
      if (current != null)
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(left: 22),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.line))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Flexible(child: Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(19))),
                const SizedBox(width: 12),
                Text('${hhmm(current.start)} – ${hhmm(current.end)}', style: AppText.meta(14)),
              ]),
              const SizedBox(height: 8),
              ProgressBar(value: progress(current)),
              if (next != null) ...[
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(text: 'Sırada ${hhmm(next.start)}, ', children: [TextSpan(text: next.title, style: AppText.title(14))]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta(14),
                ),
              ],
            ]),
          ),
        )
      else
        const Spacer(),
      if (prevName != null || nextName != null) ...[
        const SizedBox(width: 16),
        SizedBox(
          width: 250,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (prevName != null) neighbour(Icons.keyboard_arrow_up_rounded, index, prevName!),
            if (prevName != null && nextName != null) const SizedBox(height: 6),
            if (nextName != null) neighbour(Icons.keyboard_arrow_down_rounded, index + 2, nextName!),
          ]),
        ),
      ],
    ]);
  }
}

/// Compact frosted-glass overlay painted directly over the video on iPhone (portrait 16:9 and landscape full-bleed).
class PhonePlayerOverlay extends StatelessWidget {
  const PhonePlayerOverlay({
    super.key,
    required this.landscape,
    required this.live,
    required this.playing,
    required this.title,
    this.subtitle,
    this.onTitleTap,
    this.onBack,
    this.onMinimize,
    this.onSystemPip,
    required this.onPlayPause,
    required this.onToggleOrientation,
    required this.onToggleFit,
    required this.coverFit,
    this.skipSecs = 10,
    this.onSeekBack,
    this.onSeekForward,
    this.onPrev,
    this.onNext,
    this.queued = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
    this.pending = false,
    this.onSeek,
    this.onScrubStart,
    this.onScrubUpdate,
    this.onScrubEnd,
    this.onScrubCancel,
    this.onTimelineInteract,
    this.osdText,
    this.menuItems = const [],
    this.onMenuSelected,
    this.onMenuWillShow,
    this.onMenuDidHide,
    this.audioLabel,
    this.subtitleLabel,
    this.rateLabel,
    this.onPickAudio,
    this.onPickSubtitle,
    this.onPickRate,
    this.onGoTo,
    this.onOpenQueue,
    this.liveChannelIndex = 0,
    this.liveChannelName = '',
    this.liveChannelLogo = '',
    this.programmes = const [],
    this.now,
    this.sleepTimerLabel,
    this.onOpenSleepTimer,
  });

  final bool landscape;
  final bool live;
  final bool playing;
  final String title;
  final String? subtitle;

  /// Optional tap action on the top-left title pill (used for series to jump to the series detail page).
  final VoidCallback? onTitleTap;
  final VoidCallback? onBack;

  /// Minimizes the phone player into the in-app Mini Player glass bar.
  /// When provided, the top-left button shows a downward chevron (`⌄`).
  final VoidCallback? onMinimize;

  /// Triggers native iOS System Picture-in-Picture when supported.
  final VoidCallback? onSystemPip;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleOrientation;
  final VoidCallback onToggleFit;
  final bool coverFit;
  final int skipSecs;
  final VoidCallback? onSeekBack;
  final VoidCallback? onSeekForward;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool queued;
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final bool pending;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onScrubStart;
  final void Function(Duration target, Duration delta, ScrubPrecision precision)? onScrubUpdate;
  final ValueChanged<Duration>? onScrubEnd;
  final VoidCallback? onScrubCancel;
  final VoidCallback? onTimelineInteract;
  final String? osdText;
  final List<GlassMenuItem> menuItems;
  final ValueChanged<String>? onMenuSelected;
  final VoidCallback? onMenuWillShow;
  final VoidCallback? onMenuDidHide;
  final String? audioLabel;
  final String? subtitleLabel;
  final String? rateLabel;
  final VoidCallback? onPickAudio;
  final VoidCallback? onPickSubtitle;
  final VoidCallback? onPickRate;
  final VoidCallback? onGoTo;
  final VoidCallback? onOpenQueue;
  final int liveChannelIndex;
  final String liveChannelName;
  final String liveChannelLogo;
  final List<Programme> programmes;
  final DateTime Function()? now;
  final String? sleepTimerLabel;
  final VoidCallback? onOpenSleepTimer;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final hPad = landscape ? (safe.left > safe.right ? safe.left : safe.right).clamp(16.0, 64.0) : 12.0;
    final topPad = landscape ? (safe.top > 0 ? safe.top : 12.0) : 8.0;
    final bottomPad = landscape ? (safe.bottom > 0 ? safe.bottom : 12.0) : 8.0;
    final centerSize = landscape ? 60.0 : 52.0;
    final osdHeight = landscape ? 32.0 : 26.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final topBarBottom = topPad + 42.0;
        final centerTop = (h - centerSize) / 2;
        final upperGap = centerTop - topBarBottom;
        final osdTop = upperGap >= osdHeight + 4
            ? topBarBottom + (upperGap - osdHeight) / 2
            : topBarBottom + 2;

        return Stack(
          children: [
            // Top and bottom readability scrims over bright video scenes.
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 88,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.videoScrim, AppColors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: landscape ? 124 : 74,
              child: const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [AppColors.videoScrim, AppColors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            // Top bar.
            Positioned(
              left: hPad,
              right: hPad,
              top: topPad,
              child: Row(
                key: const ValueKey('phone-player-top-bar'),
                children: [
                  PhoneIconButton(
                    key: onMinimize != null ? const ValueKey('phone-player-minimize') : null,
                    icon: onMinimize != null ? Icons.keyboard_arrow_down_rounded : Icons.chevron_left_rounded,
                    tooltip: onMinimize != null ? 'Küçük oynatıcıya al' : 'Geri',
                    translucent: true,
                    onTap: onMinimize ?? onBack ?? () {},
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: () {
                        final pill = GlassSurface(
                          radius: 21,
                          nativeClear: true,
                          nativeShape: NativeGlassShape.capsule,
                          interactive: onTitleTap != null,
                          color: AppColors.videoGlass,
                          shadows: const [],
                          padding: EdgeInsets.only(
                            left: landscape ? 14 : 12,
                            right: onTitleTap != null ? (landscape ? 10 : 8) : (landscape ? 14 : 12),
                          ),
                          child: SizedBox(
                            height: 40,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.title(landscape ? 15.5 : 14),
                                      ),
                                      if (subtitle != null && subtitle!.isNotEmpty)
                                        Text(
                                          subtitle!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.meta(11, color: AppColors.body),
                                        ),
                                    ],
                                  ),
                                ),
                                if (onTitleTap != null) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.body),
                                ],
                              ],
                            ),
                          ),
                        );
                        if (onTitleTap == null) return pill;
                        return Tooltip(
                          message: 'Dizi sayfasına git',
                          child: Semantics(
                            button: true,
                            label: '$title, dizi sayfasına git',
                            child: GestureDetector(
                              key: const ValueKey('phone-player-title-pill'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                AppHaptics.light(context);
                                onTitleTap!();
                              },
                              child: pill,
                            ),
                          ),
                        );
                      }(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (landscape && sleepTimerLabel != null && onOpenSleepTimer != null) ...[
                    _MiniGlassChip(
                      key: const ValueKey('phone-player-sleep-chip'),
                      icon: Icons.bedtime_rounded,
                      label: sleepTimerLabel!,
                      onTap: onOpenSleepTimer!,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (landscape && queued && onOpenQueue != null) ...[
                    _MiniGlassChip(
                      icon: Icons.queue_play_next_rounded,
                      label: live ? 'Kanallar' : 'Bölümler',
                      onTap: onOpenQueue!,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (landscape && menuItems.isEmpty && onPickAudio != null) ...[
                    _MiniGlassChip(icon: Icons.audiotrack_rounded, label: audioLabel ?? 'Ses', onTap: onPickAudio!),
                    const SizedBox(width: 6),
                  ],
                  if (landscape && menuItems.isEmpty && onPickSubtitle != null) ...[
                    _MiniGlassChip(icon: Icons.subtitles_rounded, label: subtitleLabel ?? 'Altyazı', onTap: onPickSubtitle!),
                    const SizedBox(width: 6),
                  ],
                  if (landscape && menuItems.isEmpty && !live && onPickRate != null) ...[
                    _MiniGlassChip(icon: Icons.speed_rounded, label: rateLabel ?? '1x', onTap: onPickRate!),
                    const SizedBox(width: 6),
                  ],
                  if (landscape || menuItems.isEmpty) ...[
                    PhoneIconButton(
                      icon: coverFit ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded,
                      tooltip: coverFit ? 'Ekrana sığdır' : 'Ekranı doldur',
                      translucent: true,
                      onTap: onToggleFit,
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (onSystemPip != null) ...[
                    PhoneIconButton(
                      key: const ValueKey('phone-player-pip'),
                      icon: Icons.picture_in_picture_alt_rounded,
                      tooltip: 'Yüzen pencere (PiP)',
                      translucent: true,
                      onTap: onSystemPip!,
                    ),
                    const SizedBox(width: 4),
                  ],
                  PhoneIconButton(
                    icon: landscape ? Icons.screen_rotation_rounded : Icons.fullscreen_rounded,
                    tooltip: landscape ? 'Dikey görünüm' : 'Tam ekran (Yatay)',
                    translucent: true,
                    onTap: onToggleOrientation,
                  ),
                  if (menuItems.isNotEmpty && onMenuSelected != null) ...[
                    const SizedBox(width: 4),
                    NativeGlassMenuButton(
                      key: const ValueKey('phone-player-more-menu'),
                      items: menuItems,
                      onSelected: onMenuSelected!,
                      onMenuWillShow: onMenuWillShow,
                      onMenuDidHide: onMenuDidHide,
                      menuTitle: title,
                      sfSymbol: 'ellipsis',
                      fallbackIcon: Icons.more_horiz_rounded,
                      tooltip: 'Oynatıcı seçenekleri',
                      style: NativeGlassStyle.clearGlass,
                      width: 42,
                      height: 42,
                      isRound: true,
                      iconSize: 18,
                    ),
                  ],
                ],
              ),
            ),
            // Center transport cluster.
            Center(
              child: Row(
                key: const ValueKey('phone-player-center-controls'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!live && onSeekBack != null)
                    _TransportButton(
                      icon: switch (skipSecs) {
                        5 => Icons.replay_5_rounded,
                        30 => Icons.replay_30_rounded,
                        _ => Icons.replay_10_rounded,
                      },
                      label: skipSecs == 5 || skipSecs == 10 || skipSecs == 30 ? null : '-$skipSecs',
                      tooltip: '$skipSecs sn geri',
                      onTap: onSeekBack!,
                    )
                  else if (live && queued)
                    _TransportButton(
                      icon: Icons.skip_previous_rounded,
                      tooltip: 'Önceki kanal',
                      onTap: onPrev,
                    ),
                  const SizedBox(width: 24),
                  NativeGlassButton(
                    sfSymbol: playing ? 'pause.fill' : 'play.fill',
                    tooltip: playing ? 'Duraklat' : 'Oynat',
                    width: centerSize,
                    height: centerSize,
                    isRound: true,
                    iconSize: landscape ? 24 : 21,
                    style: NativeGlassStyle.prominentGlass,
                    tintColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    onPressed: onPlayPause,
                    fallback: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        AppHaptics.light(context);
                        onPlayPause();
                      },
                      child: Container(
                        width: centerSize,
                        height: centerSize,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(offset: Offset(0, 4), blurRadius: 16, color: Color.fromRGBO(0, 0, 0, 0.38))],
                        ),
                        child: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: landscape ? 34 : 30,
                          color: AppColors.onAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  if (!live && onSeekForward != null)
                    _TransportButton(
                      icon: switch (skipSecs) {
                        5 => Icons.forward_5_rounded,
                        30 => Icons.forward_30_rounded,
                        _ => Icons.forward_10_rounded,
                      },
                      label: skipSecs == 5 || skipSecs == 10 || skipSecs == 30 ? null : '+$skipSecs',
                      tooltip: '$skipSecs sn ileri',
                      onTap: onSeekForward!,
                    )
                  else if (live && queued)
                    _TransportButton(
                      icon: Icons.skip_next_rounded,
                      tooltip: 'Sonraki kanal',
                      onTap: onNext,
                    ),
                ],
              ),
            ),
            // Bottom bar.
            Positioned(
              left: hPad,
              right: hPad,
              bottom: bottomPad,
              child: KeyedSubtree(
                key: const ValueKey('phone-player-bottom-bar'),
                child: live
                    ? (landscape
                        ? _PhoneLandscapeLiveBar(
                            index: liveChannelIndex,
                            name: liveChannelName,
                            logo: liveChannelLogo,
                            programmes: programmes,
                            now: now,
                            onPrev: onPrev,
                            onNext: onNext,
                          )
                        : Row(
                            children: [
                              const Pill('Canlı', tone: PillTone.live, height: 24, leading: LiveDot(size: 7)),
                              const SizedBox(width: 8),
                              Text('#${liveChannelIndex + 1}', style: AppText.meta(12, color: AppColors.body)),
                              if (sleepTimerLabel != null) ...[
                                const SizedBox(width: 8),
                                Pill(sleepTimerLabel!, tone: PillTone.accent, icon: Icons.bedtime_rounded, height: 24),
                              ],
                            ],
                          ))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlassSurface(
                            radius: 22,
                            nativeClear: true,
                            interactive: true,
                            color: AppColors.videoGlass,
                            padding: EdgeInsets.symmetric(horizontal: landscape ? 16 : 12, vertical: landscape ? 6 : 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: VodTimeline(
                                    position: position,
                                    duration: duration,
                                    buffer: buffer,
                                    pending: pending,
                                    precisionScrub: true,
                                    onSeek: onSeek,
                                    onScrubStart: onScrubStart,
                                    onScrubUpdate: onScrubUpdate,
                                    onScrubEnd: onScrubEnd,
                                    onScrubCancel: onScrubCancel,
                                    onInteract: onTimelineInteract,
                                  ),
                                ),
                                if (landscape && onGoTo != null) ...[
                                  const SizedBox(width: 10),
                                  _MiniGlassChip(icon: Icons.schedule_rounded, label: 'Zamana git', onTap: onGoTo!),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
        // Seek / scrub / fit OSD pill, placed cleanly in the open band between top bar and center controls.
        if (osdText != null && upperGap >= osdHeight + 2)
          Positioned(
            top: osdTop,
            left: hPad,
            right: hPad,
            child: Center(
              child: PhoneOsdBadge(
                key: const ValueKey('phone-player-osd'),
                text: osdText!,
                compact: !landscape,
              ),
            ),
          ),
      ],
    );
      },
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({required this.icon, this.label, this.tooltip, required this.onTap});

  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    Widget fallback = Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                AppHaptics.light(context);
                onTap!();
              }
            : null,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.videoGlass,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.glassBorder, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: label != null ? 20 : 24, color: AppColors.ink),
              if (label != null) Text(label!, style: AppText.meta(9.5, color: AppColors.body)),
            ],
          ),
        ),
      ),
    );
    if (tooltip != null) fallback = Tooltip(message: tooltip!, child: fallback);

    final symbol = sfSymbolForIcon(icon);
    if (symbol == null || label != null) return fallback;
    return NativeGlassButton(
      sfSymbol: symbol,
      tooltip: tooltip,
      width: 46,
      height: 46,
      isRound: true,
      iconSize: 20,
      style: NativeGlassStyle.clearGlass,
      foregroundColor: AppColors.ink,
      onPressed: onTap,
      fallback: fallback,
    );
  }
}

class _MiniGlassChip extends StatelessWidget {
  const _MiniGlassChip({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fallback = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.selection(context);
        onTap();
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: AppColors.videoGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.glassBorder, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.ink),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(12.5)),
            ),
          ],
        ),
      ),
    );
    final symbol = sfSymbolForIcon(icon);
    if (symbol == null) return fallback;
    final estimatedWidth = (label.length * 7.6 + 46).clamp(76.0, 146.0);
    return NativeGlassButton(
      sfSymbol: symbol,
      label: label,
      tooltip: label,
      width: estimatedWidth,
      height: 36,
      isRound: false,
      cornerRadius: 18,
      iconSize: 14,
      fontSize: 12.5,
      style: NativeGlassStyle.clearGlass,
      foregroundColor: AppColors.ink,
      onPressed: onTap,
      fallback: fallback,
    );
  }
}

class _PhoneLandscapeLiveBar extends StatelessWidget {
  const _PhoneLandscapeLiveBar({
    required this.index,
    required this.name,
    required this.logo,
    required this.programmes,
    this.now,
    this.onPrev,
    this.onNext,
  });

  final int index;
  final String name;
  final String logo;
  final List<Programme> programmes;
  final DateTime Function()? now;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final t = (now ?? DateTime.now)();
    final current = programmes.where((p) => !t.isBefore(p.start) && t.isBefore(p.end)).firstOrNull;
    final next = programmes.where((p) => p.start.isAfter(t)).firstOrNull;
    double progress(Programme p) {
      final total = p.end.difference(p.start).inSeconds;
      return total <= 0 ? 0 : t.difference(p.start).inSeconds / total;
    }

    return GlassSurface(
      radius: 22,
      nativeClear: true,
      color: AppColors.videoGlass,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          ChannelBadge(name: name, logo: logo, size: 42),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 185),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${index + 1}', style: AppText.meta(12, color: AppColors.ink2)),
                    const SizedBox(width: 6),
                    Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(16))),
                  ],
                ),
                const SizedBox(height: 4),
                const Pill('Canlı', tone: PillTone.live, height: 22, leading: LiveDot(size: 7)),
              ],
            ),
          ),
          if (current != null) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(left: 14),
                decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.line))),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(14))),
                        const SizedBox(width: 8),
                        Text('${hhmm(current.start)}–${hhmm(current.end)}', style: AppText.meta(12)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ProgressBar(value: progress(current), height: 4),
                    if (next != null) ...[
                      const SizedBox(height: 4),
                      Text('Sırada ${hhmm(next.start)} · ${next.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(11.5)),
                    ],
                  ],
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (onPrev != null || onNext != null) ...[
            const SizedBox(width: 10),
            PhoneIconButton(icon: Icons.keyboard_arrow_up_rounded, tooltip: 'Önceki kanal', translucent: true, onTap: onPrev),
            PhoneIconButton(icon: Icons.keyboard_arrow_down_rounded, tooltip: 'Sonraki kanal', translucent: true, onTap: onNext),
          ],
        ],
      ),
    );
  }
}

/// Companion panel rendered beneath the 16:9 video in iPhone Portrait mode:
/// info header, quick action pills, live EPG card, and one-thumb channel/episode switcher.
class PhonePlayerCompanion extends StatelessWidget {
  const PhonePlayerCompanion({
    super.key,
    required this.live,
    required this.title,
    this.subtitle,
    this.onTitleTap,
    this.logo = '',
    required this.index,
    this.programmes = const [],
    this.now,
    required this.queueTitles,
    this.queueLogos = const [],
    this.onSelectQueue,
    required this.audioLabel,
    required this.subtitleLabel,
    this.rateLabel,
    required this.coverFit,
    required this.onPickAudio,
    required this.onPickSubtitle,
    this.onPickRate,
    this.onGoTo,
    required this.onToggleOrientation,
    required this.onToggleFit,
    this.autoNext,
    this.onToggleAutoNext,
    this.hasDelayOffset = false,
    this.onOpenSync,
    this.sleepTimerLabel,
    this.onOpenSleepTimer,
  });

  final bool live;
  final String title;
  final String? subtitle;

  /// Optional tap action on the title header (used for series to jump to the series detail page).
  final VoidCallback? onTitleTap;
  final String logo;
  final int index;
  final List<Programme> programmes;
  final DateTime Function()? now;
  final List<String> queueTitles;
  final List<String> queueLogos;
  final ValueChanged<int>? onSelectQueue;
  final String audioLabel;
  final String subtitleLabel;
  final String? rateLabel;
  final bool coverFit;
  final VoidCallback onPickAudio;
  final VoidCallback onPickSubtitle;
  final VoidCallback? onPickRate;
  final VoidCallback? onGoTo;
  final VoidCallback onToggleOrientation;
  final VoidCallback onToggleFit;
  final bool? autoNext;
  final VoidCallback? onToggleAutoNext;
  final bool hasDelayOffset;
  final VoidCallback? onOpenSync;
  final String? sleepTimerLabel;
  final VoidCallback? onOpenSleepTimer;

  @override
  Widget build(BuildContext context) {
    final t = (now ?? DateTime.now)();
    final current = programmes.where((p) => !t.isBefore(p.start) && t.isBefore(p.end)).firstOrNull;
    final next = programmes.where((p) => p.start.isAfter(t)).firstOrNull;
    double progress(Programme p) {
      final total = p.end.difference(p.start).inSeconds;
      return total <= 0 ? 0 : t.difference(p.start).inSeconds / total;
    }

    final bottomPad = MediaQuery.paddingOf(context).bottom + 16;

    return ColoredBox(
      color: AppColors.ground,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad),
        children: [
          // Header block
          () {
            final header = Row(
              children: [
                if (live) ...[
                  ChannelBadge(name: title, logo: logo, size: 46),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (live) ...[
                            const Pill('Canlı', tone: PillTone.live, height: 22, leading: LiveDot(size: 7)),
                            const SizedBox(width: 8),
                            Text('#${index + 1}', style: AppText.meta(12.5)),
                            if (subtitle != null && subtitle!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Flexible(child: Text('· $subtitle', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12.5))),
                            ],
                          ] else if (subtitle != null && subtitle!.isNotEmpty)
                            Text(subtitle!, style: AppText.meta(13, color: AppColors.accentInk)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.display(21)),
                    ],
                  ),
                ),
                if (onTitleTap != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.ink3),
                ],
              ],
            );
            if (onTitleTap == null) return header;
            return Semantics(
              button: true,
              label: '$title, dizi sayfasına git',
              child: GestureDetector(
                key: const ValueKey('phone-companion-title'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AppHaptics.light(context);
                  onTitleTap!();
                },
                child: header,
              ),
            );
          }(),
          const SizedBox(height: 14),
          // Quick horizontal action strip
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                AppButton(
                  variant: AppButtonVariant.primary,
                  height: 38,
                  dense: true,
                  icon: Icons.screen_rotation_rounded,
                  label: 'Yatay tam ekran',
                  onPressed: onToggleOrientation,
                ),
                const SizedBox(width: 8),
                AppButton(height: 38, dense: true, icon: Icons.audiotrack_rounded, label: audioLabel, onPressed: onPickAudio),
                const SizedBox(width: 8),
                AppButton(height: 38, dense: true, icon: Icons.subtitles_rounded, label: subtitleLabel, onPressed: onPickSubtitle),
                if (!live && onPickRate != null) ...[
                  const SizedBox(width: 8),
                  AppButton(height: 38, dense: true, icon: Icons.speed_rounded, label: rateLabel ?? '1x', onPressed: onPickRate),
                ],
                if (!live && onGoTo != null) ...[
                  const SizedBox(width: 8),
                  AppButton(height: 38, dense: true, icon: Icons.schedule_rounded, label: 'Zamana git', onPressed: onGoTo),
                ],
                const SizedBox(width: 8),
                AppButton(
                  height: 38,
                  dense: true,
                  icon: coverFit ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded,
                  label: coverFit ? 'Sığdır' : 'Doldur',
                  onPressed: onToggleFit,
                ),
                if (onOpenSync != null) ...[
                  const SizedBox(width: 8),
                  AppButton(
                    key: const ValueKey('phone-companion-sync'),
                    variant: hasDelayOffset ? AppButtonVariant.primary : AppButtonVariant.secondary,
                    height: 38,
                    dense: true,
                    icon: Icons.tune_rounded,
                    label: 'Senkron',
                    onPressed: onOpenSync,
                  ),
                ],
                if (onOpenSleepTimer != null) ...[
                  const SizedBox(width: 8),
                  AppButton(
                    key: const ValueKey('phone-companion-sleep'),
                    variant: sleepTimerLabel != null ? AppButtonVariant.primary : AppButtonVariant.secondary,
                    height: 38,
                    dense: true,
                    icon: sleepTimerLabel != null ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                    label: sleepTimerLabel ?? 'Uyku',
                    onPressed: onOpenSleepTimer,
                  ),
                ],
              ],
            ),
          ),
          if (!live && autoNext != null && onToggleAutoNext != null) ...[
            const SizedBox(height: 12),
            AppCard(
              radius: AppSizes.tileRadius,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sonraki bölümü otomatik oynat', style: AppText.title(14)),
                        Text('Bölüm bitince 10 sn içinde sıradakine geçer', style: AppText.meta(12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppSwitch(value: autoNext!, small: true, onChanged: (_) => onToggleAutoNext!()),
                ],
              ),
            ),
          ],
          if (live && current != null) ...[
            const SizedBox(height: 14),
            AppCard(
              radius: AppSizes.tileRadius,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(child: Pill('Şimdi yayında', tone: PillTone.accent, height: 24)),
                      const SizedBox(width: 8),
                      Text('${hhmm(current.start)} – ${hhmm(current.end)}', maxLines: 1, style: AppText.meta(13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(current.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.title(16)),
                  const SizedBox(height: 8),
                  ProgressBar(value: progress(current), height: 5),
                  if (next != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('Sırada ${hhmm(next.start)}', style: AppText.meta(12.5)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(next.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(13, color: AppColors.body))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (queueTitles.length > 1 && onSelectQueue != null) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Text(live ? 'Kanallar' : 'Bölümler', style: AppText.title(17)),
                const SizedBox(width: 8),
                Text(groupCount(queueTitles.length), style: AppText.meta(13)),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < queueTitles.length && i < 40; i++) ...[
              _QueueItemRow(
                number: i + 1,
                title: live ? queueTitles[i] : playerTitle(queueTitles[i]).$1,
                subtitle: live ? null : episodeLabel(queueTitles[i]),
                logo: i < queueLogos.length ? queueLogos[i] : '',
                live: live,
                active: i == index,
                onTap: () {
                  AppHaptics.selection(context);
                  onSelectQueue!(i);
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _QueueItemRow extends StatelessWidget {
  const _QueueItemRow({
    required this.number,
    required this.title,
    this.subtitle,
    this.logo = '',
    required this.live,
    required this.active,
    required this.onTap,
  });

  final int number;
  final String title;
  final String? subtitle;
  final String logo;
  final bool live;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.5) : AppColors.line),
        ),
        child: Row(
          children: [
            if (live) ...[
              ChannelBadge(name: title, logo: logo, size: 36),
              const SizedBox(width: 10),
            ] else ...[
              SizedBox(
                width: 28,
                child: Text('$number', textAlign: TextAlign.center, style: AppText.meta(13, color: active ? AppColors.accentInk : AppColors.ink2)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(14.5, color: active ? AppColors.accentInk : AppColors.ink),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12, color: active ? AppColors.accentInk : AppColors.ink2)),
                ],
              ),
            ),
            if (active) ...[
              const SizedBox(width: 8),
              Icon(Icons.graphic_eq_rounded, size: 18, color: AppColors.accent),
            ],
          ],
        ),
      ),
    );
  }
}

/// Which device level [PhoneGestureHud] is currently displaying.
enum PhoneGestureHudKind {
  brightness,
  volume,
}

/// Floating Liquid Glass pill meter shown during iPhone brightness and volume swipe gestures.
class PhoneGestureHud extends StatelessWidget {
  const PhoneGestureHud({
    super.key,
    required this.kind,
    required this.value,
    this.compact = false,
  });

  final PhoneGestureHudKind kind;
  final double value;
  final bool compact;

  IconData _icon(double v) {
    if (kind == PhoneGestureHudKind.brightness) {
      if (v < 0.34) return Icons.brightness_low_rounded;
      if (v < 0.67) return Icons.brightness_medium_rounded;
      return Icons.brightness_high_rounded;
    }
    if (v <= 0.005) return Icons.volume_off_rounded;
    if (v < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    final pct = (clamped * 100).round();
    final h = compact ? 28.0 : 38.0;
    final w = compact ? 172.0 : 210.0;

    return IgnorePointer(
      child: GlassSurface(
        key: const ValueKey('phone-gesture-hud'),
        radius: h / 2,
        nativeClear: true,
        nativeShape: NativeGlassShape.capsule,
        color: AppColors.videoGlass,
        shadows: const [],
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
        child: SizedBox(
          width: w,
          height: h,
          child: Row(
            children: [
              Icon(_icon(clamped), size: compact ? 15 : 19, color: AppColors.accentInk),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: compact ? 4.5 : 6,
                    child: Stack(
                      children: [
                        const Positioned.fill(child: ColoredBox(color: AppColors.line)),
                        FractionallySizedBox(
                          widthFactor: clamped,
                          heightFactor: 1,
                          child: const ColoredBox(color: AppColors.accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              SizedBox(
                width: compact ? 32 : 38,
                child: Text(
                  '%$pct',
                  textAlign: TextAlign.right,
                  style: AppText.label(compact ? 11.5 : 13).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact floating pill shown while press-and-holding VOD video at 2× speed.
class SpeedHoldBadge extends StatelessWidget {
  const SpeedHoldBadge({super.key, this.compact = false, this.glass = true});

  final bool compact;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 28.0 : 34.0;
    final content = SizedBox(
      height: h,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fast_forward_rounded, size: compact ? 15 : 18, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(
            compact ? '2× Hızlı' : '2× Hızlı oynatma',
            style: AppText.label(compact ? 12 : 13.5).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    if (!glass) {
      return IgnorePointer(
        child: Container(
          key: const ValueKey('speed-hold-badge'),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(h / 2),
            boxShadow: AppShadows.overlay,
          ),
          child: content,
        ),
      );
    }

    return IgnorePointer(
      child: GlassSurface(
        key: const ValueKey('speed-hold-badge'),
        radius: h / 2,
        nativeClear: true,
        nativeShape: NativeGlassShape.capsule,
        color: AppColors.videoGlass,
        shadows: const [],
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
        child: content,
      ),
    );
  }
}

/// Clickable top-bar pill showing an active sleep timer on desktop player chrome.
class SleepTimerPill extends StatelessWidget {
  const SleepTimerPill({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusRing(
      key: const ValueKey('sleep-timer-pill'),
      radius: 22,
      lift: false,
      tooltip: 'Uyku zamanlayıcısı',
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
          boxShadow: AppShadows.chip,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bedtime_rounded, size: 17, color: AppColors.accentInk),
            const SizedBox(width: 7),
            Text(
              label,
              style: AppText.label(14, color: AppColors.accentInk).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Unified touch gesture host for the iPhone/phone video surface:
/// - Single tap: toggle player chrome
/// - Double tap: left/right skip (VOD) or prev/next channel (Live), center play/pause (VOD)
/// - Long press (VOD): temporary 2× playback speed while held + floating [SpeedHoldBadge]
/// - Vertical drag:
///   - Left zone: screen brightness + [PhoneGestureHud]
///   - Right zone: system/player volume + [PhoneGestureHud]
///   - Center zone (portrait): swipe down to minimize into the Mini Player
class PhoneVideoGestureSurface extends StatefulWidget {
  const PhoneVideoGestureSurface({
    super.key,
    required this.landscape,
    required this.live,
    required this.controlsVisible,
    required this.enabled,
    required this.brightnessEnabled,
    required this.onTap,
    required this.onDoubleTapZone,
    required this.onSpeedHoldStart,
    required this.onSpeedHoldEnd,
    required this.readBrightness,
    required this.writeBrightness,
    required this.readVolume,
    required this.writeVolume,
    required this.child,
    this.onMinimizeSwipe,
    this.onVolumeGestureEnd,
  });

  final bool landscape;
  final bool live;
  final bool controlsVisible;
  final bool enabled;
  final bool brightnessEnabled;
  final VoidCallback onTap;
  final void Function(TapDownDetails details, double width) onDoubleTapZone;
  final VoidCallback? onMinimizeSwipe;
  final Future<bool> Function() onSpeedHoldStart;
  final Future<void> Function() onSpeedHoldEnd;
  final Future<double> Function() readBrightness;
  final Future<void> Function(double value) writeBrightness;
  final Future<double> Function() readVolume;
  final Future<void> Function(double value) writeVolume;
  final VoidCallback? onVolumeGestureEnd;
  final Widget child;

  @override
  State<PhoneVideoGestureSurface> createState() => _PhoneVideoGestureSurfaceState();
}

class _PhoneVideoGestureSurfaceState extends State<PhoneVideoGestureSurface> {
  TapDownDetails? _lastDoubleTap;
  bool _holding2x = false;

  PhoneVerticalGesture _activeDrag = PhoneVerticalGesture.none;
  double _dragValue = 0.5;
  double _pendingDy = 0.0;
  bool _readingInitial = false;
  int _dragToken = 0;
  double _minimizeDy = 0.0;
  int _lastBoundHit = 0; // -1 at 0%, 1 at 100%, 0 in between

  PhoneGestureHudKind? _hudKind;
  double _hudValue = 0.5;
  Timer? _hudHideTimer;

  @override
  void didUpdateWidget(PhoneVideoGestureSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_holding2x && (widget.live || !widget.enabled)) {
      _stopSpeedHold();
    }
  }

  @override
  void dispose() {
    _hudHideTimer?.cancel();
    if (_holding2x) {
      _holding2x = false;
      widget.onSpeedHoldEnd();
    }
    super.dispose();
  }

  Future<void> _startSpeedHold() async {
    if (!widget.enabled || widget.live || _activeDrag != PhoneVerticalGesture.none || _holding2x) {
      return;
    }
    final accepted = await widget.onSpeedHoldStart();
    if (!mounted || !accepted) return;
    AppHaptics.medium(context);
    setState(() => _holding2x = true);
  }

  void _stopSpeedHold() {
    if (!_holding2x) return;
    setState(() => _holding2x = false);
    widget.onSpeedHoldEnd();
  }

  void _scheduleHudHide() {
    _hudHideTimer?.cancel();
    _hudHideTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hudKind = null);
    });
  }

  void _onVerticalDragStart(DragStartDetails details, Size size) {
    if (!widget.enabled || _holding2x) {
      _activeDrag = PhoneVerticalGesture.none;
      return;
    }
    final kind = classifyPhoneVerticalGesture(
      localPosition: details.localPosition,
      size: size,
      landscape: widget.landscape,
      brightnessEnabled: widget.brightnessEnabled,
      controlsVisible: widget.controlsVisible,
      live: widget.live,
    );
    _activeDrag = kind;
    _minimizeDy = 0.0;
    _lastBoundHit = 0;

    if (kind != PhoneVerticalGesture.brightness && kind != PhoneVerticalGesture.volume) {
      return;
    }

    _hudHideTimer?.cancel();
    final token = ++_dragToken;
    _readingInitial = true;
    _pendingDy = 0.0;
    final hudKind = kind == PhoneVerticalGesture.brightness
        ? PhoneGestureHudKind.brightness
        : PhoneGestureHudKind.volume;

    final future = kind == PhoneVerticalGesture.brightness
        ? widget.readBrightness()
        : widget.readVolume();
    future.then((initial) {
      if (!mounted || token != _dragToken || _activeDrag != kind) return;
      _readingInitial = false;
      final base = initial.clamp(0.0, 1.0).toDouble();
      final next = _pendingDy == 0.0
          ? base
          : applyVerticalDragDelta(
              currentValue: base,
              deltaDy: _pendingDy,
              viewportHeight: size.height,
            );
      _pendingDy = 0.0;
      _dragValue = next;
      setState(() {
        _hudKind = hudKind;
        _hudValue = next;
      });
      if (kind == PhoneVerticalGesture.brightness) {
        widget.writeBrightness(next);
      } else {
        widget.writeVolume(next);
      }
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, Size size) {
    if (_activeDrag == PhoneVerticalGesture.none) return;
    if (_activeDrag == PhoneVerticalGesture.minimize) {
      _minimizeDy += details.delta.dy;
      return;
    }
    if (_readingInitial) {
      _pendingDy += details.delta.dy;
      return;
    }
    final next = applyVerticalDragDelta(
      currentValue: _dragValue,
      deltaDy: details.delta.dy,
      viewportHeight: size.height,
    );
    if ((next - _dragValue).abs() < 0.0005) return;
    _dragValue = next;

    final bound = next <= 0.001 ? -1 : (next >= 0.999 ? 1 : 0);
    if (bound != 0 && bound != _lastBoundHit) {
      AppHaptics.selection(context);
    }
    _lastBoundHit = bound;

    final hudKind = _activeDrag == PhoneVerticalGesture.brightness
        ? PhoneGestureHudKind.brightness
        : PhoneGestureHudKind.volume;
    setState(() {
      _hudKind = hudKind;
      _hudValue = next;
    });

    if (_activeDrag == PhoneVerticalGesture.brightness) {
      widget.writeBrightness(next);
    } else {
      widget.writeVolume(next);
    }
  }

  void _finishVerticalDrag({double? velocity}) {
    final drag = _activeDrag;
    _activeDrag = PhoneVerticalGesture.none;
    _readingInitial = false;
    _pendingDy = 0.0;
    _dragToken++;

    if (drag == PhoneVerticalGesture.minimize) {
      if ((velocity ?? 0) > 320 || _minimizeDy > 64) {
        AppHaptics.light(context);
        widget.onMinimizeSwipe?.call();
      }
      _minimizeDy = 0.0;
      return;
    }
    if (drag == PhoneVerticalGesture.volume) {
      widget.onVolumeGestureEnd?.call();
    }
    if (drag == PhoneVerticalGesture.brightness || drag == PhoneVerticalGesture.volume) {
      _scheduleHudHide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final topPad = widget.landscape ? (safeTop > 0 ? safeTop : 12.0) : 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final centerSize = widget.landscape ? 60.0 : 52.0;
        final badgeH = widget.landscape ? 38.0 : 28.0;
        final double hudTop;
        if (widget.controlsVisible) {
          final topBarBottom = topPad + 42.0;
          final centerTop = (size.height - centerSize) / 2;
          final gap = centerTop - topBarBottom;
          hudTop = gap >= badgeH + 2
              ? topBarBottom + (gap - badgeH) / 2
              : topBarBottom + 1;
        } else {
          hudTop = widget.landscape ? (safeTop > 0 ? safeTop + 14.0 : 22.0) : 14.0;
        }
        return GestureDetector(
          key: const ValueKey('phone-video-gesture-surface'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTapDown: (d) => _lastDoubleTap = d,
          onDoubleTap: () {
            if (_lastDoubleTap != null) {
              widget.onDoubleTapZone(_lastDoubleTap!, constraints.maxWidth);
            }
          },
          onLongPressStart: !widget.live && widget.enabled ? (_) => _startSpeedHold() : null,
          onLongPressEnd: !widget.live ? (_) => _stopSpeedHold() : null,
          onLongPressCancel: _stopSpeedHold,
          onVerticalDragStart: widget.enabled ? (d) => _onVerticalDragStart(d, size) : null,
          onVerticalDragUpdate: widget.enabled ? (d) => _onVerticalDragUpdate(d, size) : null,
          onVerticalDragEnd: widget.enabled ? (d) => _finishVerticalDrag(velocity: d.primaryVelocity) : null,
          onVerticalDragCancel: () => _finishVerticalDrag(),
          child: Stack(
            children: [
              widget.child,
              if (_holding2x)
                Positioned(
                  top: hudTop,
                  left: 16,
                  right: 16,
                  child: Center(child: SpeedHoldBadge(compact: !widget.landscape)),
                ),
              if (_hudKind != null)
                Positioned(
                  top: _holding2x ? hudTop + (widget.landscape ? 42 : 34) : hudTop,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: PhoneGestureHud(
                      kind: _hudKind!,
                      value: _hudValue,
                      compact: !widget.landscape,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Interactive synchronization and deinterlace panel for both iOS bottom sheets and Desktop/TV dialogs.
class PlayerSyncPanel extends StatelessWidget {
  const PlayerSyncPanel({
    super.key,
    required this.subDelayMs,
    required this.audioDelayMs,
    required this.deinterlace,
    required this.onAdjustSubDelay,
    required this.onResetSubDelay,
    required this.onAdjustAudioDelay,
    required this.onResetAudioDelay,
    required this.onDeinterlaceChanged,
    this.compact = false,
  });

  final int subDelayMs;
  final int audioDelayMs;
  final String deinterlace;
  final ValueChanged<int> onAdjustSubDelay;
  final VoidCallback onResetSubDelay;
  final ValueChanged<int> onAdjustAudioDelay;
  final VoidCallback onResetAudioDelay;
  final ValueChanged<String> onDeinterlaceChanged;
  final bool compact;

  Widget _delaySection({
    required BuildContext context,
    required String title,
    required String hint,
    required int valueMs,
    required Key valueKey,
    required int coarseMs,
    required int fineMs,
    required String coarseNegLabel,
    required String fineNegLabel,
    required String finePosLabel,
    required String coarsePosLabel,
    required ValueChanged<int> onAdjust,
    required VoidCallback onReset,
    required Key resetKey,
  }) {
    final btnHeight = compact ? 38.0 : 42.0;
    return AppCard(
      radius: AppSizes.tileRadius,
      shadows: const [],
      color: AppColors.surface,
      border: Border.all(color: AppColors.line),
      padding: EdgeInsets.all(compact ? 12 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppText.title(15)),
                    const SizedBox(height: 2),
                    Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.meta(12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Pill(
                formatDelayMs(valueMs),
                key: valueKey,
                tone: valueMs == 0 ? PillTone.neutral : PillTone.accent,
                height: 28,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AppButton(
                label: coarseNegLabel,
                height: btnHeight,
                dense: true,
                onPressed: () {
                  AppHaptics.selection(context);
                  onAdjust(-coarseMs);
                },
              ),
              AppButton(
                label: fineNegLabel,
                height: btnHeight,
                dense: true,
                onPressed: () {
                  AppHaptics.selection(context);
                  onAdjust(-fineMs);
                },
              ),
              AppButton(
                label: finePosLabel,
                height: btnHeight,
                dense: true,
                onPressed: () {
                  AppHaptics.selection(context);
                  onAdjust(fineMs);
                },
              ),
              AppButton(
                label: coarsePosLabel,
                height: btnHeight,
                dense: true,
                onPressed: () {
                  AppHaptics.selection(context);
                  onAdjust(coarseMs);
                },
              ),
              AppButton(
                key: resetKey,
                label: 'Sıfırla',
                height: btnHeight,
                dense: true,
                variant: valueMs == 0 ? AppButtonVariant.secondary : AppButtonVariant.danger,
                onPressed: valueMs == 0
                    ? null
                    : () {
                        AppHaptics.light(context);
                        onReset();
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normDeint = AppSettings.normalizeDeinterlace(deinterlace);
    return SingleChildScrollView(
      padding: EdgeInsets.all(compact ? 14 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _delaySection(
            context: context,
            title: 'Altyazı gecikmesi',
            hint: 'Altyazı erken geliyorsa +, geç geliyorsa −',
            valueMs: subDelayMs,
            valueKey: const ValueKey('sync-sub-delay-value'),
            coarseMs: 500,
            fineMs: 100,
            coarseNegLabel: '−0.5 sn',
            fineNegLabel: '−0.1 sn',
            finePosLabel: '+0.1 sn',
            coarsePosLabel: '+0.5 sn',
            onAdjust: onAdjustSubDelay,
            onReset: onResetSubDelay,
            resetKey: const ValueKey('sync-sub-delay-reset'),
          ),
          const SizedBox(height: 12),
          _delaySection(
            context: context,
            title: 'Ses gecikmesi',
            hint: 'Ses görüntüden önceyse +, sonraysa −',
            valueMs: audioDelayMs,
            valueKey: const ValueKey('sync-audio-delay-value'),
            coarseMs: 250,
            fineMs: 50,
            coarseNegLabel: '−250 ms',
            fineNegLabel: '−50 ms',
            finePosLabel: '+50 ms',
            coarsePosLabel: '+250 ms',
            onAdjust: onAdjustAudioDelay,
            onReset: onResetAudioDelay,
            resetKey: const ValueKey('sync-audio-delay-reset'),
          ),
          const SizedBox(height: 12),
          AppCard(
            radius: AppSizes.tileRadius,
            shadows: const [],
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            padding: EdgeInsets.all(compact ? 12 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Tarama giderme (Deinterlace)', style: AppText.title(15)),
                const SizedBox(height: 2),
                Text('Canlı TV yayınlarında yatay çizgilenmeyi giderir', style: AppText.meta(12)),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Segmented<String>(
                    key: const ValueKey('sync-deinterlace'),
                    value: normDeint,
                    options: AppSettings.deinterlaceOptions,
                    onChanged: (v) {
                      AppHaptics.selection(context);
                      onDeinterlaceChanged(v);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive Sleep Timer picker rendered inside an iOS bottom sheet or Desktop/TV dialog.
class SleepTimerPicker extends StatelessWidget {
  const SleepTimerPicker({
    super.key,
    required this.state,
    required this.live,
    required this.isSeries,
    required this.onSelectDuration,
    required this.onSelectEndOfCurrent,
    required this.onExtend15,
    required this.onCancel,
    this.useSheet = false,
  });

  final SleepTimerState state;
  final bool live;
  final bool isSeries;
  final ValueChanged<Duration> onSelectDuration;
  final VoidCallback onSelectEndOfCurrent;
  final VoidCallback onExtend15;
  final VoidCallback onCancel;
  final bool useSheet;

  @override
  Widget build(BuildContext context) {
    final endLabel = isSeries ? 'Bu bölüm bitince' : 'Bu film bitince';
    final rows = <Widget>[
      if (state.isActive)
        Padding(
          padding: EdgeInsets.fromLTRB(useSheet ? 12 : 0, useSheet ? 8 : 0, useSheet ? 12 : 0, 10),
          child: Container(
            key: const ValueKey('sleep-timer-active-banner'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bedtime_rounded, size: 18, color: AppColors.accentInk),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.detailLabel(isSeries: isSeries),
                        style: AppText.title(14.5, color: AppColors.accentInk),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (state.mode == SleepTimerMode.countdown)
                      AppButton(
                        key: const ValueKey('sleep-timer-extend'),
                        label: '+15 dk uzat',
                        height: 36,
                        dense: true,
                        variant: AppButtonVariant.primary,
                        onPressed: onExtend15,
                      ),
                    AppButton(
                      key: const ValueKey('sleep-timer-cancel'),
                      label: 'Zamanlayıcıyı iptal et',
                      height: 36,
                      dense: true,
                      variant: AppButtonVariant.danger,
                      onPressed: onCancel,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      for (final mins in sleepTimerPresetsMinutes)
        if (useSheet)
          SheetOptionTile(
            label: '$mins dakika',
            leadingIcon: Icons.timer_outlined,
            onTap: () => onSelectDuration(Duration(minutes: mins)),
          )
        else
          SimpleDialogOption(
            onPressed: () => onSelectDuration(Duration(minutes: mins)),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18, color: AppColors.ink2),
                const SizedBox(width: 12),
                Expanded(child: Text('$mins dakika', style: AppText.label(15))),
              ],
            ),
          ),
      if (!live)
        if (useSheet)
          SheetOptionTile(
            label: endLabel,
            leadingIcon: Icons.flag_outlined,
            selected: state.mode == SleepTimerMode.endOfCurrent,
            onTap: onSelectEndOfCurrent,
          )
        else
          SimpleDialogOption(
            onPressed: onSelectEndOfCurrent,
            child: Row(
              children: [
                Icon(
                  Icons.flag_outlined,
                  size: 18,
                  color: state.mode == SleepTimerMode.endOfCurrent ? AppColors.accent : AppColors.ink2,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    endLabel,
                    style: AppText.label(
                      15,
                      color: state.mode == SleepTimerMode.endOfCurrent ? AppColors.accentInk : AppColors.ink,
                    ),
                  ),
                ),
                if (state.mode == SleepTimerMode.endOfCurrent)
                  const Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
              ],
            ),
          ),
    ];

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(vertical: useSheet ? 8 : 0),
      children: rows,
    );
  }
}
