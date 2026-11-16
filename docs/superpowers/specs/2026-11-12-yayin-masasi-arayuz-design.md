# Yayın Masası: arayüz yeniden tasarımı

> **REDDEDİLDİ (2026-11-16).** Kullanıcı bu tasarımı beğenmedi. Bu belgeyi uygulama. Geçerli tasarım: `docs/superpowers/specs/2026-11-16-gunduz-arayuz-design.md`, plan: `docs/superpowers/plans/2026-11-16-gunduz-arayuz.md`.

Tarih: 2026-11-12. Durum: tasarım yönü seçildi, kod yazılmadı.

Bu belge, uygulamanın bütün arayüzünü "Yayın Masası" tasarım diline taşımak için gereken her kararı içerir. Uygulama planı: `docs/superpowers/plans/2026-11-12-yayin-masasi-arayuz.md`.

## Kaynaklar

- **Mockup dosyaları (depoda):** `docs/superpowers/specs/yayin-masasi-mockups/`. Her ekran 1280×720 mantıksal piksel, bütün ölçü ve renkler satır içi `style` özelliklerinde yazılı. Bu belgede yazmayan bir ölçü gerekirse oradan oku.
- **Canlı tuval:** https://claude.ai/artifact/XTx16h164VDjxJa6srBaYB (yalnızca hesap sahibi açabilir).
- Bu belge ile mockup çelişirse bu belge geçerlidir. Bilinen çelişkiler "Mockup'tan bilinçli sapmalar" bölümünde.

| Ekran | Mockup dosyası | Kod |
|---|---|---|
| Ana sayfa | `Main.dc.html` | `lib/src/home_page.dart` (`_homeView`) |
| Canlı TV | `B-Canli.dc.html` | `lib/src/home_page.dart` (`_liveList`), yeni `lib/src/guide_grid.dart` |
| Filmler, Diziler | `B-Filmler.dc.html` | `lib/src/home_page.dart` (`_posterGrid`) |
| Dizi ve film detayı | `B-Detay.dc.html` | `lib/src/detail_page.dart` |
| Oynatıcı, film ve dizi | `B-Oynatici.dc.html` | `lib/src/player_page.dart` (`_chrome`) |
| Oynatıcı, canlı | `B-OynaticiCanli.dc.html` | `lib/src/player_page.dart` (`_chrome`) |
| Profil seçimi | `B-Profiller.dc.html` | `lib/src/login_page.dart` |
| Ayarlar | `B-Ayarlar.dc.html` | `lib/src/settings_page.dart` |
| Tasarım dili | `B-Sistem.dc.html` | yeni `lib/src/ui/` |

## Amaç ve neden

Uygulama bugün varsayılan Material 3 koyu temasıyla (mor tohum rengi, `NavigationRail`, `ListTile`) çalışıyor. Kullanıcı tasarımın çok önemli olduğunu söyledi, Netflix benzeri ilk taslağı "sıradan" bulup reddetti ve üç yönden "Yayın Masası"nı seçti.

Fikir: arayüz bir yayın kontrol odası gibi görünür. Görüntüler monitör, altlarında etiket çubuğu var. Düğmeler yayın masası tuşu. Sayılar zaman kodu. Canlı TV bir yayın akışı tablosu.

## Hedefler

- Bütün ekranlar aşağıdaki tasarım diline geçer, eski görünümden iz kalmaz.
- Kumanda ile kullanım bugünkünden kötüleşmez: odak her an açıkça görünür, hiçbir öğe ulaşılamaz kalmaz.
- 1 GB RAM'li Android TV stick'te akıcı kalır.
- Mevcut bütün işlevler korunur (aşağıda "Korunacak davranışlar").

## Hedef dışı

- Yeni özellik yok: geriye dönük izleme, "izlendi" işareti, genel arama, açık tema, hareketli geçişler eklenmez.
- Veri katmanı değişmez. Tek istisna: `XtreamClient.shortEpg` sınırı 3'ten 6'ya çıkar (yayın akışı tablosu için).
- `UiScale`, `PhoneRemote`, `AccountStore`, `Library`, `EpgCache` mantığı değişmez.

## Kesinlikle yapılmayacaklar

- Parlama, bulanıklık (`BackdropFilter`), gölge, renk geçişi. Tek istisna yok.
- Kehribarı odak, konum ve saat dışında bir şey için kullanmak.
- Kırmızıyı canlı yayın, oynatılan öğe ve etkin bölüm dışında bir şey için kullanmak.
- 4'ten büyük köşe yarıçapı, yuvarlak düğme, hap biçimli etiket.
- 12 pikselden küçük metin.
- `NavigationRail`, `ListTile`, `Card`, `Chip`, `FilledButton` gibi varsayılan Material görünümlerini olduğu gibi bırakmak.

## Tasarım dili

### Renkler

| Ad (`AppColors`) | Değer | Kullanım |
|---|---|---|
| `ground` | `#0E1011` | Sayfa zemini |
| `gridLine` | beyaz, %2,8 opak | Zemindeki 40 piksellik ızgara çizgileri, 1 piksel |
| `panel` | `#181B1D` | Satır, görseli olmayan ekran kutusu |
| `key` | `#1B1F21` | Tuş yüzeyi |
| `panelHi` | `#262C30` | Seçili yan liste öğesi, tablodaki "şimdi" bloğu, fare üstündeyken |
| `well` | `#050606` | Etiket çubuğu, bilgi çubuğu, metin alanı, oynatıcı paneli |
| `line` | `#2A3034` | Ayırıcı çizgi, ilerleme çubuğu zemini |
| `keyBorder` | `#30373B` | Tuş ve alan çerçevesi, sönük gösterge |
| `lineHi` | `#3A4247` | Seçili öğe çerçevesi, kesikli çerçeve |
| `dim` | `#5B666C` | Etiket çerçevesi, kapalı anahtar topuzu |
| `text` | `#E9EDEF` | Birincil metin |
| `text2` | `#C5CDD1` | İkincil metin |
| `text3` | `#8B969C` | Soluk metin, etiket, ipucu |
| `amber` | `#FFB020` | Odak çerçevesi, konum çubuğu, saat, kanal numarası, kalan süre |
| `amberTint` | `#2A2414` | Odaklanan öğenin zemini |
| `red` | `#FF3B30` | Etkin bölüm tuşu, PGM ve CANLI etiketi, "şimdi" çizgisi, seçili kategori ışığı |
| `onRed` | `#140504` | Kırmızı üstündeki metin |
| `buffered` | `#4A545A` | Konum çubuğunda tamponlanan kısım |

Oynatıcıda video üstüne binen paneller `well` rengini %92 opaklıkla kullanır (`#050606` alfa 0.92). Başka yerde saydamlık yok.

### Yazı

İki aile, ikisi de uygulamaya gömülür (ağdan yüklenmez):

- **Archivo** değişken yazı tipi, `wdth` 62–125 ve `wght` 400–800 eksenleri. Kaynak: Google Fonts, OFL lisansı, `ofl/archivo/Archivo[wdth,wght].ttf`.
- **IBM Plex Mono** 500 ve 600. Kaynak: Google Fonts, OFL lisansı, `IBMPlexMono-Medium.ttf` ve `IBMPlexMono-SemiBold.ttf`.

İkisi de Türkçe harfleri içerir. Dosyaların indirilmesi için kullanıcıdan izin iste.

Flutter'da değişken eksenler `fontVariations` ile verilir: `FontVariation('wght', 800)` ve `FontVariation('wdth', 125)`. `fontWeight` tek başına yetmez, ikisini birlikte ver.

| Rol (`AppText`) | Aile, genişlik, kalınlık | Boyutlar | Kullanım |
|---|---|---|---|
| `display` | Archivo, wdth 125, wght 800 | 38, 36, 26, 24, 22, 20 | Sayfa başlığı, kanal adı, marka, ekran kutusundaki ad |
| `body` | Archivo, wdth 100, wght 600 (gövde metni 400) | 20, 18, 17, 16, 15 | İçerik adları, açıklama |
| `label` | Archivo, wdth 88, wght 600 | 15, 14, 13, 12 | Tuş yazısı, etiket çubuğu, sütun başlığı, ipucu |
| `heading` | Archivo, wdth 112, wght 600, 14, renk `text3` | 14 | Bölüm başlığı ("Son izlediklerin", "Kanallarım") |
| `mono` | IBM Plex Mono 600 (ikincil 500), tabular rakam | 52, 34, 22, 20, 15, 14, 13, 12 | Kanal numarası, saat, zaman kodu, yıl, sayı |

Etiket metinleri cümle düzeninde yazılır. Yalnızca `PGM`, `CANLI` ve `OK` büyük harftir.

### Ölçüler

| Ad | Değer |
|---|---|
| Köşe yarıçapı | 4 (etiket 2, tuş başlığı 3) |
| Odak çerçevesi | Görsel kutularda 4 piksel, içe doğru. Satır, tuş, hücrede 3 piksel |
| Sayfa kenar boşluğu | 28 |
| Üst çubuk | Üstten 16, yükseklik 44, altında y=72'de 1 piksel `line` |
| Üst çubuk tuşu | Yükseklik 40, yatay dolgu 16, aralık 6 |
| Diğer tuşlar | Yükseklik 44, yatay dolgu 14–16, aralık 8 |
| Yan liste | Genişlik 196, öğe yüksekliği 44, aralık 4 |
| İçerik sütunu | Yan listeden sonra 20 boşluk (x=244) |
| Etiket çubuğu | 28 (ana ekran 44, profil 54, arka plan görseli 32) |
| Bilgi çubuğu | Yükseklik 76, yatay dolgu 18 |
| Kutu aralığı | 12 |
| Satır aralığı | 4 |
| En küçük dokunma alanı | 44×44 (üst çubuk tuşu 40 yüksekliğinde, genişliği yeterli) |

### Bileşenler

Hepsi `lib/src/ui/` altında. Durum örnekleri `B-Sistem.dc.html` dosyasında.

**Odak kutusu (`FocusBox`).** Dokunma, fare ve odak davranışını tek yerde toplar. Odakta: 3 piksel `amber` çerçeve ve `amberTint` zemin. Fare üstündeyken: `panelHi` zemin, çerçeve yok. Çerçeve yer kaplamaz, olağan durumda aynı kalınlıkta saydam çerçeve bulunur, böylece odak gelince düzen kaymaz. Geçiş 120 ms.

**Tuş (`AppKey`).** Üç görünüm:
- Olağan: zemin `key`, 1 piksel `keyBorder`, metin `text2` (üst çubukta) ya da `text`, `label` 15.
- Etkin: zemin ve çerçeve `red`, metin `onRed`, kalınlık 700. Yalnızca üst çubukta bulunulan bölüm için.
- Seçili: zemin ve çerçeve `text`, metin `ground`, kalınlık 700. Sezon tuşları ve seçenek grupları için.
- Odak her görünümün üstüne 3 piksel `amber` çerçeve ekler, zemin `amberTint`, metin beyaz.
- İsteğe bağlı: solda ikon, solda soluk ön ek ("Ses", "Altyazı", "Sıralama"), solda 8 piksel ışık noktası.

**Etiket (`Tag`).** Dolu: zemin `red`, metin `onRed`, `mono` 13, dolgu 2×8, yarıçap 2 (`PGM`, `CANLI`). Çerçeveli: 1 piksel `dim`, metin `text2`, `mono` 13 (yıl, dil).

**Tuş başlığı (`KeyCap`).** 1 piksel `dim` çerçeve, yarıçap 3, dolgu 1×7, `mono` 12. "OK" ipucu için, yanında `label` 14–15 açıklama.

**Ekran kutusu (`ScreenTile`).** Üstte görsel, altta `well` renkli etiket çubuğu. Çubukta solda ad (`label` 14, tek satır, taşarsa üç nokta), sağda `mono` 12 `amber` bilgi (yıl, kalan süre, kanal numarası). Odakta görselin içine 4 piksel `amber` çerçeve, çubuk zemini `amberTint`. Oynatılan öğede çubuğun başında `PGM` etiketi.

**Yan liste öğesi (`SideKey`).** Solda 8 piksel ışık noktası, ad, sağda `mono` 13 `text3` sayı. Seçili: zemin `panelHi`, 1 piksel `lineHi`, metin beyaz 700, ışık `red`. Seçili değil: saydam zemin, metin `text2` 500, ışık `keyBorder`.

**Konum çubuğu (`ProgressLine`).** Zemin `line`, dolgu `amber`, köşesiz. Yükseklik 3 (kartlarda), 4 (canlı oynatıcı), 8 (oynatıcı konum çubuğu).

**Anahtar (`AppSwitch`).** 54×28 kutu, `well` zemin, 1 piksel `dim`, yarıçap 4, iç dolgu 3. İçinde 22 genişliğinde topuz, yarıçap 2. Açık: topuz sağda, renk `text`, solunda "Açık" yazısı. Kapalı: topuz solda, renk `dim`, "Kapalı" yazısı `text2`.

**Seçenek grubu (`Segmented`).** `well` zemin, 1 piksel `keyBorder`, yarıçap 4, iç dolgu 3, seçenekler arası 2. Seçenek yüksekliği 34, yatay dolgu 14, `label` 14. Seçili seçenek: zemin `text`, metin `ground`, 700.

**Ses göstergesi (`LevelMeter`).** 10 dikdörtgen, her biri 7×20, aralık 3. Yanan `text`, sönük `keyBorder`.

**Saat (`ClockText`).** `mono` 22 `amber`, `SS:DD:SN` biçimi, saniyede bir güncellenir. Oynatıcıda 20.

**Marka (`BrandMark`).** Yedi dikey renk çubuğu, her biri 7×30: `#C8C8C8`, `#C8C800`, `#00C8C8`, `#00C800`, `#C800C8`, `#D01818`, `#1818D0`. Yanında "IPTV", `display` 20, harf aralığı 0.02 em. Renk çubukları kehribar ve kırmızı kuralının tek istisnasıdır, başka yerde kullanılmaz.

**Bilgi çubuğu (`InfoBar`).** Liste ekranlarının altında sabit, 76 yüksekliğinde `well` kutu. O an odaklanan öğeyi anlatır.

## Ekranlar

Ölçüler 1280×720 içindir. Gerçek pencerede genişlikler orantılı uzar, sütun sayıları genişlikten hesaplanır ("Duyarlı düzen" bölümü).

### Ortak iskelet

Sol `NavigationRail` kalkar. Yerine üst çubuk gelir: marka, altı tuş (Ana sayfa, Canlı TV, Filmler, Diziler, Favoriler, Ayarlar), sağda hesap adı (yalnızca ana sayfada, tıklanınca Ayarlar) ve saat. Bulunulan bölümün tuşu "etkin" görünümdedir.

Her tuşun bir `ValueKey`'i olur: `nav-home`, `nav-live`, `nav-movies`, `nav-series`, `nav-favorites`, `nav-settings`.

Zemin: `ground` üstüne 40 piksel aralıklı ızgara çizgileri. Bir kez çizilir (`CustomPainter` ve `RepaintBoundary`).

### Ana sayfa

Dikey kaydırılan tek sütun.

1. **Üst sıra.** Solda ana ekran (16:9, içerik genişliğinin yaklaşık %52'si, mockup'ta 640×360), sağda "Son izlediklerin" başlığı altında 2×2 ekran kutusu.
   - Ana ekran `Library.continueWatching` listesinin ilk öğesidir. Etiket çubuğu (44): `PGM` etiketi, ad, "OK Devam et" ipucu, sağda kalan süre zaman kodu (`-01:12:00`). Altında 3 piksel konum çubuğu. Açılışta odak buradadır. Seçilince `_openHistory` çalışır.
   - Görsel: film ve dizide afiş `BoxFit.cover` ile 16:9'a kırpılır, `cacheWidth` 640. Canlı kanalda logo `BoxFit.contain`, `panel` zemin, 24 dolgu.
   - 2×2 kutular listenin sonraki dört öğesidir. Etiket: ad ve kalan süre.
   - Liste boşsa bu sıra hiç çizilmez.
2. **Kanallarım.** Favori canlı kanallar, beşli sıra (genişliğe göre), yatay kaydırma. Görsel alanında logo (`contain`, `panel` zemin), logo yoksa kanal adı `display` 20. Etiket: kanal numarası (favori kanal listesindeki sıra + 1, üç haneli), o anki program adı (`EpgCache`), sağda kırmızı nokta.
3. **Filmlerim** ve **Dizilerim.** Favori film ve diziler, afiş kutuları (2:3) yatay sırada. Etiket: ad ve yıl.
4. Geçmiş ve favori yoksa: ortada mevcut metin ("Burası senin sayfan. …").

### Canlı TV

Sol: kategori yan listesi (aşağıda "Kategori sütunu"). Sağ: yayın akışı tablosu. Alt: bilgi çubuğu.

**Tablo.**
- Zaman penceresi 150 dakika. Başlangıç: şimdiki zaman 30 dakikaya aşağı yuvarlanır, sonra 30 dakika çıkarılır (21:47 için 21:00). 30 saniyede bir yeniden hesaplanır.
- Üst cetvel (30 yükseklik): solda "{kategori}, {n} kanal" (`heading`), sağda her 30 dakikada bir saat etiketi (`mono` 13 `text3`, solunda 1 piksel `lineHi` çizgi).
- Satır (yükseklik 50, aralık 4): solda 180 genişliğinde kanal hücresi: numara (`mono` 14 `amber`, listedeki sıra + 1, üç haneli), ad (`body` 16), en sağda favori düğmesi. Sağda zaman alanı.
- Program bloğu: konumu ve genişliği başlangıç ve bitiş saatinden hesaplanır, pencere dışına taşan kısmı kırpılır, bloklar arasında 3 piksel boşluk. İçinde ad (`body` 15, tek satır) ve saat aralığı (`mono` 12). Olağan: zemin `panel`, 1 piksel `line`. O an yayında olan: zemin `panelHi`, 1 piksel `lineHi`.
- "Şimdi" çizgisi: tablonun tamamı boyunca 2 piksel `red`, üstünde kırmızı etiket içinde saat (`mono` 13).
- Program bilgisi yoksa ya da yüklenirken: satırın tamamını kaplayan tek blok, içinde kategori adı, metin `text3`. Dönen yükleme göstergesi yok.

**Odak.** Odak satır düzeyindedir, program hücresi düzeyinde değil. Odaklanan satırda o an yayındaki blok 3 piksel `amber` çerçeve ve `amberTint` zemin alır. OK kanalı açar. Satırın favori düğmesi ayrı bir odak durağıdır (bugünkü gibi).

**Bilgi çubuğu.** Odaklanan kanal: numara (`mono` 34 `amber`), ad (`display` 22), `CANLI` etiketi, program adı ve saat aralığı, 3 piksel konum çubuğu, sağda "Sırada" ile sıradaki program.

### Filmler ve Diziler

Sol: kategori yan listesi. Sağ üst: arama alanı, sıralama tuşu, toplam sayı. Altında afiş ızgarası. En altta bilgi çubuğu.

- **Arama alanı:** `well` zemin, 1 piksel `keyBorder`, yükseklik 44, solda büyüteç. Odakta çerçeve 3 piksel `amber`.
- **Sıralama tuşu:** soluk ön ek "Sıralama", seçili değer, aşağı ok. Açılır menü gösterir (bugünkü dört seçenek). Yalnızca film ve dizide.
- **Izgara:** ekran kutuları, afiş oranı 2:3'e yakın (133×190), etiket çubuğunda ad ve yıl. Favori ise sağ üstte 24×24 `well` kare içinde dolu kalp. Favori düğmesi bugünkü gibi ayrı odak durağıdır, favori değilse yalnızca kutu odakta ya da fare üstündeyken görünür (içi boş kalp).
- **Bilgi çubuğu:** ad (`display` 24), yıl ve dil etiketleri, kategori adı, favori durumu, "OK Ayrıntılar".

### Kategori sütunu

Canlı TV, Filmler ve Diziler'de ortak. Genişlik 196.

- En üstte kategori arama alanı (bugünkü `RemoteTextField`, yeni görünümle). Ağaçta ana aramadan önce gelmeye devam etmeli, testler buna dayanıyor.
- "Tümü" ve kategoriler yan liste öğesi olarak. Uzun basma ve sağ tık davranışı aynen kalır.
- En altta kesikli çerçeveli "Kategorileri düzenle" tuşu. İpucu metni (`tooltip`) "Kategorileri düzenle / gizle" olarak kalır, testler bunu arıyor.

### Favoriler

Arama alanı ve altında üç başlıklı tek kaydırma alanı: "Kanallar" (16:9 kutular), "Filmler" ve "Diziler" (afiş kutuları). Boş başlık çizilmez. Hiç favori yoksa mevcut metin kalır.

### Detay

Üst çubukta menü tuşları yerine "Geri" tuşu, yol ("Diziler / Breaking Bad") ve saat.

- Sol: afiş 200×300.
- Orta (genişlik 572): ad (`display` 38), künye tablosu, açıklama (`body` 15, kalınlık 400, satır yüksekliği 1.5, renk `text2`), tuşlar.
  - Künye: iki sütunlu tablo, sol sütun 96 genişliğinde `label` 15 `text3`. Satırlar: Puan (`mono` `amber`), Yıl (`mono`), Tür, Dil, Süre (yalnızca film), Yönetmen, Oyuncular. Boş olan satır çizilmez.
  - Tuşlar: filmde "Oynat" ya da "Devam et 21:04" (açılışta odak burada), ardından "Favorilere ekle" ya da "Favorilerde". Dizide yalnızca favori tuşu.
- Sağ: arka plan görseli varsa 400×225 ekran kutusu, etiket çubuğunda dizide "{n} sezon, {m} bölüm", filmde süre. Görsel yoksa kutu çizilmez, orta sütun genişler.
- Dizide altında sezon tuşları ("1. sezon" …), seçili olan "seçili" görünümde, sağda "{n} bölüm". `ExpansionTile` kalkar, yalnızca seçili sezonun bölümleri listelenir. Açılışta devam eden bölümün sezonu, yoksa ilk sezon seçilidir.
- Bölüm tablosu: sütun başlıkları (Bölüm, Başlık, Süre, Durum, `label` 13 `text3`), satır yüksekliği 52, zemin `panel`. Sütunlar: numara (`mono` 15 `amber`, "B03"), küçük görsel 92×40, başlık, süre, durum. Durum yalnızca devam eden bölümde dolar: 110 genişliğinde kehribar konum çubuğu ve "27 dk kaldı". Oynatma sırası bugünkü gibi bütün sezonları kapsar.

### Oynatıcı, film ve dizi

Video tam ekran. Üstünde iki katman:

- **Üst sıra (üstten 20):** "Geri" tuşu (44×44), yanında `well` kutu içinde `PGM` etiketi ve ad (`display` 18), sağda saat.
- **Alt panel (alttan 24, yanlardan 28):** `well` %92, yarıçap 4, dolgu 18.
  - Konum satırı: solda geçen süre (`mono` 20 `amber`, `00:21:04`), ortada konum çubuğu, sağda kalan süre (`mono` 20 `text2`, `-00:27:08`). Çubuk: yükseklik 8, zemin `line`, tamponlanan `buffered`, oynatılan `amber`, tutamaç 4×22 beyaz dikdörtgen. Altında 6 yüksekliğinde cetvel: çubuğun her onda birinde 1 piksel `dim` çizgi.
  - Tuş satırı, soldan sağa: önceki bölüm, geri sar (`-10`, ayardaki süre), oynat ve duraklat (72 genişlik, açılışta odak burada), ileri sar (`+10`), sonraki bölüm, "Zamana git", ses kapatma tuşu ve ses göstergesi, boşluk, "Otomatik sonraki açık" tuşu (ışık noktasıyla), "Hız" tuşu, "Ses" tuşu, "Altyazı" tuşu, tam ekran.
- Ses göstergesi yalnızca kumanda modu kapalıyken görünür (bugünkü ses kaydırıcısı gibi). Bir dikdörtgene tıklamak sesi o düzeye getirir.

### Oynatıcı, canlı

- **Üst sıra:** "Geri" tuşu ve saat.
- **Alt panel:**
  - Kanal satırı: numara (`mono` 52 `amber`, sıradaki yeri + 1, üç haneli), ad (`display` 26), altında `CANLI` etiketi. Ortada program adı (`body` 20, 700), saat aralığı, 4 piksel konum çubuğu, "Sırada" satırı. Sağda 300 genişliğinde iki satır: bir önceki ve bir sonraki kanal (ok, numara, ad, varsa o anki program).
  - Tuş satırı: önceki kanal, oynat ve duraklat, sonraki kanal, ses, ipucu metni (yalnızca kumanda modunda: "Kumandada yukarı ve aşağı tuşları kanal değiştirir."), "Ses", "Altyazı", tam ekran.

Hata kutusu, kısa bilgi yazısı, sıradaki bölüm sayacı, yazılan kanal numarası, parça seçme ve "Zamana git" pencereleri aynı dille yeniden giydirilir: `well` ya da `panel` zemin, yarıçap 4, 1 piksel `keyBorder`, düğmeler `AppKey`.

### Profil seçimi ve giriş

- Üst çubuk: yalnızca marka ve saat.
- Başlık "Kullanıcı seç" (`display` 36), sola yaslı. Düzenleme modunda "Silinecek kullanıcıyı seç".
- Profil kutuları dörtlü sırada: 135 yüksekliğinde `panel` alan içinde adın ilk harfi (`display` 64), 54 yüksekliğinde etiket çubuğunda ad, sunucu adresi (`mono` 12 `text3`) ve son kullanılanda çerçeveli "Son kullanılan" etiketi. Renkli yuvarlak avatar kalkar. Düzenleme modunda kutunun sağ üstünde kırmızı "Sil" etiketi.
- "Kullanıcı ekle" kutusu: kesikli çerçeve, artı ikonu, etikette "Telefondan QR ile ya da elle".
- Altında "Kullanıcıları düzenle" tuşu (düzenlemede "Bitti").
- Giriş formu: 380 genişliğinde sütun, alanlar arama alanıyla aynı görünümde, üstte "Telefondan gir (QR)" tuşu.
- Otomatik giriş ekranı: marka, "{ad} olarak giriş yapılıyor...", 3 piksel belirsiz kehribar çubuk, "Vazgeç / kullanıcı değiştir" tuşu.
- QR penceresi (`RemoteEntryDialog`): aynı pencere görünümü, QR beyaz zeminde kalır.

### Ayarlar

- Sol: bölüm yan listesi (Hesap, Oynatıcı, İçerik, Telefonu kumanda yap, Görünüm, Kısayollar). Tıklanınca sağdaki liste o bölüme kayar ve o öğe seçili görünür.
- Sağ: tek kaydırma alanı.
  - En üstte hesap çubuğu (68, `well`): ad (`display` 20), sunucu, "Abonelik bitişi", "Eşzamanlı bağlantı" (`mono` `amber`, yanında yenile tuşu, sınır doluysa `red`), sağda "Kullanıcı değiştir" tuşu.
  - Her bölüm başlığı `display` 24.
  - Satır (yükseklik 62): solda başlık (`body` 16) ve açıklama (`body` 14, 400, `text3`), sağda denetim. Açılır menüler `Segmented`, anahtarlar `AppSwitch` olur. Satırın tamamı odak kutusudur.
  - Seçenek kümeleri koddakiyle aynı kalır (ön bellek 10, 15, 30, 60, 120 sn. Sarma 5, 10, 30 sn. Ölçek %50–%140).
  - Kısayollar: sol sütunda tuş başlıkları (`KeyCap`), sağda açıklama.

## Davranış kararları

**Geri tuşu (ana ekran).** Üst çubuğa kumandayla ulaşmak uzun listelerde zorlaşacağı için Geri tuşu sırası değişir. Kumanda modunda: odak üst çubukta değilse Geri, odağı etkin bölüm tuşuna taşır. Odak zaten üst çubuktaysa bugünkü sıra işler (kategori seçiliyse "Tümü", ana sayfada değilse Ana sayfa, değilse uygulamadan çık). Kumanda modu kapalıyken sıra bugünkü gibidir.

**Yön tuşları.** Üst çubukta sol ve sağ tuşlar arasında gezer, aşağı içeriğe iner. Kategori sütununda sağ, içeriğe geçer.

**Odak takibi.** Bilgi çubuğunun gösterdiği öğe bir `ValueNotifier<Item?>` içinde tutulur. Odak değişimi bütün sayfayı yeniden çizdirmemelidir (20 000 öğelik listelerde `setState` yasak).

**Favori.** Liste ekranlarındaki kalp düğmeleri bugünkü gibi ayrı odak durağı olarak kalır, yalnızca görünümü değişir.

**Kanal numarası.** Xtream'in kendi numarası kullanılmaz. Numara, gösterilen listedeki sıra + 1'dir. Bu, oynatıcıda rakamla kanal seçmeyle (`_typeDigit`) aynı sayıdır.

**Metin alanları.** `RemoteTextField` davranışı değişmez.

**Kumanda modu.** `tvMode` artık odak renginin koyuluğunu belirlemez (odak görünümü her zaman aynıdır). Otomatik odak, metin alanı davranışı, ses göstergesinin gizlenmesi ve Geri tuşu sırası için kullanılmaya devam eder.

## Korunacak davranışlar

Kontrol listesi olarak kullan, her biri yeni arayüzde de çalışmalı:

- Otomatik giriş ve iptali, çoklu hesap, onaylı silme, telefondan QR ile giriş.
- Sekme değişince arama kutusunun boşalması.
- Kategori arama, sıralama, gizleme, en üste alma, düzenleme penceresi (sürükle bırak ve oklar).
- Canlı listede "şimdi" bilgisi ve ilerleme, favori ekleme.
- Liste yüklenemezse hata metni ve "Tekrar dene".
- Film detayında devam etme, dizide bütün sezonları kapsayan oynatma sırası.
- Oynatıcı: önceki ve sonraki, sarma, zamana gitme, ses, hız, ses ve altyazı parçası, tam ekran, otomatik sonraki bölüm ve sayacı, rakamla kanal seçme, yukarı ve aşağı ile kanal değiştirme, hata ve yeniden deneme, fare gizlenince denetimlerin kaybolması.
- Ayarlardaki bütün seçenekler, telefon kumandası QR kodu, bağlantı sayacı.
- `UiScale` %50–%140 arası her ölçekte tıklanabilirlik.

## Duyarlı düzen

- İçerik genişliği pencereden hesaplanır, sabit 1280 varsayılmaz.
- Afiş ızgarası sütun sayısı: `floor((genişlik + 12) / 145)`, en az 2. Kutu genişliği kalan alanı eşit paylaşır, afiş yüksekliği genişliğin 1,43 katı.
- Ana sayfada üst sıra 900'den dar içerikte alt alta dizilir.
- Üst çubuk tuşları sığmazsa yatay kayar. 900'den dar pencerede hesap adı gizlenir.
- Yayın akışı tablosunda kanal hücresi 180 sabit kalır, zaman alanı kalan genişliği alır.
- Detayda sağdaki arka plan kutusu 1100'den dar pencerede gizlenir.

## Performans kuralları

- `BackdropFilter`, `BoxShadow`, `ShaderMask` yok.
- Listeler `builder` ile kurulur, sabit satır yüksekliği (`itemExtent` ya da `mainAxisExtent`) verilir.
- Küçük görseller `cacheWidth` 260 ile çözülür (mevcut `PosterImage`), ana ekran 640 ile.
- Zemin ızgarası ve "şimdi" çizgisi kendi `RepaintBoundary`'lerinde durur.
- Saat saniyede bir yalnızca kendi metnini yeniden çizer.

## Metin değişiklikleri

Mevcut Türkçe metinler korunur. Değişen ve yeni olanlar:

| Yer | Eski | Yeni |
|---|---|---|
| Menü | Ana Sayfa | Ana sayfa |
| Ana sayfa başlığı | Kaldığın yerden devam et | Son izlediklerin |
| Ana ekran ipucu | (yok) | Devam et |
| Bilgi çubuğu ipucu | (yok) | Ayrıntılar |
| Sıralama tuşu ön eki | (ikon) | Sıralama |
| Sıralama seçeneği | Yıl (yeni → eski) | Yıl, yeniden eskiye |
| Cetvel başlığı | (yok) | {kategori}, {n} kanal |
| Bilgi çubuğu | (yok) | Sırada |
| Sezon tuşu | {n}. Sezon ({m} bölüm) | {n}. sezon |
| Bölüm durumu | Devam ediliyor (21:04) | {n} dk kaldı |
| Oynatıcı tuşu | (ikon) | Otomatik sonraki açık / kapalı |
| Canlı oynatıcı ipucu | (yok) | Kumandada yukarı ve aşağı tuşları kanal değiştirir. |
| Profil ekleme etiketi | (boş) | Telefondan QR ile ya da elle |
| Favoriler başlıkları | (yok) | Kanallar, Filmler, Diziler |

Testlerin aradığı şu metinler değişmemeli: "Kullanıcı seç", "Son kullanılan", "Kullanıcıları düzenle", "Giriş bilgilerinizi girin", "Kullanıcı Ekle", "Vazgeç / kullanıcı değiştir", "giriş yapılıyor", "Tekrar dene", "Sonuç yok", "Tamam", "En üste al", "Ön bellek (tampon)".

## Mockup'tan bilinçli sapmalar

- **İzlendi ve İzlenmedi.** Mockup'taki bölüm tablosu bunları gösteriyor. Uygulamada "izlendi" verisi yok (sona kadar izlenince konum siliniyor), bu yüzden yalnızca devam eden bölüm işaretlenir.
- **Hız tuşu.** Oynatıcı mockup'ında yok ama uygulamada var, korunur ("Otomatik sonraki" ile "Ses" arasında).
- **Ayar adları ve seçenekleri.** Mockup'ta kısaltılmış adlar ve farklı seçenek kümeleri var. Koddaki adlar ve kümeler geçerlidir.
- **Ana ekran görseli.** Mockup'ta geniş bir sahne var. Geçmiş kaydında yalnızca afiş bulunduğu için afiş 16:9'a kırpılarak gösterilir.
- **Örnek veri.** Program adları, sayılar, sunucu adresi ve tarih yer tutucudur.
- **Favori düğmesi.** Mockup'taki yayın akışı tablosunda görünmüyor, kanal hücresinin sağ ucunda yer alır.

## Uygulayana bırakılanlar

- Dosya içi yardımcı widget'ların adları ve bölünmesi.
- Odak geçişinin tam eğrisi (120 ms civarı, doğrusal ya da `easeOut`).
- Açılır menü ve pencere iç boşluklarının ince ayarı.
- Dar pencerelerde kırılma noktalarının ±50 piksel ayarı.

## Riskler

- **Program verisi.** Sağlayıcı `get_short_epg` için az kayıt dönerse tablo seyrek görünür. Satır yine de oynatılabilir olmalı.
- **Yazı tipi dosyaları.** Depoya iki yazı tipi eklenir (yaklaşık 1 MB). İndirme kullanıcı onayı ister.
- **Odak çubuğu erişimi.** Geri tuşu sırası değiştiği için TV stick üzerinde elle denenmeli.
