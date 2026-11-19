import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/player_chrome.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/xtream.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(backgroundColor: Colors.black, body: Align(alignment: Alignment.bottomCenter, child: SizedBox(width: 1200, child: w))),
    );
Programme p(String t, DateTime s, DateTime e) => Programme(title: t, start: s, end: e);

void main() {
  setUp(() {});

  testWidgets('the timeline shows elapsed time and time left', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const VodTimeline(position: Duration(minutes: 21, seconds: 4), duration: Duration(minutes: 48, seconds: 12))));
    expect(find.text('21:04'), findsOneWidget);
    expect(find.text('-27:08'), findsOneWidget);
  });

  testWidgets('an unknown duration shows no time left and a disabled bar', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var seeks = 0;
    await tester.pumpWidget(_wrap(VodTimeline(position: const Duration(seconds: 5), duration: Duration.zero, onSeek: (_) => seeks++)));
    expect(find.text('--:--'), findsOneWidget);
    expect(find.textContaining('-0:'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('vod-timeline-track')));
    await tester.drag(find.byKey(const ValueKey('vod-timeline-track')), const Offset(80, 0));
    expect(seeks, 0);
  });

  test('scrubRateFor delivers second-by-second precision on long movies and accelerates on fast swipes', () {
    // 2-hour movie on a narrow ~215 pt iPhone portrait track (linear scale would be ~33.5 s/pt).
    final (slowRate, slowGear) = scrubRateFor(
      durationSeconds: 7200,
      trackWidth: 215,
      speedPxPerSec: 30,
      verticalOffsetPx: 0,
    );
    expect(slowGear, ScrubPrecision.normal);
    expect(slowRate, lessThanOrEqualTo(0.35));

    // Pulling finger vertically locks finer Apple-style gears regardless of horizontal speed.
    final (quarterRate, quarterGear) = scrubRateFor(
      durationSeconds: 7200,
      trackWidth: 215,
      speedPxPerSec: 300,
      verticalOffsetPx: 55,
    );
    expect(quarterGear, ScrubPrecision.quarter);
    expect(quarterRate, lessThanOrEqualTo(0.45));

    final (fineRate, fineGear) = scrubRateFor(
      durationSeconds: 7200,
      trackWidth: 215,
      speedPxPerSec: 400,
      verticalOffsetPx: 95,
    );
    expect(fineGear, ScrubPrecision.fine);
    expect(fineRate, lessThanOrEqualTo(0.15));

    // Fast horizontal swipe on the bar ramps up so long jumps stay easy.
    final (fastRate, _) = scrubRateFor(
      durationSeconds: 7200,
      trackWidth: 215,
      speedPxPerSec: 520,
      verticalOffsetPx: 0,
    );
    expect(fastRate, greaterThan(20));
  });

  testWidgets('precision VodTimeline scrubs second-by-second relative to current position and commits once on release', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final committed = <Duration>[];
    final updates = <Duration>[];
    const start = Duration(minutes: 1, seconds: 12);
    const total = Duration(hours: 2, seconds: 1);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: 345,
            child: VodTimeline(
              position: start,
              duration: total,
              precisionScrub: true,
              onScrubUpdate: (target, _, _) => updates.add(target),
              onScrubEnd: committed.add,
            ),
          ),
        ),
      ),
    ));

    final track = find.byKey(const ValueKey('vod-timeline-track'));

    // Single tap on a precision touch bar does not abruptly jump minutes ahead.
    await tester.tap(track);
    await tester.pump();
    expect(committed, isEmpty);

    // Gentle relative drag (18 pt over 9 slow frames) moves only a few seconds, NOT minutes!
    final center = tester.getCenter(track);
    final gesture = await tester.startGesture(center);
    for (var i = 0; i < 9; i++) {
      await gesture.moveBy(const Offset(2, 0), timeStamp: Duration(milliseconds: (i + 1) * 45));
      await tester.pump();
    }
    // No seek committed yet while finger is still down.
    expect(committed, isEmpty);
    expect(updates, isNotEmpty);

    await gesture.up();
    await tester.pump();

    expect(committed, hasLength(1));
    final deltaSecs = (committed.single - start).inSeconds;
    expect(deltaSecs, greaterThanOrEqualTo(3));
    expect(deltaSecs, lessThanOrEqualTo(15));
  });

  testWidgets('desktop VodTimeline still allows clicking the track directly', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Duration? sought;
    await tester.pumpWidget(_wrap(VodTimeline(
      position: Duration.zero,
      duration: const Duration(minutes: 60),
      precisionScrub: false,
      onSeek: (d) => sought = d,
    )));

    await tester.tap(find.byKey(const ValueKey('vod-timeline-track')));
    await tester.pump();
    expect(sought, isNotNull);
    expect(sought!.inMinutes, inInclusiveRange(28, 32));
  });

  testWidgets('live info shows the channel, the current and the next programme, and its neighbours', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 16, 21, 47);
    await tester.pumpWidget(_wrap(LiveInfo(index: 11, name: 'TRT Spor', now: () => now, prevName: 'TRT 1', nextName: 'NTV', programmes: [
      p('Stadyum', DateTime(2026, 11, 16, 21), DateTime(2026, 11, 16, 22, 30)),
      p('Spor Haberleri', DateTime(2026, 11, 16, 22, 30), DateTime(2026, 11, 16, 23)),
    ])));
    expect(find.text('12'), findsOneWidget);
    expect(find.text('TRT Spor'), findsOneWidget);
    expect(find.text('Canlı'), findsOneWidget);
    expect(find.text('Stadyum'), findsOneWidget);
    expect(find.text('21:00 – 22:30'), findsOneWidget);
    expect(find.textContaining('Sırada 22:30'), findsOneWidget);
    expect(find.text('TRT 1'), findsOneWidget);
    expect(find.text('NTV'), findsOneWidget);
  });

  testWidgets('live info without programme data shows only the channel', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const LiveInfo(index: 0, name: 'Kanal X')));
    expect(find.text('Kanal X'), findsOneWidget);
    expect(find.textContaining('Sırada'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the title pill goes back', (tester) async {
    var back = 0;
    await tester.pumpWidget(_wrap(PlayerTitlePill(onBack: () => back++, title: 'Breaking Bad', subtitle: '1. sezon 3. bölüm')));
    await tester.tap(find.byTooltip('Geri'));
    expect(back, 1);
    expect(find.text('1. sezon 3. bölüm'), findsOneWidget);
  });

  test('playerTitle splits a series episode into title and season line', () {
    expect(playerTitle('Breaking Bad S01E03'), ('Breaking Bad', '1. sezon 3. bölüm'));
    expect(playerTitle('Arrival |2016| EN'), ('Arrival', null));
  });
}
