import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = Account(name: 'Demo', host: 'http://x', username: 'u', password: 'p');

class _FakeClient extends XtreamClient {
  _FakeClient() : super(_acc);

  @override
  Future<List<Item>> live() async => [];
  @override
  Future<List<Item>> movies() async => [];
  @override
  Future<List<Item>> series() async => [];
  @override
  Future<List<Programme>> shortEpg(int streamId) async => [];
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _seedFavorites({List<String> channels = const [], List<String> movies = const []}) async {
  var n = 0;
  for (final c in channels) {
    await Library.instance.toggleFavorite(Item(id: 'l${++n}', name: c, logo: '', group: 'Ulusal', kind: Kind.live, url: 'http://x/live/u/p/$n.ts'));
  }
  for (final m in movies) {
    await Library.instance.toggleFavorite(Item(id: 'm${++n}', name: m, logo: '', group: 'Sinema', kind: Kind.movie, url: 'http://x/movie/u/p/$n.mkv'));
  }
}

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  AppSettings.instance
    ..tvMode = false
    ..groupOrder = {}
    ..hiddenGroups = {};
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: HomePage(client: _FakeClient(), info: AccountInfo(status: 'Active', maxConnections: 1), account: _acc),
  ));
  await _settle(tester, 5);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Library.instance.use(_acc);
  });

  testWidgets('favorites are grouped by kind and empty groups are not drawn', (tester) async {
    await _seedFavorites(channels: ['TRT 1'], movies: ['Arrival |2016| EN']);
    await _pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('nav-favorites')));
    await _settle(tester);
    expect(find.text('Kanallar'), findsOneWidget);
    expect(find.text('Filmler'), findsNWidgets(2), reason: 'the section heading and the menu item');
    expect(find.text('Diziler'), findsOneWidget, reason: 'only the menu item');
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('TRT 1'), findsOneWidget);
  });

  testWidgets('no favorites shows the existing hint', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('nav-favorites')));
    await _settle(tester);
    expect(find.textContaining('Henüz favori yok'), findsOneWidget);
  });
}
