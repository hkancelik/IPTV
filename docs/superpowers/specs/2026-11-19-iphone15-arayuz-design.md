# Kömür × iPhone 15: Dikey ve Yatay Arayüz Tasarım Belgesi

Tarih: 2026-11-19 · Hedef cihaz: **iPhone 15** (6.1" Super Retina XDR OLED · `393 × 852 pt` @3x = `1179 × 2556 px`) ve tüm iPhone 15/16 ailesi.

## 1. Neden iPhone 15'e Özel Tasarım?

Mevcut **Kömür** arayüzü masaüstü ve Android TV'nin geniş yatay ekranları (`1280 × 720+`) için sol menü kartı (`SideMenu`) ve yan yana iki sütunlu kategori paneliyle tasarlanmıştır. iPhone 15'in `393 × 852 pt` dikey ve `852 × 393 pt` yatay geometrisinde bu yapı hem sıkışır hem de tek elle kullanıma uymaz.

Bu sürüm, uygulamanın **Kömür** kimliğini (`#0B0B0D` OLED zemin, `#151517` yüzeyler, `#A78BFA` lavanta vurgu, **Fraunces** başlık + **Hanken Grotesk** arayüz tipografisi) birebir korurken **modern iOS / iPhone 15 ergonomi ve tasarım dilini** (Dynamic Island güvenli alanları, yüzen buzlu cam kapsül gezinme çubuğu, iOS alt sayfaları, dokunsal geri bildirim, kenardan kaydırarak geri dönme ve dikey/yatay hibrit video oynatıcı) ekler.

## 2. iPhone 15 Donanım ve Güvenli Alan Ölçüleri

| Özellik | Dikey (Portrait) | Yatay (Landscape) |
|---|---|---|
| Mantıksal çözünürlük | `393 × 852 pt` | `852 × 393 pt` |
| Fiziksel piksel (@3x) | `1179 × 2556 px` | `2556 × 1179 px` |
| Dynamic Island üst/yan güvenli alan | Üst `59 pt` | Sol & Sağ `59 pt` |
| Home Indicator alt güvenli alan | Alt `34 pt` | Alt `21 pt` |
| Ekran köşe yarıçapı (eşmerkezli referans) | `55 pt` | `55 pt` |
| En küçük dokunma hedefi (Apple HIG) | `44 × 44 pt` | `44 × 44 pt` |

### Düzen Seçimi (`lib/src/ui/layout.dart`)

- **`AppLayoutMode.desktop`**: Masaüstü, iPad (`shortestSide >= 600`) ve Android TV (`tvMode == true`). Mevcut `SideMenu` düzeni değişmeden korunur.
- **`AppLayoutMode.phonePortrait`**: iOS üzerinde `shortestSide < 600` (veya herhangi bir platformda `shortestSide < 420` / `width < 560`) ve `height >= width`.
- **`AppLayoutMode.phoneLandscape`**: Aynı cihazların yatay (`width > height`) konumu.

## 3. Tasarım Dili ve Yüzey Katmanları

| Belirteç (`AppColors`) | Değer | Kullanım |
|---|---|---|
| `ground` | `#0B0B0D` | OLED gerçek koyu kömür zemin (çerçeve ve Dynamic Island ile bütünleşir) |
| `surface` | `#151517` | Kartlar, satırlar, iOS alt sayfaları |
| `surfaceAlt` | `#1E1E22` | İkincil butonlar, arama alanı, istatistik kutuları |
| `glass` | `rgba(21, 21, 23, 0.85)` + `blur(20)` | Yüzen alt kapsül sekme çubuğu ve yatay sol ray |
| `videoGlass` | `rgba(18, 18, 22, 0.75)` + `blur(20)` | Video üstü yüzen denetimler |
| `glassBorder` | `#2E2E36` | OLED cam yüzeylerin 1 px ince çerçevesi |
| `accent` / `accentSoft` / `accentInk` | `#A78BFA` / `#2A2342` / `#C4B5FD` | Aktif sekme, ana eylem düğmeleri, ilerleme çubukları |
| `live` / `liveSoft` | `#FF5C6C` / `#3A1E24` | Canlı rozeti, favori kalbi, silme uyarıları |

**iOS'a Özel İyileştirmeler:**
- **Durum Çubuğu**: Koyu zemin üzerinde parlak beyaz saat/pil/sinyal ikonları (`SystemUiOverlayStyle.light`, `UIStatusBarStyleLightContent`, `UIUserInterfaceStyle = Dark`).
- **Tekrarlanan Saat Hapı Yok**: iPhone durum çubuğunda saat zaten sol üstte bulunduğundan `ClockPill` telefon düzeninde gizlenir; başlığa yer açılır.
- **Buzlu Cam Yüzen Gezinme**:
  - **Dikey**: Home Indicator'ın üzerinde yüzen **5 sekmeli buzlu cam kapsül** (`Ana sayfa`, `Canlı TV`, `Filmler`, `Diziler`, `Favoriler`). Sağ üst başlıkta **Ayarlar** (`nav-settings`) ve **Profil** (`nav-account`) daire düğmeleri.
  - **Yatay**: Sol güvenli alanın (Dynamic Island) hemen iç tarafında **60 pt genişliğinde ince yüzen cam ray** (`PhoneLandscapeRail`) — tüm 6 sekme + profil avatarı.
- **iOS Alt Sayfaları (`showAppSheet`)**: Masaüstü açılır menüleri (`showMenu`) ve büyük diyaloglar yerine tutamaçlı, yuvarlatılmış Kömür alt sayfalar (Sıralama, Aranabilir Kategori Seçici, Kategori Düzenleyici, Oynatıcı Ses/Altyazı/Hız/Kanal Listesi, Ayar Seçicileri).
- **Cupertino Geri Kaydırma**: `CupertinoPageRoute` ile sol kenardan kaydırarak doğal iOS geri dönüşü.
- **Dokunsal Geri Bildirim (`AppHaptics`)**: Sekme geçişleri, kategori filtreleri, anahtarlar ve favori dokunuşlarında hafif `selectionClick` / `lightImpact`.

## 4. Ekran Bazlı Dikey ve Yatay Tasarım Özeti

| Ekran | Dikey (393 × 852) | Yatay (852 × 393) |
|---|---|---|
| **Ana Sayfa** | Kompakt "Kaldığın yerden" hero kartı, yatay kaydırmalı "Son izlediklerin" kartları, tam genişlikte EPG'li "Kanallarım" kartı, yatay poster şeritleri. | İki sütunlu pano: solda Hero + Son izlediklerin + Poster şeritleri, sağda sabit `268 pt` canlı EPG'li "Kanallarım" paneli. |
| **Canlı TV** | Satır içi arama kutusu + yatay kategori çipleri + aranabilir "Tüm kategoriler" alt sayfası + satır içi EPG ilerleme çubuklu dokunmatik kanal satırları. | İki bölmeli Master–Detail: solda `188 pt` kategori paneli, sağda kanal numarası + rozet + EPG saat aralığı + ilerleme çubuklu geniş kanal satırları. |
| **Filmler & Diziler** | Arama + "Sırala" alt sayfa butonu + yatay kategori çipleri + klasik iPhone **3 sütunlu** `2:3` poster ızgarası (uzun basarak favoriye ekle). | Solda `188 pt` kategori paneli, sağda 4–5 sütunlu poster ızgarası + üst çubukta arama ve sıralama. |
| **Film / Dizi Detayı** | Dynamic Island arkasına uzanan sinematik backdrop geçişi, yüzen Geri/Favori düğmeleri, poster + başlık + rozetler, tam genişlikte "Oynat", genişletilebilir özet, yatay sezon hapları ve tek sütunlu bölüm kartları. | İki bölmeli düzen: solda Geri + poster + başlık + özet + Oynat/Favori kartı, sağda sezon seçimi ve kaydırılabilir bölüm kartları (filmlerde geniş sahne görseli + künye). |
| **Oynatıcı (Canlı & VOD)** | Üstte `16:9` kenardan kenara video + dokununca açılan şeffaf denetimler (çift dokunuşla `±10 sn` sarma, Doldur/Sığdır, Yatay Tam Ekran); altta **etkileşimli eşlikçi panel** (hızlı eylem hapları, canlı EPG kartı ve tek elle dokunarak geçilebilen kanal/bölüm listesi). | Kenardan kenara **tam ekran OLED video** (denetimler gizlenince durum çubuğu otomatik kaybolur), Dynamic Island güvenli alanları içinde buzlu cam üst çubuk (Ses, Altyazı, Hız, Kanallar/Bölümler alt sayfası, Sığdır/Doldur, Dikey), orta oynatma kümesi ve alt zaman çubuğu / canlı EPG şeridi. |
| **Ayarlar** | Üstte yatay bölüm atlama çipleri, 2 sütunlu istatistik kutulu Hesap kartı, yığılmış segmented seçiciler, iOS alt sayfa seçicileri. | İki bölmeli iOS Ayarlar: solda `176 pt` bölüm dizini, sağda ayar kartları. |
| **Profiller & Giriş** | 2 sütunlu kompakt profil kartları; yeni hesap formunda iOS URL/parola klavye desteğiyle manuel alanlar üstte, QR altta. | Solda marka/başlık/düzenle, sağda yatay kaydırılabilir profil kartları; formda 2×2 kompakt yatay yerleşim. |

## 5. Native iOS / Xcode Hazırlığı (`ios/`)

- **Uygulama İkonu**: Varsayılan Flutter logosu yerine `assets/icon/icon-bg.svg` kaynağından tüm 19 iOS boyutu (alfa kanalsız, tam kare PNG24) üretildi.
- **Koyu OLED Açılış Ekranı**: `LaunchScreen.storyboard` ve `Main.storyboard` arka planı `#0B0B0D` yapıldı, `LaunchImage@1x/2x/3x` eklendi (açılışta beyaz flaş yok).
- **Sessiz Modda Ses (`AVAudioSession`)**: `ios/Runner/AppDelegate.swift` içinde `.playback` / `.moviePlayback` kategorisi ayarlandı — iPhone 15 sessiz moddayken bile yayın sesi sorunsuz çıkar.
- **Yerel Ağ İzni**: `Info.plist` içine `NSLocalNetworkUsageDescription` ve koyu durum çubuğu anahtarları eklendi.

## 6. Kız Arkadaşının Mac'inde Xcode ile iPhone 15'e Kurulum Adımları

```bash
# 1. Projeyi Mac'e al ve bağımlılıkları indir
git pull
flutter pub get
cd ios && pod install && cd ..

# 2. Xcode workspace'ini aç (mutlaka .xcworkspace, .xcodeproj değil!)
open ios/Runner.xcworkspace
```

Xcode içinde:
1. Sol panelden **Runner** projesini → **Signing & Capabilities** sekmesini seç.
2. **Automatically manage signing** kutusunu işaretle.
3. **Team** açılır listesinden kendi Apple ID hesabını seç (ücretsiz kişisel Apple ID ile 7 gün geçerli, ücretli Apple Developer ile 1 yıl).
4. **Bundle Identifier** çakışırsa `dev.nailhakan.iptvApp` sonuna kendi ekini yaz (örn. `dev.nailhakan.iptvApp.hakan`).
5. iPhone 15'i USB-C kablo ile Mac'e bağla, üstteki cihaz listesinden **iPhone 15**'i seç ve **▶ Run** (veya terminalden `flutter run --release`) çalıştır.
6. İlk kurulumda iPhone 15 üzerinde: **Ayarlar → Genel → VPN ve Aygıt Yönetimi** kısmından geliştirici sertifikasına güven, ve **Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu** açık olsun.

## 7. Tasarım Örnekleri ve Ekran Görüntüleri

- **İnteraktif HTML Tasarım Vitrini (Dikey & Yatay)**: `docs/superpowers/specs/iphone15-mockups/index.html`
- **Gerçek Flutter Render Ekran Görüntüleri**: `docs/screenshots/iphone15/`
