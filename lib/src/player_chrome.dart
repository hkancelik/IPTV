import 'package:flutter/material.dart';

import 'title_utils.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/format.dart';
import 'ui/layout.dart';
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
  const PlayerTitlePill({super.key, required this.onBack, required this.title, this.subtitle});

  final VoidCallback onBack;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Container(
        height: 56,
        padding: const EdgeInsets.fromLTRB(6, 0, 20, 0),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(28), boxShadow: AppShadows.overlay),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppButton(icon: Icons.chevron_left_rounded, tooltip: 'Geri', onPressed: onBack),
          const SizedBox(width: 12),
          Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(16))),
          if (subtitle != null) ...[
            const SizedBox(width: 12),
            Flexible(child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(14))),
          ],
        ]),
      );
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

/// Elapsed time, position bar (buffered part lighter) and time left.
class VodTimeline extends StatelessWidget {
  const VodTimeline({super.key, required this.position, required this.duration, this.buffer = Duration.zero, this.pending = false, this.onSeek});

  final Duration position;
  final Duration duration;
  final Duration buffer;

  /// The position is a target being chosen with the remote, not the playing one.
  final bool pending;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    final known = duration > Duration.zero;
    final max = known ? duration.inMilliseconds.toDouble() : 1.0;
    final value = known ? position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble() : 0.0;
    final buffered = known ? buffer.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble() : 0.0;
    return Row(children: [
      Text(clockTime(position), style: AppText.title(15, color: pending ? AppColors.accent : AppColors.ink).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(width: 12),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 8,
            trackShape: const RoundedRectSliderTrackShape(),
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: AppColors.line,
            secondaryActiveTrackColor: AppColors.buffered,
            disabledActiveTrackColor: AppColors.line,
            disabledInactiveTrackColor: AppColors.line,
            disabledSecondaryActiveTrackColor: AppColors.line,
            thumbShape: const _RingThumb(),
            overlayShape: SliderComponentShape.noOverlay,
            overlayColor: AppColors.transparent,
          ),
          child: Slider(
            value: value,
            max: max,
            secondaryTrackValue: buffered,
            onChanged: !known || onSeek == null ? null : (v) => onSeek!(Duration(milliseconds: v.round())),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Text(known ? '-${clockTime(duration - position)}' : '--:--', style: AppText.meta(15)),
    ]);
  }
}

/// 20 px blue knob with a 3 px white rim and a small shadow.
class _RingThumb extends SliderComponentShape {
  const _RingThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(20, 20);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    if (enableAnimation.value == 0) return;
    final c = context.canvas;
    c.drawCircle(center.translate(0, 2), 11, Paint()..color = AppColors.onImageTrack.withValues(alpha: 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    c.drawCircle(center, 10, Paint()..color = AppColors.surface);
    c.drawCircle(center, 7, Paint()..color = AppColors.accent);
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
    required this.onBack,
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
  });

  final bool landscape;
  final bool live;
  final bool playing;
  final String title;
  final String? subtitle;
  final VoidCallback onBack;
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

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final hPad = landscape ? (safe.left > safe.right ? safe.left : safe.right).clamp(16.0, 64.0) : 12.0;
    final topPad = landscape ? (safe.top > 0 ? safe.top : 12.0) : 8.0;
    final bottomPad = landscape ? (safe.bottom > 0 ? safe.bottom : 12.0) : 8.0;

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
            children: [
              PhoneIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Geri',
                translucent: true,
                onTap: onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(landscape ? 17 : 15)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12, color: AppColors.body)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (landscape && queued && onOpenQueue != null) ...[
                _MiniGlassChip(
                  icon: Icons.queue_play_next_rounded,
                  label: live ? 'Kanallar' : 'Bölümler',
                  onTap: onOpenQueue!,
                ),
                const SizedBox(width: 6),
              ],
              if (landscape && onPickAudio != null) ...[
                _MiniGlassChip(icon: Icons.audiotrack_rounded, label: audioLabel ?? 'Ses', onTap: onPickAudio!),
                const SizedBox(width: 6),
              ],
              if (landscape && onPickSubtitle != null) ...[
                _MiniGlassChip(icon: Icons.subtitles_rounded, label: subtitleLabel ?? 'Altyazı', onTap: onPickSubtitle!),
                const SizedBox(width: 6),
              ],
              if (landscape && !live && onPickRate != null) ...[
                _MiniGlassChip(icon: Icons.speed_rounded, label: rateLabel ?? '1x', onTap: onPickRate!),
                const SizedBox(width: 6),
              ],
              PhoneIconButton(
                icon: coverFit ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded,
                tooltip: coverFit ? 'Ekrana sığdır' : 'Ekranı doldur',
                translucent: true,
                onTap: onToggleFit,
              ),
              const SizedBox(width: 4),
              PhoneIconButton(
                icon: landscape ? Icons.screen_rotation_rounded : Icons.fullscreen_rounded,
                tooltip: landscape ? 'Dikey görünüm' : 'Tam ekran (Yatay)',
                translucent: true,
                onTap: onToggleOrientation,
              ),
            ],
          ),
        ),
        // Center transport cluster.
        Center(
          child: Row(
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AppHaptics.light(context);
                  onPlayPause();
                },
                child: Container(
                  width: landscape ? 60 : 52,
                  height: landscape ? 60 : 52,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.overlay,
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: landscape ? 34 : 30,
                    color: AppColors.onAccent,
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
                      ],
                    ))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassSurface(
                      radius: 20,
                      color: AppColors.videoGlass,
                      padding: EdgeInsets.symmetric(horizontal: landscape ? 16 : 12, vertical: landscape ? 8 : 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: VodTimeline(
                              position: position,
                              duration: duration,
                              buffer: buffer,
                              pending: pending,
                              onSeek: onSeek,
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
      ],
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
    Widget child = Opacity(
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
    if (tooltip != null) child = Tooltip(message: tooltip!, child: child);
    return child;
  }
}

class _MiniGlassChip extends StatelessWidget {
  const _MiniGlassChip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
  });

  final bool live;
  final String title;
  final String? subtitle;
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
          Row(
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
            ],
          ),
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
