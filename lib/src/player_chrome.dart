import 'package:flutter/material.dart';

import 'title_utils.dart';
import 'ui/basics.dart';
import 'ui/format.dart';
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
