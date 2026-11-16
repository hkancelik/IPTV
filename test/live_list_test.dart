import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/tokens.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = Account(name: 'Demo', host: 'http://x', username: 'u', password: 'p');

class _FakeClient extends XtreamClient {
  _FakeClient() : super(_acc);

  @override
  Future<List<Item>> live() async => [
        Item(id: 'l1', name: 'TRT 1', logo: '', group: 'Ulusal', kind: Kind.live, url: 'http://x/live/u/p/1.ts'),
        Item(id: 'l2', name: 'NTV', logo: '', group: 'Haber', kind: Kind.live, url: 'http://x/live/u/p/2.ts'),
        Item(id: 'lx', name: 'Kanal X', logo: '', group: 'Yerel', kind: Kind.live, url: 'http://x/live/u/p/x.ts'),
      ];
  @override
  Future<List<Item>> movies() async => [];
  @override
  Future<List<Item>> series() async => [];
  @override
  Future<List<Programme>> shortEpg(int streamId) async {
    if (streamId != 1) return [];
    final now = DateTime.now();
    return [Programme(title: 'Ana Haber', start: now.subtract(const Duration(minutes: 20)), end: now.add(const Duration(minutes: 40)))];
  }
}

class _Pushes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.add(route);
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Pushes> _pumpLive(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await Library.instance.use(_acc);
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  AppSettings.instance
    ..tvMode = false
    ..groupOrder = {}
    ..hiddenGroups = {};
  final pushes = _Pushes();
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    navigatorObservers: [pushes],
    home: HomePage(client: _FakeClient(), info: AccountInfo(status: 'Active', maxConnections: 1), account: _acc),
  ));
  await _settle(tester, 5);
  await tester.tap(find.byKey(const ValueKey('nav-live')));
  await _settle(tester);
  return pushes;
}

void main() {
  testWidgets('channels are numbered by position and carry their badge', (tester) async {
    await _pumpLive(tester);
    expect(find.text('1'), findsWidgets);
    expect(find.text('3'), findsWidgets);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('NT'), findsOneWidget);
  });

  testWidgets('a channel with programme data shows the programme and its time range', (tester) async {
    await _pumpLive(tester);
    expect(find.text('Ana Haber'), findsOneWidget);
    expect(find.textContaining(' – '), findsOneWidget);
  });

  testWidgets('a channel without programme data shows its category and still opens', (tester) async {
    final pushes = await _pumpLive(tester);
    expect(find.text('Yerel'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final before = pushes.routes.length;
    await tester.tap(find.text('Kanal X'));
    expect(pushes.routes.length, before + 1, reason: 'the player route was pushed');
  });

  testWidgets('the edit categories key keeps its tooltip and opens the dialog', (tester) async {
    await _pumpLive(tester);
    await tester.tap(find.byTooltip('Kategorileri düzenle / gizle'));
    await _settle(tester);
    expect(find.text('Kategorileri düzenle'), findsWidgets);
  });

  testWidgets('the channel list leaves room for the focus ring', (tester) async {
    await _pumpLive(tester);
    final list = tester.widget<ListView>(find.byKey(const ValueKey('channel-list')));
    final pad = list.padding!.resolve(TextDirection.ltr);
    expect(pad.left, greaterThanOrEqualTo(AppSizes.scrollPad));
    expect(pad.top, greaterThanOrEqualTo(AppSizes.scrollPad));
  });

  testWidgets('the heart is its own stop and toggles the favorite', (tester) async {
    await _pumpLive(tester);
    await tester.tap(find.byTooltip('Favorilere ekle').first);
    await tester.pump();
    expect(Library.instance.favorites.map((i) => i.name), ['TRT 1']);
  });
}
