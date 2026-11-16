# Gündüz Arayüzü Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Uygulamanın bütün ekranlarını, işlev kaybı olmadan, açık renkli "Gündüz" tasarım diline taşımak.

**Architecture:** Önce `lib/src/ui/` altında renk, gölge, yazı ve ölçü belirteçleri ile ortak bileşenler kurulur. Sonra ekranlar tek tek bu bileşenlerle yeniden yazılır. Veri katmanı (`xtream.dart`, `library.dart`, `accounts.dart`, `settings.dart`) ve oynatma mantığı değişmez. Her görev kendi testleriyle biter, uygulama her görevden sonra çalışır durumda kalır.

**Tech Stack:** Flutter (Dart SDK ^3.13.7), Material 3 üstünde özel açık tema, `media_kit`, `flutter_test`. Yeni paket yok. Tek gömülü yazı tipi: Manrope (değişken).

**Spec:** `docs/superpowers/specs/2026-11-16-gunduz-arayuz-design.md`. Ekran mockup'ları: `docs/superpowers/specs/gunduz-mockups/*.dc.html` (1280×720, ölçüler satır içi `style` içinde). Her görevde ilgili mockup dosyasını ve belgedeki ekran bölümünü oku.

> `docs/superpowers/plans/2026-11-12-yayin-masasi-arayuz.md` reddedilmiş eski bir plandır. Onu uygulama.

## Başlamadan önce

- Flutter yol üzerinde değil. Her komuttan önce: `export PATH="$HOME/development/flutter/bin:$PATH"`.
- Çalışma `master` üzerinde değil, `feat/gunduz-ui` dalında yapılır.
- Görev sonlarındaki commit adımları için kullanıcıdan bir kez onay al. Commit iletileri depodaki biçimi izler (`feat: …`, `fix: …`, İngilizce).
- Yazı tipi dosyasını indirmek için kullanıcıdan izin iste (Görev 1).

## Global Constraints

- Zemin açıktır. Koyu yüzey yalnızca oynatıcıdaki videonun kendisidir.
- Tek vurgu rengi `#2F5BFF`. Kırmızı (`#FF4D5E` ailesi) yalnızca canlı yayın, favori ve silme içindir.
- `BackdropFilter` ve `ShaderMask` kullanılmaz. `LinearGradient` yalnızca sahne görselinin beyaza geçişinde kullanılır.
- En küçük köşe yarıçapı 10. Keskin köşe yok.
- En küçük metin 12 piksel. `AppColors.ink3` metin rengi olarak kullanılmaz.
- En küçük tıklama alanı 44×44.
- Odak: 3 piksel `#0F1728` çerçeve, öğeden 4 piksel dışarıda, artı `AppShadows.lift`. Odak gelince düzen kaymaz.
- Kumanda modunda tekrarlanan öğelerde gölge yok, 1 piksel `AppColors.line` kenarlık var (`AppShadows.forRepeated()`).
- Kaydırma alanları her yönde en az 8 piksel iç boşluk bırakır.
- Renk, gölge ve yazı değerleri yalnızca `AppColors`, `AppShadows`, `AppText` üzerinden kullanılır. Ekran dosyalarında `Color(0x…)` ve `Colors.…` kalmaz (`Colors.transparent`, QR'ın beyazı ve videonun siyahı dışında).
- Listeler `builder` ile ve sabit öğe yüksekliğiyle kurulur.
- Mevcut Türkçe metinler korunur. Değişenler belgedeki "Metin değişiklikleri" tablosundadır.
- Yeni paket eklenmez. `UiScale` %50–%140 arası her ölçekte çalışır.
- Her görevin sonunda `flutter analyze` hatasız, `flutter test` tamamı geçer.

## Review Focus

Belgenin ima ettiği ama gözden kaçması kolay durumlar. Her birinin testi parantezdeki göreve eklendi.

1. **Logosu, program bilgisi ya da düzgün adı olmayan kanal** (boş ad, tek harf, yalnızca rakam): rozet boş kalmaz ya da çökmez, satır çizilir, kanal açılır. (Görev 2, 6)
2. **Çok uzun ad ve dar pencere**: 80 karakterlik Türkçe ad, 800×600 pencere, %50 ve %140 ölçek. Taşma hatası çıkmaz, metin üç noktayla kesilir. (Görev 4, 7, 12 test, Görev 13 elle)
3. **Boş kütüphane**: geçmiş ve favori yokken ana sayfa çökmez, ana kart ve boş bölümler çizilmez, davet metni görünür. (Görev 5)
4. **Süresi bilinmeyen içerik** (`durationMs == 0`, canlı kanal geçmişi, boş bölüm süresi): kalan süre ve konum çubuğu yazılmaz, sıfıra bölme ya da "-0:00" görünmez. (Görev 1, 5, 9, 10)
5. **Kenardaki öğenin odak çerçevesi**: listenin ilk ve son öğesi odaktayken çerçeve kesilmez. (Görev 6, 7)

---

## Dosya yapısı

Yeni dosyalar:

| Dosya | Sorumluluk |
|---|---|
| `lib/src/ui/tokens.dart` | `AppColors`, `AppShadows`, `AppSizes`, `AppText`, `badgeTints` |
| `lib/src/ui/format.dart` | Süre, saat, selam, kısaltma ve renk seçimi yardımcıları |
| `lib/src/ui/app_theme.dart` | `buildAppTheme()` |
| `lib/src/ui/focus_ring.dart` | `FocusRing` |
| `lib/src/ui/basics.dart` | `AppButton`, `AppCard`, `Pill`, `LiveDot`, `ChannelBadge`, `ProgressBar` |
| `lib/src/ui/controls.dart` | `AppSwitch`, `Segmented`, `SearchField`, `ClockPill`, `SideItem` |
| `lib/src/ui/shell.dart` | `SideMenu`, `PageHeader` |
| `lib/src/player_chrome.dart` | Oynatıcının `Player` gerektirmeyen görsel parçaları |
| `assets/fonts/` | `Manrope-Variable.ttf`, `OFL-Manrope.txt` |

Değişen dosyalar: `pubspec.yaml`, `lib/main.dart`, `lib/src/home_page.dart`, `lib/src/detail_page.dart`, `lib/src/player_page.dart`, `lib/src/login_page.dart`, `lib/src/remote_entry.dart`, `lib/src/settings_page.dart`, `lib/src/epg_widgets.dart`, `lib/src/poster_card.dart`, `README.md`.

Silinen dosya: `lib/src/focus_frame.dart` (Görev 13).

---

### Task 1: Yazı tipi, belirteçler, yardımcılar ve tema

**Files:**
- Create: `assets/fonts/Manrope-Variable.ttf`, `assets/fonts/OFL-Manrope.txt`
- Create: `lib/src/ui/tokens.dart`, `lib/src/ui/format.dart`, `lib/src/ui/app_theme.dart`
- Modify: `pubspec.yaml` (`flutter:` altına `fonts:`), `lib/main.dart:35-54`
- Test: `test/ui/tokens_test.dart`, `test/ui/format_test.dart`

**Interfaces:**
- Produces:
  - `abstract final class AppColors` — belgedeki "Renkler" tablosundaki her ad için `static const Color`.
  - `const List<(Color bg, Color ink)> badgeTints` — belgedeki altı çift, aynı sırayla.
  - `abstract final class AppShadows` — `static const List<BoxShadow> panel, card, chip, lift, overlay` (değerler belgede) ve `static List<BoxShadow> forRepeated()`: `AppSettings.instance.tvMode` açıksa boş liste, değilse `card`. `static Border? repeatedBorder()`: kumanda modunda 1 piksel `AppColors.line`, değilse `null`.
  - `abstract final class AppSizes` — `panelRadius = 28.0`, `cardRadius = 24.0`, `tileRadius = 20.0`, `itemRadius = 16.0`, `smallRadius = 14.0`, `tagRadius = 10.0`, `ring = 3.0`, `ringGap = 4.0`, `scrollPad = 8.0`, `menuWidth = 212.0`, `menuCompact = 76.0`, `sideWidth = 216.0`, `buttonHeight = 44.0`, `primaryHeight = 48.0`.
  - `abstract final class AppText`:
    - `static TextStyle display(double size, {Color color = AppColors.ink})` — 800, harf aralığı `size * -0.02`, satır yüksekliği 1.12.
    - `static TextStyle title(double size, {Color color = AppColors.ink})` — 800.
    - `static TextStyle label(double size, {Color color = AppColors.ink})` — 700.
    - `static TextStyle meta(double size, {Color color = AppColors.ink2})` — 600, tabular rakam.
    - `static TextStyle body({double size = 15, Color color = AppColors.body})` — 500, satır yüksekliği 1.55.
    - Hepsi `fontFamily: 'Manrope'`, kalınlık hem `fontWeight` hem `FontVariation('wght', n)` ile.
  - `ThemeData buildAppTheme()`.
  - `format.dart`:
    - `String remainingText(Duration left)` — "1 sa 12 dk kaldı", "2 sa kaldı", "27 dk kaldı". Bir dakikadan az kalanlar "1 dk kaldı".
    - `String clockTime(Duration d)` — "21:04", "1:02:04".
    - `String hhmm(DateTime t)` — "09:05".
    - `String greeting(DateTime t)` — saat aralıkları belgede.
    - `String minutesLabel(String raw)` — Xtream süre metni: "00:48:12" → "48 dk", "01:05:00" → "65 dk", "2880" (saniye) → "48 dk", "45 min" ya da başka biçim → olduğu gibi, boş → boş.
    - `String badgeText(String name)` — belgedeki kural. Boş ad → "?".
    - `(Color, Color) tintFor(String seed)` — `badgeTints` içinden, bugünkü `_avatarColor` karmasıyla.

- [ ] **Step 1: Kullanıcıdan izin alıp yazı tipini indir**

```bash
mkdir -p assets/fonts
curl -fL -o assets/fonts/Manrope-Variable.ttf "https://github.com/google/fonts/raw/main/ofl/manrope/Manrope%5Bwght%5D.ttf"
curl -fL -o assets/fonts/OFL-Manrope.txt "https://github.com/google/fonts/raw/main/ofl/manrope/OFL.txt"
file assets/fonts/Manrope-Variable.ttf
```

Expected: "TrueType Font data". Adres 404 dönerse aynı dosyayı fonts.google.com'daki Manrope sayfasından al, yine kullanıcıya sor.

- [ ] **Step 2: `pubspec.yaml` içine yazı tipini ekle**

```yaml
  fonts:
    - family: Manrope
      fonts:
        - asset: assets/fonts/Manrope-Variable.ttf
```

- [ ] **Step 3: Başarısız testleri yaz**

`test/ui/tokens_test.dart`:

```dart
test('display style is extra-bold Manrope with tight tracking', () {
  final s = AppText.display(40);
  expect(s.fontFamily, 'Manrope');
  expect(s.fontWeight, FontWeight.w800);
  expect(s.fontVariations, contains(const FontVariation('wght', 800)));
  expect(s.letterSpacing, closeTo(-0.8, 0.001));
});
test('meta style is secondary ink with tabular figures', () {
  final s = AppText.meta(14);
  expect(s.color, AppColors.ink2);
  expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
});
test('the theme is light and uses the single accent', () {
  final t = buildAppTheme();
  expect(t.brightness, Brightness.light);
  expect(t.scaffoldBackgroundColor, AppColors.ground);
  expect(t.colorScheme.primary, AppColors.accent);
  expect(t.colorScheme.surface, AppColors.surface);
  expect(t.colorScheme.error, AppColors.live);
});
test('palette values match the spec', () {
  expect(AppColors.ground, const Color(0xFFE9EDF4));
  expect(AppColors.ink, const Color(0xFF0F1728));
  expect(AppColors.accent, const Color(0xFF2F5BFF));
  expect(AppColors.live, const Color(0xFFFF4D5E));
  expect(badgeTints, hasLength(6));
});
test('repeated items lose their shadow in remote mode', () {
  AppSettings.instance.tvMode = true;
  addTearDown(() => AppSettings.instance.tvMode = false);
  expect(AppShadows.forRepeated(), isEmpty);
  expect(AppShadows.repeatedBorder(), isNotNull);
  AppSettings.instance.tvMode = false;
  expect(AppShadows.forRepeated(), AppShadows.card);
  expect(AppShadows.repeatedBorder(), isNull);
});
```

`test/ui/format_test.dart`:

```dart
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
```

`badgeText` büyük harfe çevirirken Türkçe "ı" ve "i" için `foldTr` kullanmaz, `toUpperCase()` sonucu "I" olur. Beklenen değer buna göre yazıldı.

- [ ] **Step 4: Testlerin başarısız olduğunu gör**

Run: `flutter test test/ui/tokens_test.dart test/ui/format_test.dart`
Expected: FAIL, dosyalar yok.

- [ ] **Step 5: Üç dosyayı yaz**

`buildAppTheme()` kararları: `brightness: Brightness.light`, `useMaterial3: true`, `fontFamily: 'Manrope'`, `scaffoldBackgroundColor: ground`, `ColorScheme.light(primary: accent, onPrimary: onAccent, secondary: ink, surface: surface, onSurface: ink, error: live, onError: onAccent)`, `splashFactory: NoSplash.splashFactory`, `focusColor` ve `hoverColor` saydam (odağı `FocusRing` çizer), `textTheme` varsayılan rengi `ink`. Alt temalar: `inputDecorationTheme` (çerçevesiz, dolu değil, `isDense`, ipucu `meta` 15), `progressIndicatorTheme` (`accent`, zemin `line`), `textSelectionTheme` (imleç `accent`), `scrollbarTheme` (tutamaç `dashed`, yuvarlak). Pencere ve menü temaları Görev 13'te.

`tintFor`: `(seed.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xFFFF)) % 6`.

- [ ] **Step 6: `lib/main.dart` içinde temayı bağla**

`ColorScheme.fromSeed`, `focusOverlay`, `focusSide`, `focusStyle` ve beş düğme teması silinir. `theme: buildAppTheme()` olur. `ListenableBuilder` ve `UiScale` kalır. Android'de durum çubuğu ikonları koyu olmalı: `SystemUiOverlayStyle.dark` (`AnnotatedRegion` ile `MaterialApp` içinde).

- [ ] **Step 7: Bütün testleri çalıştır**

Run: `flutter test`
Expected: PASS. Mevcut testler de geçmeli.

- [ ] **Step 8: Commit**

```bash
git add assets/fonts pubspec.yaml lib/main.dart lib/src/ui test/ui docs/superpowers
git commit -m "feat: Gündüz design tokens, bundled Manrope and the light theme"
```

---

### Task 2: Odak halkası ve temel bileşenler

**Files:**
- Create: `lib/src/ui/focus_ring.dart`, `lib/src/ui/basics.dart`
- Test: `test/ui/basics_test.dart`

**Interfaces:**
- Consumes: Görev 1.
- Produces:

```dart
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, this.child, this.builder, this.onTap, this.onLongPress, this.onSecondaryTapUp,
    this.onFocusChange, this.focusNode, this.autofocus = false, this.radius = AppSizes.cardRadius,
    this.inside = false, this.lift = true, this.hoverColor, this.tooltip, this.semanticLabel});
  final Widget? child;                                                // child ya da builder, biri zorunlu
  final Widget Function(BuildContext context, bool focused, bool hovered)? builder;
  final bool inside;     // true: çerçeve içeriden, zemin surfaceAlt (tam genişlik satırlar)
  final bool lift;       // odakta AppShadows.lift
  final Color? hoverColor;
}

enum AppButtonVariant { primary, secondary, onPage, danger }

class AppButton extends StatelessWidget {
  const AppButton({super.key, this.label, this.icon, this.trailingIcon, this.prefix, required this.onPressed,
    this.variant = AppButtonVariant.secondary, this.height = AppSizes.buttonHeight, this.width,
    this.autofocus = false, this.focusNode, this.tooltip, this.child});
  final String? prefix;          // soluk ön ek ("Sırala:")
  final Widget? child;           // label yerine (içinde anahtar olan "Otomatik sonraki" gibi)
  final VoidCallback? onPressed; // null: soluk, tıklanmaz
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.radius = AppSizes.panelRadius,
    this.padding = EdgeInsets.zero, this.shadows = AppShadows.panel, this.border, this.color = AppColors.surface});
}

enum PillTone { accent, live, warn, neutral, onImage }
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = PillTone.neutral, this.icon, this.leading, this.height = 28});
}
class LiveDot extends StatelessWidget { const LiveDot({super.key, this.size = 9}); }

class ChannelBadge extends StatelessWidget {
  const ChannelBadge({super.key, required this.name, this.logo = '', this.size = 46});
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.height = 6, this.onImage = false});
  final double value;            // 0..1, dışı kırpılır, NaN 0 sayılır
}
```

- [ ] **Step 1: Başarısız testleri yaz**

```dart
Widget _app(Widget w) => MaterialApp(theme: buildAppTheme(), home: Scaffold(body: Center(child: w)));

testWidgets('FocusRing reports focus to its builder and activates on Enter', (tester) async {
  var taps = 0; bool? seen;
  await tester.pumpWidget(_app(FocusRing(autofocus: true, onTap: () => taps++,
    builder: (_, focused, _) { seen = focused; return const SizedBox(width: 80, height: 44); })));
  await tester.pump();
  expect(seen, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  expect(taps, 1);
});
testWidgets('FocusRing keeps its layout size when focus arrives', (tester) async {
  final node = FocusNode();
  await tester.pumpWidget(_app(FocusRing(focusNode: node, onTap: () {}, child: const SizedBox(width: 80, height: 44))));
  final before = tester.getRect(find.byType(FocusRing));
  node.requestFocus(); await tester.pumpAndSettle();
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
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/ui/basics_test.dart`
Expected: FAIL, sınıflar yok.

- [ ] **Step 3: İki dosyayı yaz**

Kararlar:
- `FocusRing`: `FocusableActionDetector` (Enter, Space ve `select` etkinleştirir) + `MouseRegion` + `GestureDetector`. Çerçeve `CustomPaint(foregroundPainter:)` ile, `inside: false` iken öğenin 4 piksel dışına boyanır (`RRect.inflate(4 + 1.5)` üstüne 3 piksel kontur). Bu yüzden `FocusRing` hiçbir zaman `ClipRRect` ile sarılmaz, kırpma içerideki görselde yapılır.
- Gölge: `AnimatedContainer(duration: 120 ms, decoration: BoxDecoration(borderRadius, boxShadow: focused && lift ? AppShadows.lift : const []))`. Fare üstündeyken `hoverColor` verilmişse zemin o olur.
- Basma: `AnimatedScale(scale: pressed ? 0.98 : 1, duration: 120 ms)`.
- `AppButton`: `FocusRing(radius: height / 2)` içinde. Görünüm renkleri: `primary` mavi/beyaz, `secondary` `surfaceAlt`/`ink`, `onPage` beyaz/`ink` + `AppShadows.chip`, `danger` `liveSoft`/`liveInk`. Yazı `AppText.label(15)` (`height` 44 altında 14). Yalnızca ikon varsa genişlik = yükseklik. `onPressed == null` iken `canRequestFocus: false` ve opaklık 0.5.
- `ChannelBadge`: logo boş değilse `surface` zemin üstünde `PosterImage(logo, fit: BoxFit.contain)`, 6 piksel iç boşluk, hata olursa kısaltmaya düşer. Yazı boyutu `size * 0.28`, kalınlık 800.
- `ProgressBar`: `value.isNaN ? 0 : value.clamp(0, 1)`. `onImage` iken zemin `ink` %45 opak, dolgu beyaz.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test test/ui && flutter analyze`
Expected: PASS, analiz temiz.

- [ ] **Step 5: Commit**

```bash
git add lib/src/ui test/ui
git commit -m "feat: focus ring, buttons, cards, pills, channel badge and progress bar"
```

---

### Task 3: Denetimler: anahtar, seçenek grubu, arama, saat, yan öğe

**Files:**
- Create: `lib/src/ui/controls.dart`
- Test: `test/ui/controls_test.dart`

**Interfaces:**
- Consumes: Görev 1 ve 2, `RemoteTextField` (`lib/src/tv_text_field.dart`).
- Produces:

```dart
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged, this.small = false, this.focusable = true});
  final bool focusable;          // false: satırın kendisi odak alır (ayar satırı)
}
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});
  final T value; final Map<T, String> options; final ValueChanged<T> onChanged;
}
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, this.onChanged, this.controller, this.onPage = true, this.width});
  final bool onPage;             // true: beyaz + chip gölgesi, false: surfaceAlt (panel içinde)
}
class ClockPill extends StatefulWidget {
  const ClockPill({super.key, this.now});
  final DateTime Function()? now;  // test için
}
class SideItem extends StatelessWidget {
  const SideItem({super.key, required this.label, this.count, required this.selected, required this.onTap,
    this.onLongPress, this.onSecondaryTapUp, this.tooltip, this.height = 42});
  final String? count;           // biçimlenmiş sayı ("1.248")
}
String groupCount(int n);         // 1248 → "1.248"
```

- [ ] **Step 1: Başarısız testleri yaz**

```dart
testWidgets('Segmented reports the tapped option and marks the current one', (tester) async {
  int? picked;
  await tester.pumpWidget(_app(Segmented<int>(value: 10, options: const {5: '5 sn', 10: '10 sn', 30: '30 sn'}, onChanged: (v) => picked = v)));
  await tester.tap(find.text('30 sn'));
  expect(picked, 30);
  expect(tester.getSemantics(find.text('10 sn')), containsSemantics(isSelected: true));
  expect(tester.getSemantics(find.text('30 sn')), isNot(containsSemantics(isSelected: true)));
});
testWidgets('Segmented with a value outside its options selects nothing and does not throw', (tester) async {
  await tester.pumpWidget(_app(Segmented<int>(value: 45, options: const {10: '10 sn', 15: '15 sn'}, onChanged: (_) {})));
  expect(tester.takeException(), isNull);
});
testWidgets('AppSwitch toggles and reports its state to semantics', (tester) async {
  bool? next;
  await tester.pumpWidget(_app(AppSwitch(value: true, onChanged: (v) => next = v)));
  expect(tester.getSemantics(find.byType(AppSwitch)), containsSemantics(isToggled: true));
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
  await tester.pumpWidget(_app(SizedBox(width: 192, child: SideItem(label: 'Çok Uzun Bir Kategori Adı Netflix Filmleri Arşivi', count: '1.248', selected: true, onTap: () {}))));
  expect(tester.takeException(), isNull);
  expect(find.text('1.248'), findsOneWidget);
});
test('groupCount', () {
  expect(groupCount(64), '64');
  expect(groupCount(1248), '1.248');
  expect(groupCount(18420), '18.420');
});
```

`_app` yardımcısı Görev 2'deki gibidir, bu dosyada da tanımla.

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/ui/controls_test.dart`
Expected: FAIL.

- [ ] **Step 3: `controls.dart` dosyasını yaz**

Kararlar:
- `Segmented` seçenekleri `Semantics(selected: …, button: true, inMutuallyExclusiveGroup: true)` ile sarılır. Her seçenek `FocusRing(radius: 14, lift: false)`.
- `AppSwitch`: `Semantics(toggled: value)`. `focusable: false` iken `ExcludeFocus` içinde çizilir.
- `SearchField`: `RemoteTextField(decoration: InputDecoration(hintText:, prefixIcon: Icon(Icons.search_rounded, size: 18), border: InputBorder.none, isDense: true))` bir hap kabın içinde. Odakta kabın etrafına `FocusRing` gibi 3 piksel `ink` çerçeve (`Focus` dinleyerek). Yükseklik 44 (sayfa) ya da 40 (panel).
- `ClockPill`: `Timer` bir sonraki dakika başına kurulur, sonra dakikada bir. `dispose` içinde iptal.
- `groupCount`: binlik ayraç nokta.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test test/ui && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/ui test/ui
git commit -m "feat: switch, segmented choice, search field, clock and side list item"
```

---

### Task 4: İskelet: sol menü ve sayfa başlığı

**Files:**
- Create: `lib/src/ui/shell.dart`
- Modify: `lib/src/home_page.dart:309-352` (`build`), `:354-421` (`_content` iskeleti ve başlıklar)
- Modify: `test/home_page_test.dart`, `test/group_order_test.dart` (yalnızca sekme ve arama bulucuları)
- Test: `test/ui/shell_test.dart`, `test/home_page_test.dart`

**Interfaces:**
- Consumes: Görev 1–3.
- Produces:

```dart
const navLabels = ['Ana sayfa', 'Canlı TV', 'Filmler', 'Diziler', 'Favoriler', 'Ayarlar'];
const navKeys = ['nav-home', 'nav-live', 'nav-movies', 'nav-series', 'nav-favorites', 'nav-settings'];
const navIcons = [Icons.home_rounded, Icons.live_tv_rounded, Icons.movie_rounded, Icons.video_library_rounded, Icons.favorite_rounded, Icons.tune_rounded];

class SideMenu extends StatelessWidget {
  const SideMenu({super.key, required this.selected, required this.onSelect, required this.accountName,
    required this.onAccount, this.compact});
  final bool? compact;           // null: genişliğe göre (1000'den dar pencerede true)
}
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});
}
```

`HomePage` içinde `_content()` artık her sekme için `Column([PageHeader, Expanded(gövde)])` döner. Arama alanlarının anahtarları değişmez: ana arama `ValueKey('search$_tab')`, kategori arama `ValueKey('groupSearch$_tab')`.

- [ ] **Step 1: Mevcut testlerdeki bulucuları değiştir**

- `find.byIcon(Icons.movie)` → `find.byKey(const ValueKey('nav-movies'))`, `Icons.tv` → `nav-live`, `Icons.video_library` → `nav-series`.
- `test/home_page_test.dart` içindeki `find.byType(TextField).at(1)` iki kullanımı: ana arama artık ağaçta kategori aramasından önce gelebilir. Arama kutusunu sırayla değil anahtarla bul: `find.descendant(of: find.byKey(ValueKey('search${tab}')), matching: find.byType(EditableText))`. `_searchText` yardımcısına `int tab` parametresi ekle. Testin gerisine dokunma.

- [ ] **Step 2: Başarısız testleri ekle**

`test/ui/shell_test.dart`:

```dart
const long = 'Çok Uzun Bir Hesap Adı Şeytanın Ağzından Çıkmış Öyküler ve Diğer Başıboş Güzellikler';

testWidgets('SideMenu reports the tapped section and marks the current one', (tester) async {
  int? picked;
  await tester.pumpWidget(_app(SideMenu(selected: 0, onSelect: (i) => picked = i, accountName: 'Hakan', onAccount: () {})));
  await tester.tap(find.byKey(const ValueKey('nav-movies')));
  expect(picked, 2);
  for (final l in navLabels) { expect(find.text(l), findsOneWidget); }
  expect(tester.getSemantics(find.byKey(const ValueKey('nav-home'))), containsSemantics(isSelected: true));
});
testWidgets('the account chip switches user', (tester) async {
  var switched = 0;
  await tester.pumpWidget(_app(SideMenu(selected: 0, onSelect: (_) {}, accountName: 'Hakan', onAccount: () => switched++)));
  await tester.tap(find.byKey(const ValueKey('nav-account')));
  expect(switched, 1);
  expect(find.byTooltip('Kullanıcı değiştir'), findsOneWidget);
});
testWidgets('in a narrow window the menu keeps only icons and does not overflow', (tester) async {
  tester.view.physicalSize = const Size(800, 600); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(SideMenu(selected: 0, onSelect: (_) {}, accountName: long, onAccount: () {})));
  expect(tester.takeException(), isNull);
  expect(find.text('Ana sayfa'), findsNothing);
  expect(find.byKey(const ValueKey('nav-home')), findsOneWidget);
});
testWidgets('PageHeader cuts a long title instead of overflowing', (tester) async {
  tester.view.physicalSize = const Size(800, 600); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(PageHeader(title: long, subtitle: '64 kanal', actions: const [SizedBox(width: 300, height: 44)])));
  expect(tester.takeException(), isNull);
});
```

`_app` bu testte `Scaffold(body: w)` döner (ortalamaz).

`test/home_page_test.dart`:

```dart
testWidgets('the shell is the side menu, not a navigation rail', (tester) async {
  await _pumpHome(tester, _FakeClient());
  expect(find.byType(NavigationRail), findsNothing);
  expect(find.byType(SideMenu), findsOneWidget);
});
testWidgets('each list tab has its own heading', (tester) async {
  await _pumpHome(tester, _FakeClient());
  await tester.tap(find.byKey(const ValueKey('nav-movies')));
  await _settle(tester);
  expect(find.widgetWithText(PageHeader, 'Filmler'), findsOneWidget);
  expect(find.text('1 film'), findsOneWidget);
});
```

- [ ] **Step 3: Testlerin başarısız olduğunu gör**

Run: `flutter test test/ui/shell_test.dart test/home_page_test.dart test/group_order_test.dart`
Expected: yeni testler ve bulucusu değişenler FAIL.

- [ ] **Step 4: `shell.dart` dosyasını yaz ve `HomePage.build` gövdesini değiştir**

Kararlar:
- `SideMenu`: `AppCard` içinde, dış boşluk 24, iç boşluk 22/14/16. Marka: 36×36 mavi kare (yarıçap 12) içinde beyaz `Icons.play_arrow_rounded`, yanında "IPTV" (`title` 20). Öğeler `FocusRing(radius: 16)`, yükseklik 48. Seçili öğe `Semantics(selected: true)`. Hesap çipi: `surfaceAlt` zemin, yarıçap 18, koyu dairede baş harf ve ad, `Tooltip('Kullanıcı değiştir')`. Dar hâlde genişlik 76, yalnızca ikonlar, her öğenin `tooltip`'i adıdır.
- `HomePage.build`: `Scaffold(body: Row([SideMenu(selected: _tab, onSelect: _select, accountName: widget.account.name, onAccount: () => Navigator.of(context).pop()), SizedBox(width: 26), Expanded(_content())]))`. `NavigationRail` ve `VerticalDivider` silinir. `PopScope` mantığı aynen kalır.
- Başlıklar: ana sayfa `greeting(DateTime.now())` + ", " + hesap adı. Canlı TV alt bilgisi "{kategori ya da 'Tümü'}, {n} kanal". Filmler ve Diziler "{n} film" / "{n} dizi" (`groupCount` ile). Sağ eylemler: arama (`SearchField(hint: 'Kanal ara' | 'Film ara' | 'Dizi ara' | 'Favorilerde ara')`), film ve dizide sıralama düğmesi (Görev 7'de içi dolar, şimdilik mevcut `DropdownButton` kalabilir), saat. Ayarlar başlığı "Ayarlar".
- Bu görevde gövdeler eski hâliyle kalabilir. Görev 5–8 onları yeniler.

- [ ] **Step 5: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/ui/shell.dart lib/src/home_page.dart test
git commit -m "feat: side menu card and page headers replace the navigation rail"
```

---

### Task 5: Ana sayfa

**Files:**
- Modify: `lib/src/home_page.dart:423-485` (`_homeView`, `_row`, `_card`, `_itemCard`, `_historyCard`)
- Modify: `lib/src/poster_card.dart` (`PosterImage`'a `cacheWidth` parametresi, varsayılan 260)
- Modify: `lib/src/epg_widgets.dart:62-92` (`NowPlaying` yazı stilleri `AppText.meta(13)`, çubuk `ProgressBar`)
- Test: `test/home_view_test.dart`
- Mockup: `Main.dc.html`

**Interfaces:**
- Consumes: `AppCard`, `AppButton`, `Pill`, `ProgressBar`, `ChannelBadge`, `LiveDot`, `remainingText`, `EpgCache`, `NowPlaying`, `Library.instance.continueWatching`, `HistoryEntry.positionMs/durationMs/progress`.

- [ ] **Step 1: Başarısız testleri yaz**

`test/home_page_test.dart` içindeki `_FakeClient` ve `_pumpHome` kalıbını kopyala. Geçmişi `Library.instance.use(_acc)` sonrasında `touch(...)` ve `savePosition(url, position, total)` ile doldur (`_seedHistory`). Favorileri `toggleFavorite(item)` ile ekle.

```dart
testWidgets('an empty library shows the invitation and no continue card', (tester) async {
  await _pumpHome(tester);
  expect(find.textContaining('Burası senin sayfan'), findsOneWidget);
  expect(find.text('Kaldığın yerden'), findsNothing);
  expect(find.text('Son izlediklerin'), findsNothing);
  expect(find.text('Kanallarım'), findsNothing);
  expect(tester.takeException(), isNull);
});
testWidgets('the newest resumable entry is the continue card, with its time left', (tester) async {
  await _seedHistory(url: 'http://x/movie/u/p/1.mkv', title: 'Dune |2024| TR-EN', kind: Kind.movie,
    position: const Duration(hours: 1, minutes: 34), total: const Duration(hours: 2, minutes: 46));
  await _pumpHome(tester);
  expect(find.text('Kaldığın yerden'), findsOneWidget);
  expect(find.text('Dune'), findsOneWidget);
  expect(find.text('1 sa 12 dk kaldı'), findsOneWidget);
  expect(find.text('Devam et'), findsOneWidget);
});
testWidgets('an entry with unknown duration shows no time left', (tester) async {
  await _seedHistory(url: 'http://x/movie/u/p/2.mkv', title: 'Süresiz', kind: Kind.movie,
    position: const Duration(minutes: 5), total: Duration.zero);
  await _pumpHome(tester);
  expect(find.text('Süresiz'), findsOneWidget);
  expect(find.textContaining('kaldı'), findsNothing);
});
testWidgets('the greeting names the account', (tester) async {
  await _pumpHome(tester);
  expect(find.textContaining(', Demo'), findsOneWidget);
});
testWidgets('favorite channels fill the channel panel', (tester) async {
  await _seedFavoriteChannels(['TRT 1', 'NTV']);
  await _pumpHome(tester);
  expect(find.text('Kanallarım'), findsOneWidget);
  expect(find.text('T1'), findsOneWidget);
  expect(find.text('NT'), findsOneWidget);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/home_view_test.dart`
Expected: FAIL.

- [ ] **Step 3: `_homeView` gövdesini yeniden yaz**

Belgenin "Ana sayfa" bölümü ve mockup'a göre. Kararlar:
- Gövde `ListView(padding: EdgeInsets.fromLTRB(8, 8, 26, 24))`, içinde ana kart ve alt bölüm.
- Ana kart: `AppCard(radius: 28)` + `ClipRRect`. Sağdaki görsel `PosterImage(logo, cacheWidth: 640)`, genişlik 560 (kart 900'den darsa kartın %45'i), üstünde soldan sağa beyazdan saydama 200 piksellik `LinearGradient` (izin verilen tek geçiş). Canlı kanal kaydında görsel yerine `ChannelBadge(size: 120)` ortada, `surfaceAlt` zemin.
- Kalan süre: `durationMs > 0` ise `remainingText(Duration(milliseconds: durationMs - positionMs))`, değilse çubuk ve süre çizilmez.
- "Devam et" `AppButton(variant: primary, height: 48, icon: Icons.play_arrow_rounded, autofocus: AppSettings.instance.tvMode)`, odak halkası belgede.
- Alt bölüm `LayoutBuilder`: genişlik 900 ve üstüyse `Row([Expanded(sol), SizedBox(20), SizedBox(width: 326, kanal paneli)])`, darsa alt alta.
- Son izlediklerin kartı: `FocusRing(radius: 24)` içinde beyaz kart, `AppShadows.forRepeated()` ve `repeatedBorder()`. Alt satır: dizide `parseTitle` sonucu bölüm bilgisi bugün başlıkta duruyorsa olduğu gibi, yanına kalan süre.
- Kanal paneli: `AppCard`, iç liste `ListView.builder(itemExtent: 60)`. Satırda `NowPlaying(cache: _epg, item: it, fallback: groupLabel(it.group))`.
- Filmlerim ve Dizilerim: yatay `ListView.separated`, afiş 92×132, `FocusRing(radius: 16)`.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/home_page.dart lib/src/poster_card.dart lib/src/epg_widgets.dart test/home_view_test.dart
git commit -m "feat: home tab with a greeting, continue card, recents and a channel panel"
```

---

### Task 6: Kategori paneli ve Canlı TV listesi

**Files:**
- Modify: `lib/src/home_page.dart:374-421` (kategori sütunu), `:534-554` (`_heart`, `_liveList`)
- Test: `test/live_list_test.dart`, mevcut `test/group_order_test.dart`
- Mockup: `G-Canli.dc.html`

**Interfaces:**
- Consumes: `AppCard`, `SideItem`, `SearchField(onPage: false)`, `AppButton`, `ChannelBadge`, `ProgressBar`, `NowPlaying`, `groupCount`.
- Produces: `_HomePageState` içinde `Widget _categoryPanel(Kind kind, _View view)` ve `Widget _channelRow(Item it, int index)`. Görev 7 ve 8 bunları kullanır.

- [ ] **Step 1: Başarısız testleri yaz**

`_FakeClient.live()` üç kanal dönsün: `TRT 1` (`group: 'Ulusal'`), `NTV` (`group: 'Haber'`), `Kanal X` (`streamId` yok, `id: 'lx'`, `group: 'Yerel'`). `shortEpg` üzerine yazılarak `TRT 1` için bir program, diğerleri için boş liste dönsün.

```dart
testWidgets('channels are numbered by position and carry their badge', (tester) async {
  await _pumpLive(tester);
  expect(find.text('1'), findsWidgets);
  expect(find.text('T1'), findsOneWidget);
  expect(find.text('NT'), findsOneWidget);
});
testWidgets('a channel without programme data shows its category and still opens', (tester) async {
  await _pumpLive(tester);
  expect(find.text('Yerel'), findsWidgets);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  await tester.tap(find.text('Kanal X'));
  await _settle(tester);
  expect(find.byType(PlayerPage), findsOneWidget);
});
testWidgets('the edit categories key keeps its tooltip and opens the dialog', (tester) async {
  await _pumpLive(tester);
  await tester.tap(find.byTooltip('Kategorileri düzenle / gizle'));
  await _settle(tester);
  expect(find.text('Kategorileri düzenle'), findsWidgets);
});
testWidgets('the channel list leaves room for the focus ring', (tester) async {
  await _pumpLive(tester);
  final list = tester.widget<ListView>(find.byKey(const ValueKey('channel-list')));
  final pad = list.padding!.resolve(TextDirection.ltr);
  expect(pad.left, greaterThanOrEqualTo(AppSizes.scrollPad));
  expect(pad.top, greaterThanOrEqualTo(AppSizes.scrollPad));
});
```

`PlayerPage` açılırken `media_kit` test ortamında çalışmazsa son iki satır yerine `_open` çağrısının yapıldığını doğrula (`Navigator` gözlemcisi ile bir rota eklendiğini kontrol et).

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/live_list_test.dart`
Expected: FAIL.

- [ ] **Step 3: Kategori paneli ve kanal satırını yaz**

Kararlar:
- Liste sekmelerinin düzeni: `Row([SizedBox(width: 216, _categoryPanel), SizedBox(width: 20), Expanded(liste)])`, alttan 24.
- Kategori paneli: `AppCard`, iç boşluk 14/12. Üstte `SearchField(key: ValueKey('groupSearch$_tab'), hint: 'Kategori ara', onPage: false)`. Altında `ListView` içinde "Tümü" ve kategoriler `SideItem` olarak, sayılar `groupCount`. Mevcut `onSecondaryTapUp` ve `onLongPress` davranışı korunur, `Tooltip` adı tam gösterir. En altta `AppButton(icon: Icons.tune_rounded, label: 'Kategorileri düzenle', tooltip: 'Kategorileri düzenle / gizle', variant: secondary)`. Hesap adı satırı kalkar.
- Kanal listesi: `ListView.builder(key: ValueKey('channel-list'), padding: EdgeInsets.fromLTRB(8, 8, 26, 24), itemExtent: 76, …)`. Satır: `FocusRing(radius: 20)` içinde beyaz kap (yükseklik 68), `AppShadows.forRepeated()`. Sıra numarası `index + 1`.
- Kalp düğmesi: `AppButton(icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, …)` yerine renkleri özel olduğu için `FocusRing(radius: 22)` + `Icon` (favoriyse `live`, değilse `ink3`), boyut 44×44, ipucu metinleri bugünküyle aynı.
- `NowPlaying` satırın ikinci satırını ve sağdaki saat aralığı ile çubuğu çizer. Bu yüzden `NowPlaying`'e `layout: NowPlayingLayout.row` seçeneği ekle: program varsa `({Widget subtitle, Widget trailing})` üretir. Program yoksa ikinci satır kategori adı, sağ taraf boş.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS, `group_order_test.dart` dahil.

- [ ] **Step 5: Commit**

```bash
git add lib/src/home_page.dart lib/src/epg_widgets.dart test/live_list_test.dart
git commit -m "feat: category panel and live TV channel rows"
```

---

### Task 7: Filmler ve Diziler ızgarası, sıralama

**Files:**
- Modify: `lib/src/home_page.dart:487-514` (`_searchBar` sıralaması), `:516-572` (`_body`, `_posterGrid`)
- Modify: `lib/src/poster_card.dart` (`PosterCard` silinir, `PosterImage` kalır)
- Test: `test/poster_grid_test.dart`
- Mockup: `G-Filmler.dc.html`

**Interfaces:**
- Consumes: `_categoryPanel`, `FocusRing`, `AppButton(prefix: 'Sırala:')`, `PosterImage`.
- Produces: `int posterColumns(double width)` (üst düzey işlev, `home_page.dart` içinde) ve `Widget _posterTile(Item it)`. Görev 8 kullanır.

- [ ] **Step 1: Başarısız testleri yaz**

```dart
test('posterColumns', () {
  expect(posterColumns(756), 5);
  expect(posterColumns(788), 6);
  expect(posterColumns(300), 2);
  expect(posterColumns(100), 2);
});
testWidgets('a poster shows its clean title and year with language', (tester) async {
  await _pumpHome(tester, movies: [_movie('Kış Uykusu |2014| TR')]);
  await tester.tap(find.byKey(const ValueKey('nav-movies')));
  await _settle(tester);
  expect(find.text('Kış Uykusu'), findsOneWidget);
  expect(find.text('2014, TR'), findsOneWidget);
});
testWidgets('the sort key opens the four orders and applies the chosen one', (tester) async {
  await _pumpHome(tester, movies: [_movie('Zeta'), _movie('Alfa')]);
  await tester.tap(find.byKey(const ValueKey('nav-movies')));
  await _settle(tester);
  await tester.tap(find.text('Sırala:'));
  await _settle(tester);
  expect(find.text('Yıl, yeniden eskiye'), findsOneWidget);
  await tester.tap(find.text('A – Z').last);
  await _settle(tester);
  expect(tester.getTopLeft(find.text('Alfa')).dx < tester.getTopLeft(find.text('Zeta')).dx, isTrue);
});
testWidgets('live TV has no sort key', (tester) async {
  await _pumpHome(tester);
  await tester.tap(find.byKey(const ValueKey('nav-live')));
  await _settle(tester);
  expect(find.text('Sırala:'), findsNothing);
});
testWidgets('a long title and an 800 px window do not overflow', (tester) async {
  tester.view.physicalSize = const Size(800, 600); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _pumpHome(tester, movies: [_movie('Çok Uzun Bir Film Adı: Şeytanın Ağzından Çıkmış Öyküler ve Diğerleri |1999| TR')]);
  await tester.tap(find.byKey(const ValueKey('nav-movies')));
  await _settle(tester);
  expect(tester.takeException(), isNull);
});
testWidgets('the grid leaves room for the focus ring', (tester) async {
  await _pumpHome(tester, movies: [_movie('A')]);
  await tester.tap(find.byKey(const ValueKey('nav-movies')));
  await _settle(tester);
  final grid = tester.widget<GridView>(find.byKey(const ValueKey('poster-grid')));
  expect(grid.padding!.resolve(TextDirection.ltr).left, greaterThanOrEqualTo(AppSizes.scrollPad));
});
```

`_pumpHome(tester, movies: …)` için `_FakeClient`'a `movies` listesi parametresi ekle. `_movie(name)` bir `Item(kind: Kind.movie, url: 'u', …)` döner.

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/poster_grid_test.dart`
Expected: FAIL.

- [ ] **Step 3: Izgarayı ve sıralamayı yaz**

Kararlar:
- `posterColumns(w) = max(2, ((w + 16) / 134).floor())`.
- `GridView.builder(key: ValueKey('poster-grid'), padding: EdgeInsets.fromLTRB(8, 8, 26, 24), SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: posterColumns(w - 34), crossAxisSpacing: 16, mainAxisSpacing: 20, mainAxisExtent: kutuGenişliği * 1.53 + 52))`.
- Afiş kutusu: `FocusRing(radius: 20)` dışta, içte `ClipRRect(20)` + `PosterImage`. Gölge `AppShadows.forRepeated()`. Altında ad (`title` 15, tek satır) ve `'${year}, ${tags.first}'` (yıl ya da dil yoksa olan, ikisi de yoksa satır yok).
- Kalp: sağ üstte 30×30 beyaz daire, ayrı odak durağı. Favori değilse yalnızca kutu ya da kalp odakta veya fare üstündeyken görünür (opaklık 0, odaklanabilir kalır).
- Sıralama: `AppButton(variant: onPage, prefix: 'Sırala:', label: seçili ad, trailingIcon: Icons.expand_more_rounded)`, tıklanınca `showMenu`. Seçenek adları: "Varsayılan", "Yeni eklenen", "A – Z", "Yıl, yeniden eskiye".
- Yükleniyor: ortada 220 genişliğinde belirsiz `LinearProgressIndicator` (yükseklik 6, yuvarlak) ve "Yükleniyor...". Hata metni aynı, düğme `AppButton(variant: primary, label: 'Tekrar dene')`. "Sonuç yok" aynı.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/home_page.dart lib/src/poster_card.dart test/poster_grid_test.dart
git commit -m "feat: poster grid with rounded tiles, favorite badge and a sort key"
```

---

### Task 8: Favoriler sekmesi

**Files:**
- Modify: `lib/src/home_page.dart:359-366` (favoriler dalı), `:574-587` (`_mixedList` silinir)
- Test: `test/favorites_tab_test.dart`

**Interfaces:**
- Consumes: `_channelRow`, `_posterTile`, `posterColumns`, `AppText.title(18)`.

- [ ] **Step 1: Başarısız testleri yaz**

```dart
testWidgets('favorites are grouped by kind and empty groups are not drawn', (tester) async {
  await _seedFavorites(channels: ['TRT 1'], movies: ['Arrival |2016| EN']);
  await _pumpHome(tester);
  await tester.tap(find.byKey(const ValueKey('nav-favorites')));
  await _settle(tester);
  expect(find.text('Kanallar'), findsOneWidget);
  expect(find.text('Filmler'), findsNWidgets(2), reason: 'the section heading and the menu item');
  expect(find.text('Diziler'), findsOneWidget, reason: 'only the menu item');
  expect(find.text('Arrival'), findsOneWidget);
});
testWidgets('no favorites shows the existing hint', (tester) async {
  await _pumpHome(tester);
  await tester.tap(find.byKey(const ValueKey('nav-favorites')));
  await _settle(tester);
  expect(find.textContaining('Henüz favori yok'), findsOneWidget);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/favorites_tab_test.dart`
Expected: FAIL.

- [ ] **Step 3: Favoriler dalını yeniden yaz**

`CustomScrollView(slivers: …)`, iç boşluk 8/8/26/24. Her dolu tür için bir başlık ve bir sliver: kanallar `SliverFixedExtentList(itemExtent: 76)` + `_channelRow`, film ve diziler `SliverGrid` + `_posterTile`. Kanal sırası favori kanal listesindeki sıradır. Boş durumda mevcut metin `AppCard` içinde, ortada.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/home_page.dart test/favorites_tab_test.dart
git commit -m "feat: favorites tab grouped into channels, movies and series"
```

---

### Task 9: Detay sayfası

**Files:**
- Modify: `lib/src/detail_page.dart` (tamamı. `_play`, `initState` ve oynatma sırası mantığı korunur)
- Test: `test/detail_page_test.dart`
- Mockup: `G-Detay.dc.html`

**Interfaces:**
- Consumes: `AppCard`, `AppButton`, `Pill`, `ProgressBar`, `ClockPill`, `FocusRing`, `remainingText`, `clockTime`, `minutesLabel`, `Library.instance.positionFor`, `Library.instance.history`.
- Produces: `_DetailPageState` içinde `int? _season` ve `Episode? _resumeEpisode(List<Episode>)`.

- [ ] **Step 1: Başarısız testleri yaz**

Sahte istemci `seriesData` ve `vodDetails` üzerine yazar. Bölüm adresleri `'http://x/series/u/p/{season}{number}.mkv'` biçimindedir. Geçmişi `Library.instance.touch` ve `savePosition` ile doldur.

```dart
testWidgets('only the selected season is listed and its key switches the list', (tester) async {
  await _pumpDetail(tester, _series(seasons: {1: ['Pilot', 'İkinci'], 2: ['Dönüş']}));
  expect(find.text('Pilot'), findsOneWidget);
  expect(find.text('Dönüş'), findsNothing);
  expect(find.byType(ExpansionTile), findsNothing);
  await tester.tap(find.text('2. sezon'));
  await _settle(tester);
  expect(find.text('Dönüş'), findsOneWidget);
  expect(find.text('Pilot'), findsNothing);
});
testWidgets('the season of the episode in progress is selected and offered on open', (tester) async {
  await _seedPosition(_episodeUrl(2, 1), const Duration(minutes: 21), const Duration(minutes: 48));
  await _pumpDetail(tester, _series(seasons: {1: ['Pilot'], 2: ['Dönüş']}));
  expect(find.text('Dönüş'), findsOneWidget);
  expect(find.text('27 dk kaldı'), findsOneWidget);
  expect(find.text('1. bölümden devam et'), findsOneWidget);
});
testWidgets('a series with nothing in progress offers the first episode', (tester) async {
  await _pumpDetail(tester, _series(seasons: {1: ['Pilot']}));
  expect(find.text('İlk bölümü oynat'), findsOneWidget);
});
testWidgets('a movie with a saved position offers to resume', (tester) async {
  await _seedPosition(_movieUrl, const Duration(minutes: 21, seconds: 4), const Duration(hours: 2));
  await _pumpDetail(tester, _movie());
  expect(find.text('Devam et 21:04'), findsOneWidget);
});
testWidgets('empty facts are left out and nothing breaks', (tester) async {
  await _pumpDetail(tester, _movie(details: Details()));
  expect(find.textContaining('Yönetmen'), findsNothing);
  expect(find.textContaining('Oyuncular'), findsNothing);
  expect(find.text('Oynat'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
testWidgets('an episode with an unknown duration shows no minutes', (tester) async {
  await _pumpDetail(tester, _series(seasons: {1: ['Pilot']}, duration: ''));
  expect(find.textContaining(' dk'), findsNothing);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/detail_page_test.dart`
Expected: FAIL.

- [ ] **Step 3: Sayfayı yeniden yaz**

Kararlar:
- `AppBar` kalkar. Üst satır: `AppButton(variant: onPage, icon: Icons.chevron_left_rounded, label: 'Geri', onPressed: maybePop)`, yol (`meta` 15 "Filmler" ya da "Diziler", `Icons.chevron_right_rounded`, ad `label` 15), sağda `ClockPill`.
- Gövde `ListView(padding: EdgeInsets.fromLTRB(26, 16, 26, 24))`.
- Bilgi kartı `AppCard` + `ClipRRect(28)`, yükseklik en az 300, içerik uzarsa uzar. Afiş `ClipRRect(20)` 168×252. Açıklama `maxLines: 3`. Arka plan görseli sağda, 600 genişlik, beyaz geçişle. Görsel adresi boşsa ya da pencere 1100'den darsa çizilmez.
- Etiketler `Pill` ile, sırası belgede. Puan `'0'` ya da boşsa yok.
- Birincil düğme: `AppButton(variant: primary, height: 48, icon: Icons.play_arrow_rounded, autofocus: AppSettings.instance.tvMode)`. Film metni `resume == null ? 'Oynat' : 'Devam et ${clockTime(resume)}'`. Dizi metni `_resumeEpisode` varsa `'${e.number}. bölümden devam et'`, yoksa `'İlk bölümü oynat'`. Dizide basılınca `_play(queue, position[e]!)`.
- `_resumeEpisode`: bölümler sezon ve numara sırasıyla gezilir, `Library.instance.positionFor(e.url) != null` olan ilki.
- Favori düğmesi: favoriyse `AppButton(variant: danger, icon: Icons.favorite_rounded, label: 'Favorilerde')`, değilse `AppButton(variant: secondary, icon: Icons.favorite_border_rounded, label: 'Favorilere ekle')`.
- Sezonlar: `_season ??= _resumeEpisode?.season ?? ilk sezon`. Düğmeler hap, seçili olan `primary`, diğerleri `onPage`.
- Bölüm ızgarası: 4 sütun (pencere 1100'den darsa 3, 800'den darsa 2), aralık 16. Kart `FocusRing(radius: 24)` + beyaz kart. Görsel yoksa `widget.item.logo`. Etiket `Pill('${e.number}. bölüm', tone: PillTone.onImage)`. Alt satır: devam ediyorsa ve süre biliniyorsa `remainingText(...)` (`accentInk`), devam ediyor ama süre bilinmiyorsa "Devam ediliyor", değilse `minutesLabel(e.duration)` (boşsa satır yok). Başlık `e.title` boşsa `'${e.number}. bölüm'`.
- Yükleniyor: kartın içinde 220 genişliğinde belirsiz mavi çubuk. Hata metni aynı, renk `liveText`.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/detail_page.dart test/detail_page_test.dart
git commit -m "feat: detail page with an info card, season pills and episode cards"
```

---

### Task 10: Oynatıcı

**Files:**
- Create: `lib/src/player_chrome.dart`
- Modify: `lib/src/player_page.dart:330-347` (rakam göstergesi), `:712-800` (`build` içindeki kutular), `:804-918` (`_chrome`), `:920-953` (`_seekBar`), `:955-1042` (`_GoToDialog` görünümü), `_pick` penceresi
- Test: `test/player_chrome_test.dart`
- Mockup: `G-Oynatici.dc.html`, `G-OynaticiCanli.dc.html`

**Interfaces:**
- Consumes: `AppButton`, `AppSwitch(small: true)`, `Pill`, `LiveDot`, `ChannelBadge`, `ProgressBar`, `ClockPill`, `clockTime`, `hhmm`.
- Produces (hiçbiri `Player` gerektirmez, bu yüzden test edilebilir):

```dart
class PlayerTitlePill extends StatelessWidget {
  const PlayerTitlePill({super.key, required this.onBack, required this.title, this.subtitle});
}
class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.children});   // beyaz, yarıçap 28, AppShadows.overlay, iç boşluk 18/22/16
}
class VodTimeline extends StatelessWidget {
  const VodTimeline({super.key, required this.position, required this.duration, this.buffer = Duration.zero,
    this.pending = false, this.onSeek});
  final ValueChanged<Duration>? onSeek;
}
class LiveInfo extends StatelessWidget {
  const LiveInfo({super.key, required this.index, required this.name, this.logo = '', this.programmes = const [],
    this.prevName, this.nextName, this.now});
  final int index;                      // sıradaki yeri, 0 tabanlı
  final DateTime Function()? now;
}
```

`_Controls` yeni parametreler alır: `required int index`, `String? prevTitle`, `String? logo`, `String? subtitle`. `_PlayerPageState._video()` bunları `_index`, `widget.queue[_index - 1].title`, `entry.logo` ile verir. Dizi bölümünde alt bilgi, başlıktaki `S01E03` kalıbından "1. sezon 3. bölüm" olarak türetilir (`RegExp(r'S(\d+)E(\d+)')`), kalıp yoksa alt bilgi yok.

- [ ] **Step 1: Başarısız testleri yaz**

```dart
Widget _wrap(Widget w) => MaterialApp(theme: buildAppTheme(), home: Scaffold(backgroundColor: Colors.black, body: Align(alignment: Alignment.bottomCenter, child: SizedBox(width: 1200, child: w))));
Programme p(String t, DateTime s, DateTime e) => Programme(title: t, start: s, end: e);

testWidgets('the timeline shows elapsed time and time left', (tester) async {
  await tester.pumpWidget(_wrap(const VodTimeline(position: Duration(minutes: 21, seconds: 4), duration: Duration(minutes: 48, seconds: 12))));
  expect(find.text('21:04'), findsOneWidget);
  expect(find.text('-27:08'), findsOneWidget);
});
testWidgets('an unknown duration shows no time left and a disabled bar', (tester) async {
  await tester.pumpWidget(_wrap(const VodTimeline(position: Duration(seconds: 5), duration: Duration.zero)));
  expect(find.text('--:--'), findsOneWidget);
  expect(find.textContaining('-0:'), findsNothing);
  expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
});
testWidgets('live info shows the channel, the current and the next programme, and its neighbours', (tester) async {
  final now = DateTime(2026, 11, 16, 21, 47);
  await tester.pumpWidget(_wrap(LiveInfo(index: 11, name: 'TRT Spor', now: () => now, prevName: 'TRT 1', nextName: 'NTV', programmes: [
    p('Stadyum', DateTime(2026, 11, 16, 21), DateTime(2026, 11, 16, 22, 30)),
    p('Spor Haberleri', DateTime(2026, 11, 16, 22, 30), DateTime(2026, 11, 16, 23)),
  ])));
  expect(find.text('12'), findsOneWidget);
  expect(find.text('TRT Spor'), findsOneWidget);
  expect(find.text('Canlı'), findsOneWidget);
  expect(find.text('Stadyum'), findsOneWidget);
  expect(find.text('21:00 – 22:30'), findsOneWidget);
  expect(find.textContaining('Sırada 22:30'), findsOneWidget);
  expect(find.text('TRT 1'), findsOneWidget);
  expect(find.text('NTV'), findsOneWidget);
});
testWidgets('live info without programme data shows only the channel', (tester) async {
  await tester.pumpWidget(_wrap(const LiveInfo(index: 0, name: 'Kanal X')));
  expect(find.text('Kanal X'), findsOneWidget);
  expect(find.textContaining('Sırada'), findsNothing);
  expect(tester.takeException(), isNull);
});
testWidgets('the title pill goes back', (tester) async {
  var back = 0;
  await tester.pumpWidget(_wrap(PlayerTitlePill(onBack: () => back++, title: 'Breaking Bad', subtitle: '1. sezon 3. bölüm')));
  await tester.tap(find.byTooltip('Geri'));
  expect(back, 1);
  expect(find.text('1. sezon 3. bölüm'), findsOneWidget);
});
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/player_chrome_test.dart`
Expected: FAIL.

- [ ] **Step 3: `player_chrome.dart` dosyasını yaz**

Kararlar:
- `VodTimeline`: Material `Slider` korunur, `SliderTheme` ile giydirilir: iz yüksekliği 8, yuvarlak iz, etkin `accent`, pasif `line`, `secondaryTrackValue` tampon ve rengi `buffered`, tutamaç 20 piksellik mavi daire, 3 piksel beyaz kenar, küçük gölge, kaplama saydam. Sol metin `clockTime(position)` (`title` 15, `pending` iken `accent`). Sağ metin süre biliniyorsa `'-${clockTime(duration - position)}'`, bilinmiyorsa `--:--` (`meta` 15).
- `LiveInfo`: şimdiki program `start <= now < end`, sıradaki `start > now` olan ilk kayıt. Komşular `prevName` ve `nextName` doluysa çizilir, numaraları `index` ve `index + 2`.
- `PlayerTitlePill`: beyaz hap, yükseklik 52, `AppShadows.overlay`. Geri düğmesi `AppButton(variant: secondary, icon: Icons.chevron_left_rounded, tooltip: 'Geri', height: 40)`.

- [ ] **Step 4: `_chrome`, `_seekBar` ve kutuları yeni parçalarla kur**

Kararlar:
- Karartma geçişleri (`LinearGradient`) silinir. Video olduğu gibi kalır, üstünde sol üstte `PlayerTitlePill`, sağ üstte `ClockPill`, altta 28 piksel kenar boşluğuyla `PlayerCard`.
- Tuş sırası belgenin "Oynatıcı" bölümlerinde. `_playNode` oynat düğmesinde kalır (`AppButton(variant: primary, height: 60, width: 60)`). `FocusScope` ve `_barFocused` mantığı aynen korunur.
- Sarma düğmeleri `AppButton(variant: secondary, label: '-${_skip.inSeconds}')` ve `'+${…}'`, genişlik 56.
- Otomatik sonraki: `AppButton(variant: secondary, child: Row([Text('Otomatik sonraki'), AppSwitch(small: true, focusable: false, value: on, onChanged: …)]))`. Tıklama davranışı aynı.
- Hız: `AppButton(label: r == 1.0 ? '1x' : '${r}x')`.
- Ses ve altyazı: `AppButton(label: geçerli parçanın _trackLabel değeri, en çok 14 karakter)`. Altyazı kapalıyken "Altyazı kapalı".
- Ses: `AppButton(icon: …, variant: secondary)` kapatma için, yanında kumanda modu kapalıyken 100 genişliğinde ses çubuğu (`SliderTheme`: iz 6, etkin `ink`, tutamaç yok, sürüklenebilir).
- Canlıda `LiveInfo`'ya `widget.epg` sonucu `FutureBuilder` ile verilir. Canlıda orta tuşlar "Önceki kanal", oynat, "Sonraki kanal" (`AppButton` ikon ve yazıyla).
- Hata kutusu, sayaç kutusu, kısa bilgi: beyaz kart, yarıçap 28, `AppShadows.overlay`, metin `ink`, düğmeler `AppButton`. Yazılan kanal numarası: sağ üstte beyaz kart içinde `display` 40.
- Tampon göstergesi: ortada `CircularProgressIndicator`, beyaz daire zemin üstünde (video karanlık olabilir).
- `_pick` ve `_GoToDialog`: yapı aynı, görünüm Görev 13'teki pencere temasından gelir. Seçili parça satırında solda `Icons.check_rounded` (`accent`).

- [ ] **Step 5: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 6: Elle dene**

Run: `flutter run -d linux`
Bir film ve bir canlı kanal aç. Dene: sarma, zamana gitme, ses, hız, parça seçme, tam ekran, sonraki bölüm sayacı, rakamla kanal seçme, yukarı ve aşağı ile kanal değiştirme, fare durunca denetimlerin gizlenmesi. Parlak bir sahnede beyaz kartın ve hapın okunaklı kaldığına bak.

- [ ] **Step 7: Commit**

```bash
git add lib/src/player_chrome.dart lib/src/player_page.dart test/player_chrome_test.dart
git commit -m "feat: player controls in a floating white card with a channel info block"
```

---

### Task 11: Profil seçimi, giriş ve QR penceresi

**Files:**
- Modify: `lib/src/login_page.dart:172-296` (görünüm), `:298-418` (`_avatarColor`, `_ProfileCard`, `_AddCard` yeniden yazılır; `_avatarColor` yerine `tintFor`)
- Modify: `lib/src/remote_entry.dart:128-155` (pencere görünümü)
- Test: mevcut `test/login_page_test.dart` (değişmeden geçmeli) ve yeni testler aynı dosyada
- Mockup: `G-Profiller.dc.html`

**Interfaces:**
- Consumes: `AppCard`, `AppButton`, `Pill`, `FocusRing`, `ClockPill`, `tintFor`, `SearchField` görünümü (alanlar için).

- [ ] **Step 1: Başarısız testleri ekle**

```dart
testWidgets('a profile card shows the initial, the name and no Material avatar', (tester) async {
  await _pump(tester, auto: false, saved: [_a, _b], last: _a.key);
  expect(find.text(_a.name.characters.first.toUpperCase()), findsWidgets);
  expect(find.byType(CircleAvatar), findsNothing);
  expect(find.text('Telefondan QR ya da elle'), findsOneWidget);
  expect(find.text('Açılışta son kullanılan hesapla otomatik giriş yapılır.'), findsOneWidget);
});
testWidgets('edit mode marks every profile for deletion', (tester) async {
  await _pump(tester, auto: false, saved: [_a, _b], last: _a.key);
  await tester.tap(find.text('Kullanıcıları düzenle'));
  await _settle(tester);
  expect(find.text('Sil'), findsNWidgets(2));
  expect(find.text('Silinecek kullanıcıyı seç'), findsOneWidget);
  expect(find.text('Bitti'), findsOneWidget);
});
```

`_a`, `_b`, `_pump`, `_settle` dosyada zaten var.

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/login_page_test.dart`
Expected: yeni testler FAIL, eskiler PASS.

- [ ] **Step 3: Görünümü yeniden yaz**

Kararlar:
- Sol üstte marka (Görev 4'teki mavi kare ve "IPTV", `SideMenu`'den ayrı küçük bir `BrandMark` widget'ı olarak `shell.dart` içine taşı), sağ üstte `ClockPill`.
- Profil kartları `Wrap(spacing: 22, runSpacing: 22, alignment: center)`. Kart: `FocusRing(radius: 28)` + `AppCard(radius: 28)`, genişlik 210, iç boşluk 26/16/22. Daire 96, renk çifti `tintFor(account.key)`. Sunucu `Uri.tryParse(host)?.host ?? host`. "Son kullanılan" `Pill(tone: accent)`, olmayan kartta aynı yükseklikte boşluk. Düzenlemede sağ üstte `Pill('Sil', tone: live)`.
- Ekleme kartı: 2 piksel kesikli çerçeve (`CustomPaint`, `dashed` rengi, yarıçap 28).
- Form: `AppCard(radius: 28)` 420 genişlik, iç boşluk 28. Alanlar `RemoteTextField` + `InputDecoration(labelText:, filled: true, fillColor: surfaceAlt, border: OutlineInputBorder(borderRadius: 22, borderSide: none))`, odakta 3 piksel `ink` çerçeve. "Telefondan gir (QR)" `AppButton(variant: secondary, icon: Icons.qr_code_2_rounded)`. "Kullanıcı Ekle" `AppButton(variant: primary)`, meşgulken içinde küçük beyaz dönen gösterge. "Kayıtlı kullanıcılara dön" `AppButton(variant: onPage)`.
- Açılış ekranı: ortada `AppCard`: marka, metin, 220 genişliğinde belirsiz mavi çubuk, `AppButton('Vazgeç / kullanıcı değiştir')`.
- Silme onayı ve QR penceresi yapısı aynı, düğmeler `AppButton`. QR beyaz zeminde kalır.
- Hata metni rengi `liveText`.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS, eski login testleri değişmeden.

- [ ] **Step 5: Commit**

```bash
git add lib/src/login_page.dart lib/src/remote_entry.dart lib/src/ui/shell.dart test/login_page_test.dart
git commit -m "feat: profile picker, sign-in card and QR dialog in the light look"
```

---

### Task 12: Ayarlar

**Files:**
- Modify: `lib/src/settings_page.dart` (tamamı. `_ConnectionTile._refresh` mantığı korunur)
- Modify: `test/settings_page_test.dart`
- Mockup: `G-Ayarlar.dc.html`

**Interfaces:**
- Consumes: `AppCard`, `SideItem`, `Segmented`, `AppSwitch(focusable: false)`, `AppButton`, `FocusRing(inside: true)`, `Pill`, `ChannelBadge`.
- Produces: seçenek denetimlerine anahtarlar: `setting-audioLang`, `setting-subLang`, `setting-skipSecs` (`Segmented`), `setting-cacheSecs`, `setting-uiScale` (açılır menü düğmesi).

- [ ] **Step 1: Mevcut testleri yeni denetime göre güncelle, yenilerini ekle**

```dart
testWidgets('the Android default buffer of 15 s is shown as the selected buffer size', (tester) async {
  await _pumpSettings(tester, cacheSecs: 15);
  expect(tester.takeException(), isNull);
  expect(find.descendant(of: find.byKey(const ValueKey('setting-cacheSecs')), matching: find.text('15 sn')), findsOneWidget);
});
testWidgets('a stored value that is not one of the choices does not break the settings page', (tester) async {
  await _pumpSettings(tester, cacheSecs: 45);
  expect(tester.takeException(), isNull);
  expect(find.text('Ön bellek (tampon)'), findsOneWidget);
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
  await tester.tap(find.text('Donanım hızlandırma'));
  await tester.pump();
  expect(AppSettings.instance.hwdec, !before);
});
testWidgets('nothing overflows at 800 x 600', (tester) async {
  await _pumpSettings(tester, cacheSecs: 15);
  tester.view.physicalSize = const Size(800, 600);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
});
```

`hwdec` testi gerçek tercih dosyasına yazmaz, `SharedPreferences.setMockInitialValues` zaten çağrılıyor. Testin sonunda değeri geri al (`addTearDown`).

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `flutter test test/settings_page_test.dart`
Expected: FAIL.

- [ ] **Step 3: Sayfayı yeniden yaz**

Kararlar:
- `StatelessWidget` yerine `StatefulWidget`: seçili bölüm indeksi ve her bölüm kartı için bir `GlobalKey`. Bölüm öğesi `Scrollable.ensureVisible(key.currentContext!, duration: 200 ms, alignment: 0)` çağırır. Kaydırma dinleyicisi en üstte görünen kartın bölümünü seçili yapar.
- Düzen: `Row([SizedBox(width: 216, bölüm paneli), SizedBox(20), Expanded(SingleChildScrollView(padding: 8/8/26/24, Column(kartlar)))])`. `SingleChildScrollView` seçildi çünkü kart sayısı az ve `ensureVisible` için bütün kartların kurulmuş olması gerekir.
- Bölümler ve satırları koddakiyle aynı sırada. Hesap kartı ayrı, en üstte.
- Satır: `FocusRing(inside: true, radius: 18)`, yükseklik en az 64, iç boşluk 8/12. Anahtar satırında satırın tamamı tıklanınca değer değişir, anahtar `focusable: false`. Seçenek satırında odak `Segmented` içindeki seçeneklere girer, satır odak almaz.
- Açıklamalar `maxLines: 2`. Pencere 900'den darsa `Segmented` satır altına iner (`Wrap`).
- Ön bellek ve arayüz ölçeği: `AppButton(key:, label: seçili değer, trailingIcon: Icons.expand_more_rounded)` + `showMenu`. Kayıtlı değer seçeneklerde yoksa düğme "Özel" yazar.
- Bağlantı sayacı: `ok` ya da `liveText` renkli `title` 15, yanında `AppButton(icon: Icons.refresh_rounded, tooltip: 'Yenile')`, meşgulken küçük gösterge.
- Telefon kumandası QR bloğu: QR beyaz zeminde, `ClipRRect(16)`, yanında metinler.
- Kısayollar: solda `Pill(tuş, tone: neutral)`, sağda açıklama.

- [ ] **Step 4: Testleri çalıştır**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/settings_page.dart test/settings_page_test.dart
git commit -m "feat: settings with a section index, cards, switches and segmented choices"
```

---

### Task 13: Pencereler, menüler, temizlik ve son doğrulama

**Files:**
- Modify: `lib/src/ui/app_theme.dart` (pencere, menü, onay kutusu, ipucu temaları)
- Modify: `lib/src/home_page.dart:180-307` (`_groupMenu`, `_manageGroups` görünümü)
- Delete: `lib/src/focus_frame.dart`
- Modify: `README.md` (arayüzü anlatan satırlar)
- Test: `test/ui/theme_test.dart`

- [ ] **Step 1: Başarısız testi yaz**

```dart
test('dialogs and menus are white rounded cards', () {
  final t = buildAppTheme();
  expect(t.dialogTheme.backgroundColor, AppColors.surface);
  expect((t.dialogTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(28));
  expect(t.popupMenuTheme.color, AppColors.surface);
  expect((t.popupMenuTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(20));
  expect(t.checkboxTheme.shape, isA<RoundedRectangleBorder>());
  expect(t.tooltipTheme.decoration, isA<BoxDecoration>());
});
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `flutter test test/ui/theme_test.dart`
Expected: FAIL.

- [ ] **Step 3: Temayı tamamla**

Kararlar: `dialogTheme` (zemin `surface`, yarıçap 28, yükselti 0 ama `shadowColor` ile `overlay` benzeri gölge için `elevation: 24`, `surfaceTintColor` saydam, başlık `display` 24), `popupMenuTheme` ve `menuTheme` (zemin `surface`, yarıçap 20, `surfaceTintColor` saydam, metin `label` 15), `checkboxTheme` (işaretli dolgu `accent`, işaret beyaz, kenar `dashed`, yarıçap 6), `tooltipTheme` (zemin `ink`, yazı beyaz `label` 13, yarıçap 10), `dividerTheme` (`line`, 1), `snackBarTheme` (zemin `ink`, yarıçap 16, yüzer).

- [ ] **Step 4: Kategori düzenleme penceresini ve sağ tık menüsünü giydir**

`_manageGroups`: `ListTile` satırları yerine 52 yüksekliğinde `FocusRing(inside: true, radius: 16)` satırı. İkon düğmeleri `AppButton(icon:, height: 36, width: 36, tooltip:)`. İpucu metinleri ("En üste al", "Yukarı", "Aşağı") ve "Tamam", "Sırayı sıfırla" aynen kalır. `Checkbox` kalır (test onu arıyor). Arama alanı `SearchField(onPage: false)`.

- [ ] **Step 5: Kalıntı taraması**

```bash
grep -rn "FocusFrame\|NavigationRail\|ListTile(\|SwitchListTile\|ExpansionTile\|FilledButton\|OutlinedButton\|TextButton\|DropdownButton\|CircleAvatar\|Chip(\|Card(" lib/
grep -rn "BackdropFilter\|ShaderMask" lib/
grep -rn "Color(0x\|Colors\.\(white\|black\|red\|grey\|white10\|white24\|black54\|black87\)" lib/src --include=*.dart | grep -v "lib/src/ui/tokens.dart"
```

Expected: ilk iki komut boş. Üçüncüde yalnızca QR kodunun beyaz zemini ve oynatıcının siyah zemini kalır. Kalan her satırı belirteçlere çevir, sonra `lib/src/focus_frame.dart` dosyasını sil.

- [ ] **Step 6: Bütün testler ve analiz**

Run: `flutter analyze && flutter test`
Expected: analiz temiz, bütün testler PASS.

- [ ] **Step 7: Linux'ta ekran ekran karşılaştır**

Run: `flutter run -d linux`
Pencereyi 1280×720 yap. Her ekranı ilgili mockup dosyasıyla yan yana koy: ana sayfa, canlı TV, filmler, diziler, favoriler, film detayı, dizi detayı, iki oynatıcı, profil seçimi, giriş formu, ayarlar, kategori düzenleme penceresi. Sonra pencereyi 800×600 yap, Ayarlar'dan ölçeği %50 ve %140 yapıp taşma olmadığına bak. Yalnızca klavyeyle (yön tuşları, Enter, Esc) her ekrandaki her denetime ulaşılabildiğini ve odak çerçevesinin hiçbir yerde kesilmediğini doğrula.

- [ ] **Step 8: TV stick üzerinde elle dene**

Bunu kullanıcı yapar ya da kullanıcıyla birlikte yapılır. Kontrol listesi: odak her an görünüyor mu, gölgesiz kartlar düz ve temiz duruyor mu, 20 000 filmlik ızgarada ve uzun kanal listesinde gezinmek akıcı mı, oynatıcıda yukarı ve aşağı kanal değiştiriyor mu, metin alanına OK ile girilip çıkılabiliyor mu, karanlık odada ekran rahatsız edici parlak mı.

- [ ] **Step 9: README'yi güncelle ve commit**

`README.md` içinde arayüzü anlatan cümleleri yeni düzene göre düzelt (açık tema, sol menü kartı, kart görünümü). Yeni özellik iddia etme.

```bash
git add -A lib test README.md
git commit -m "feat: dialogs and menus in the light look; remove the old focus frame"
```

---

## Kapsam dışı bırakılanlar

Bunlar konuşmada geçti ama bu planda yok. İstenirse ayrı iş olarak ele alınır:

- Karanlık tema (renkler `AppColors` üzerinden geldiği için sonra eklemek kolay).
- "İzlendi" işareti ve geriye dönük yayın akışı.
- Ekran geçiş animasyonları.
