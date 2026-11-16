import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/shell.dart';

Widget _app(Widget w) => MaterialApp(theme: buildAppTheme(), home: Scaffold(body: w));

const long = 'Çok Uzun Bir Hesap Adı Şeytanın Ağzından Çıkmış Öyküler ve Diğer Başıboş Güzellikler';

void main() {
  testWidgets('SideMenu reports the tapped section and marks the current one', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int? picked;
    await tester.pumpWidget(_app(SideMenu(selected: 0, onSelect: (i) => picked = i, accountName: 'Hakan', onAccount: () {})));
    await tester.tap(find.byKey(const ValueKey('nav-movies')));
    expect(picked, 2);
    for (final l in navLabels) {
      expect(find.text(l), findsOneWidget);
    }
    expect(tester.getSemantics(find.byKey(const ValueKey('nav-home'))), isSemantics(isSelected: true));
  });
  testWidgets('the account chip switches user', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var switched = 0;
    await tester.pumpWidget(_app(SideMenu(selected: 0, onSelect: (_) {}, accountName: 'Hakan', onAccount: () => switched++)));
    await tester.tap(find.byKey(const ValueKey('nav-account')));
    expect(switched, 1);
    expect(find.byTooltip('Kullanıcı değiştir'), findsOneWidget);
  });
  testWidgets('in a narrow window the menu keeps only icons and does not overflow', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(SideMenu(selected: 0, onSelect: (_) {}, accountName: long, onAccount: () {})));
    expect(tester.takeException(), isNull);
    expect(find.text('Ana sayfa'), findsNothing);
    expect(find.byKey(const ValueKey('nav-home')), findsOneWidget);
  });
  testWidgets('PageHeader cuts a long title instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(PageHeader(title: long, subtitle: '64 kanal', actions: const [SizedBox(width: 300, height: 44)])));
    expect(tester.takeException(), isNull);
  });
}
