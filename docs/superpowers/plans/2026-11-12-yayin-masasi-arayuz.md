# Yayın Masası Arayüzü Implementation Plan

> **REDDEDİLDİ (2026-11-16).** Kullanıcı bu tasarımı beğenmedi. Bu belgeyi uygulama. Geçerli tasarım: `docs/superpowers/specs/2026-11-16-gunduz-arayuz-design.md`, plan: `docs/superpowers/plans/2026-11-16-gunduz-arayuz.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Uygulamanın bütün ekranlarını, işlev kaybı olmadan "Yayın Masası" tasarım diline taşımak.

**Architecture:** Önce `lib/src/ui/` altında renk, yazı ve ölçü belirteçleri ile ortak bileşenler kurulur. Sonra ekranlar tek tek bu bileşenlerle yeniden yazılır. Veri katmanı (`xtream.dart`, `library.dart`, `accounts.dart`, `settings.dart`) ve oynatma mantığı değişmez. Her görev kendi testleriyle biter ve uygulama her görevden sonra çalışır durumda kalır.

**Tech Stack:** Flutter (Dart SDK ^3.13.7), Material 3 üstünde özel tema, `media_kit`, `flutter_test`. Yeni paket yok. İki gömülü yazı tipi: Archivo (değişken) ve IBM Plex Mono.

**Spec:** `docs/superpowers/specs/2026-11-12-yayin-masasi-arayuz-design.md`. Ekran mockup'ları: `docs/superpowers/specs/yayin-masasi-mockups/*.dc.html` (1280×720, ölçüler satır içi `style` içinde). Her görevde ilgili mockup dosyasını ve belgedeki ekran bölümünü oku.

## Başlamadan önce

- Flutter yol üzerinde değil. Her komuttan önce: `export PATH="$HOME/development/flutter/bin:$PATH"`.
- Çalışma `master` üzerinde değil, `feat/yayin-masasi-ui` dalında yapılır.
- Depoda kullanıcıya ait kaydedilmemiş değişiklikler var. Bunlara dokunma ve `git add` ile ekleme: `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/drawable-xhdpi/`, `assets/icon/banner.png`, `assets/icon/banner.svg`, `info:`.
- Bu belgelerin kendisi (`docs/superpowers/`) henüz commit edilmedi. İlk commit'e dahil et.
- Görev sonlarındaki commit adımları için kullanıcıdan bir kez onay al. Commit iletileri depodaki biçimi izler (`feat: …`, `fix: …`, İngilizce).
- Yazı tipi dosyalarını indirmek için kullanıcıdan izin iste (Görev 1).

## Global Constraints

- Parlama, bulanıklık, gölge, renk geçişi yok: `BackdropFilter`, `BoxShadow`, `ShaderMask`, `LinearGradient` kullanılmaz. Tek istisna yok.
- Kehribar `#FFB020` yalnızca odak, konum çubuğu, saat, kanal numarası ve kalan süre içindir.
- Kırmızı `#FF3B30` yalnızca etkin bölüm tuşu, `PGM` ve `CANLI` etiketi, "şimdi" çizgisi, seçili yan liste ışığı ve hata durumu içindir.
- Köşe yarıçapı 4 (etiket 2, tuş başlığı 3). Yuvarlak düğme yok.
- En küçük metin 12 piksel. En küçük tıklama alanı 44×44 (üst çubuk tuşu yüksekliği 40).
- Odak çerçevesi görsel kutularda 4 piksel, diğer her yerde 3 piksel, renk `#FFB020`. Odak gelince düzen kaymaz.
- Renk ve yazı değerleri yalnızca `AppColors` ve `AppText` üzerinden kullanılır. Ekran dosyalarında `Color(0x…)` ya da `Colors.…` (saydam ve QR'ın beyazı dışında) kalmaz.
- Listeler `builder` ile ve sabit satır yüksekliğiyle kurulur. Odak değişimi `HomePage` üzerinde `setState` çağırmaz.
- Mevcut Türkçe metinler korunur. Değişenler belgede "Metin değişiklikleri" tablosundadır.
- Yeni paket eklenmez. `UiScale` %50–%140 arası her ölçekte çalışır.
- Her görevin sonunda `flutter analyze` hatasız, `flutter test` tamamı geçer.

## Review Focus

Belgenin ima ettiği ama gözden kaçması kolay beş durum. Her birinin testi parantezdeki göreve eklendi.

1. **Program bilgisi olmayan kanal** (boş liste ya da `streamId` yok): satır kategori adını gösteren tek blokla çizilir, dönen gösterge kalmaz, kanal yine açılır. (Görev 7)
2. **Çok uzun ad ve dar alan**: 80 karakterlik Türkçe ad, 800×600 pencere, %50 ve %140 ölçek. Hiçbir yerde taşma hatası (`RenderFlex overflowed`) çıkmaz, metin üç noktayla kesilir. (Görev 3 ve 12'de test, Görev 13'te elle)
3. **Boş kütüphane**: geçmiş ve favori yokken ana sayfa çökmez, ana ekran çizilmez, davet metni görünür. (Görev 5)
4. **Gece yarısını aşan ve pencere dışında kalan program**: 23:00–00:30 doğru yere oturur, pencere başlamadan biten program çizilmez, sıfır ya da eksi genişlikte blok oluşmaz. (Görev 7)
5. **Süresi bilinmeyen içerik** (`durationMs == 0`, canlı kanal geçmişi): kalan süre ve konum çubuğu yazılmaz, sıfıra bölme ya da `-00:00:00` görünmez. (Görev 5, 10)

---

## Dosya yapısı

Yeni dosyalar:

| Dosya | Sorumluluk |
|---|---|
| `lib/src/ui/tokens.dart` | `AppColors`, `AppSizes`, `AppText` |
| `lib/src/ui/format.dart` | Zaman kodu, kanal numarası, kalan süre, saat biçimleri |
| `lib/src/ui/app_theme.dart` | `buildAppTheme()` |
| `lib/src/ui/focus_box.dart` | `FocusBox` |
| `lib/src/ui/app_key.dart` | `AppKey`, `Tag`, `KeyCap` |
| `lib/src/ui/controls.dart` | `ProgressLine`, `AppSwitch`, `Segmented`, `LevelMeter`, `ClockText` |
| `lib/src/ui/brand.dart` | `BrandMark`, `GridBackground` |
| `lib/src/ui/screen_tile.dart` | `ScreenTile` |
| `lib/src/ui/shell.dart` | `TopBar`, `SideKey`, `InfoBar` |
| `lib/src/guide_grid.dart` | Yayın akışı tablosu ve yerleşim hesabı |
| `lib/src/player_chrome.dart` | Oynatıcının `Player` gerektirmeyen görsel parçaları |
| `assets/fonts/` | `Archivo-Variable.ttf`, `IBMPlexMono-Medium.ttf`, `IBMPlexMono-SemiBold.ttf`, lisans metinleri |

Değişen dosyalar: `pubspec.yaml`, `lib/main.dart`, `lib/src/home_page.dart`, `lib/src/detail_page.dart`, `lib/src/player_page.dart`, `lib/src/login_page.dart`, `lib/src/remote_entry.dart`, `lib/src/settings_page.dart`, `lib/src/epg_widgets.dart`, `lib/src/poster_card.dart`, `lib/src/tv_text_field.dart`, `lib/src/xtream.dart` (yalnızca `shortEpg` sınırı), `README.md`.

Silinen dosya: `lib/src/focus_frame.dart` (Görev 13).

---

### Task 1: Yazı tipleri, belirteçler ve tema

**Files:**
- Create: `assets/fonts/Archivo-Variable.ttf`, `assets/fonts/IBMPlexMono-Medium.ttf`, `assets/fonts/IBMPlexMono-SemiBold.ttf`, `assets/fonts/OFL-Archivo.txt`, `assets/fonts/OFL-IBMPlexMono.txt`
- Create: `lib/src/ui/tokens.dart`, `lib/src/ui/format.dart`, `lib/src/ui/app_theme.dart`
- Modify: `pubspec.yaml` (`flutter:` altına `fonts:`), `lib/main.dart:35-54`
- Test: `test/ui/tokens_test.dart`, `test/ui/format_test.dart`

**Interfaces:**
- Produces:
  - `abstract final class AppColors` — belgedeki "Renkler" tablosundaki her ad için `static const Color`: `ground`, `gridLine`, `panel`, `key`, `panelHi`, `well`, `line`, `keyBorder`, `lineHi`, `dim`, `text`, `text2`, `text3`, `amber`, `amberTint`, `red`, `onRed`, `buffered`, ayrıca `wellOverlay` (`well`, alfa 0.92).
  - `abstract final class AppSizes` — `radius = 4.0`, `tagRadius = 2.0`, `capRadius = 3.0`, `focus = 3.0`, `tileFocus = 4.0`, `page = 28.0`, `gap = 12.0`, `keyGap = 8.0`, `rowGap = 4.0`, `keyHeight = 44.0`, `navKeyHeight = 40.0`, `sideWidth = 196.0`, `labelBar = 28.0`, `infoBar = 76.0`.
  - `abstract final class AppText`:
    - `static TextStyle display(double size, {Color color = AppColors.text})` — Archivo, `wdth` 125, `wght` 800, satır yüksekliği 1.1.
    - `static TextStyle body(double size, {int weight = 600, Color color = AppColors.text})` — Archivo, `wdth` 100.
    - `static TextStyle label(double size, {int weight = 600, Color color = AppColors.text})` — Archivo, `wdth` 88.
    - `static TextStyle heading({Color color = AppColors.text3})` — Archivo, `wdth` 112, `wght` 600, boyut 14.
    - `static TextStyle mono(double size, {int weight = 600, Color color = AppColors.amber})` — IBM Plex Mono, `FontFeature.tabularFigures()`.
  - `ThemeData buildAppTheme()`.
  - `format.dart`: `String timecode(Duration d, {bool negative = false})`, `String channelNo(int index)`, `String remainingText(Duration left)`, `String hhmm(DateTime t)`.

- [ ] **Step 1: Kullanıcıdan izin alıp yazı tiplerini indir**

```bash
mkdir -p assets/fonts
curl -fL -o assets/fonts/Archivo-Variable.ttf "https://github.com/google/fonts/raw/main/ofl/archivo/Archivo%5Bwdth%2Cwght%5D.ttf"
curl -fL -o assets/fonts/IBMPlexMono-Medium.ttf "https://github.com/google/fonts/raw/main/ofl/ibmplexmono/IBMPlexMono-Medium.ttf"
curl -fL -o assets/fonts/IBMPlexMono-SemiBold.ttf "https://github.com/google/fonts/raw/main/ofl/ibmplexmono/IBMPlexMono-SemiBold.ttf"
curl -fL -o assets/fonts/OFL-Archivo.txt "https://github.com/google/fonts/raw/main/ofl/archivo/OFL.txt"
curl -fL -o assets/fonts/OFL-IBMPlexMono.txt "https://github.com/google/fonts/raw/main/ofl/ibmplexmono/OFL.txt"
file assets/fonts/*.ttf
```

Expected: üç dosya da "TrueType Font data". Bir adres 404 dönerse aynı dosyayı fonts.google.com'daki aile sayfasından al, yine kullanıcıya sor.

- [ ] **Step 2: `pubspec.yaml` içine yazı tiplerini ekle**

```yaml
  fonts:
    - family: Archivo
      fonts:
        - asset: assets/fonts/Archivo-Variable.ttf
    - family: IBM Plex Mono
      fonts:
        - asset: assets/fonts/IBMPlexMono-Medium.ttf
          weight: 500
        - asset: assets/fonts/IBMPlexMono-SemiBold.ttf
          weight: 600
```

- [ ] **Step 3: Başarısız testleri yaz**

`test/ui/tokens_test.dart`:

```dart
test('display style is wide extra-bold Archivo', () {
  final s = AppText.display(38);
  expect(s.fontFamily, 'Archivo');
  expect(s.fontSize, 38);
  expect(s.fontVariations, containsAll(const [FontVariation('wdth', 125), FontVariation('wght', 800)]));
});
test('label style is the narrow width', () {
  expect(AppText.label(15).fontVariations, contains(const FontVariation('wdth', 88)));
});
test('mono style is IBM Plex Mono with tabular figures, amber by default', () {
  final s = AppText.mono(22);
  expect(s.fontFamily, 'IBM Plex Mono');
  expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
  expect(s.color, AppColors.amber);
});
test('theme carries no Material purple', () {
  final t = buildAppTheme();
  expect(t.scaffoldBackgroundColor, AppColors.ground);
  expect(t.colorScheme.primary, AppColors.amber);
  expect(t.colorScheme.error, AppColors.red);
  expect(t.colorScheme.surface, AppColors.panel);
});
test('palette values match the spec', () {
  expect(AppColors.ground, const Color(0xFF0E1011));
  expect(AppColors.amber, const Color(0xFFFFB020));
  expect(AppColors.red, const Color(0xFFFF3B30));
  expect(AppColors.well, const Color(0xFF050606));
});
```

`test/ui/format_test.dart`:

```dart
test('timecode', () {
  expect(timecode(const Duration(hours: 1, minutes: 12)), '01:12:00');
  expect(timecode(const Duration(minutes: 27, seconds: 8), negative: true), '-00:27:08');
  expect(timecode(Duration.zero), '00:00:00');
});
test('channelNo is the 1-based position, padded to three digits', () {
  expect(channelNo(0), '001');
  expect(channelNo(2), '003');
  expect(channelNo(1247), '1248');
});
test('remainingText', () {
  expect(remainingText(const Duration(hours: 1, minutes: 12)), '1 sa 12 dk kaldı');
  expect(remainingText(const Duration(hours: 2)), '2 sa kaldı');
  expect(remainingText(const Duration(minutes: 27)), '27 dk kaldı');
  expect(remainingText(const Duration(seconds: 40)), '1 dk kaldı');
});
test('hhmm pads both parts', () {
  expect(hhmm(DateTime(2026, 1, 1, 0, 5)), '00:05');
});
```

- [ ] **Step 4: Testlerin başarısız olduğunu gör**

Run: `flutter test test/ui/tokens_test.dart test/ui/format_test.dart`
Expected: FAIL, dosyalar yok.

- [ ] **Step 5: `tokens.dart`, `format.dart`, `app_theme.dart` dosyalarını yaz**

`buildAppTheme()` kararları: `brightness` koyu, `useMaterial3: true`, `fontFamily: 'Archivo'`, `scaffoldBackgroundColor: ground`, `ColorScheme.dark(primary: amber, onPrimary: ground, secondary: text, surface: panel, onSurface: text, error: red, onError: onRed)`, `splashFactory: NoSplash.splashFactory`, `focusColor` ve `hoverColor` saydam (odak görünümünü `FocusBox` çizer). Bu görevde ayrıca şu alt temalar verilir: `inputDecorationTheme` (dolu `well`, 1 piksel `keyBorder`, yarıçap 4, odakta 3 piksel `amber`, `isDense`), `progressIndicatorTheme` (`amber`, zemin `line`), `textSelectionTheme` (imleç `amber`). Pencere ve menü temaları Görev 13'te.

- [ ] **Step 6: `lib/main.dart` içinde temayı bağla**

`ColorScheme.fromSeed`, `focusOverlay`, `focusSide`, `focusStyle` ve beş düğme teması silinir. `theme: buildAppTheme()` olur. `ListenableBuilder` ve `UiScale` kalır.

- [ ] **Step 7: Testleri ve bütün paketi çalıştır**

Run: `flutter test`
Expected: PASS. Mevcut testler de geçmeli (tema değişimi davranışı etkilemez).

- [ ] **Step 8: Commit**

```bash
git add assets/fonts pubspec.yaml lib/main.dart lib/src/ui test/ui docs/superpowers
git commit -m "feat: design tokens, bundled fonts and the Yayın Masası theme"
```

---

### Task 2: Temel bileşenler

**Files:**
- Create: `lib/src/ui/focus_box.dart`, `lib/src/ui/app_key.dart`, `lib/src/ui/controls.dart`, `lib/src/ui/brand.dart`
- Test: `test/ui/widgets_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `AppSizes`, `AppText` (Görev 1).
- Produces:

```dart
class FocusBox extends StatefulWidget {
  const FocusBox({super.key, this.child, this.builder, this.onTap, this.onLongPress, this.onSecondaryTapUp,
    this.onFocusChange, this.focusNode, this.autofocus = false, this.borderWidth = AppSizes.focus,
    this.color = Colors.transparent, this.focusColor = AppColors.amberTint, this.tooltip, this.semanticLabel});
  final Widget? child;                                              // child ya da builder, biri zorunlu
  final Widget Function(BuildContext context, bool focused)? builder;
  final ValueChanged<bool>? onFocusChange;
  final GestureTapUpCallback? onSecondaryTapUp;
}

enum AppKeyVariant { normal, active, picked }

class AppKey extends StatelessWidget {
  const AppKey({super.key, this.label, this.icon, this.prefix, this.led, required this.onPressed,
    this.variant = AppKeyVariant.normal, this.height = AppSizes.keyHeight, this.width,
    this.autofocus = false, this.focusNode, this.tooltip, this.mono = false, this.dashed = false});
  final String? label; final IconData? icon; final String? prefix;   // prefix: soluk ön ek ("Ses")
  final Color? led;                                                  // 8 piksel ışık noktası
  final VoidCallback? onPressed;                                     // null: soluk, tıklanmaz
}

class Tag extends StatelessWidget { const Tag(this.text, {super.key, this.solid = false}); }
class KeyCap extends StatelessWidget { const KeyCap(this.text, {super.key}); }

class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.height = 3, this.color = AppColors.amber});
  final double value;                                                // 0..1, dışı kırpılır
}
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});
}
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});
  final T value; final Map<T, String> options; final ValueChanged<T> onChanged;
}
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.value, this.onChanged, this.segments = 10});
  final double value; final ValueChanged<double>? onChanged;         // 0..1
}
class ClockText extends StatefulWidget {
  const ClockText({super.key, this.size = 22, this.now});
  final DateTime Function()? now;                                    // test için
}
class BrandMark extends StatelessWidget { const BrandMark({super.key}); }
class GridBackground extends StatelessWidget { const GridBackground({super.key, required this.child}); }
```

- [ ] **Step 1: Başarısız testleri yaz**

```dart
testWidgets('FocusBox reports focus to its builder and activates on Enter', (tester) async {
  var taps = 0; bool? seen;
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Center(child: FocusBox(
    autofocus: true, onTap: () => taps++,
    builder: (_, focused) { seen = focused; return const SizedBox(width: 80, height: 44); }))));
  await tester.pump();
  expect(seen, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  expect(taps, 1);
});
testWidgets('FocusBox keeps its size when focus arrives', (tester) async {
  final node = FocusNode();
  await tester.pumpWidget(MaterialApp(home: Center(child: FocusBox(focusNode: node, onTap: () {}, child: const SizedBox(width: 80, height: 44)))));
  final before = tester.getSize(find.byType(FocusBox));
  node.requestFocus(); await tester.pumpAndSettle();
  expect(tester.getSize(find.byType(FocusBox)), before);
});
testWidgets('Segmented reports the tapped option and marks the current one', (tester) async {
  int? picked;
  await tester.pumpWidget(MaterialApp(home: Material(child: Segmented<int>(value: 15, options: const {10: '10 sn', 15: '15 sn', 30: '30 sn'}, onChanged: (v) => picked = v))));
  await tester.tap(find.text('30 sn'));
  expect(picked, 30);
  expect(tester.getSemantics(find.text('15 sn')), containsSemantics(isSelected: true));
  expect(tester.getSemantics(find.text('30 sn')), isNot(containsSemantics(isSelected: true)));
});
testWidgets('Segmented with a value outside its options selects nothing and does not throw', (tester) async {
  await tester.pumpWidget(MaterialApp(home: Material(child: Segmented<int>(value: 45, options: const {10: '10 sn', 15: '15 sn'}, onChanged: (_) {}))));
  expect(tester.takeException(), isNull);
});
testWidgets('AppSwitch shows its state in words and toggles', (tester) async {
  bool? next;
  await tester.pumpWidget(MaterialApp(home: Material(child: AppSwitch(value: true, onChanged: (v) => next = v))));
  expect(find.text('Açık'), findsOneWidget);
  await tester.tap(find.byType(AppSwitch));
  expect(next, isFalse);
});
testWidgets('LevelMeter sets the level of the tapped segment', (tester) async {
  double? level;
  await tester.pumpWidget(MaterialApp(home: Material(child: Center(child: LevelMeter(value: 0.7, onChanged: (v) => level = v)))));
  await tester.tapAt(tester.getTopLeft(find.byType(LevelMeter)) + const Offset(2, 10));
  expect(level, closeTo(0.1, 0.001));
});
testWidgets('ClockText shows hours, minutes and seconds', (tester) async {
  await tester.pumpWidget(MaterialApp(home: ClockText(now: () => DateTime(2026, 11, 12, 21, 47, 5))));
  expect(find.text('21:47:05'), findsOneWidget);
});
testWidgets('a disabled AppKey does not fire', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: Material(child: AppKey(label: 'Sil', onPressed: null))));
  await tester.tap(find.text('Sil'));
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/ui/widgets_test.dart`
Expected: FAIL, sınıflar yok.

- [ ] **Step 3: Dört dosyayı yaz**

Kararlar:
- `FocusBox`: `FocusableActionDetector` ya da `InkWell` + `Focus`. Olağan durumda aynı kalınlıkta saydam çerçeve bulunur. Fare üstündeyken zemin `panelHi`. Geçiş 120 ms. Dalga efekti yok.
- `AppKey` görünümleri belgenin "Tuş" maddesindeki gibi. `mono: true` etiketi IBM Plex Mono ile yazar (`-10`, `+10`). `dashed: true` 1 piksel kesikli `lineHi` çerçeve çizer (`CustomPainter`).
- `ClockText` kendi `Timer.periodic(1 sn)` ile yalnızca kendini yeniler, `dispose` içinde iptal eder.
- `BrandMark` yedi renk belgede yazıyor.
- `GridBackground`: `CustomPaint` + `RepaintBoundary`, 40 piksel aralık, `AppColors.gridLine`, 1 piksel.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test test/ui/widgets_test.dart && flutter analyze`
Expected: PASS, analiz temiz.

- [ ] **Step 5: Commit**

```bash
git add lib/src/ui test/ui
git commit -m "feat: core Yayın Masası widgets (focus box, keys, tags, controls)"
```

---

### Task 3: Ekran kutusu ve iskelet parçaları

**Files:**
- Create: `lib/src/ui/screen_tile.dart`, `lib/src/ui/shell.dart`
- Test: `test/ui/shell_test.dart`

**Interfaces:**
- Consumes: Görev 1 ve 2.
- Produces:

```dart
class ScreenTile extends StatelessWidget {
  const ScreenTile({super.key, required this.image, required this.title, this.trailing, this.leading,
    this.onTap, this.onFocusChange, this.aspectRatio = 16 / 9, this.imageHeight,
    this.labelHeight = AppSizes.labelBar, this.playing = false, this.badge, this.autofocus = false, this.subtitle});
  final Widget image; final String title;
  final String? trailing;        // sağda mono kehribar (yıl, kalan süre)
  final Widget? leading;         // çubuğun başında (kanal numarası gibi)
  final String? subtitle;        // 54'lük çubukta ikinci satır (profil)
  final bool playing;            // çubuğun başına PGM etiketi
  final Widget? badge;           // görselin sağ üstü (favori)
}

const navLabels = ['Ana sayfa', 'Canlı TV', 'Filmler', 'Diziler', 'Favoriler', 'Ayarlar'];
const navKeys = ['nav-home', 'nav-live', 'nav-movies', 'nav-series', 'nav-favorites', 'nav-settings'];

class TopBar extends StatelessWidget {
  const TopBar({super.key, this.selected, this.onSelect, this.accountName, this.onAccount,
    this.activeKeyNode, this.leading, this.clockSize = 22});
  final int? selected; final ValueChanged<int>? onSelect;
  final FocusNode? activeKeyNode;   // etkin bölüm tuşunun düğümü, debugLabel 'nav-active'
  final Widget? leading;            // verilirse menü tuşlarının yerine çizilir (detay: Geri + yol)
}

class SideKey extends StatelessWidget {
  const SideKey({super.key, required this.label, this.count, required this.selected, required this.onTap,
    this.onLongPress, this.onSecondaryTapUp, this.tooltip});
}

class InfoBar extends StatelessWidget {
  const InfoBar({super.key, required this.children});   // 76 yükseklik, well, Row
}
```

- [ ] **Step 1: Başarısız testleri yaz**

```dart
const long = 'Çok Uzun Bir Film Adı: Şeytanın Ağzından Çıkmış Öyküler ve Diğer Başıboş Güzellikler Üstüne';

testWidgets('TopBar reports the tapped section and marks the current one', (tester) async {
  int? picked;
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: TopBar(selected: 0, onSelect: (i) => picked = i))));
  await tester.tap(find.byKey(const ValueKey('nav-movies')));
  expect(picked, 2);
  for (final l in navLabels) { expect(find.text(l), findsOneWidget); }
});
testWidgets('TopBar does not overflow in an 800 px wide window', (tester) async {
  tester.view.physicalSize = const Size(800, 600); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: TopBar(selected: 0, onSelect: (_) {}, accountName: long))));
  expect(tester.takeException(), isNull);
});
testWidgets('ScreenTile shows title, trailing value and the PGM tag, and cuts a long title', (tester) async {
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: Center(child: SizedBox(width: 133,
    child: ScreenTile(image: const ColoredBox(color: AppColors.panel), title: long, trailing: '2014', playing: true, onTap: () {}))))));
  expect(find.text('PGM'), findsOneWidget);
  expect(find.text('2014'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
testWidgets('SideKey shows its count and fires on tap', (tester) async {
  var taps = 0;
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: SizedBox(width: 196, child: SideKey(label: long, count: 64, selected: true, onTap: () => taps++)))));
  await tester.tap(find.byType(SideKey));
  expect(taps, 1);
  expect(find.text('64'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/ui/shell_test.dart`
Expected: FAIL, sınıflar yok.

- [ ] **Step 3: İki dosyayı yaz**

Kararlar:
- `TopBar`: yükseklik 44, üstte 16 boşluk ve altta 1 piksel `line` çizgisi dahil toplam 73 yüksekliğinde. Tuş sırası yatay `SingleChildScrollView` içinde. Hesap adı 900'den dar genişlikte gizlenir. Sağda `ClockText`.
- `TopBar` orta bölümü: `leading` verilmişse o çizilir. Verilmemişse ve `onSelect` doluysa altı menü tuşu çizilir. İkisi de yoksa yalnızca marka ve saat kalır (profil seçimi).
- `Segmented` seçenekleri `Semantics(selected: …, button: true)` ile sarılır, seçili olan `selected: true` bildirir.
- `TopBar` tuşlarının sayı metni `label` 15, etkin olan `AppKeyVariant.active`.
- `ScreenTile`: `FocusBox(borderWidth: 0)` kullanır, odak çerçevesini görselin üstüne `foregroundDecoration` ile 4 piksel içe çizer, çubuk zeminini `amberTint` yapar.
- Sayılar binlik ayraçsız yazılır (`mono` 13).

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test test/ui && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/ui test/ui
git commit -m "feat: screen tile, top bar, side list and info bar widgets"
```

---

### Task 4: Ana iskelet: üst çubuk ve Geri tuşu

**Files:**
- Modify: `lib/src/home_page.dart:309-352` (`build`), `lib/src/home_page.dart:354-366` (`_content` başı)
- Modify: `test/home_page_test.dart`, `test/group_order_test.dart` (yalnızca sekme bulucuları)
- Test: `test/home_page_test.dart`

**Interfaces:**
- Consumes: `TopBar`, `GridBackground`, `navKeys`.
- Produces: `_HomePageState` içinde `final FocusNode _navNode = FocusNode(debugLabel: 'nav-active')` ve `final FocusScopeNode _topBarScope`. Sonraki görevler `_content()` gövdesini doldurur, iskelete dokunmaz.

- [ ] **Step 1: Mevcut testlerdeki sekme bulucularını değiştir**

`find.byIcon(Icons.movie)` yerine `find.byKey(const ValueKey('nav-movies'))`, `Icons.tv` yerine `nav-live`, `Icons.video_library` yerine `nav-series`. Başka satıra dokunma.

- [ ] **Step 2: Başarısız testleri ekle**

```dart
testWidgets('in remote mode Back first moves focus to the current section key, then goes home', (tester) async {
  await AppSettings.instance.update(tvMode: true);
  addTearDown(() => AppSettings.instance.update(tvMode: false));
  await _pump(tester);                                  // bu dosyadaki mevcut yardımcı
  await tester.tap(find.byKey(const ValueKey('nav-movies')));
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(FocusManager.instance.primaryFocus?.debugLabel, 'nav-active');
  expect(find.text('Film ara'), findsOneWidget, reason: 'still on the movies tab');
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.text('Film ara'), findsNothing, reason: 'second Back goes to the home tab');
});
testWidgets('the shell has no NavigationRail', (tester) async {
  await _pump(tester);
  expect(find.byType(NavigationRail), findsNothing);
  expect(find.byType(TopBar), findsOneWidget);
});
```

"Film ara" Görev 6'da eklenen ana arama ipucudur. Bu görevde arama alanının `hintText` değerini sekmeye göre "Kanal ara", "Film ara", "Dizi ara", "Favorilerde ara" yap.

- [ ] **Step 3: Testlerin başarısız olduğunu gör**

Run: `flutter test test/home_page_test.dart test/group_order_test.dart`
Expected: yeni iki test FAIL, bulucusu değişenler de FAIL (anahtarlar henüz yok).

- [ ] **Step 4: `build` gövdesini yeniden yaz**

`Scaffold(body: GridBackground(child: Column([TopBar(...), Expanded(child: _content())])))`. `NavigationRail` ve `VerticalDivider` silinir. `TopBar`: `selected: _tab`, `onSelect: _select`, `activeKeyNode: _navNode`, `accountName` yalnızca `_tab == _homeTab` iken, `onAccount: () => _select(_settingsTab)`.

`onPopInvokedWithResult` sırası: `AppSettings.instance.tvMode && !_topBarScope.hasFocus` ise `_navNode.requestFocus()` ve dön. Değilse mevcut üç adım aynen.

- [ ] **Step 5: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/home_page.dart test/home_page_test.dart test/group_order_test.dart
git commit -m "feat: top bar replaces the navigation rail; Back reaches it from deep lists"
```

---

### Task 5: Ana sayfa görünümü

**Files:**
- Modify: `lib/src/home_page.dart:423-485` (`_homeView`, `_row`, `_card`, `_itemCard`, `_historyCard`)
- Modify: `lib/src/poster_card.dart` (`PosterImage`'a `cacheWidth` parametresi, varsayılan 260)
- Test: `test/home_view_test.dart`
- Mockup: `Main.dc.html`

**Interfaces:**
- Consumes: `ScreenTile`, `ProgressLine`, `Tag`, `KeyCap`, `timecode`, `channelNo`, `AppText.heading`, `EpgCache`, `Library.instance.continueWatching`, `HistoryEntry.positionMs/durationMs/progress`.
- Produces: yok (yalnızca `_HomePageState` içi).

- [ ] **Step 1: Başarısız testleri yaz**

`test/home_page_test.dart` içindeki sahte istemci ve `Library.instance.use` kurulumunu örnek al.

```dart
testWidgets('an empty library shows the invitation and no programme monitor', (tester) async {
  await _pumpHome(tester);                                   // geçmiş ve favori yok
  expect(find.textContaining('Burası senin sayfan'), findsOneWidget);
  expect(find.text('PGM'), findsNothing);
  expect(tester.takeException(), isNull);
});
testWidgets('the newest resumable entry is the programme monitor, with its remaining time', (tester) async {
  await _seedHistory(url: 'http://h/movie/u/p/1.mkv', title: 'Dune |2024| TR-EN', kind: Kind.movie,
    position: const Duration(hours: 1, minutes: 34), total: const Duration(hours: 2, minutes: 46));
  await _pumpHome(tester);
  expect(find.text('PGM'), findsOneWidget);
  expect(find.text('Dune'), findsOneWidget);
  expect(find.text('-01:12:00'), findsOneWidget);
  expect(find.text('Devam et'), findsOneWidget);
});
testWidgets('an entry with unknown duration shows no remaining time', (tester) async {
  await _seedHistory(url: 'http://h/movie/u/p/2.mkv', title: 'Süresiz', kind: Kind.movie,
    position: const Duration(minutes: 5), total: Duration.zero);
  await _pumpHome(tester);
  expect(find.text('Süresiz'), findsOneWidget);
  expect(find.textContaining('-00:'), findsNothing);
});
testWidgets('favorite channels are numbered by their position', (tester) async {
  await _seedFavoriteChannels(['TRT 1', 'NTV']);
  await _pumpHome(tester);
  expect(find.text('Kanallarım'), findsOneWidget);
  expect(find.text('001'), findsOneWidget);
  expect(find.text('002'), findsOneWidget);
});
```

`_seedHistory`: `Library.instance.touch(...)` ardından `savePosition(url, position, total)`.

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/home_view_test.dart`
Expected: FAIL ('PGM' ve '-01:12:00' bulunamaz).

- [ ] **Step 3: `_homeView` gövdesini yeniden yaz**

Belgenin "Ana sayfa" bölümü ve mockup'a göre. Kararlar:
- Kalan süre: `durationMs > 0` ise `timecode(Duration(milliseconds: durationMs - positionMs), negative: true)`, değilse boş.
- Üst sıra `LayoutBuilder` ile: genişlik 900 ve üstüyse yan yana (sol `flex: 640`, sağ `flex: 564`, aralık 20), darsa alt alta.
- Ana ekrana `autofocus: AppSettings.instance.tvMode`.
- "Kanallarım" kutusunun görseli: logo varsa `PosterImage(fit: contain)`, yoksa ad `AppText.display(20)`.
- Yatay sıralar `ListView.separated`, kutu genişliği 235 (kanal) ve 133 (afiş).

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/home_page.dart lib/src/poster_card.dart test/home_view_test.dart
git commit -m "feat: home tab as a monitor wall (programme monitor, recents, channels)"
```

---

### Task 6: Kategori sütunu, afiş ızgarası ve bilgi çubuğu

**Files:**
- Modify: `lib/src/home_page.dart:368-421` (liste sekmeleri), `:487-514` (`_searchBar`), `:516-572` (`_body`, `_heart`, `_posterGrid`)
- Modify: `lib/src/poster_card.dart` (`PosterCard` silinir, `PosterImage` kalır)
- Test: `test/poster_grid_test.dart`, mevcut `test/group_order_test.dart`
- Mockup: `B-Filmler.dc.html`

**Interfaces:**
- Consumes: `SideKey`, `ScreenTile`, `InfoBar`, `AppKey`, `Tag`, `KeyCap`, `RemoteTextField`.
- Produces:
  - `int posterColumns(double width)` — `home_page.dart` içinde üst düzey işlev.
  - `final ValueNotifier<Item?> _focusedItem` — `_HomePageState` alanı. Görev 7 de kullanır.

- [ ] **Step 1: Başarısız testleri yaz**

```dart
test('posterColumns', () {
  expect(posterColumns(1008), 7);
  expect(posterColumns(600), 4);
  expect(posterColumns(200), 2);
});
testWidgets('focusing a poster describes it in the info bar', (tester) async {
  await _pumpHome(tester, movies: [_movie('Kış Uykusu |2014| TR', group: 'Yerli Filmler'), _movie('Arrival |2016| EN', group: 'Bilim Kurgu')]);
  await tester.tap(find.byKey(const ValueKey('nav-movies')));
  await tester.pumpAndSettle();
  Focus.of(tester.element(find.text('Kış Uykusu').first)).requestFocus();
  await tester.pump();
  final bar = find.byType(InfoBar);
  expect(find.descendant(of: bar, matching: find.text('Kış Uykusu')), findsOneWidget);
  expect(find.descendant(of: bar, matching: find.text('2014')), findsOneWidget);
  expect(find.descendant(of: bar, matching: find.text('Yerli Filmler')), findsOneWidget);
  expect(find.descendant(of: bar, matching: find.text('Ayrıntılar')), findsOneWidget);
});
testWidgets('the sort key opens the four orders and applies the chosen one', (tester) async {
  await _pumpHome(tester, movies: [_movie('Zeta'), _movie('Alfa')]);
  await tester.tap(find.byKey(const ValueKey('nav-movies')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sıralama'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('A – Z').last);
  await tester.pumpAndSettle();
  expect(tester.getTopLeft(find.text('Alfa').first).dx < tester.getTopLeft(find.text('Zeta').first).dx, isTrue);
});
testWidgets('live TV has no sort key', (tester) async {
  await _pumpHome(tester);
  await tester.tap(find.byKey(const ValueKey('nav-live')));
  await tester.pumpAndSettle();
  expect(find.text('Sıralama'), findsNothing);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/poster_grid_test.dart`
Expected: FAIL.

- [ ] **Step 3: Liste sekmelerini yeniden yaz**

Kararlar:
- Düzen: `Row([SizedBox(width: 196, kategori sütunu), SizedBox(width: 20), Expanded(Column([araç satırı, Expanded(ızgara), InfoBar]))])`, dış dolgu 28, üst 16.
- Kategori sütunu sırası: kategori arama alanı, "Tümü", kategoriler, en altta `AppKey(dashed: true, label: 'Kategorileri düzenle', tooltip: 'Kategorileri düzenle / gizle')`. Hesap adı satırı kalkar.
- Sayılar binlik ayraçsız.
- `posterColumns(w) = max(2, ((w + 12) / 145).floor())`. Izgara `SliverGridDelegateWithFixedCrossAxisCount`, `mainAxisExtent = kutuGenişliği * 1.43 + 28`, aralıklar 12.
- Kutu: `ScreenTile(image: PosterImage(...), title: parsed.title, trailing: parsed.year, onFocusChange: (f) { if (f) _focusedItem.value = item; })`. Fare üstüne gelince de aynı değer yazılır.
- Favori düğmesi `badge` olarak verilir: 24×24 `well` kare, dolu ya da içi boş kalp, ayrı odak durağı, `tooltip` metinleri aynı kalır.
- Bilgi çubuğu `ValueListenableBuilder<Item?>` ile `_focusedItem` dinler. Değer `null` iken boş çubuk çizilir.
- Sıralama: `AppKey(prefix: 'Sıralama', label: seçili ad, icon: aşağı ok)`, tıklanınca `showMenu`. Seçenek adları: "Varsayılan", "Yeni eklenen", "A – Z", "Yıl, yeniden eskiye".
- Yükleniyor durumu: ortada 3 piksel belirsiz `LinearProgressIndicator` (genişlik 220) ve "Yükleniyor...". Hata ve "Sonuç yok" metinleri aynı, düğme `AppKey`.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS, `group_order_test.dart` dahil.

- [ ] **Step 5: Commit**

```bash
git add lib/src/home_page.dart lib/src/poster_card.dart test/poster_grid_test.dart
git commit -m "feat: category column, poster grid with label bars and the info bar"
```

---

### Task 7: Canlı TV yayın akışı tablosu

**Files:**
- Create: `lib/src/guide_grid.dart`
- Modify: `lib/src/home_page.dart:542-554` (`_liveList` silinir, yerine `GuideGrid`), `lib/src/epg_widgets.dart:62-92` (`NowPlaying` yeni yazı stilleriyle), `lib/src/xtream.dart:312` (`'limit': '6'`)
- Test: `test/guide_grid_test.dart`
- Mockup: `B-Canli.dc.html`

**Interfaces:**
- Consumes: `EpgCache.get/cached`, `Programme.start/end/title/isNow/progress`, `_focusedItem`, `channelNo`, `hhmm`, `InfoBar`, `Tag`, `ProgressLine`.
- Produces:

```dart
const guideMinutes = 150;
DateTime guideWindowStart(DateTime now);

class GuideBlock {
  const GuideBlock({required this.programme, required this.left, required this.width, required this.isNow});
  final Programme programme; final double left; final double width; final bool isNow;
}
List<GuideBlock> layoutBlocks(List<Programme> list, DateTime windowStart, double width, DateTime now);

class GuideGrid extends StatefulWidget {
  const GuideGrid({super.key, required this.items, required this.epg, required this.header,
    required this.onOpen, required this.focused, required this.heart, this.now});
  final List<Item> items; final EpgCache epg; final String header;          // "Ulusal, 64 kanal"
  final ValueChanged<Item> onOpen; final ValueNotifier<Item?> focused;
  final Widget Function(Item item) heart; final DateTime Function()? now;   // test için
}
```

- [ ] **Step 1: Başarısız testleri yaz**

`Programme` kurucusunun biçimi için `lib/src/xtream.dart:130` satırına bak, aşağıdaki `p(...)` yardımcısını ona göre yaz.

```dart
final ws = DateTime(2026, 11, 12, 21);
DateTime t(int h, int m, [int day = 12]) => DateTime(2026, 11, day, h, m);

test('the window starts half an hour before the current half hour', () {
  expect(guideWindowStart(t(21, 47)), t(21, 0));
  expect(guideWindowStart(t(21, 5)), t(20, 30));
  expect(guideWindowStart(t(0, 10)), t(23, 30, 11));
});
test('blocks are placed by time, clipped to the window, 3 px apart', () {
  final b = layoutBlocks([p('A', t(20, 0), t(22, 30)), p('B', t(22, 30), t(23, 0))], ws, 828, t(21, 47));
  expect(b, hasLength(2));
  expect(b[0].left, 0);
  expect(b[0].width, closeTo(493.8, 0.5));
  expect(b[0].isNow, isTrue);
  expect(b[1].left, closeTo(496.8, 0.5));
  expect(b[1].width, closeTo(162.6, 0.5));
  expect(b[1].isNow, isFalse);
});
test('a programme crossing midnight is clipped at the window end', () {
  final b = layoutBlocks([p('Gece', t(23, 0), t(0, 30, 13))], ws, 828, t(21, 47));
  expect(b.single.left, closeTo(662.4, 0.5));
  expect(b.single.width, closeTo(162.6, 0.5));
});
test('programmes outside the window and empty ones are dropped', () {
  final b = layoutBlocks([p('Eski', t(19, 0), t(20, 30)), p('Sonra', t(23, 45), t(0, 30, 13)), p('Boş', t(22, 0), t(22, 0))], ws, 828, t(21, 47));
  expect(b, isEmpty);
  expect(layoutBlocks([p('A', t(21, 0), t(22, 0))], ws, 0, t(21, 47)), isEmpty);
});
testWidgets('a channel without programme data shows its category and still opens', (tester) async {
  Item? opened;
  await _pumpGrid(tester, items: [_channel('Kanal X', group: 'Yerel')], programmes: const {}, onOpen: (i) => opened = i);
  await tester.pumpAndSettle();
  expect(find.text('Yerel'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  await tester.tap(find.text('Kanal X'));
  expect(opened?.name, 'Kanal X');
});
testWidgets('rows are numbered and the focused channel fills the notifier', (tester) async {
  final focused = ValueNotifier<Item?>(null);
  await _pumpGrid(tester, items: [_channel('TRT 1'), _channel('ATV')], focused: focused);
  expect(find.text('001'), findsOneWidget);
  expect(find.text('002'), findsOneWidget);
  Focus.of(tester.element(find.text('ATV'))).requestFocus();
  await tester.pump();
  expect(focused.value?.name, 'ATV');
});
```

`_pumpGrid` sahte bir `XtreamClient` ile `EpgCache` kurar. Örnek için `test/epg_cache_test.dart` dosyasına bak.

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/guide_grid_test.dart`
Expected: FAIL, dosya yok.

- [ ] **Step 3: `guide_grid.dart` dosyasını yaz**

Kararlar:
- `guideWindowStart`: dakikayı 30'a aşağı yuvarla, saniyeyi sıfırla, 30 dakika çıkar.
- `layoutBlocks`: piksel başına dakika `width / 150`. Sol `max(start, windowStart)`, sağ `min(end, windowEnd)`. Genişlik `(sağ - sol) * ölçek - 3`. Genişlik 1'den küçükse blok atılır. `isNow`: `start <= now < end`.
- Tablo: üstte cetvel satırı (30), altında `ListView.builder(itemExtent: 54)`. Kanal hücresi 180 sabit, zaman alanı `LayoutBuilder` ile.
- Satır `FocusBox(borderWidth: 0)`. Odaklanan satırda `isNow` bloğu 3 piksel `amber` çerçeve ve `amberTint` zemin alır. Blok yoksa satırın tek bloğu alır.
- Program verisi `FutureBuilder(future: epg.get(id), initialData: epg.cached(id))`. Veri yok ya da boşsa tek blok, metin `item.group` (`groupLabel` ile), renk `text3`.
- "Şimdi" çizgisi ve saat etiketi tablonun üstünde `Positioned`, kendi `RepaintBoundary` içinde. `Timer.periodic(30 sn)` ile `setState`, `dispose` içinde iptal.
- Kanal hücresinin sağ ucunda `heart(item)`.

- [ ] **Step 4: `home_page.dart` içinde bağla ve bilgi çubuğunu ekle**

Canlı sekmesinde ızgara yerine `GuideGrid(items: shown, epg: _epg, header: '${kategori adı ya da "Tümü"}, ${shown.length} kanal', onOpen: _open, focused: _focusedItem, heart: _heart)`. Bilgi çubuğu: numara (`mono` 34), ad (`display` 22), `Tag('CANLI', solid: true)`, program adı ve saat aralığı, `ProgressLine`, "Sırada" satırı. Program verisi yoksa yalnızca numara, ad ve etiket.

- [ ] **Step 5: `shortEpg` sınırını 6 yap**

`lib/src/xtream.dart:312` içinde `'limit': '3'` yerine `'limit': '6'`. `test/xtream_test.dart` ve `test/epg_cache_test.dart` içinde 3'e bağlı bir beklenti varsa güncelle.

- [ ] **Step 6: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/src/guide_grid.dart lib/src/home_page.dart lib/src/epg_widgets.dart lib/src/xtream.dart test/guide_grid_test.dart
git commit -m "feat: live TV as a time-axis guide grid with a now line"
```

---

### Task 8: Favoriler sekmesi

**Files:**
- Modify: `lib/src/home_page.dart:359-366` (favoriler dalı), `:574-587` (`_mixedList` silinir)
- Test: `test/favorites_tab_test.dart`

**Interfaces:**
- Consumes: `ScreenTile`, `AppText.heading`, `posterColumns`, `_heart`, `_open`.

- [ ] **Step 1: Başarısız testleri yaz**

```dart
testWidgets('favorites are grouped by kind and empty groups are not drawn', (tester) async {
  await _seedFavorites(channels: ['TRT 1'], movies: ['Arrival |2016| EN']);
  await _pumpHome(tester);
  await tester.tap(find.byKey(const ValueKey('nav-favorites')));
  await tester.pumpAndSettle();
  expect(find.text('Kanallar'), findsOneWidget);
  expect(find.text('Filmler'), findsNWidgets(2), reason: 'the section heading and the top bar key');
  expect(find.text('Diziler'), findsOneWidget, reason: 'only the top bar key');
  expect(find.text('Arrival'), findsOneWidget);
});
testWidgets('no favorites shows the existing hint', (tester) async {
  await _pumpHome(tester);
  await tester.tap(find.byKey(const ValueKey('nav-favorites')));
  await tester.pumpAndSettle();
  expect(find.textContaining('Henüz favori yok'), findsOneWidget);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/favorites_tab_test.dart`
Expected: FAIL.

- [ ] **Step 3: Favoriler dalını yeniden yaz**

`CustomScrollView`: her dolu tür için bir başlık (`AppText.heading`) ve bir `SliverGrid`. Kanallar 16:9 kutu (genişlik hedefi 235), film ve diziler afiş kutusu (`posterColumns`). Arama alanı üstte, ipucu "Favorilerde ara". Kanal numarası favori kanal listesindeki sıradır.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/home_page.dart test/favorites_tab_test.dart
git commit -m "feat: favorites tab grouped into channel, movie and series tiles"
```

---

### Task 9: Detay sayfası

**Files:**
- Modify: `lib/src/detail_page.dart` (tamamı; `_play`, `initState` ve oynatma sırası mantığı korunur)
- Test: `test/detail_page_test.dart`
- Mockup: `B-Detay.dc.html`

**Interfaces:**
- Consumes: `TopBar(leading: …)`, `GridBackground`, `AppKey`, `ScreenTile`, `ProgressLine`, `Library.instance.positionFor`, `Library.instance.history`, `remainingText`.
- Produces: `_DetailPageState` içinde `int? _season` (seçili sezon).

- [ ] **Step 1: Başarısız testleri yaz**

Sahte istemci için `test/xtream_test.dart` içindeki örneği kullan.

```dart
testWidgets('only the selected season is listed and its key switches the list', (tester) async {
  await _pumpDetail(tester, _series(seasons: {1: ['Pilot', 'İkinci'], 2: ['Dönüş']}));
  await tester.pumpAndSettle();
  expect(find.text('Pilot'), findsOneWidget);
  expect(find.text('Dönüş'), findsNothing);
  expect(find.byType(ExpansionTile), findsNothing);
  await tester.tap(find.text('2. sezon'));
  await tester.pumpAndSettle();
  expect(find.text('Dönüş'), findsOneWidget);
  expect(find.text('Pilot'), findsNothing);
});
testWidgets('the season of the episode in progress is selected on open', (tester) async {
  await _seedPosition(_episodeUrl(season: 2, number: 1), const Duration(minutes: 21), const Duration(minutes: 48));
  await _pumpDetail(tester, _series(seasons: {1: ['Pilot'], 2: ['Dönüş']}));
  await tester.pumpAndSettle();
  expect(find.text('Dönüş'), findsOneWidget);
  expect(find.text('27 dk kaldı'), findsOneWidget);
});
testWidgets('a movie with a saved position offers to resume', (tester) async {
  await _seedPosition(_movieUrl, const Duration(minutes: 21, seconds: 4), const Duration(hours: 2));
  await _pumpDetail(tester, _movie());
  await tester.pumpAndSettle();
  expect(find.text('Devam et 21:04'), findsOneWidget);
});
testWidgets('empty facts are left out and a missing backdrop draws no monitor', (tester) async {
  await _pumpDetail(tester, _movie(details: Details()));       // hepsi boş
  await tester.pumpAndSettle();
  expect(find.text('Yönetmen'), findsNothing);
  expect(find.text('Oyuncular'), findsNothing);
  expect(find.text('Puan'), findsNothing);
  expect(find.text('Oynat'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/detail_page_test.dart`
Expected: FAIL.

- [ ] **Step 3: Sayfayı yeniden yaz**

Kararlar:
- `AppBar` kalkar. Üstte `TopBar(leading: Row([AppKey(icon: sol ok, label: 'Geri', height: 40, onPressed: maybePop), yol metni]))`. Yol: "Filmler" ya da "Diziler", "/", ad.
- Tam ekran yarı saydam arka plan görseli kalkar. Arka plan yalnızca sağdaki 400×225 kutuda gösterilir, pencere 1100'den darsa ya da adres boşsa hiç çizilmez.
- Künye satırları ve sırası belgede. Puan `'0'` ya da boşsa satır yok. "Dil" satırı `parsedTitleOf(item).tags` birleşimidir.
- Film tuşları: `AppKey(icon: oynat, label: resume == null ? 'Oynat' : 'Devam et ${_fmt(resume)}', autofocus: tvMode)`.
- Sezon seçimi: `_season ??=` devam eden bölümün sezonu, yoksa ilk sezon. "Devam eden" şu demek: `Library.instance.positionFor(e.url) != null` olan ilk bölüm.
- Bölüm satırı: `FocusBox`, yükseklik 52, zemin `panel`. Numara `'B${two(e.number)}'`. Başlık `e.title` boşsa `'${e.number}. Bölüm'`.
- Durum sütunu: `Library.instance.history` içinde adresi eşleşen kayıt varsa ve `durationMs > 0` ise `ProgressLine(value: progress)` ve `remainingText(...)`. Kayıt var ama süre bilinmiyorsa yalnızca "Devam ediliyor". Kayıt yoksa boş.
- Yükleniyor: künyenin yerinde 3 piksel belirsiz çubuk. Hata metni aynı, renk `red`.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/detail_page.dart test/detail_page_test.dart
git commit -m "feat: detail page with a facts table, season keys and an episode rundown"
```

---

### Task 10: Oynatıcı

**Files:**
- Create: `lib/src/player_chrome.dart`
- Modify: `lib/src/player_page.dart:330-347` (rakam göstergesi), `:712-800` (`build` içindeki kutular), `:804-918` (`_chrome`), `:920-953` (`_seekBar`), `:955-1042` (`_GoToDialog` görünümü), `_pick` penceresi
- Test: `test/player_chrome_test.dart`
- Mockup: `B-Oynatici.dc.html`, `B-OynaticiCanli.dc.html`

**Interfaces:**
- Consumes: `AppKey`, `Tag`, `ProgressLine`, `LevelMeter`, `ClockText`, `timecode`, `channelNo`, `hhmm`.
- Produces (hepsi `Player` gerektirmez, bu yüzden test edilebilir):

```dart
class PlayerTopRow extends StatelessWidget {
  const PlayerTopRow({super.key, required this.onBack, this.title, this.live = false});
}
class VodTimeline extends StatelessWidget {
  const VodTimeline({super.key, required this.position, required this.duration, this.buffer = Duration.zero,
    this.pending = false, this.onSeek});
  final ValueChanged<Duration>? onSeek;
}
class LiveBanner extends StatelessWidget {
  const LiveBanner({super.key, required this.index, required this.title, this.programmes = const [],
    this.prevTitle, this.nextTitle, this.now});
  final int index;                      // sıradaki yeri, 0 tabanlı
  final List<Programme> programmes;
  final DateTime Function()? now;
}
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({super.key, required this.children});   // wellOverlay, yarıçap 4, dolgu 18
}
```

`_Controls` yeni parametreler alır: `required int index`, `String? prevTitle`. `_PlayerPageState._video()` bunları `_index` ve `widget.queue[_index - 1].title` ile verir.

- [ ] **Step 1: Başarısız testleri yaz**

```dart
testWidgets('the timeline shows elapsed time and time left', (tester) async {
  await tester.pumpWidget(_wrap(const VodTimeline(position: Duration(minutes: 21, seconds: 4), duration: Duration(minutes: 48, seconds: 12))));
  expect(find.text('00:21:04'), findsOneWidget);
  expect(find.text('-00:27:08'), findsOneWidget);
});
testWidgets('an unknown duration shows no time left and a disabled bar', (tester) async {
  await tester.pumpWidget(_wrap(const VodTimeline(position: Duration(seconds: 5), duration: Duration.zero)));
  expect(find.text('--:--'), findsOneWidget);
  expect(find.textContaining('-00:'), findsNothing);
  expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
});
testWidgets('the live banner shows number, name, the current and the next programme', (tester) async {
  final now = DateTime(2026, 11, 12, 21, 47);
  await tester.pumpWidget(_wrap(LiveBanner(index: 11, title: 'TRT Spor', now: () => now, prevTitle: 'TRT 1', nextTitle: 'NTV', programmes: [
    p('Stadyum', DateTime(2026, 11, 12, 21), DateTime(2026, 11, 12, 22, 30)),
    p('Spor Haberleri', DateTime(2026, 11, 12, 22, 30), DateTime(2026, 11, 12, 23)),
  ])));
  expect(find.text('012'), findsOneWidget);
  expect(find.text('CANLI'), findsOneWidget);
  expect(find.text('Stadyum'), findsOneWidget);
  expect(find.text('21:00 – 22:30'), findsOneWidget);
  expect(find.text('Sırada'), findsOneWidget);
  expect(find.text('Spor Haberleri'), findsOneWidget);
  expect(find.text('011'), findsOneWidget);
  expect(find.text('013'), findsOneWidget);
});
testWidgets('the live banner without programme data shows only the channel', (tester) async {
  await tester.pumpWidget(_wrap(const LiveBanner(index: 0, title: 'Kanal X')));
  expect(find.text('001'), findsOneWidget);
  expect(find.text('Kanal X'), findsOneWidget);
  expect(find.text('Sırada'), findsNothing);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/player_chrome_test.dart`
Expected: FAIL, dosya yok.

- [ ] **Step 3: `player_chrome.dart` dosyasını yaz**

Kararlar:
- `VodTimeline`: Material `Slider` korunur (sürükleme ve erişilebilirlik için), `SliderTheme` ile giydirilir: iz yüksekliği 8, köşesiz iz biçimi, etkin `amber`, pasif `line`, `secondaryTrackValue` tampon ve rengi `buffered`, tutamaç 4×22 beyaz dikdörtgen (özel `SliderComponentShape`), kaplama yok. Altında 6 yüksekliğinde cetvel (`CustomPaint`, onda bir aralıklarla 1 piksel `dim`).
- Sol metin `timecode(position)`, `mono` 20 `amber`, `pending` ise beyaz. Sağ metin süre biliniyorsa `timecode(duration - position, negative: true)`, bilinmiyorsa `--:--`.
- `LiveBanner`: şimdiki program `start <= now < end`, sıradaki `start > now` olan ilk kayıt. Komşu satırları `prevTitle` ve `nextTitle` doluysa çizilir, numaraları `channelNo(index - 1)` ve `channelNo(index + 1)`.

- [ ] **Step 4: `_chrome`, `_seekBar` ve kutuları yeni parçalarla yeniden kur**

Kararlar:
- Üst ve alt karartma (`LinearGradient`) silinir. Yerine `PlayerTopRow` ve `PlayerPanel`.
- Tuş sırası belgenin "Oynatıcı" bölümlerinde. `_playNode` oynat tuşunda kalır. `FocusScope` ve `_barFocused` mantığı aynen korunur.
- Sarma tuşları `AppKey(mono: true)`, etiketleri `-N` ve `+N`. N ayardaki sarma süresinin saniyesidir (`AppSettings.instance.skipSecs`).
- Otomatik sonraki: `AppKey(led: on ? AppColors.text : AppColors.keyBorder, label: 'Otomatik sonraki ${on ? 'açık' : 'kapalı'}')`. Tıklama davranışı aynı.
- Hız: `AppKey(prefix: 'Hız', label: r == 1.0 ? '1x' : '${r}x')`.
- Ses ve altyazı: `AppKey(prefix: 'Ses', label: geçerli parçanın _trackLabel değeri, en çok 14 karakter)`.
- Ses: `AppKey(icon: ses ikonu)` kapatma için, yanında `LevelMeter(value: v / 100, onChanged: (x) => p.setVolume(x * 100))`, yalnızca `!_tv` iken.
- Canlıda `LiveBanner`'a `widget.epg` sonucu `FutureBuilder` ile verilir.
- Hata kutusu, kısa bilgi yazısı, sayaç kutusu: zemin `AppColors.wellOverlay`, yarıçap 4, 1 piksel `keyBorder`, düğmeler `AppKey`. Yazılan kanal numarası: `mono` 52 `amber`, `well` kutu içinde.
- Tampon göstergesi: ortada `CircularProgressIndicator` kalır, renk temadan `amber`.
- `_pick` penceresi ve `_GoToDialog`: yapı aynı, görünüm Görev 13'teki pencere temasından gelir. Seçili satırda onay ikonu yerine solda 8 piksel `red` ışık.

- [ ] **Step 5: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 6: Elle dene**

Run: `flutter run -d linux`
Bir film ve bir canlı kanal aç. Dene: sarma, zamana gitme, ses, hız, parça seçme, tam ekran, sonraki bölüm sayacı, rakamla kanal seçme, fare durunca denetimlerin gizlenmesi.

- [ ] **Step 7: Commit**

```bash
git add lib/src/player_chrome.dart lib/src/player_page.dart test/player_chrome_test.dart
git commit -m "feat: player controls as an on-screen panel with timecodes and a channel banner"
```

---

### Task 11: Profil seçimi, giriş ve QR penceresi

**Files:**
- Modify: `lib/src/login_page.dart:172-296` (görünüm), `:298-418` (`_avatarColor`, `_ProfileCard`, `_AddCard` silinir)
- Modify: `lib/src/remote_entry.dart:128-155` (pencere görünümü)
- Test: mevcut `test/login_page_test.dart` (değişmeden geçmeli) ve yeni iki test aynı dosyada
- Mockup: `B-Profiller.dc.html`

**Interfaces:**
- Consumes: `GridBackground`, `TopBar(selected: null)`, `ScreenTile(subtitle:, labelHeight: 54)`, `AppKey`, `Tag`, `BrandMark`.

- [ ] **Step 1: Başarısız testleri ekle**

```dart
testWidgets('a profile tile shows the initial, the name and the server', (tester) async {
  await _pumpWithAccounts(tester);                       // dosyadaki mevcut kurulum: Ev ve Ofis
  expect(find.text('O'), findsOneWidget);
  expect(find.text('E'), findsOneWidget);
  expect(find.byType(CircleAvatar), findsNothing);
  expect(find.text('Telefondan QR ile ya da elle'), findsOneWidget);
});
testWidgets('edit mode marks every profile for deletion', (tester) async {
  await _pumpWithAccounts(tester);
  await tester.tap(find.text('Kullanıcıları düzenle'));
  await tester.pump();
  expect(find.text('Sil'), findsNWidgets(2));
  expect(find.text('Silinecek kullanıcıyı seç'), findsOneWidget);
  expect(find.text('Bitti'), findsOneWidget);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/login_page_test.dart`
Expected: yeni iki test FAIL, eskiler PASS.

- [ ] **Step 3: Görünümü yeniden yaz**

Kararlar:
- `Scaffold(body: GridBackground(child: Column([TopBar(), Expanded(...)])))`. `TopBar` menüsüz: marka ve saat.
- Profil sırası: en çok dört sütunlu ızgara, kutu genişliği 240 hedefli, sola yaslı, içerik en çok 1008 genişliğinde ortalanmış sütunda.
- Profil kutusu: `ScreenTile(image: panel zemin üstünde baş harf display 64, title: ad, subtitle: sunucu, labelHeight: 54, leading/trailing: son kullanılansa Tag('Son kullanılan'))`. Düzenlemede `badge: Tag('Sil', solid: true)`.
- Ekleme kutusu: aynı boyut, görsel alanı kesikli çerçeve ve artı ikonu, `title: 'Kullanıcı ekle'`, `subtitle: 'Telefondan QR ile ya da elle'`.
- Form: 380 genişlik, `OutlinedButton` ve `FilledButton` yerine `AppKey`. "Kullanıcı Ekle" tuşu `AppKeyVariant.picked`. Meşgulken etiket yerine 3 piksel belirsiz çubuk.
- Açılış ekranı: `BrandMark`, metin, 220 genişliğinde 3 piksel belirsiz çubuk, `AppKey('Vazgeç / kullanıcı değiştir')`.
- Silme onayı ve QR penceresi yapısı aynı, düğmeler `AppKey`. QR beyaz zeminde kalır.
- Hata metni rengi `AppColors.red`.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS, eski login testleri değişmeden.

- [ ] **Step 5: Commit**

```bash
git add lib/src/login_page.dart lib/src/remote_entry.dart test/login_page_test.dart
git commit -m "feat: profile picker, sign-in form and QR dialog in the new language"
```

---

### Task 12: Ayarlar

**Files:**
- Modify: `lib/src/settings_page.dart` (tamamı; `_ConnectionTile._refresh` mantığı korunur)
- Modify: `test/settings_page_test.dart`
- Mockup: `B-Ayarlar.dc.html`

**Interfaces:**
- Consumes: `SideKey`, `Segmented`, `AppSwitch`, `AppKey`, `KeyCap`, `FocusBox`, `AppText`.
- Produces: her seçenek grubuna `ValueKey('setting-<alan>')`: `setting-audioLang`, `setting-subLang`, `setting-skipSecs`, `setting-cacheSecs`, `setting-uiScale`.

- [ ] **Step 1: Mevcut testleri yeni denetime göre güncelle, yenilerini ekle**

```dart
testWidgets('the Android default buffer of 15 s is the selected buffer size', (tester) async {
  await _pump(tester, cacheSecs: 15);                    // dosyadaki mevcut yardımcı
  expect(tester.widget<Segmented<int>>(find.byKey(const ValueKey('setting-cacheSecs'))).value, 15);
});
testWidgets('a stored value that is not one of the choices does not break the settings page', (tester) async {
  await _pump(tester, cacheSecs: 45);
  expect(find.text('Ön bellek (tampon)'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
testWidgets('a section key scrolls its section into view', (tester) async {
  await _pump(tester);
  expect(find.text('Tam ekrandan çık / geri').hitTestable(), findsNothing);
  await tester.tap(find.widgetWithText(SideKey, 'Kısayollar'));
  await tester.pumpAndSettle();
  expect(find.text('Tam ekrandan çık / geri').hitTestable(), findsOneWidget);
});
testWidgets('nothing overflows at 800 x 600', (tester) async {
  tester.view.physicalSize = const Size(800, 600); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _pump(tester);
  expect(tester.takeException(), isNull);
});
testWidgets('toggling a switch row writes the setting', (tester) async {
  await _pump(tester);
  await tester.tap(find.text('Donanım hızlandırma'));
  await tester.pump();
  expect(AppSettings.instance.hwdec, isFalse);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/settings_page_test.dart`
Expected: FAIL.

- [ ] **Step 3: Sayfayı yeniden yaz**

Kararlar:
- `StatelessWidget` yerine `StatefulWidget`: seçili bölüm indeksi ve her bölüm başlığı için bir `GlobalKey` tutar. Bölüm tuşu `Scrollable.ensureVisible(key.currentContext!, duration: 200 ms)` çağırır.
- Sağ taraf `ListView` değil, `SingleChildScrollView` içinde `Column` olur. Satır sayısı az ve `ensureVisible` için bütün bölüm başlıklarının kurulmuş olması gerekir.
- Bölüm adları koddakiyle aynı: Hesap, Oynatıcı, İçerik, Telefonu kumanda yap, Görünüm, Kısayollar.
- Hesap çubuğu belgenin "Ayarlar" bölümündeki gibi. Bağlantı metni `mono` 15, sınır doluysa `red` ve altında mevcut uyarı cümlesi. Yenile `AppKey(icon: yenile, tooltip: 'Yenile')`.
- Satır: `FocusBox`, yükseklik en az 62. Anahtar satırında satırın tamamı tıklanınca değer değişir. Seçenek satırında odak `Segmented` içindeki seçeneklere girer.
- Seçenek kümeleri ve adları koddakiyle aynı. 900'den dar alanda `Segmented` satır altına iner (`Wrap`).
- Açıklama metinleri iki satıra kadar sarar, kesilmez.
- Telefon kumandası QR bloğu: QR beyaz zeminde, yanında metinler `body` 14.
- Kısayollar: sol sütunda `KeyCap('Boşluk')` gibi, sağda açıklama.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/settings_page.dart test/settings_page_test.dart
git commit -m "feat: settings with a section index, segmented choices and lit switches"
```

---

### Task 13: Pencereler, menüler, temizlik ve son doğrulama

**Files:**
- Modify: `lib/src/ui/app_theme.dart` (pencere, menü, onay kutusu, ipucu temaları)
- Modify: `lib/src/home_page.dart:180-307` (`_groupMenu`, `_manageGroups` görünümü)
- Modify: `lib/src/tv_text_field.dart` (yalnızca varsayılan süsleme temadan gelsin diye gereksiz `OutlineInputBorder` kullanımları çağıranlardan temizlenir)
- Delete: `lib/src/focus_frame.dart`
- Modify: `README.md` (arayüz anlatan satırlar)
- Test: `test/ui/theme_test.dart`

**Interfaces:**
- Consumes: bütün önceki görevler.

- [ ] **Step 1: Başarısız testi yaz**

```dart
test('dialogs and menus use the flat panel look', () {
  final t = buildAppTheme();
  expect(t.dialogTheme.backgroundColor, AppColors.panel);
  expect((t.dialogTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(4));
  expect(t.dialogTheme.elevation, 0);
  expect(t.popupMenuTheme.color, AppColors.panel);
  expect(t.popupMenuTheme.elevation, 0);
  expect(t.tooltipTheme.decoration, isA<BoxDecoration>());
});
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `flutter test test/ui/theme_test.dart`
Expected: FAIL.

- [ ] **Step 3: Temayı tamamla**

Kararlar: `dialogTheme` (zemin `panel`, yarıçap 4, 1 piksel `keyBorder`, yükselti 0, başlık `display` 22), `popupMenuTheme` ve `menuTheme` (zemin `panel`, yarıçap 4, 1 piksel `keyBorder`, yükselti 0, metin `body` 15), `checkboxTheme` (işaretli dolgu `text`, işaret `ground`, kenar `dim`, yarıçap 2), `tooltipTheme` (zemin `well`, 1 piksel `keyBorder`, yarıçap 3, `label` 13), `dividerTheme` (`line`, 1), `scrollbarTheme` (tutamaç `lineHi`, yarıçap 0), `listTileTheme` (seçili renk `text`).

- [ ] **Step 4: Kategori düzenleme penceresi ve sağ tık menüsünü giydir**

`_manageGroups`: `ListTile` satırları yerine 48 yüksekliğinde `FocusBox` satırı, ikon düğmeleri `AppKey(icon:, height: 36, width: 36, tooltip:)`. İpucu metinleri ("En üste al", "Yukarı", "Aşağı") ve "Tamam", "Sırayı sıfırla" aynen kalır. `Checkbox` kalır (test onu arıyor).

- [ ] **Step 5: Kalıntı taraması**

```bash
grep -rn "FocusFrame\|NavigationRail\|ListTile(\|SwitchListTile\|ExpansionTile\|FilledButton\|OutlinedButton\|TextButton\|DropdownButton\|CircleAvatar\|Chip(\|Card(" lib/
grep -rn "BoxShadow\|BackdropFilter\|LinearGradient\|ShaderMask" lib/
grep -rn "Color(0x\|Colors\.\(white\|black\|red\|grey\)" lib/src --include=*.dart | grep -v "lib/src/ui/tokens.dart"
```

Expected: ilk iki komut boş döner. Üçüncüde yalnızca QR kodunun beyaz zemini ve `Colors.transparent` kalır. Kalan her satırı belirteçlere çevir, sonra `lib/src/focus_frame.dart` dosyasını sil.

- [ ] **Step 6: Bütün testler ve analiz**

Run: `flutter analyze && flutter test`
Expected: analiz temiz, bütün testler PASS.

- [ ] **Step 7: Linux'ta ekran ekran karşılaştır**

Run: `flutter run -d linux`
Pencereyi 1280×720 yap. Her ekranı ilgili mockup dosyasıyla yan yana koy: ana sayfa, canlı TV, filmler, diziler, favoriler, film detayı, dizi detayı, iki oynatıcı, profil seçimi, giriş formu, ayarlar, kategori düzenleme penceresi. Sonra pencereyi 800×600 yap ve Ayarlar'dan ölçeği %50 ve %140 yapıp taşma olmadığına bak. Yalnızca klavyeyle (yön tuşları, Enter, Esc) her ekrandaki her denetime ulaşılabildiğini doğrula.

- [ ] **Step 8: TV stick üzerinde elle dene**

Bunu kullanıcı yapar ya da kullanıcıyla birlikte yapılır. Kontrol listesi: odak her an görünüyor mu, Geri tuşu uzun listeden üst çubuğa götürüyor mu, yayın akışı tablosu kaydırırken takılıyor mu, 20 000 filmlik listede gezinmek akıcı mı, oynatıcıda yukarı ve aşağı kanal değiştiriyor mu, metin alanına OK ile girilip çıkılabiliyor mu.

- [ ] **Step 9: README'yi güncelle ve commit**

`README.md` içinde arayüzü anlatan cümleleri yeni düzene göre düzelt (üst çubuk, yayın akışı tablosu, bölüm tablosu). Yeni özellik iddia etme.

```bash
git add -A lib test README.md
git commit -m "feat: dialogs and menus in the new language; remove the old focus frame"
```

---

## Kapsam dışı bırakılanlar

Bunlar tasarım konuşmasında geçti ama bu planda yok. İstenirse ayrı iş olarak ele alınır:

- "İzlendi" işareti (bölüm tablosunda mockup'ta görünüyor, verisi yok).
- Yayın akışı tablosunda geçmiş programlara dönme ya da ileri tarihlere kaydırma.
- Açık tema.
- Ekran geçiş animasyonları.
