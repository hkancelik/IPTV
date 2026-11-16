import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/settings_page.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/controls.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = Account(name: 'Demo', host: 'http://x', username: 'u', password: 'p');

Future<void> _pumpSettings(WidgetTester tester, {required int cacheSecs}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final before = AppSettings.instance.cacheSecs;
  addTearDown(() => AppSettings.instance.cacheSecs = before);
  AppSettings.instance
    ..tvMode = false
    ..phoneRemote = false
    ..uiScale = 1.0
    ..cacheSecs = cacheSecs;
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: SettingsPage(info: AccountInfo(status: 'Active', maxConnections: 1), account: _acc, client: XtreamClient(_acc), onLogout: () {})),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the Android default buffer of 15 s is shown as the selected buffer size', (tester) async {
    await _pumpSettings(tester, cacheSecs: 15);
    expect(tester.takeException(), isNull);
    expect(find.descendant(of: find.byKey(const ValueKey('setting-cacheSecs')), matching: find.text('15 sn')), findsOneWidget);
  });

  testWidgets('a stored value that is not one of the choices does not break the settings page', (tester) async {
    await _pumpSettings(tester, cacheSecs: 45);
    expect(tester.takeException(), isNull);
    expect(find.text('Ön bellek (tampon)'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('setting-cacheSecs')), matching: find.text('Özel')), findsOneWidget);
  });

  testWidgets('a section key scrolls its section into view', (tester) async {
    await _pumpSettings(tester, cacheSecs: 15);
    expect(find.text('Tam ekrandan çık / geri').hitTestable(), findsNothing);
    await tester.tap(find.widgetWithText(SideItem, 'Kısayollar'));
    await tester.pumpAndSettle();
    expect(find.text('Tam ekrandan çık / geri').hitTestable(), findsOneWidget);
  });

  testWidgets('tapping a switch row writes the setting', (tester) async {
    await _pumpSettings(tester, cacheSecs: 15);
    final before = AppSettings.instance.hwdec;
    addTearDown(() => AppSettings.instance.hwdec = before);
    await tester.tap(find.text('Donanım hızlandırma'));
    await tester.pump();
    expect(AppSettings.instance.hwdec, !before);
  });

  testWidgets('the skip choice is a segmented control that writes the setting', (tester) async {
    await _pumpSettings(tester, cacheSecs: 15);
    final before = AppSettings.instance.skipSecs;
    addTearDown(() => AppSettings.instance.skipSecs = before);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('setting-skipSecs')), matching: find.text('30 sn')));
    await tester.pump();
    expect(AppSettings.instance.skipSecs, 30);
  });

  testWidgets('nothing overflows at 800 x 600', (tester) async {
    await _pumpSettings(tester, cacheSecs: 15);
    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
