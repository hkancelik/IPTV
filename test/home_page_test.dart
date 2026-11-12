import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = Account(name: 'Demo', host: 'http://x', username: 'u', password: 'p');

class _FakeClient extends XtreamClient {
  _FakeClient({this.moviesError}) : super(_acc);

  final Object? moviesError;

  @override
  Future<List<Item>> live() async => [];

  @override
  Future<List<Item>> movies() async {
    if (moviesError != null) throw moviesError!;
    return [Item(id: 'm1', name: 'Batman', logo: '', group: 'Aksiyon', kind: Kind.movie, url: 'u')];
  }

  @override
  Future<List<Item>> series() async => [Item(id: 's1', name: 'Dark', logo: '', group: 'Dram', kind: Kind.series, seriesId: 1)];
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpHome(WidgetTester tester, XtreamClient client) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  AppSettings.instance
    ..tvMode = false
    ..groupOrder = {}
    ..hiddenGroups = {};
  await tester.pumpWidget(MaterialApp(home: HomePage(client: client, info: AccountInfo(status: 'Active', maxConnections: 1), account: _acc)));
  await _settle(tester, 5);
}

/// The content search box (the second text field; the first one filters the category sidebar).
String _searchText(WidgetTester tester) =>
    tester.widget<EditableText>(find.descendant(of: find.byType(TextField).at(1), matching: find.byType(EditableText))).controller.text;

void main() {
  testWidgets('switching tabs empties the search box together with the filter', (tester) async {
    await _pumpHome(tester, _FakeClient());
    await tester.tap(find.byIcon(Icons.movie));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).at(1), 'bat');
    await _settle(tester, 2);
    expect(_searchText(tester), 'bat');

    await tester.tap(find.byIcon(Icons.video_library));
    await _settle(tester);

    expect(find.text('Dark'), findsOneWidget, reason: 'the series list is not filtered');
    expect(_searchText(tester), '', reason: 'so the search box must not still show the old query');
  });

  testWidgets('a list that fails to load shows the error with a retry button, whatever the failure is', (tester) async {
    await _pumpHome(tester, _FakeClient(moviesError: StateError('boom')));
    await tester.tap(find.byIcon(Icons.movie));
    await _settle(tester);

    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text('Sonuç yok'), findsNothing);
  });
}
