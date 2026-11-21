import 'dart:ui' show Color;

import 'tokens.dart';

/// "1 sa 12 dk kaldı", "2 sa kaldı", "27 dk kaldı". Less than a minute counts as one.
String remainingText(Duration left) {
  final minutes = left.inSeconds <= 0 ? 1 : (left.inSeconds / 60).ceil();
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m dk kaldı';
  if (m == 0) return '$h sa kaldı';
  return '$h sa $m dk kaldı';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Player-style time: "21:04", "1:02:04". Negative durations count as zero.
String clockTime(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(sec)}' : '$m:${_two(sec)}';
}

/// Wall-clock "09:05".
String hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// Greeting for the hour of [t].
String greeting(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 12) return 'Günaydın';
  if (h >= 12 && h < 18) return 'İyi günler';
  if (h >= 18 && h < 22) return 'İyi akşamlar';
  return 'İyi geceler';
}

final _clock = RegExp(r'^(\d+):(\d{1,2})(?::(\d{1,2}))?$');
final _digits = RegExp(r'^\d+$');

/// Xtream's episode / movie duration as minutes: "00:48:12" → "48 dk", "2880" (seconds) → "48 dk". Other
/// formats are returned as they are; an empty or zero duration gives ''.
String minutesLabel(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  int? minutes;
  final m = _clock.firstMatch(s);
  if (m != null) {
    final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
    minutes = m.group(3) == null ? a : a * 60 + b; // "48:12" is mm:ss, "00:48:12" is hh:mm:ss
  } else if (_digits.hasMatch(s)) {
    minutes = int.parse(s) ~/ 60;
  }
  if (minutes == null) return s;
  return minutes <= 0 ? '' : '$minutes dk';
}

/// Two-letter badge text: first letters of the first two words, or the first two letters of a single word.
String badgeText(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  String first(String w) => String.fromCharCode(w.runes.first);
  final text = words.length >= 2 ? first(words[0]) + first(words[1]) : String.fromCharCodes(words[0].runes.take(2));
  return text.toUpperCase();
}

/// A stable soft colour pair for a name.
(Color, Color) tintFor(String seed) => badgeTints[seed.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xFFFF) % badgeTints.length];

final _episode = RegExp(r'S(\d+)\s*E(\d+)', caseSensitive: false);

/// "1. sezon 3. bölüm" from an "S01E03" mark in a title, or null.
String? episodeLabel(String title) {
  final m = _episode.firstMatch(title);
  if (m == null) return null;
  return '${int.parse(m.group(1)!)}. sezon ${int.parse(m.group(2)!)}. bölüm';
}

const _trMonthsShort = [
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];

const _trMonthsFull = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// "18 Kas" or "18 Kas 2026" when [includeYear] is true.
String shortDateTr(DateTime date, {bool includeYear = false}) {
  final d = date.day;
  final m = _trMonthsShort[(date.month - 1).clamp(0, 11)];
  return includeYear ? '$d $m ${date.year}' : '$d $m';
}

/// "Kas" for month 1..12.
String shortMonthTr(int month) => _trMonthsShort[(month - 1).clamp(0, 11)];

/// "Kasım 2026".
String monthYearTr(DateTime date) => '${_trMonthsFull[(date.month - 1).clamp(0, 11)]} ${date.year}';

/// "★★★★½" text representation for a 0.5–5.0 rating.
String starGlyphs(double rating) {
  final clamped = rating.clamp(0.5, 5.0);
  final full = clamped.floor();
  final half = (clamped - full) >= 0.5;
  return '${'★' * full}${half ? '½' : ''}';
}

