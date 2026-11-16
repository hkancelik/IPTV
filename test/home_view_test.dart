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

/// Fresh, empty library of the demo account. Call before seeding.
Future<void> _reset() async {
  SharedPreferences.setMockInitialValues({});
  await Library.instance.use(_acc);
}

Future<void> _seedHistory({required String url, required String title, required Kind kind, required Duration position, required Duration total}) async {
  await Library.instance.touch(url: url, title: title, logo: '', kind: kind);
  await Library.instance.savePosition(url, position, total);
}

Future<void> _seedFavoriteChannels(List<String> names) async {
  for (var i = 0; i < names.length; i++) {
    await Library.instance.toggleFavorite(Item(id: 'l${i + 1}', name: names[i], logo: '', group: 'Ulusal', kind: Kind.live, url: 'http://x/live/u/p/${i + 1}.ts'));
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
  setUp(_reset);

  testWidgets('an empty library shows the invitation and no continue card', (tester) async {
    await _pumpHome(tester);
    expect(find.textContaining('Burası senin sayfan'), findsOneWidget);
    expect(find.text('Kaldığın yerden'), findsNothing);
    expect(find.text('Son izlediklerin'), findsNothing);
    expect(find.text('Kanallarım'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the newest resumable entry is the continue card, with its time left', (tester) async {
    await _seedHistory(
        url: 'http://x/movie/u/p/1.mkv',
        title: 'Dune |2024| TR-EN',
        kind: Kind.movie,
        position: const Duration(hours: 1, minutes: 34),
        total: const Duration(hours: 2, minutes: 46));
    await _pumpHome(tester);
    expect(find.text('Kaldığın yerden'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('1 sa 12 dk kaldı'), findsOneWidget);
    expect(find.text('Devam et'), findsOneWidget);
  });

  testWidgets('an entry with unknown duration shows no time left', (tester) async {
    await _seedHistory(url: 'http://x/movie/u/p/2.mkv', title: 'Süresiz', kind: Kind.movie, position: const Duration(minutes: 5), total: Duration.zero);
    await _pumpHome(tester);
    expect(find.text('Süresiz'), findsOneWidget);
    expect(find.textContaining('kaldı'), findsNothing);
  });

  testWidgets('older entries go to the recents with their episode and time left', (tester) async {
    await _seedHistory(
        url: 'http://x/series/u/p/13.mkv', title: 'Breaking Bad S01E03', kind: Kind.series, position: const Duration(minutes: 21), total: const Duration(minutes: 48));
    await _seedHistory(url: 'http://x/movie/u/p/1.mkv', title: 'Dune', kind: Kind.movie, position: const Duration(minutes: 30), total: const Duration(hours: 2));
    await _pumpHome(tester);
    expect(find.text('Son izlediklerin'), findsOneWidget);
    expect(find.text('1. sezon 3. bölüm, 27 dk kaldı'), findsOneWidget);
  });

  testWidgets('the greeting names the account', (tester) async {
    await _pumpHome(tester);
    expect(find.textContaining(', Demo'), findsOneWidget);
  });

  testWidgets('favorite channels fill the channel panel', (tester) async {
    await _seedFavoriteChannels(['TRT 1', 'NTV']);
    await _pumpHome(tester);
    expect(find.text('Kanallarım'), findsOneWidget);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('NT'), findsOneWidget);
  });

  testWidgets('an 800 px window stacks the channel panel and does not overflow', (tester) async {
    await _seedFavoriteChannels(['TRT 1', 'Çok Uzun Bir Kanal Adı Şeytanın Ağzından Çıkmış Öyküler ve Diğerleri HD']);
    await _seedHistory(
        url: 'http://x/movie/u/p/1.mkv',
        title: 'Çok Uzun Bir Film Adı: Şeytanın Ağzından Çıkmış Öyküler ve Diğer Başıboş Güzellikler',
        kind: Kind.movie,
        position: const Duration(minutes: 30),
        total: const Duration(hours: 2));
    await _pumpHome(tester);
    tester.view.physicalSize = const Size(800, 600);
    await _settle(tester, 3);
    expect(tester.takeException(), isNull);
  });
}
