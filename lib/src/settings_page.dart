import 'package:flutter/material.dart';

import 'package:qr_flutter/qr_flutter.dart';

import 'phone_remote.dart';
import 'player_session.dart';
import 'settings.dart';
import 'system_pip.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/focus_ring.dart';
import 'ui/layout.dart';
import 'ui/tokens.dart';
import 'xtream.dart';

const _sections = ['Hesap', 'Oynatıcı', 'İçerik', 'Telefonu kumanda yap', 'Görünüm', 'Kısayollar'];

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.info, required this.account, required this.client, required this.onLogout});

  final XtreamClient client;
  final AccountInfo info;
  final Account account;
  final VoidCallback onLogout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selected = 0;
  final _keys = [for (final _ in _sections) GlobalKey()];
  final _scroll = ScrollController();
  bool _jumping = false; // a section key is scrolling: don't let the listener pick another section meanwhile

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_follow);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int get _visibleSectionCount =>
      Theme.of(context).platform == TargetPlatform.iOS ? _sections.length - 1 : _sections.length;

  /// Marks the section whose card is at the top of the scroll area.
  void _follow() {
    if (_jumping) return;
    final view = context.findRenderObject() as RenderBox?;
    if (view == null) return;
    final top = view.localToGlobal(Offset.zero).dy + 40;
    final count = _visibleSectionCount;
    var pick = 0;
    for (var i = 0; i < count; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.localToGlobal(Offset.zero).dy <= top) pick = i;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 1) pick = count - 1;
    if (pick != _selected) setState(() => _selected = pick);
  }

  Future<void> _go(int i) async {
    setState(() => _selected = i);
    final c = _keys[i].currentContext;
    if (c == null) return;
    _jumping = true;
    await Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 200), alignment: 0);
    _jumping = false;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([s, PhoneRemote.instance, PlayerSession.instance]),
      builder: (context, _) {
        final mode = layoutModeOf(context);
        final phone = mode != AppLayoutMode.desktop;
        final portrait = mode == AppLayoutMode.phonePortrait;
        final landscape = mode == AppLayoutMode.phoneLandscape;
        final isIos = Theme.of(context).platform == TargetPlatform.iOS;
        final showShortcuts = !isIos;
        final sections = showShortcuts ? _sections : _sections.sublist(0, _sections.length - 1);
        final narrow = phone || MediaQuery.sizeOf(context).width < 900;
        final pad = MediaQuery.paddingOf(context);
        final leftPad = landscape ? (pad.left > 0 ? pad.left : 14.0) : AppSizes.scrollPad;
        final rightPad = landscape ? 12.0 : 16.0;
        final bottomPad = portrait
            ? phoneBottomClearance(context)
            : (landscape ? (pad.bottom > 0 ? pad.bottom + 8 : 16.0) : 16.0);

        final cards = SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(portrait ? 16 : AppSizes.scrollPad, AppSizes.scrollPad, rightPad, bottomPad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KeyedSubtree(key: _keys[0], child: portrait ? _phoneAccountCard() : _accountCard()),
            const SizedBox(height: 16),
            _Section(key: _keys[1], title: 'Oynatıcı', children: [
              _ChoiceRow(
                title: 'Tercih edilen ses dili',
                narrow: narrow,
                control: Segmented<String>(
                  key: const ValueKey('setting-audioLang'),
                  value: s.audioLang,
                  options: const {'auto': 'Dosya varsayılanı', 'tr': 'Türkçe', 'en': 'İngilizce'},
                  onChanged: (v) {
                    AppHaptics.selection(context);
                    s.update(audioLang: v);
                  },
                ),
              ),
              _ChoiceRow(
                title: 'Tercih edilen altyazı',
                narrow: narrow,
                control: Segmented<String>(
                  key: const ValueKey('setting-subLang'),
                  value: s.subLang,
                  options: const {'off': 'Kapalı', 'tr': 'Türkçe', 'en': 'İngilizce'},
                  onChanged: (v) {
                    AppHaptics.selection(context);
                    s.update(subLang: v);
                  },
                ),
              ),
              _ChoiceRow(
                title: 'Altyazı boyutu',
                narrow: narrow,
                control: Segmented<double>(
                  key: const ValueKey('setting-subtitleScale'),
                  value: s.subtitleScale,
                  options: AppSettings.subtitleSizeOptions,
                  onChanged: (v) {
                    AppHaptics.selection(context);
                    s.update(subtitleScale: v);
                  },
                ),
              ),
              _ChoiceRow(
                title: 'İleri/geri sarma süresi',
                narrow: narrow,
                control: Segmented<int>(
                  key: const ValueKey('setting-skipSecs'),
                  value: s.skipSecs,
                  options: const {5: '5 sn', 10: '10 sn', 30: '30 sn'},
                  onChanged: (v) {
                    AppHaptics.selection(context);
                    s.update(skipSecs: v);
                  },
                ),
              ),
              _ChoiceRow(
                title: 'Ön bellek (tampon)',
                narrow: narrow,
                control: _MenuChoice<int>(
                  key: const ValueKey('setting-cacheSecs'),
                  title: 'Ön bellek (tampon)',
                  useSheet: phone,
                  value: s.cacheSecs,
                  options: const {10: '10 sn', 15: '15 sn', 30: '30 sn', 60: '60 sn', 120: '120 sn'},
                  onChanged: (v) => s.update(cacheSecs: v),
                ),
              ),
              _SwitchRow(
                title: 'Donanım hızlandırma',
                desc: 'Video takılıyor ya da bozuk görünüyorsa kapatmayı dene',
                value: s.hwdec,
                onChanged: (v) => s.update(hwdec: v),
              ),
              _SwitchRow(
                title: 'Kaldığım yerden devam et',
                desc: 'Film ve dizilerde son konumu hatırla',
                value: s.resume,
                onChanged: (v) => s.update(resume: v),
              ),
              _SwitchRow(
                title: 'Sonraki bölümü otomatik oynat',
                desc: 'Bölüm bitince 10 saniye sayar, sonra sıradaki bölüme geçer',
                value: s.autoNext,
                onChanged: (v) => s.update(autoNext: v),
              ),
              if (isIos)
                _SwitchRow(
                  key: const ValueKey('setting-autoPipOnLeave'),
                  title: 'Uygulamadan çıkınca yüzen oynatıcı (PiP)',
                  desc: 'Ana ekrana veya başka uygulamaya geçince izlediğin yayın yüzen pencerede devam eder',
                  value: s.autoPipOnLeave,
                  onChanged: (v) {
                    s.update(autoPipOnLeave: v);
                    SystemPip.instance.setAutoStart(v);
                  },
                ),
            ]),
            _Section(key: _keys[2], title: 'İçerik', children: [
              _SwitchRow(
                title: 'Yetişkin içeriği gizle',
                desc: 'Adı veya kategorisi "adult, xxx, 18+" içerenleri listelerden çıkarır',
                value: s.hideAdult,
                onChanged: (v) => s.update(hideAdult: v),
              ),
              _SwitchRow(
                title: 'Yinelenen filmleri/dizileri gizle',
                desc: '"Tümü" görünümünde aynı adı taşıyan kayıtlardan yalnızca biri gösterilir',
                value: s.dedupe,
                onChanged: (v) => s.update(dedupe: v),
              ),
              _ChoiceRow(
                title: 'Gizlenen kategoriler',
                desc: s.hiddenGroups.isEmpty ? 'Yok. Bir kategoriyi gizlemek için listenin üstündeki ayar ikonunu kullan.' : '${s.hiddenGroups.length} kategori gizli',
                narrow: portrait && s.hiddenGroups.isNotEmpty,
                control: s.hiddenGroups.isEmpty ? null : AppButton(label: 'Hepsini göster', onPressed: () => s.update(hiddenGroups: <String>{})),
              ),
            ]),
            _Section(key: _keys[3], title: 'Telefonu kumanda yap', children: [
              _SwitchRow(
                title: 'Telefonla kumanda et',
                desc: 'Telefonun tarayıcısından yön tuşları, oynat/duraklat, sarma ve yazı yazma. Yalnızca aynı Wi-Fi/ağda çalışır.',
                value: s.phoneRemote,
                onChanged: (v) {
                  s.update(phoneRemote: v);
                  PhoneRemote.instance.setEnabled(v);
                },
              ),
              if (s.phoneRemote) _PhoneRemoteInfo(remote: PhoneRemote.instance, stacked: portrait),
            ]),
            _Section(key: _keys[4], title: 'Görünüm', children: [
              _ChoiceRow(
                title: 'Arayüz ölçeği',
                narrow: narrow,
                control: _MenuChoice<double>(
                  key: const ValueKey('setting-uiScale'),
                  title: 'Arayüz ölçeği',
                  useSheet: phone,
                  value: s.uiScale,
                  options: isIos ? AppSettings.iosUiScaleOptions : AppSettings.fullUiScaleOptions,
                  onChanged: (v) => s.update(uiScale: v),
                ),
              ),
              if (!isIos)
                _SwitchRow(
                  title: 'Kumanda (TV) modu',
                  desc: 'Büyük yazı, belirgin odak çerçevesi ve kumanda ile gezinme. Android TV / Fire Stick\'te otomatik açık',
                  value: s.tvMode,
                  onChanged: (v) => s.update(tvMode: v),
                ),
            ]),
            if (showShortcuts)
              _Section(key: _keys[5], title: 'Kısayollar', children: const [
                _KeyRow('Boşluk', 'Oynat / duraklat'),
                _KeyRow('← / →', 'Geri / ileri sar'),
                _KeyRow('↑ / ↓', 'Ses aç / kıs'),
                _KeyRow('M', 'Sessiz'),
                _KeyRow('F', 'Tam ekran'),
                _KeyRow('Esc', 'Tam ekrandan çık / geri'),
              ]),
          ]),
        );

        if (portrait) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sections.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final on = i == _selected;
                    return GestureDetector(
                      onTap: () {
                        AppHaptics.selection(context);
                        _go(i);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on ? AppColors.accentSoft : AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: on ? AppColors.accent.withValues(alpha: 0.45) : AppColors.line),
                        ),
                        child: Text(
                          sections[i],
                          style: AppText.label(13, color: on ? AppColors.accentInk : AppColors.ink2),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: cards),
            ],
          );
        }

        return LayoutBuilder(builder: (context, box) {
          final showIndex = landscape ? box.maxWidth >= 520 : box.maxWidth >= 640;
          final sideW = landscape ? 176.0 : AppSizes.sideWidth;
          return Padding(
            padding: EdgeInsets.only(left: leftPad),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // The section index is only a shortcut: in a narrow area the cards get the room instead.
              if (showIndex) ...[
                Padding(
                  padding: EdgeInsets.only(top: AppSizes.scrollPad, bottom: landscape ? (pad.bottom > 0 ? pad.bottom : 10) : 16),
                  child: SizedBox(
                    width: sideW,
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(AppSizes.scrollPad),
                        itemExtent: 44,
                        itemCount: sections.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SideItem(label: sections[i], selected: i == _selected, onTap: () => _go(i), height: 40),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: cards),
            ]),
          );
        });
      },
    );
  }

  Widget _phoneAccountCard() {
    final exp = widget.info.expiry;
    final date = exp == null ? 'Bilinmiyor' : '${exp.day.toString().padLeft(2, '0')}.${exp.month.toString().padLeft(2, '0')}.${exp.year}';
    final host = Uri.tryParse(widget.account.host)?.host ?? widget.account.host;
    Widget statBox(String label, Widget value) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppSizes.itemRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12)),
              const SizedBox(height: 4),
              value,
            ],
          ),
        );
    return AppCard(
      radius: AppSizes.cardRadius,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            ChannelBadge(name: widget.account.name, size: 50),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(18)),
                Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: statBox('Abonelik bitişi', Text(date, style: AppText.title(14)))),
              const SizedBox(width: 10),
              Expanded(child: statBox('Bağlantılar', _ConnectionTile(client: widget.client, initial: widget.info, compact: true))),
            ],
          ),
          const SizedBox(height: 14),
          AppButton(label: 'Kullanıcı değiştir', icon: Icons.logout_rounded, width: double.infinity, onPressed: widget.onLogout),
        ],
      ),
    );
  }

  Widget _accountCard() {
    final exp = widget.info.expiry;
    final date = exp == null ? 'Bilinmiyor' : '${exp.day.toString().padLeft(2, '0')}.${exp.month.toString().padLeft(2, '0')}.${exp.year}';
    final host = Uri.tryParse(widget.account.host)?.host ?? widget.account.host;
    Widget fact(String label, Widget value) => Container(
          padding: const EdgeInsets.only(left: 16),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.line))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: AppText.meta(13)), value]),
        );
    return AppCard(
      radius: AppSizes.cardRadius,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Wrap(spacing: 18, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          ChannelBadge(name: widget.account.name, size: 52),
          const SizedBox(width: 14),
          Flexible(
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(17)),
              Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
            ]),
          ),
          ),
        ]),
        fact('Abonelik bitişi', Text(date, style: AppText.title(15))),
        fact('Eşzamanlı bağlantılar', _ConnectionTile(client: widget.client, initial: widget.info)),
        AppButton(label: 'Kullanıcı değiştir', icon: Icons.logout_rounded, onPressed: widget.onLogout),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: AppCard(
        radius: AppSizes.cardRadius,
        shadows: AppShadows.card,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 6), child: Text(title, style: AppText.title(18))),
          ...children,
        ]),
      ),
    );
  }
}

Widget _texts(String title, String? desc) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: AppText.title(15)),
      if (desc != null) ...[const SizedBox(height: 2), Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.meta(13))],
    ]);

/// A row with a switch: the whole row takes focus and toggles.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({super.key, required this.title, this.desc, required this.value, required this.onChanged});

  final String title;
  final String? desc;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        child: FocusRing(
          inside: true,
          radius: 18,
          onTap: () {
            AppHaptics.selection(context);
            onChanged(!value);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(child: _texts(title, desc)),
              const SizedBox(width: 16),
              AppSwitch(value: value, focusable: false, onChanged: onChanged),
            ]),
          ),
        ),
      );
}

/// A row with a choice control; the focus goes into the control, not the row.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.title, this.desc, required this.control, required this.narrow});

  final String title;
  final String? desc;
  final Widget? control;
  final bool narrow; // the control goes under the title

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        alignment: Alignment.centerLeft,
        child: narrow && control != null
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _texts(title, desc),
                const SizedBox(height: 10),
                SingleChildScrollView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, child: control),
              ])
            : Row(children: [
                Expanded(child: _texts(title, desc)),
                if (control != null) ...[const SizedBox(width: 16), control!],
              ]),
      );
}

/// A choice with many options: a key with the current value that opens a menu (or iOS bottom sheet on phone).
class _MenuChoice<T> extends StatelessWidget {
  const _MenuChoice({super.key, required this.value, required this.options, required this.onChanged, this.title = 'Seçim', this.useSheet = false});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final String title;
  final bool useSheet;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (context) => AppButton(
          label: options[value] ?? 'Özel',
          trailingIcon: Icons.expand_more_rounded,
          onPressed: () async {
            if (useSheet) {
              final picked = await showAppSheet<T>(
                context: context,
                title: title,
                builder: (ctx) => ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final e in options.entries)
                      SheetOptionTile(
                        label: e.value,
                        selected: e.key == value,
                        onTap: () => Navigator.of(ctx).pop(e.key),
                      ),
                  ],
                ),
              );
              if (picked != null) onChanged(picked);
              return;
            }
            final box = context.findRenderObject()! as RenderBox;
            final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
            final at = box.localToGlobal(Offset(0, box.size.height + 6), ancestor: overlay);
            final picked = await showMenu<T>(
              context: context,
              position: RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx - box.size.width, 0),
              items: [
                for (final e in options.entries)
                  PopupMenuItem(
                    value: e.key,
                    child: Row(children: [
                      SizedBox(width: 28, child: e.key == value ? const Icon(Icons.check_rounded, size: 18, color: AppColors.accent) : null),
                      Text(e.value),
                    ]),
                  ),
              ],
            );
            if (picked != null) onChanged(picked);
          },
        ),
      );
}

class _KeyRow extends StatelessWidget {
  const _KeyRow(this.keys, this.action);

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          SizedBox(width: 100, child: Align(alignment: Alignment.centerLeft, child: Pill(keys))),
          const SizedBox(width: 12),
          Expanded(child: Text(action, style: AppText.meta(14, color: AppColors.ink))),
        ]),
      );
}

/// "Active connections: 1/2" with a refresh button, so it is easy to see whether another device is streaming.
class _ConnectionTile extends StatefulWidget {
  const _ConnectionTile({required this.client, required this.initial, this.compact = false});

  final XtreamClient client;
  final AccountInfo initial;
  final bool compact;

  @override
  State<_ConnectionTile> createState() => _ConnectionTileState();
}

class _ConnectionTileState extends State<_ConnectionTile> {
  late AccountInfo _info = widget.initial;
  bool _busy = false;
  String? _error;

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final i = await widget.client.authenticate();
      if (mounted) setState(() => _info = i);
    } on XtreamException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    final text = i.maxConnections > 0 ? (widget.compact ? '${i.activeConnections} / ${i.maxConnections}' : '${i.activeConnections} / ${i.maxConnections} kullanımda') : 'Sınır bilinmiyor';
    final color = _error != null || i.limitReached ? AppColors.liveText : AppColors.ok;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(_error ?? text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.title(widget.compact ? 14 : 15, color: color))),
        const SizedBox(width: 6),
        _busy
            ? SizedBox(width: widget.compact ? 28 : 44, height: widget.compact ? 28 : 44, child: Padding(padding: EdgeInsets.all(widget.compact ? 6 : 12), child: const CircularProgressIndicator(strokeWidth: 2)))
            : AppButton(icon: Icons.refresh_rounded, height: widget.compact ? 30 : AppSizes.buttonHeight, dense: widget.compact, tooltip: 'Yenile', onPressed: _refresh),
      ]),
      if (i.limitReached && _error == null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text('Sınır dolu: başka bir cihazda izleme açık olabilir.', style: AppText.meta(12, color: AppColors.liveText)),
        ),
    ]);
  }
}

/// QR code + address of the phone remote page.
class _PhoneRemoteInfo extends StatelessWidget {
  const _PhoneRemoteInfo({required this.remote, this.stacked = false});

  final PhoneRemote remote;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final url = remote.url;
    if (url == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Text(remote.error ?? 'Başlatılıyor...', style: AppText.label(14, color: remote.error == null ? AppColors.ink2 : AppColors.liveText)),
      );
    }
    final qr = ClipRRect(
      borderRadius: BorderRadius.circular(AppSizes.itemRadius),
      child: Container(
        color: AppColors.qrGround,
        padding: const EdgeInsets.all(10),
        child: QrImageView(data: url.toString(), size: stacked ? 140 : 150, backgroundColor: AppColors.qrGround),
      ),
    );
    final info = Column(crossAxisAlignment: stacked ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
      Text('Telefonun kamerasıyla okut', textAlign: stacked ? TextAlign.center : TextAlign.start, style: AppText.title(15)),
      const SizedBox(height: 6),
      SelectableText(url.toString(), textAlign: stacked ? TextAlign.center : TextAlign.start, style: AppText.label(14, color: AppColors.accentInk)),
      const SizedBox(height: 6),
      Text('Bu adres uygulama her açıldığında değişir. Kumandayı açık bırakmak istemezsen anahtarı kapat.', textAlign: stacked ? TextAlign.center : TextAlign.start, style: AppText.meta(13)),
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: stacked
          ? Column(children: [qr, const SizedBox(height: 14), info])
          : Row(children: [qr, const SizedBox(width: 18), Expanded(child: info)]),
    );
  }
}
