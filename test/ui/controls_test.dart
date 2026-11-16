import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/tv_text_field.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/controls.dart';

Widget _app(Widget w) => MaterialApp(theme: buildAppTheme(), home: Scaffold(body: Center(child: w)));

void main() {
  testWidgets('Segmented reports the tapped option and marks the current one', (tester) async {
    int? picked;
    await tester.pumpWidget(_app(Segmented<int>(value: 10, options: const {5: '5 sn', 10: '10 sn', 30: '30 sn'}, onChanged: (v) => picked = v)));
    await tester.tap(find.text('30 sn'));
    expect(picked, 30);
    expect(tester.getSemantics(find.text('10 sn')), isSemantics(isSelected: true));
    expect(tester.getSemantics(find.text('30 sn')), isNot(isSemantics(isSelected: true)));
  });
  testWidgets('Segmented with a value outside its options selects nothing and does not throw', (tester) async {
    await tester.pumpWidget(_app(Segmented<int>(value: 45, options: const {10: '10 sn', 15: '15 sn'}, onChanged: (_) {})));
    expect(tester.takeException(), isNull);
  });
  testWidgets('AppSwitch toggles and reports its state to semantics', (tester) async {
    bool? next;
    await tester.pumpWidget(_app(AppSwitch(value: true, onChanged: (v) => next = v)));
    expect(tester.getSemantics(find.byType(AppSwitch)), isSemantics(isToggled: true));
    await tester.tap(find.byType(AppSwitch));
    expect(next, isFalse);
  });
  testWidgets('ClockPill shows hours and minutes', (tester) async {
    await tester.pumpWidget(_app(ClockPill(now: () => DateTime(2026, 11, 16, 9, 5, 40))));
    expect(find.text('09:05'), findsOneWidget);
  });
  testWidgets('SearchField types through RemoteTextField', (tester) async {
    String? typed;
    await tester.pumpWidget(_app(SizedBox(width: 300, child: SearchField(hint: 'Film ara', onChanged: (v) => typed = v))));
    await tester.enterText(find.byType(TextField), 'dune');
    expect(typed, 'dune');
    expect(find.byType(RemoteTextField), findsOneWidget);
  });
  testWidgets('SideItem cuts a long label and shows its count', (tester) async {
    await tester.pumpWidget(_app(SizedBox(
        width: 192,
        child: SideItem(label: 'Çok Uzun Bir Kategori Adı Netflix Filmleri Arşivi', count: '1.248', selected: true, onTap: () {}))));
    expect(tester.takeException(), isNull);
    expect(find.text('1.248'), findsOneWidget);
  });
  test('groupCount', () {
    expect(groupCount(64), '64');
    expect(groupCount(1248), '1.248');
    expect(groupCount(18420), '18.420');
  });
}
