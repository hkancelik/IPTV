import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xtream.dart';

/// User preferences, persisted with shared_preferences.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  String audioLang = 'auto'; // auto | tr | en
  String subLang = 'off'; // off | tr | en
  double subtitleScale = 1.0; // subtitle size multiplier: 0.85 | 1.0 | 1.25 | 1.5
  bool hwdec = true;
  String deinterlace = 'auto'; // no | auto | yes
  int cacheSecs = !kIsWeb && Platform.isAndroid ? 15 : 30;
  int skipSecs = 10;
  bool hideAdult = false;
  bool resume = true;
  bool autoNext = true; // start the next episode 10 s after one ends
  bool autoPipOnLeave = true; // iOS: enter system Picture-in-Picture automatically when leaving the app
  bool dedupe = true;
  bool phoneRemote = false; // control the app from a phone's browser (local network)
  bool tvMode = !kIsWeb && Platform.isAndroid; // remote-control friendly UI
  double uiScale = !kIsWeb && Platform.isAndroid ? 0.7 : 1.0; // whole-UI zoom
  String downloadDir = ''; // empty = platform default (PC: ~/Downloads/IPTV, iOS: Documents/IPTV)
  Set<String> hiddenGroups = {}; // "kind:group"
  Map<String, List<String>> groupOrder = {}; // kind name -> category names, user's order

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    audioLang = p.getString('audioLang') ?? audioLang;
    subLang = p.getString('subLang') ?? subLang;
    subtitleScale = p.getDouble('subtitleScale') ?? subtitleScale;
    hwdec = p.getBool('hwdec') ?? hwdec;
    deinterlace = normalizeDeinterlace(p.getString('deinterlace') ?? deinterlace);
    cacheSecs = p.getInt('cacheSecs') ?? cacheSecs;
    skipSecs = p.getInt('skipSecs') ?? skipSecs;
    hideAdult = p.getBool('hideAdult') ?? hideAdult;
    resume = p.getBool('resume') ?? resume;
    autoNext = p.getBool('autoNext') ?? autoNext;
    autoPipOnLeave = p.getBool('autoPipOnLeave') ?? autoPipOnLeave;
    dedupe = p.getBool('dedupe') ?? dedupe;
    phoneRemote = p.getBool('phoneRemote') ?? phoneRemote;
    tvMode = p.getBool('tvMode') ?? tvMode;
    uiScale = p.getDouble('uiScale') ?? uiScale;
    downloadDir = p.getString('downloadDir') ?? downloadDir;
    if (!kIsWeb && Platform.isIOS) {
      tvMode = false;
      if (uiScale < 0.8 || uiScale > 1.0) uiScale = 1.0;
    }
    hiddenGroups = (p.getStringList('hiddenGroups') ?? const <String>[]).toSet();
    try {
      final raw = p.getString('groupOrder');
      if (raw != null) {
        groupOrder = (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, [for (final e in v as List) e as String]));
      }
    } catch (_) {
      groupOrder = {};
    }
    notifyListeners();
  }

  Future<void> update({String? audioLang, String? subLang, double? subtitleScale, bool? hwdec, String? deinterlace, int? cacheSecs, int? skipSecs, bool? hideAdult, bool? resume, bool? autoNext, bool? autoPipOnLeave, bool? dedupe, bool? tvMode, bool? phoneRemote, double? uiScale, String? downloadDir, Set<String>? hiddenGroups, Map<String, List<String>>? groupOrder}) async {
    this.audioLang = audioLang ?? this.audioLang;
    this.subLang = subLang ?? this.subLang;
    this.subtitleScale = subtitleScale ?? this.subtitleScale;
    this.hwdec = hwdec ?? this.hwdec;
    this.deinterlace = deinterlace == null ? this.deinterlace : normalizeDeinterlace(deinterlace);
    this.cacheSecs = cacheSecs ?? this.cacheSecs;
    this.skipSecs = skipSecs ?? this.skipSecs;
    this.hideAdult = hideAdult ?? this.hideAdult;
    this.resume = resume ?? this.resume;
    this.autoNext = autoNext ?? this.autoNext;
    this.autoPipOnLeave = autoPipOnLeave ?? this.autoPipOnLeave;
    this.dedupe = dedupe ?? this.dedupe;
    this.tvMode = tvMode ?? this.tvMode;
    this.phoneRemote = phoneRemote ?? this.phoneRemote;
    this.uiScale = uiScale ?? this.uiScale;
    this.downloadDir = downloadDir ?? this.downloadDir;
    this.hiddenGroups = hiddenGroups ?? this.hiddenGroups;
    this.groupOrder = groupOrder ?? this.groupOrder;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('audioLang', this.audioLang);
    await p.setString('subLang', this.subLang);
    await p.setDouble('subtitleScale', this.subtitleScale);
    await p.setBool('hwdec', this.hwdec);
    await p.setString('deinterlace', this.deinterlace);
    await p.setInt('cacheSecs', this.cacheSecs);
    await p.setInt('skipSecs', this.skipSecs);
    await p.setBool('hideAdult', this.hideAdult);
    await p.setBool('resume', this.resume);
    await p.setBool('autoNext', this.autoNext);
    await p.setBool('autoPipOnLeave', this.autoPipOnLeave);
    await p.setBool('dedupe', this.dedupe);
    await p.setBool('tvMode', this.tvMode);
    await p.setBool('phoneRemote', this.phoneRemote);
    await p.setDouble('uiScale', this.uiScale);
    await p.setString('downloadDir', this.downloadDir);
    await p.setStringList('hiddenGroups', this.hiddenGroups.toList());
    await p.setString('groupOrder', jsonEncode(this.groupOrder));
  }

  /// mpv `alang` value for the chosen audio language ('' = leave to the file's default).
  String get alang => switch (audioLang) { 'tr' => 'tr,tur', 'en' => 'en,eng', _ => '' };
  String get slang => switch (subLang) { 'tr' => 'tr,tur', 'en' => 'en,eng', _ => '' };

  /// Category names in the order the user chose; categories without a saved position keep the provider's
  /// order and come after the ordered ones.
  List<String> orderedGroups(Kind kind, Iterable<String> providerOrder) {
    final saved = groupOrder[kind.name] ?? const <String>[];
    final present = providerOrder.toSet();
    final first = [for (final g in saved) if (present.contains(g)) g];
    final firstSet = first.toSet();
    return [...first, for (final g in providerOrder) if (!firstSet.contains(g)) g];
  }

  static String groupKey(Kind kind, String group) => '${kind.name}:$group';

  static final subtitleSizeOptions = <double, String>{
    0.85: 'Küçük',
    1.0: 'Normal',
    1.25: 'Büyük',
    1.5: 'Çok büyük',
  };

  static const deinterlaceOptions = <String, String>{
    'no': 'Kapalı',
    'auto': 'Otomatik',
    'yes': 'Açık',
  };

  static String normalizeDeinterlace(String raw) => deinterlaceOptions.containsKey(raw) ? raw : 'auto';

  static String nextDeinterlace(String current) => switch (normalizeDeinterlace(current)) {
        'no' => 'auto',
        'auto' => 'yes',
        _ => 'no',
      };

  static final iosUiScaleOptions = <double, String>{0.8: '%80', 0.9: '%90', 1.0: '%100'};
  static final fullUiScaleOptions = <double, String>{
    0.5: '%50',
    0.6: '%60',
    0.7: '%70',
    0.8: '%80',
    0.9: '%90',
    1.0: '%100',
    1.2: '%120',
    1.4: '%140',
  };

  static final adultPattern = RegExp(r'(adult|xxx|18\+|porn|nsfw)', caseSensitive: false);
}
