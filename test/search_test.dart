import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/title_utils.dart';

void main() {
  test('foldTr strips Turkish diacritics and case', () {
    expect(foldTr('Kör Nokta ŞİŞE ISIK ığ'), 'kor nokta sise isik ig');
  });

  test('matchesQuery needs every word, ignoring diacritics', () {
    expect(matchesQuery('Kör Nokta |2009|', 'kor nok'), isTrue);
    expect(matchesQuery('Kör Nokta', 'nokta kor'), isTrue);
    expect(matchesQuery('Kör Nokta', 'kor ev'), isFalse);
    expect(matchesQuery('Kör Nokta', '  '), isTrue);
  });
}
