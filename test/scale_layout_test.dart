import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/home_page.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/shell.dart';
import 'package:iptv_app/src/ui_scale.dart';
import 'package:iptv_app/src/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = Account(name: 'Çok Uzun Bir Hesap Adı Şeytanın Ağzından Çıkmış Öyküler', host: 'http://x', username: 'u', password: 'p');
const _long = 'Çok Uzun Bir Ad: Şeytanın Ağzından Çıkmış Öyküler ve Diğer Başıboş Güzellikler HD';

class _Fake extends XtreamClient {
  _Fake() : super(_acc);
  @override
  Future<List<Item>> live() async => [Item(id: 'l1', name: _long, logo: '', group: _long, kind: Kind.live, url: 'http://x/1.ts')];
  @override
  Future<List<Item>> movies() async => [Item(id: 'm1', name: '$_long |1999| TR', logo: '', group: _long, kind: Kind.movie, url: 'http://x/1.mkv')];
  @override
  Future<List<Item>> series() async => [];
  @override
  Future<List<Programme>> shortEpg(int id) async => [];
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final scale in [0.5, 1.4]) {
    testWidgets('every tab lays out at ${(scale * 100).round()} % in an 800 x 600 window', (t) async {
      SharedPreferences.setMockInitialValues({});
      await Library.instance.use(_acc);
      await Library.instance.touch(url: 'http://x/1.mkv', title: _long, logo: '', kind: Kind.movie);
      await Library.instance.savePosition('http://x/1.mkv', const Duration(minutes: 30), const Duration(hours: 2));
      await Library.instance.toggleFavorite(Item(id: 'l1', name: _long, logo: '', group: _long, kind: Kind.live, url: 'http://x/1.ts'));
      t.view.physicalSize = const Size(800, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      AppSettings.instance
        ..tvMode = false
        ..groupOrder = {}
        ..hiddenGroups = {};
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => UiScale(scale: scale, child: child!),
        home: HomePage(client: _Fake(), info: AccountInfo(status: 'Active', maxConnections: 1), account: _acc),
      ));
      await _settle(t);
      expect(t.takeException(), isNull, reason: 'home');
      for (final k in ['nav-live', 'nav-movies', 'nav-favorites', 'nav-settings']) {
        // At 140 % the menu is taller than the window and scrolls.
        await t.scrollUntilVisible(find.byKey(ValueKey(k)), 40, scrollable: find.descendant(of: find.byType(SideMenu), matching: find.byType(Scrollable)));
        await t.tap(find.byKey(ValueKey(k)));
        await _settle(t);
        expect(t.takeException(), isNull, reason: k);
      }
    });
  }
}
