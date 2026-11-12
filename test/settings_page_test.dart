import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/settings_page.dart';
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
    home: Scaffold(body: SettingsPage(info: AccountInfo(status: 'Active', maxConnections: 1), account: _acc, client: XtreamClient(_acc), onLogout: () {})),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the Android default buffer of 15 s is shown as the selected buffer size', (tester) async {
    await _pumpSettings(tester, cacheSecs: 15);
    expect(tester.takeException(), isNull);
    expect(find.text('15 sn'), findsOneWidget);
  });

  testWidgets('a stored value that is not one of the choices does not break the settings page', (tester) async {
    await _pumpSettings(tester, cacheSecs: 45);
    expect(tester.takeException(), isNull);
    expect(find.text('Ön bellek (tampon)'), findsOneWidget);
  });
}
