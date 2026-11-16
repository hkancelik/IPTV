# Gündüz: arayüz yeniden tasarımı

Tarih: 2026-11-16. Durum: kullanıcı onayladı, kod yazılmadı.

Bu belge uygulamanın bütün arayüzünü "Gündüz" tasarım diline taşımak için gereken kararları içerir. Uygulama planı: `docs/superpowers/plans/2026-11-16-gunduz-arayuz.md`.

`docs/superpowers/specs/2026-11-12-yayin-masasi-arayuz-design.md` ve ona bağlı plan reddedilmiş eski bir yöndür. Onlara bakma.

## Kaynaklar

- **Mockup dosyaları (depoda):** `docs/superpowers/specs/gunduz-mockups/`. Her ekran 1280×720 mantıksal piksel. Bütün ölçü ve renkler satır içi `style` özelliklerinde yazılı. Bu belgede yazmayan bir ölçü gerekirse oradan oku.
- **Canlı tuval:** https://claude.ai/artifact/XTx16h164VDjxJa6srBaYB (yalnızca hesap sahibi açabilir).
- Bu belge ile mockup çelişirse bu belge geçerlidir. Bilinen çelişkiler "Mockup'tan bilinçli sapmalar" bölümünde.

| Ekran | Mockup dosyası | Kod |
|---|---|---|
| Ana sayfa | `Main.dc.html` | `lib/src/home_page.dart` (`_homeView`) |
| Canlı TV | `G-Canli.dc.html` | `lib/src/home_page.dart` (`_liveList`) |
| Filmler, Diziler | `G-Filmler.dc.html` | `lib/src/home_page.dart` (`_posterGrid`) |
| Film ve dizi detayı | `G-Detay.dc.html` | `lib/src/detail_page.dart` |
| Oynatıcı, film ve dizi | `G-Oynatici.dc.html` | `lib/src/player_page.dart` |
| Oynatıcı, canlı | `G-OynaticiCanli.dc.html` | `lib/src/player_page.dart` |
| Profil seçimi | `G-Profiller.dc.html` | `lib/src/login_page.dart` |
| Ayarlar | `G-Ayarlar.dc.html` | `lib/src/settings_page.dart` |

## Amaç ve neden

Uygulama bugün varsayılan Material 3 koyu temasıyla çalışıyor (mor tohum rengi, `NavigationRail`, `ListTile`). Kullanıcı tasarımın çok önemli olduğunu söyledi. Netflix benzeri koyu bir taslağı, teknik ve düz bir "yayın masası" yönünü ve iki başka koyu yönü reddetti. Dört yeni yön arasından açık renkli "Gündüz"ü seçti ve sekiz ekranlık hâlini onayladı.

Fikir: TV uygulamalarının neredeyse hepsi karanlık. Bu uygulama ferah, açık ve yumuşak durur. Her şey beyaz, büyük köşeli kartlarda yaşar. Renk yalnızca içerikten (afiş, sahne) ve tek bir mavi vurgudan gelir.

## Hedefler

- Bütün ekranlar bu belgedeki dile geçer, eski görünümden iz kalmaz.
- Kumanda ile kullanım bugünkünden kötüleşmez: odak her an açıkça görünür, hiçbir öğe ulaşılamaz kalmaz.
- 1 GB RAM'li Android TV stick'te akıcı kalır.
- Mevcut bütün işlevler korunur (aşağıda "Korunacak davranışlar").

## Hedef dışı

- Yeni özellik yok: karanlık tema, geriye dönük yayın akışı, "izlendi" işareti, genel arama, ekran geçiş animasyonu eklenmez.
- Veri katmanı değişmez (`xtream.dart`, `library.dart`, `accounts.dart`, `settings.dart`). `UiScale`, `PhoneRemote`, `EpgCache` mantığı değişmez.

## Kesinlikle yapılmayacaklar

- Koyu zemin. Tek istisna oynatıcıdaki videonun kendisi.
- İkinci bir vurgu rengi. Mavi tektir. Kırmızı yalnızca canlı yayın, favori ve silme içindir.
- Bulanıklık (`BackdropFilter`), parlama, renk geçişli zemin. Tek istisna: ana sayfa ve detaydaki sahne görselinin beyaza doğru yumuşak geçişi.
- Keskin köşe. En küçük yarıçap 10.
- 12 pikselden küçük metin. Soluk gri (`ink3`) ile yazılmış okunacak metin.
- Varsayılan Material görünümlerini olduğu gibi bırakmak: `NavigationRail`, `ListTile`, `Card`, `Chip`, `ExpansionTile`, `DropdownButton`, `FilledButton`, `CircleAvatar`.

## Tasarım dili

### Renkler

| Ad (`AppColors`) | Değer | Kullanım |
|---|---|---|
| `ground` | `#E9EDF4` | Sayfa zemini |
| `surface` | `#FFFFFF` | Kart, panel, satır |
| `surfaceAlt` | `#F2F4F9` | Kart içindeki ikincil düğme, arama alanı, fare üstü |
| `line` | `#E3E7F0` | Ayırıcı, ilerleme çubuğu zemini |
| `dashed` | `#C5CCDB` | Kesikli çerçeve, kapalı anahtar zemini |
| `ink` | `#0F1728` | Birincil metin, odak çerçevesi |
| `ink2` | `#55607A` | İkincil metin |
| `ink3` | `#8A93A8` | Yalnızca ikon ve devre dışı öğe, metin için kullanılmaz |
| `body` | `#3A4560` | Uzun açıklama metni |
| `accent` | `#2F5BFF` | Etkin menü öğesi, birincil düğme, ilerleme, açık anahtar |
| `onAccent` | `#FFFFFF` | Mavi üstündeki metin |
| `accentSoft` | `#E7ECFF` | Seçili kategori ve bölüm zemini, "Kaldığın yerden" etiketi |
| `accentInk` | `#2447D6` | `accentSoft` üstündeki metin, kalan süre |
| `buffered` | `#C9D2EA` | Oynatıcı konum çubuğunda tamponlanan kısım |
| `live` | `#FF4D5E` | Canlı noktası, dolu favori kalbi |
| `liveSoft` | `#FFE3E6` | "Canlı" etiketi ve "Favorilerde" düğmesi zemini |
| `liveInk` | `#8A1226` | `liveSoft` üstündeki metin |
| `liveText` | `#C81E3A` | Beyaz üstünde "Canlı" yazısı |
| `ok` | `#0F5A2E` | Bağlantı sayacı uygunken |
| `warnSoft` | `#FFF0D6` | Puan etiketi zemini |
| `warnInk` | `#7A4A00` | Puan etiketi metni |

**Kanal rozeti renkleri.** Kanallar ve profiller için altı yumuşak çift (zemin, yazı). Seçim, adın karakter kodlarından türetilen sayının 6'ya bölümünden kalanla yapılır (bugünkü `_avatarColor` mantığı gibi):

| Zemin | Yazı |
|---|---|
| `#FFE3E6` | `#8A1226` |
| `#E7ECFF` | `#1E3BB8` |
| `#FFF0D6` | `#7A4A00` |
| `#DDF5E6` | `#0F5A2E` |
| `#EFE6FF` | `#4B1FA8` |
| `#DDF3F7` | `#0B5566` |

### Gölgeler

| Ad (`AppShadows`) | Değer | Kullanım |
|---|---|---|
| `panel` | `0 14 40` blur, `rgba(20,30,70,0.09)` | Menü kartı, kategori paneli, büyük kartlar, ayar kartları |
| `card` | `0 10 30`, `rgba(20,30,70,0.07)` | Tekrarlanan kartlar ve satırlar |
| `chip` | `0 8 24`, `rgba(20,30,70,0.07)` | Saat, arama alanı, küçük düğmeler |
| `lift` | `0 18 40`, `rgba(20,30,70,0.18)` | Odaklanan öğe |
| `overlay` | `0 20 50`, `rgba(0,0,0,0.30)` | Oynatıcıdaki beyaz kartlar |

**Düşük donanım kuralı.** Kumanda modunda (`AppSettings.instance.tvMode`) tekrarlanan öğelerde (`card` gölgesi) gölge çizilmez, yerine 1 piksel `line` kenarlık kullanılır. Büyük paneller ve odaklanan öğe gölgesini korur. Bu kural tek bir yerde, `AppShadows.forRepeated()` içinde uygulanır.

### Yazı

Tek aile: **Manrope**, değişken yazı tipi (`wght` 200–800). Kaynak Google Fonts, OFL lisansı, dosya `ofl/manrope/Manrope[wght].ttf`. Türkçe harfleri içerir. Uygulamaya gömülür. İndirmek için kullanıcıdan izin iste.

Flutter'da kalınlık hem `fontWeight` hem `FontVariation('wght', n)` ile verilir.

| Rol (`AppText`) | Kalınlık | Boyut | Kullanım |
|---|---|---|---|
| `display` | 800, harf aralığı -0.02 em | 40, 38, 32, 28, 24 | Sayfa başlığı, büyük kart başlığı |
| `title` | 800 | 20, 18, 17, 16, 15 | Bölüm başlığı, kart ve satır adı |
| `label` | 700 | 15, 14, 13 | Düğme, etiket |
| `meta` | 600 | 15, 14, 13 | İkincil satır, sayı, saat aralığı. Varsayılan renk `ink2` |
| `body` | 500, satır yüksekliği 1.55 | 15 | Açıklama paragrafı, renk `body` |

Sayılar (saat, süre, sayaç) `FontFeature.tabularFigures()` ile yazılır. Bütün metinler cümle düzenindedir, büyük harfle yazılmış etiket yoktur.

### Ölçüler

| Ad (`AppSizes`) | Değer |
|---|---|
| Panel yarıçapı | 28 |
| Kart yarıçapı | 24 |
| Görsel ve satır yarıçapı | 20 |
| Küçük öğe yarıçapı | 16 (menü öğesi), 14 (kategori öğesi, seçenek) |
| Etiket yarıçapı | 10 |
| Hap düğme | yükseklik/2 |
| Sayfa kenar boşluğu | 24 (menü), 26 (içerik sağ) |
| Menü kartı genişliği | 212, dar pencerede 76 |
| Menü ile içerik arası | 26 (içerik x=262) |
| Kategori paneli genişliği | 216, içerikle arası 20 |
| Başlık satırı | üstten 26, yükseklik 44 |
| İçerik üstü | 84 |
| Düğme yüksekliği | 44 (ikincil), 48 (birincil), 60 (oynat) |
| Menü öğesi yüksekliği | 48 |
| Kategori öğesi yüksekliği | 42 |
| Satır yüksekliği | 68 (kanal), 64 (ayar) |
| Odak çerçevesi | 3 piksel `ink`, öğeden 4 piksel dışarıda |
| En küçük tıklama alanı | 44×44 |

### Odak, fare ve basma

- **Odak:** 3 piksel `ink` renkli çerçeve, öğenin 4 piksel dışında, öğenin köşe yarıçapı + 4 ile çizilir. Öğe `lift` gölgesini alır. Düzen kaymaz: çerçeve öğenin sınırları dışına boyanır.
- Çerçeve dışarı taştığı için kaydırılan listeler ve ızgaralar her yönde en az 8 piksel iç boşluk bırakır, yoksa kenardaki öğenin çerçevesi kırpılır.
- Ayar satırları gibi tam genişlikteki satırlarda çerçeve içeriden çizilir (4 piksel dışarı yerine 0) ve zemin `surfaceAlt` olur.
- **Fare üstü:** zemin `surfaceAlt` (beyaz kartlarda) ya da gölge `card`'dan `lift`'e yükselir (görsel kartlarda).
- **Basma:** dalga efekti yok. 120 ms içinde yüzde 98'e küçülüp geri gelir.

### Bileşenler

Hepsi `lib/src/ui/` altında.

- **`FocusRing`.** Odak ve fare durumunu takip eder, çerçeveyi ve kaldırma gölgesini çizer. Bütün tıklanabilir öğeler bunu kullanır.
- **`AppButton`.** Hap biçimli düğme. Görünümler: `primary` (mavi zemin, beyaz yazı), `secondary` (`surfaceAlt` zemin, `ink` yazı), `onPage` (beyaz zemin, `chip` gölgesi, sayfa zemini üstünde), `danger` (`liveSoft` zemin, `liveInk` yazı). Solda isteğe bağlı ikon. Yalnızca ikonlu hâli yuvarlaktır.
- **`AppCard`.** Beyaz, yarıçap 28 ya da 24, `panel` ya da `card` gölgesi.
- **`Pill`.** Küçük etiket: yükseklik 26–28, yarıçap 10 ya da 13, `label` 12–13. Renk çiftleri: mavi (`accentSoft`/`accentInk`), kırmızı (`liveSoft`/`liveInk`), turuncu (`warnSoft`/`warnInk`), nötr (`surfaceAlt`/`body`).
- **`LiveDot`.** 8–10 piksellik `live` daire.
- **`ChannelBadge`.** Kanalın rozeti: kare, yarıçap boyutun üçte biri, renk çifti adın karma değerinden. Logo varsa beyaz zemin üstünde logo (`BoxFit.contain`, 6 piksel iç boşluk), yoksa kısaltma. Kısaltma kuralı: ilk iki kelimenin ilk harfleri, tek kelimeyse ilk iki harf, büyük harf (`TRT 1` → `T1`, `NTV` → `NT`).
- **`ProgressBar`.** Yuvarlak uçlu, zemin `line`, dolgu `accent`. Yükseklik 6 (satırda), 8 (ana kart ve oynatıcı). Görsel üstünde: zemin yarı saydam koyu, dolgu beyaz, yükseklik 4.
- **`AppSwitch`.** 52×30 (ayarlarda) ya da 40×24 (oynatıcıda), yuvarlak. Açık: zemin `accent`, topuz sağda. Kapalı: zemin `dashed`, topuz solda. Topuz beyaz, hafif gölgeli.
- **`Segmented`.** `surfaceAlt` zemin, yarıçap 18, iç boşluk 4. Seçenek yüksekliği 34, yarıçap 14, `label` 13. Seçili seçenek beyaz zemin, `ink` yazı, küçük gölge. Diğerleri saydam, `ink2` yazı.
- **`SearchField`.** Hap biçimli alan, solda büyüteç. Sayfa üstünde beyaz ve `chip` gölgeli, panel içinde `surfaceAlt`. Bugünkü `RemoteTextField` davranışını kullanır.
- **`ClockPill`.** Beyaz hap içinde `SS:DD`, `title` 15, dakikada bir yenilenir.
- **`SideMenu`.** Sol menü kartı. Üstte mavi kare marka ve "IPTV", altı öğe (ikon ve yazı), en altta hesap çipi. Etkin öğe: mavi zemin, beyaz yazı, kalınlık 800. Diğerleri: saydam, `ink2` yazı, kalınlık 600. Pencere 1000 pikselden darsa yalnızca ikonlu 76 genişliğinde hâl.
- **`PageHeader`.** Başlık (`display` 28), yanında isteğe bağlı alt bilgi (`meta` 15), sağda eylemler ve saat.
- **`SideItem`.** Kategori ve ayar bölümü öğesi. Seçili: `accentSoft` zemin, `accentInk` yazı, kalınlık 800. Seçili değil: saydam, `ink` yazı, 600. Sağda isteğe bağlı sayı (`meta` 13).

### İkonlar

Material'ın yuvarlak ikonları (`Icons.*_rounded`) kullanılır. Menü: `home_rounded`, `live_tv_rounded`, `movie_rounded`, `video_library_rounded`, `favorite_rounded`, `tune_rounded`. Mockup'taki çizgi ikonlara en yakın aile budur ve yeni paket gerektirmez. Boyut 20 (menü, düğme), 18 (küçük düğme).

## Ekranlar

Ölçüler 1280×720 içindir. Gerçek pencerede genişlikler orantılı uzar, sütun sayıları genişlikten hesaplanır ("Duyarlı düzen").

### Ortak iskelet

`NavigationRail` kalkar. Solda `SideMenu` kartı, sağda içerik. Menü öğelerinin anahtarları: `nav-home`, `nav-live`, `nav-movies`, `nav-series`, `nav-favorites`, `nav-settings`. Hesap çipi `nav-account`, ipucu metni "Kullanıcı değiştir", seçilince bugünkü "Kullanıcı değiştir" ile aynı şeyi yapar (profil ekranına döner).

Geri tuşu davranışı bugünkü gibi kalır: kategori seçiliyse "Tümü"ye, değilse Ana sayfaya, oradaysa uygulamadan çıkar.

### Ana sayfa

Dikey kaydırılan tek sütun.

1. **Başlık.** Günün saatine göre selam ve hesap adı: 05–12 "Günaydın", 12–18 "İyi günler", 18–22 "İyi akşamlar", 22–05 "İyi geceler". Örnek: "İyi akşamlar, Hakan". Sağda saat.
2. **Kaldığın yer kartı.** Tam genişlik, yükseklik 246. `Library.continueWatching` listesinin ilk öğesi. Sağda 560 genişliğinde sahne görseli (afiş `BoxFit.cover`, `cacheWidth` 640), soluna doğru 200 piksellik beyaz geçiş. Solda: mavi "Kaldığın yerden" etiketi, başlık (`display` 32, en çok 2 satır), konum çubuğu ve kalan süre ("1 sa 12 dk kaldı"), mavi "Devam et" düğmesi. Açılışta odak bu düğmededir. Liste boşsa kart çizilmez.
3. **Alt bölüm, iki sütun.** Solda içerik sütunu, sağda 326 genişliğinde "Kanallarım" paneli.
   - **Son izlediklerin:** devam listesinin sonraki öğeleri, üç sütunlu kartlar. Kart: beyaz, iç boşluk 8, üstte 104 yüksekliğinde görsel ve üstünde beyaz ilerleme çizgisi, altta ad ve alt satır ("1. sezon 3. bölüm, 27 dk kaldı" ya da "1 sa 40 dk kaldı"). Liste kısaysa çizilmez.
   - **Filmlerim** ve **Dizilerim:** favori film ve diziler, 92×132 afişler yatay sırada. Boşsa çizilmez.
   - **Kanallarım paneli:** başlık ve sağda kırmızı noktalı "Canlı". Favori kanallar satır satır: rozet, ad, o anki program (`EpgCache`), küçük ilerleme çubuğu. Panel kendi içinde kayar. Favori kanal yoksa panel çizilmez ve sol sütun tam genişlik alır.
4. Geçmiş ve favori yoksa: bugünkü davet metni ortada, beyaz bir kart içinde.

### Canlı TV

- **Başlık:** "Canlı TV", yanında "{kategori}, {n} kanal" (kategori yoksa "Tümü"), sağda kanal arama alanı (genişlik 300) ve saat.
- **Kategori paneli (sol, 216):** üstte "Kategori ara" alanı, "Tümü" ve kategoriler `SideItem` olarak (sağda sayı), en altta ayar ikonlu "Kategorileri düzenle" düğmesi. Uzun basma ve sağ tık davranışı aynen kalır. Düğmenin ipucu metni "Kategorileri düzenle / gizle".
- **Kanal listesi (sağ):** her kanal kendi beyaz satırında (yükseklik 68, yarıçap 20, aralık 8). Satır: sıra numarası (`meta` 14, sağa yaslı, 28 genişlik), rozet (46), ad (`title` 16) ve o anki program (`meta` 13), sağda saat aralığı ve 150 genişliğinde ilerleme çubuğu, en sağda kalp düğmesi (favoriyse dolu `live`, değilse `ink3` çizgi). Program bilgisi yoksa ikinci satırda kategori adı, saat aralığı ve çubuk çizilmez.
- Kalp düğmesi bugünkü gibi ayrı bir odak durağıdır.

### Filmler ve Diziler

- **Başlık:** "Filmler" ya da "Diziler", yanında toplam sayı ("18.420 film", "4.312 dizi"), sağda arama (260), sıralama düğmesi ("Sırala:" soluk, seçili değer, aşağı ok, açılır menü) ve saat.
- **Kategori paneli:** Canlı TV ile aynı.
- **Afiş ızgarası:** afiş yarıçap 20, oran 2:3'e yakın (mockup'ta 112×172), altında ad (`title` 15, tek satır) ve "2014, TR" (`meta` 13). Favoriyse sağ üstte beyaz yuvarlak içinde dolu kırmızı kalp. Kalp düğmesi ayrı odak durağıdır, favori değilse yalnızca afiş odakta ya da fare üstündeyken görünür.
- Sıralama seçenekleri: "Varsayılan", "Yeni eklenen", "A – Z", "Yıl, yeniden eskiye".

### Favoriler

Başlık "Favoriler", sağda arama ("Favorilerde ara") ve saat. Altında üç bölüm: "Kanallar" (Canlı TV satırlarıyla aynı görünüm), "Filmler" ve "Diziler" (afiş ızgarası). Boş bölüm çizilmez. Hiç favori yoksa bugünkü metin beyaz bir kartta.

### Detay

Sol menü yok.

- **Üst satır:** beyaz "Geri" düğmesi, yol ("Diziler › Breaking Bad"), sağda saat.
- **Bilgi kartı (tam genişlik, 300):** solda afiş 168×252 (yarıçap 20). Ortada (genişlik 500): ad (`display` 38), etiket satırı, açıklama (`body` 15, en çok 3 satır), oyuncular ve yönetmen (`meta` 13), düğmeler. Sağda arka plan görseli (600 genişlik, soluna doğru beyaz geçiş). Görsel yoksa ya da pencere 1100'den darsa sağ taraf boş kalır.
  - Etiketler: puan (turuncu, yıldızlı, boş ya da "0" ise yok), yıl, tür, dil (`parsedTitleOf(item).tags`), filmde süre, dizide "{n} sezon". Boş olan çizilmez.
  - Düğmeler: birincil mavi düğme (açılışta odak burada), yanında favori düğmesi. Favoriyse `danger` görünümünde "Favorilerde", değilse `secondary` "Favorilere ekle".
  - Birincil düğme metni: film için "Oynat" ya da "Devam et 21:04". Dizi için devam eden bölüm varsa "{n}. bölümden devam et", yoksa "İlk bölümü oynat". Dizide bu düğme ilgili bölümü bugünkü oynatma sırasıyla açar.
- **Sezon düğmeleri:** hap biçimli, seçili olan mavi. Sağda "{n} bölüm". `ExpansionTile` kalkar, yalnızca seçili sezonun bölümleri görünür. Açılışta devam eden bölümün sezonu, yoksa ilk sezon seçilidir.
- **Bölüm kartları:** dört sütunlu ızgara. Kart beyaz, iç boşluk 8: üstte 128 yüksekliğinde görsel, sol üstünde beyaz "{n}. bölüm" etiketi, devam ediyorsa altında beyaz ilerleme çizgisi. Altında başlık ve süre ("48 dk"). Devam eden bölümde süre yerine "27 dk kaldı" (`accentInk`). Görsel yoksa dizinin afişi kullanılır.

### Oynatıcı, film ve dizi

Video tam ekran, siyah zemin. Denetimler görünürken:

- **Sol üst:** beyaz hap: gri yuvarlak "Geri" düğmesi, ad (`title` 16), alt bilgi (`meta` 14, dizide "1. sezon 3. bölüm").
- **Sağ üst:** saat.
- **Alt kart:** sağdan, soldan ve alttan 24–28 boşluklu beyaz kart, yarıçap 28, `overlay` gölgesi.
  - Konum satırı: geçen süre (`title` 15), konum çubuğu (yükseklik 8, tamponlanan `buffered`, oynatılan `accent`, 20 piksellik mavi topuz, beyaz kenarlı), kalan süre (`meta` 15, "-27:08").
  - Tuş satırı üç bölüm. Sol: ses kapatma (yuvarlak, `secondary`), ses çubuğu (yalnızca kumanda modu kapalıyken), "Zamana git". Orta: önceki bölüm, "-10", oynat ve duraklat (60 piksel mavi daire, açılışta odak burada), "+10", sonraki bölüm. Sağ: "Otomatik sonraki" düğmesi (içinde küçük anahtar), hız ("1x"), ses parçası (geçerli dilin adı, en çok 14 karakter), altyazı ("Altyazı kapalı" ya da dilin adı), tam ekran.
- Sarma tuşlarının sayısı ayardaki sarma süresidir ("-10", "-30").
- Hata kutusu, sonraki bölüm sayacı, kısa bilgi yazısı, yazılan kanal numarası, parça seçme ve "Zamana git" pencereleri: beyaz kart, yarıçap 28, `overlay` gölgesi, düğmeler `AppButton`.

### Oynatıcı, canlı

- **Sol üst:** beyaz hap: "Geri", "Canlı TV", kategori adı. **Sağ üst:** saat.
- **Alt kart:**
  - Üst bölüm: rozet (72), sıra numarası (`meta` 14) ve kanal adı (`display` 24), altında kırmızı "Canlı" etiketi. Ortada ince ayırıcıdan sonra o anki program adı (`title` 19), saat aralığı, ilerleme çubuğu ve "Sırada 22:30, Spor Haberleri". Sağda 250 genişliğinde bir önceki ve bir sonraki kanal (ok, numara, ad, varsa o anki program). Program bilgisi yoksa orta bölüm çizilmez.
  - Alt bölüm, ayırıcı çizgiden sonra: sol ses denetimi, ortada "Önceki kanal", oynat ve duraklat, "Sonraki kanal", sağda ses, altyazı ve tam ekran.

### Profil seçimi ve giriş

- Sol üstte marka, sağ üstte saat. Sol menü yok.
- Ortada başlık "Kullanıcı seç" (`display` 40), altında "Açılışta son kullanılan hesapla otomatik giriş yapılır." (`meta` 16).
- Profil kartları 210 genişliğinde, ortalanmış sırada (sığmazsa alt satıra geçer): 96 piksellik renkli daire içinde baş harf (`display` 40, renk çifti adın karmasından), ad (`title` 18), sunucu (`meta` 13), son kullanılanda mavi "Son kullanılan" etiketi. Açılışta odak ilk kartta.
- "Kullanıcı ekle" kartı: aynı boyut, 2 piksel kesikli `dashed` çerçeve, beyaz daire içinde mavi artı, "Telefondan QR ya da elle".
- Altında `onPage` görünümünde "Kullanıcıları düzenle" (düzenlemede "Bitti"). Düzenleme modunda başlık "Silinecek kullanıcıyı seç", her kartın sağ üstünde kırmızı "Sil" etiketi.
- **Giriş formu:** 420 genişliğinde beyaz kart içinde, üstte marka ve başlık, birincil olmayan "Telefondan gir (QR)" düğmesi, alanlar `SearchField` ile aynı görünümde (`surfaceAlt`, hap), mavi "Kullanıcı Ekle" düğmesi.
- **Otomatik giriş ekranı:** ortada beyaz kart: marka, "{ad} olarak giriş yapılıyor...", 220 genişliğinde belirsiz mavi çubuk, `secondary` "Vazgeç / kullanıcı değiştir".
- **QR penceresi:** beyaz kart, QR kodu beyaz zeminde.

### Ayarlar

- Sol menü, başlık "Ayarlar", saat.
- **Bölüm paneli (sol, 216):** Hesap, Oynatıcı, İçerik, Telefonu kumanda yap, Görünüm, Kısayollar. Seçilince sağdaki alan o bölüme kayar ve öğe seçili görünür. Kaydırma sırasında görünen bölüm de seçili hâle gelir.
- **Sağ alan (kayar):**
  - Hesap kartı (yükseklik 84): rozet, ad, sunucu, "Abonelik bitişi", "Eşzamanlı bağlantılar" ("1 / 2 kullanımda", uygunsa `ok`, sınır doluysa `liveText` ve altında bugünkü uyarı cümlesi, yanında yenile düğmesi), sağda "Kullanıcı değiştir".
  - Her bölüm ayrı beyaz kart, başlık `title` 18. Satır: başlık (`title` 15), açıklama (`meta` 13, iki satıra kadar), sağda denetim. Açılır menüler `Segmented`, anahtarlar `AppSwitch` olur. Anahtar satırında satırın tamamı tıklanabilir.
  - Ayar adları ve seçenek kümeleri koddakiyle aynıdır. Ön bellekte beş seçenek, arayüz ölçeğinde sekiz seçenek olduğu için bunlar `Segmented` yerine açılır menüyle seçilir (`AppButton` ve `showMenu`).
  - Telefon kumandası: QR beyaz zeminde, yanında adres ve açıklama.
  - Kısayollar: solda tuş adları hap etiket içinde, sağda açıklama.

## Korunacak davranışlar

Kontrol listesi olarak kullan. Her biri yeni arayüzde de çalışmalı:

- Otomatik giriş ve iptali, çoklu hesap, onaylı silme, telefondan QR ile giriş.
- Sekme değişince arama kutusunun boşalması.
- Kategori arama, sıralama, gizleme, en üste alma, düzenleme penceresi (sürükle bırak ve oklar).
- Canlı listede "şimdi" bilgisi ve ilerleme, favori ekleme.
- Liste yüklenemezse hata metni ve "Tekrar dene".
- Film detayında devam etme, dizide bütün sezonları kapsayan oynatma sırası.
- Oynatıcı: önceki ve sonraki, sarma, zamana gitme, ses, hız, ses ve altyazı parçası, tam ekran, otomatik sonraki bölüm ve sayacı, rakamla kanal seçme, yukarı ve aşağı ile kanal değiştirme, hata ve yeniden deneme, fare durunca denetimlerin gizlenmesi.
- Ayarlardaki bütün seçenekler, telefon kumandası QR kodu, bağlantı sayacı.
- `UiScale` %50–%140 arası her ölçekte tıklanabilirlik.
- Geri tuşu sırası.

## Duyarlı düzen

- Sabit 1280 varsayılmaz. İçerik genişliği pencereden hesaplanır.
- Pencere 1000'den darsa `SideMenu` ikonlu dar hâle geçer.
- Afiş ızgarası sütun sayısı: `max(2, floor((genişlik + 16) / 134))`. Afiş yüksekliği genişliğin 1,53 katı.
- Ana sayfada "Kanallarım" paneli 900'den dar içerikte sol sütunun altına iner.
- Detayda sağdaki arka plan görseli 1100'den dar pencerede gizlenir.
- Başlık satırındaki arama alanı dar pencerede küçülür (en az 180), saat her zaman görünür.

## Performans kuralları

- `BackdropFilter`, `ShaderMask` yok. Gölgeler "Düşük donanım kuralı"na uyar.
- Listeler `builder` ile ve sabit öğe yüksekliğiyle kurulur.
- Afişler `cacheWidth` 260 ile, ana sayfa sahnesi 640 ile çözülür.
- Odak gölgesi yalnızca odaklanan öğede çizilir. Tekrarlanan öğeler `RepaintBoundary` içinde.
- Saat dakikada bir yalnızca kendi metnini yeniler.

## Metin değişiklikleri

Mevcut Türkçe metinler korunur. Değişen ve yeni olanlar:

| Yer | Eski | Yeni |
|---|---|---|
| Menü | Ana Sayfa | Ana sayfa |
| Ana sayfa başlığı | (yok) | Günaydın / İyi günler / İyi akşamlar / İyi geceler, {ad} |
| Ana kart etiketi | (yok) | Kaldığın yerden |
| Ana sayfa bölümü | Kaldığın yerden devam et | Son izlediklerin |
| Kalan süre | (yok) | 1 sa 12 dk kaldı, 27 dk kaldı |
| Sıralama ön eki | (ikon) | Sırala: |
| Sıralama seçeneği | Yıl (yeni → eski) | Yıl, yeniden eskiye |
| Liste başlığı yanı | (yok) | {kategori}, {n} kanal / {n} film / {n} dizi |
| Detay birincil düğme, dizi | (yok) | {n}. bölümden devam et / İlk bölümü oynat |
| Detay birincil düğme, film | Devam et (21:04) | Devam et 21:04 |
| Sezon düğmesi | {n}. Sezon ({m} bölüm) | {n}. sezon |
| Bölüm etiketi | {n}. Bölüm - {başlık} | {n}. bölüm (görselde), başlık ayrı |
| Bölüm durumu | Devam ediliyor (21:04) | {n} dk kaldı |
| Oynatıcı | (ikon) | Otomatik sonraki, Zamana git, Önceki kanal, Sonraki kanal |
| Canlı oynatıcı | Şimdi: … · Sıradaki: … | Sırada {saat}, {program} |
| Profil alt başlığı | (yok) | Açılışta son kullanılan hesapla otomatik giriş yapılır. |
| Profil ekleme kartı | (boş) | Telefondan QR ya da elle |
| Favoriler bölümleri | (yok) | Kanallar, Filmler, Diziler |
| Menü hesap çipi ipucu | (yok) | Kullanıcı değiştir |

Testlerin aradığı şu metinler değişmemeli: "Kullanıcı seç", "Son kullanılan", "Kullanıcıları düzenle", "Giriş bilgilerinizi girin", "Kullanıcı Ekle", "Vazgeç / kullanıcı değiştir", "giriş yapılıyor", "Tekrar dene", "Sonuç yok", "Tamam", "En üste al", "Ön bellek (tampon)", "Kategorileri düzenle / gizle" (ipucu), "Kullanıcı silinsin mi?", "Sil".

## Mockup'tan bilinçli sapmalar

- **Saat biçimi.** Mockup'ta ve bu belgede `SS:DD` var. Saniye gösterilmez.
- **Eksik ayar satırları.** Mockup'ta ön bellek, arayüz ölçeği, içerik ve kumanda ayarları görünmüyor. Hepsi kodda kalır.
- **Ayar adları.** Koddaki adlar geçerlidir.
- **İkonlar.** Mockup'taki çizgi ikonlar yerine Material yuvarlak ikonları.
- **Hesap çipi.** Mockup'ta profil ekranına bağlı. Uygulamada "Kullanıcı değiştir" ile aynı işi yapar.
- **Kanal rozetleri.** Mockup'ta hep kısaltma var. Logo varsa logo gösterilir.
- **Örnek veri.** Afişler, program adları, sayılar, sunucu adresi ve tarih yer tutucudur.

## Uygulayana bırakılanlar

- Dosya içi yardımcı widget'ların adları ve bölünmesi.
- Basma ve odak geçişinin eğrisi (120 ms civarı, `easeOut`).
- Açılır menü ve pencere iç boşluklarının ince ayarı.
- Kırılma noktalarının ±50 piksel ayarı.

## Riskler

- **Gölgeler.** TV stick'te kaydırırken takılma olursa "Düşük donanım kuralı" büyük panellere de uygulanır.
- **Açık tema ve karanlık oda.** Kullanıcı bunu bilerek seçti. Karanlık tema ayrı bir iş olarak sonra eklenebilir, renkler `AppColors` üzerinden geldiği için kolay olur.
- **Odak çerçevesinin kırpılması.** Kaydırma alanlarına 8 piksel iç boşluk verilmezse kenardaki öğelerin çerçevesi kesilir.
- **Yazı tipi dosyası.** Depoya yaklaşık 160 KB'lık bir dosya eklenir. İndirme kullanıcı onayı ister.
