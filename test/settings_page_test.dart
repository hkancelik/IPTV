import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/settings_page.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/controls.dart';
import 'package:iptv_app/src/ui_scale.dart';
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

  testWidgets('hides Kısayollar and TV mode on iOS while keeping phone remote', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AppSettings.instance
      ..tvMode = false
      ..phoneRemote = false
      ..uiScale = 1.0
      ..subtitleScale = 1.0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
      home: Scaffold(
        body: SettingsPage(
          info: AccountInfo(status: 'Active', maxConnections: 1),
          account: _acc,
          client: XtreamClient(_acc),
          onLogout: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Kısayollar'), findsNothing);
    expect(find.text('Tam ekrandan çık / geri'), findsNothing);
    expect(find.text('Kumanda (TV) modu'), findsNothing);
    expect(find.text('Telefonu kumanda yap'), findsWidgets);
    expect(find.text('Telefonla kumanda et'), findsOneWidget);
  });

  testWidgets('iOS UI scale picker excludes breaking scales and keeps %80/%90/%100', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final beforeScale = AppSettings.instance.uiScale;
    addTearDown(() => AppSettings.instance.uiScale = beforeScale);
    AppSettings.instance
      ..tvMode = false
      ..phoneRemote = false
      ..uiScale = 1.0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
      home: Scaffold(
        body: SettingsPage(
          info: AccountInfo(status: 'Active', maxConnections: 1),
          account: _acc,
          client: XtreamClient(_acc),
          onLogout: () {},
        ),
      ),
    ));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('setting-uiScale')));
    await tester.tap(find.byKey(const ValueKey('setting-uiScale')));
    await tester.pumpAndSettle();

    expect(find.text('%50'), findsNothing);
    expect(find.text('%60'), findsNothing);
    expect(find.text('%70'), findsNothing);
    expect(find.text('%120'), findsNothing);
    expect(find.text('%140'), findsNothing);
    expect(find.text('%80'), findsOneWidget);
    expect(find.text('%90'), findsOneWidget);
    expect(find.text('%100'), findsWidgets);

    await tester.tap(find.text('%90'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.uiScale, 0.9);
  });

  testWidgets('subtitle size segmented control writes the setting', (tester) async {
    await _pumpSettings(tester, cacheSecs: 15);
    final before = AppSettings.instance.subtitleScale;
    addTearDown(() => AppSettings.instance.subtitleScale = before);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('setting-subtitleScale')), matching: find.text('Büyük')));
    await tester.pump();
    expect(AppSettings.instance.subtitleScale, 1.25);
  });

  testWidgets('iPhone landscape SettingsPage lays out without overflow at 0.8 and 0.9 scale', (tester) async {
    SharedPreferences.setMockInitialValues({});
    for (final scale in [0.8, 0.9, 1.0]) {
      tester.view.physicalSize = const Size(852, 393);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 0, bottom: 21, left: 59, right: 59);
      tester.view.viewPadding = const FakeViewPadding(top: 0, bottom: 21, left: 59, right: 59);
      addTearDown(tester.view.reset);
      AppSettings.instance
        ..tvMode = false
        ..phoneRemote = false
        ..uiScale = scale;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
        builder: (_, child) => UiScale(scale: scale, child: child!),
        home: Scaffold(
          body: SettingsPage(
            info: AccountInfo(status: 'Active', maxConnections: 1),
            account: _acc,
            client: XtreamClient(_acc),
            onLogout: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at landscape scale $scale');
    }
  });
}
