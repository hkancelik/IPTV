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
    await tester.pumpWidget(_wrap(const VodTimeline(position: Duration(seconds: 5), duration: Duration.zero)));
    expect(find.text('--:--'), findsOneWidget);
    expect(find.textContaining('-0:'), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
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
