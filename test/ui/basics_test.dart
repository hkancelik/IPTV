import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/basics.dart';
import 'package:iptv_app/src/ui/focus_ring.dart';

Widget _app(Widget w) => MaterialApp(theme: buildAppTheme(), home: Scaffold(body: Center(child: w)));

void main() {
  testWidgets('FocusRing reports focus to its builder and activates on Enter', (tester) async {
    var taps = 0;
    bool? seen;
    await tester.pumpWidget(_app(FocusRing(
        autofocus: true,
        onTap: () => taps++,
        builder: (_, focused, _) {
          seen = focused;
          return const SizedBox(width: 80, height: 44);
        })));
    await tester.pump();
    expect(seen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 1);
  });
  testWidgets('FocusRing keeps its layout size when focus arrives', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(_app(FocusRing(focusNode: node, onTap: () {}, child: const SizedBox(width: 80, height: 44))));
    final before = tester.getRect(find.byType(FocusRing));
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(FocusRing)), before);
  });
  testWidgets('a disabled AppButton does not fire and does not take focus', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(_app(AppButton(label: 'Sil', onPressed: null, focusNode: node, autofocus: true)));
    await tester.pump();
    await tester.tap(find.text('Sil'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(node.hasFocus, isFalse);
  });
  testWidgets('ChannelBadge shows the abbreviation without a logo and never throws on odd names', (tester) async {
    for (final name in ['TRT 1', '', '7', 'Çok Uzun Kanal Adı Burada']) {
      await tester.pumpWidget(_app(ChannelBadge(name: name)));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(_app(const ChannelBadge(name: 'TRT 1')));
    expect(find.text('T1'), findsOneWidget);
  });
  testWidgets('ProgressBar clamps odd values', (tester) async {
    for (final v in [-1.0, 0.0, 0.5, 2.0, double.nan]) {
      await tester.pumpWidget(_app(SizedBox(width: 200, child: ProgressBar(value: v))));
      expect(tester.takeException(), isNull);
    }
  });
}
