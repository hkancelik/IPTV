import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_chrome.dart';
import 'player_session.dart';
import 'ui/basics.dart';
import 'ui/layout.dart';
import 'ui/liquid_glass.dart';
import 'ui/tokens.dart';
import 'xtream.dart';

/// Height of the docked 2-button iPhone Mini Player glass bar.
const double phoneMiniPlayerBarHeight = 64.0;

/// Extra scroll clearance needed beneath lists while [PhoneMiniPlayerBar] is visible.
const double phoneMiniPlayerClearance = 76.0;

/// Locked Seçenek A · 2-button Liquid Glass Mini Player bar for iPhone.
///
/// Sits above [PhoneBottomBar] in portrait (and compactly at the bottom-left of
/// the content pane in landscape) with:
/// - Live 16:9 video thumbnail (`92 × 52 pt`, radius `12 pt`) + red live badge
/// - Fraunces title + italic EPG programme (live) or remaining time (VOD)
/// - Exactly 2 compact action buttons: Play/Pause and Close (`×`)
/// - Flush `2.5 pt` lavender progress bar along the bottom edge
/// - Tap or swipe up to expand back to the full player; swipe horizontally to close.
class PhoneMiniPlayerBar extends StatefulWidget {
  const PhoneMiniPlayerBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.live,
    required this.playing,
    required this.progress,
    required this.onExpand,
    required this.onPlayPause,
    required this.onClose,
    this.logo = '',
    this.videoController,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final bool live;
  final bool playing;
  final double progress;
  final VoidCallback onExpand;
  final VoidCallback onPlayPause;
  final VoidCallback onClose;
  final String logo;
  final VideoController? videoController;

  /// Slightly slimmer height for landscape floating placement.
  final bool compact;

  @override
  State<PhoneMiniPlayerBar> createState() => _PhoneMiniPlayerBarState();
}

class _PhoneMiniPlayerBarState extends State<PhoneMiniPlayerBar> {
  double _dragX = 0;

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    setState(() => _dragX = (_dragX + d.delta.dx).clamp(-140.0, 140.0));
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (_dragX.abs() > 72 || velocity.abs() > 520) {
      AppHaptics.light(context);
      widget.onClose();
    }
    if (mounted) setState(() => _dragX = 0);
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (velocity < -260) {
      AppHaptics.light(context);
      widget.onExpand();
    }
  }

  @override
  Widget build(BuildContext context) {
    final barHeight = widget.compact ? 58.0 : phoneMiniPlayerBarHeight;
    final thumbW = widget.compact ? 80.0 : 92.0;
    final thumbH = widget.compact ? 45.0 : 52.0;
    final clampedProgress = widget.progress.clamp(0.0, 1.0);
    final opacity = (1.0 - (_dragX.abs() / 180.0)).clamp(0.35, 1.0);

    return Transform.translate(
      offset: Offset(_dragX, 0),
      child: Opacity(
        opacity: opacity,
        child: GestureDetector(
          key: const ValueKey('phone-mini-player'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AppHaptics.light(context);
            widget.onExpand();
          },
          onVerticalDragEnd: _onVerticalDragEnd,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          onHorizontalDragCancel: () => setState(() => _dragX = 0),
          child: GlassSurface(
            radius: 22,
            nativeShape: NativeGlassShape.rect,
            color: AppColors.glass,
            borderColor: AppColors.glassBorder,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: barHeight,
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Row(
                          children: [
                            // Live 16:9 video preview thumbnail
                            _MiniVideoThumbnail(
                              width: thumbW,
                              height: thumbH,
                              live: widget.live,
                              title: widget.title,
                              logo: widget.logo,
                              controller: widget.videoController,
                            ),
                            const SizedBox(width: 10),
                            // Title + EPG / VOD subtitle
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.title(14.5),
                                  ),
                                  if (widget.subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 1.5),
                                    Text(
                                      widget.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: widget.live
                                          ? AppText.note(12, color: AppColors.ink2)
                                          : AppText.meta(12, color: AppColors.ink2),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Locked 2 action buttons: Play/Pause + Close
                            _MiniActionButton(
                              key: const ValueKey('mini-player-play-pause'),
                              icon: widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              tooltip: widget.playing ? 'Duraklat' : 'Oynat',
                              filled: true,
                              onTap: () {
                                AppHaptics.light(context);
                                widget.onPlayPause();
                              },
                            ),
                            const SizedBox(width: 4),
                            _MiniActionButton(
                              key: const ValueKey('mini-player-close'),
                              icon: Icons.close_rounded,
                              tooltip: 'Yayını kapat',
                              filled: false,
                              onTap: () {
                                AppHaptics.light(context);
                                widget.onClose();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Flush 2.5 pt hairline progress bar along bottom edge
                    SizedBox(
                      height: 2.5,
                      width: double.infinity,
                      child: Stack(
                        children: [
                          const Positioned.fill(child: ColoredBox(color: AppColors.line)),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: widget.live && clampedProgress <= 0 ? 1.0 : clampedProgress,
                            child: ColoredBox(
                              color: widget.live && clampedProgress <= 0 ? AppColors.live : AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniVideoThumbnail extends StatelessWidget {
  const _MiniVideoThumbnail({
    required this.width,
    required this.height,
    required this.live,
    required this.title,
    required this.logo,
    required this.controller,
  });

  final double width;
  final double height;
  final bool live;
  final String title;
  final String logo;
  final VideoController? controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.video,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            IgnorePointer(
              child: Video(
                controller: controller!,
                fit: BoxFit.cover,
                controls: NoVideoControls,
              ),
            )
          else
            Center(
              child: ChannelBadge(
                name: title,
                logo: logo,
                size: height * 0.72,
              ),
            ),
          if (live)
            Positioned(
              left: 5,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppColors.videoGlass,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 3.5),
                    Text('CANLI', style: AppText.label(8.5, color: AppColors.ink)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: filled ? 36 : 32,
            height: filled ? 36 : 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? AppColors.surfaceAlt : AppColors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: filled ? 20 : 18,
              color: filled ? AppColors.ink : AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Connects [PlayerSession.instance] to [PhoneMiniPlayerBar] for iPhone portrait & landscape shells.
class PhoneMiniPlayerSlot extends StatelessWidget {
  const PhoneMiniPlayerSlot({
    super.key,
    required this.onExpand,
    this.compact = false,
  });

  final VoidCallback onExpand;
  final bool compact;

  String _formatRemaining(Duration pos, Duration dur) {
    if (dur <= Duration.zero) return '';
    final rem = dur - pos;
    if (rem <= Duration.zero) return 'Bitmek üzere';
    final h = rem.inHours;
    final m = rem.inMinutes % 60;
    if (h > 0) return '$h sa $m dk kaldı';
    if (m > 0) return '$m dk kaldı';
    return '${rem.inSeconds} sn kaldı';
  }

  (String subtitle, double progress) _liveMeta(PlayerEntry entry, List<Programme> programmes) {
    final now = DateTime.now();
    Programme? current;
    for (final p in programmes) {
      if (!p.start.isAfter(now) && p.end.isAfter(now)) {
        current = p;
        break;
      }
    }
    if (current != null) {
      final total = current.end.difference(current.start).inSeconds;
      final done = now.difference(current.start).inSeconds;
      final pct = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
      return (current.title, pct);
    }
    return (entry.group?.isNotEmpty == true ? entry.group! : 'Canlı yayın', 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final session = PlayerSession.instance;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!session.isMiniVisible) return const SizedBox.shrink();
        final entry = session.entry;
        if (entry == null) return const SizedBox.shrink();

        final p = session.player;
        final (cleanTitle, vodSub) = session.live ? (entry.title, entry.group) : playerTitle(entry.title);

        Widget buildBar(bool playing, Duration pos, Duration dur) {
          String subtitle;
          double progress;
          if (session.live) {
            final (sub, pct) = _liveMeta(entry, session.programmes);
            subtitle = sub;
            progress = pct;
          } else {
            final rem = _formatRemaining(pos, dur);
            subtitle = rem.isNotEmpty ? rem : (vodSub ?? '');
            progress = dur > Duration.zero ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
          }

          return PhoneMiniPlayerBar(
            title: cleanTitle,
            subtitle: subtitle,
            live: session.live,
            playing: playing,
            progress: progress,
            logo: entry.logo,
            videoController: session.controller,
            compact: compact,
            onExpand: onExpand,
            onPlayPause: session.playOrPause,
            onClose: session.close,
          );
        }

        if (p == null) {
          return buildBar(session.isPlaying, session.position, session.duration);
        }

        return StreamBuilder<bool>(
          stream: p.stream.playing,
          builder: (_, playingSnap) => StreamBuilder<Duration>(
            stream: p.stream.position,
            builder: (_, posSnap) => StreamBuilder<Duration>(
              stream: p.stream.duration,
              builder: (_, durSnap) => buildBar(
                playingSnap.data ?? p.state.playing,
                posSnap.data ?? p.state.position,
                durSnap.data ?? p.state.duration,
              ),
            ),
          ),
        );
      },
    );
  }
}
