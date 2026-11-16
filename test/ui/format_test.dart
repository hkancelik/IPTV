import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/ui/format.dart';
import 'package:iptv_app/src/ui/tokens.dart';

void main() {
  test('remainingText', () {
    expect(remainingText(const Duration(hours: 1, minutes: 12)), '1 sa 12 dk kaldı');
    expect(remainingText(const Duration(hours: 2)), '2 sa kaldı');
    expect(remainingText(const Duration(minutes: 27)), '27 dk kaldı');
    expect(remainingText(const Duration(seconds: 40)), '1 dk kaldı');
  });
  test('clockTime', () {
    expect(clockTime(const Duration(minutes: 21, seconds: 4)), '21:04');
    expect(clockTime(const Duration(hours: 1, minutes: 2, seconds: 4)), '1:02:04');
    expect(clockTime(Duration.zero), '0:00');
  });
  test('hhmm', () {
    expect(hhmm(DateTime(2026, 11, 16, 9, 5)), '09:05');
  });
  test('greeting follows the hour', () {
    DateTime at(int h) => DateTime(2026, 11, 16, h);
    expect(greeting(at(5)), 'Günaydın');
    expect(greeting(at(11)), 'Günaydın');
    expect(greeting(at(12)), 'İyi günler');
    expect(greeting(at(18)), 'İyi akşamlar');
    expect(greeting(at(22)), 'İyi geceler');
    expect(greeting(at(0)), 'İyi geceler');
    expect(greeting(at(4)), 'İyi geceler');
  });
  test('minutesLabel', () {
    expect(minutesLabel('00:48:12'), '48 dk');
    expect(minutesLabel('01:05:00'), '65 dk');
    expect(minutesLabel('2880'), '48 dk');
    expect(minutesLabel('45 min'), '45 min');
    expect(minutesLabel(''), '');
  });
  test('badgeText', () {
    expect(badgeText('TRT 1'), 'T1');
    expect(badgeText('NTV'), 'NT');
    expect(badgeText('trt belgesel'), 'TB');
    expect(badgeText('X'), 'X');
    expect(badgeText('  '), '?');
    expect(badgeText('ışık tv'), 'IT');
  });
  test('tintFor is stable and stays inside the palette', () {
    expect(tintFor('TRT 1'), tintFor('TRT 1'));
    expect(badgeTints, contains(tintFor('Herhangi bir ad')));
  });
  test('episodeLabel', () {
    expect(episodeLabel('Breaking Bad S01E03'), '1. sezon 3. bölüm');
    expect(episodeLabel('Dark s2e10 - Başlık'), '2. sezon 10. bölüm');
    expect(episodeLabel('Dune'), isNull);
  });
}
