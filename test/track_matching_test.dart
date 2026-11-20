import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/library.dart';
import 'package:iptv_app/src/player_session.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('normalizeTrackLang maps ISO 639-2 codes and region tags', () {
    expect(normalizeTrackLang('tur'), 'tr');
    expect(normalizeTrackLang('TR-tr'), 'tr');
    expect(normalizeTrackLang('eng'), 'en');
    expect(normalizeTrackLang('jpn'), 'ja');
    expect(normalizeTrackLang('chi'), 'zh');
    expect(normalizeTrackLang(null), '');
  });

  test('mpvLangList expands normalized Turkish and English tags', () {
    expect(mpvLangList('tur'), 'tr,tur');
    expect(mpvLangList('tr'), 'tr,tur');
    expect(mpvLangList('eng'), 'en,eng');
    expect(mpvLangList('jpn'), 'jpn,ja');
    expect(mpvLangList(null), '');
  });

  test('matchSavedTrack matches by metadata across shifted IDs and avoids false ID fallback', () {
    final tracks = [
      AudioTrack.auto(),
      AudioTrack.no(),
      const AudioTrack('1', 'English', 'eng'),
      const AudioTrack('2', 'Japanese', 'jpn'),
      const AudioTrack('3', 'Türkçe Dublaj', 'tr'),
    ];

    // Saved from an earlier episode where Turkish was id '2' with 'tur'.
    final matched = matchSavedTrack<AudioTrack>(
      tracks,
      const TrackPref(id: '2', language: 'tur', title: 'Türkçe Dublaj'),
      idOf: (t) => t.id,
      languageOf: (t) => t.language,
      titleOf: (t) => t.title,
    );
    expect(matched?.id, '3');

    // If Turkish is missing in a stream, do NOT fall back to id '2' (Japanese).
    final withoutTurkish = tracks.where((t) => t.id != '3').toList();
    final noFalseMatch = matchSavedTrack<AudioTrack>(
      withoutTurkish,
      const TrackPref(id: '2', language: 'tur', title: 'Türkçe Dublaj'),
      idOf: (t) => t.id,
      languageOf: (t) => t.language,
      titleOf: (t) => t.title,
    );
    expect(noFalseMatch, isNull);

    // When a track has no language/title metadata, fall back to its id.
    final untagged = [
      AudioTrack.auto(),
      AudioTrack.no(),
      const AudioTrack('1', null, null),
      const AudioTrack('2', null, null),
    ];
    final byId = matchSavedTrack<AudioTrack>(
      untagged,
      const TrackPref(id: '2'),
      idOf: (t) => t.id,
      languageOf: (t) => t.language,
      titleOf: (t) => t.title,
    );
    expect(byId?.id, '2');
  });
}
