import 'package:flutter/material.dart';

import 'accounts.dart';
import 'home_page.dart';
import 'library.dart';
import 'remote_entry.dart';
import 'settings.dart';
import 'tv_text_field.dart';
import 'ui/basics.dart';
import 'ui/controls.dart';
import 'ui/focus_ring.dart';
import 'ui/format.dart';
import 'ui/layout.dart';
import 'ui/shell.dart';
import 'ui/tokens.dart';
import 'xtream.dart';

typedef ClientFactory = XtreamClient Function(Account account);
typedef HomeBuilder = Widget Function(XtreamClient client, AccountInfo info, Account account);

XtreamClient _defaultClient(Account a) => XtreamClient(a);
Widget _defaultHome(XtreamClient c, AccountInfo i, Account a) => HomePage(client: c, info: i, account: a);

/// Start page. Saved accounts are shown as profile cards; with [autoLogin] the account used last is
/// signed in right away (the user can cancel). Returning from the app (switch user) never auto-logs in again.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.autoLogin = false, this.clientFactory = _defaultClient, this.homeBuilder = _defaultHome});

  final bool autoLogin;
  final ClientFactory clientFactory;
  final HomeBuilder homeBuilder;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _showPass = false;
  bool _busy = false;
  String? _error;
  List<Account> _accounts = [];
  String? _lastKey;
  bool _loaded = false; // wait for saved accounts so the right item gets the initial focus
  bool _showForm = false;
  bool _editing = false; // profile edit mode (tap a card to delete it)
  Account? _auto; // account being signed in automatically (shows the splash)
  String? _confirming; // account whose deletion is being confirmed

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final accounts = await AccountStore.load();
    final last = await AccountStore.loadLast();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _lastKey = last;
      _loaded = true;
      _showForm = accounts.isEmpty;
    });
    if (widget.autoLogin && last != null) {
      final acc = accounts.where((a) => a.key == last).firstOrNull;
      if (acc != null) {
        setState(() => _auto = acc);
        _signIn(acc, auto: true);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// Saved accounts, the one used last first.
  List<Account> get _ordered {
    final list = [..._accounts];
    list.sort((a, b) => (b.key == _lastKey ? 1 : 0) - (a.key == _lastKey ? 1 : 0));
    return list;
  }

  Future<void> _signIn(Account acc, {bool save = false, bool auto = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = widget.clientFactory(acc);
      final info = await client.authenticate();
      if (auto && _auto == null) return; // cancelled while connecting
      if (save) {
        _accounts = [..._accounts.where((a) => a.key != acc.key), acc];
        await AccountStore.save(_accounts);
      }
      _lastKey = acc.key;
      await AccountStore.saveLast(acc.key);
      await Library.instance.use(acc); // favorites and history are per account
      if (!mounted) return;
      await Navigator.of(context).push(appRoute(context, (_) => widget.homeBuilder(client, info, acc)));
    } on XtreamException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _auto = null; // back on the profile page (failed, cancelled or signed out)
        });
      }
    }
  }

  void _cancelAuto() => setState(() => _auto = null);

  Future<void> _confirmDelete(Account a) async {
    // The cards' "Sil" tags step aside while the dialog asks, so the dialog's key is the only "Sil".
    setState(() => _confirming = a.key);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kullanıcı silinsin mi?'),
        content: Text('"${a.name}" kayıtlı kullanıcılardan kaldırılacak. Tekrar girmek için bilgilerini yeniden yazman gerekir.'),
        actions: [
          AppButton(label: 'İptal', autofocus: true, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'Sil', variant: AppButtonVariant.danger, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (mounted) setState(() => _confirming = null);
    if (ok != true || !mounted) return;
    setState(() {
      _accounts = _accounts.where((x) => x.key != a.key).toList();
      if (_accounts.isEmpty) {
        _editing = false;
        _showForm = true;
      }
    });
    await AccountStore.save(_accounts);
  }

  Future<void> _fromPhone() async {
    final data = await showDialog<Map<String, String>>(context: context, builder: (_) => const RemoteEntryDialog());
    if (data == null || !mounted) return;
    final host = (data['host'] ?? '').trim();
    final user = (data['username'] ?? '').trim();
    final pass = data['password'] ?? '';
    if (host.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Telefondan gelen bilgiler eksik');
      return;
    }
    final name = (data['name'] ?? '').trim();
    _signIn(Account(name: name.isEmpty ? user : name, host: Account.normalizeHost(host), username: user, password: pass), save: true);
  }

  void _add() {
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Sunucu, kullanıcı adı ve parola gerekli');
      return;
    }
    final acc = Account(
      name: _name.text.trim().isEmpty ? _user.text.trim() : _name.text.trim(),
      host: Account.normalizeHost(_host.text),
      username: _user.text.trim(),
      password: _pass.text,
    );
    _signIn(acc, save: true);
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold();
    final mode = layoutModeOf(context);
    if (mode != AppLayoutMode.desktop) return _buildPhone(context, mode == AppLayoutMode.phoneLandscape);
    return Scaffold(
      body: Stack(children: [
        Center(
          child: _auto != null
              ? _splash(_auto!)
              : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 90, 20, 30), child: _showForm ? _form() : _profiles()),
        ),
        const Positioned(left: 28, top: 26, child: BrandMark()),
        const Positioned(right: 28, top: 26, child: ClockPill()),
      ]),
    );
  }

  Widget _buildPhone(BuildContext context, bool landscape) {
    return Scaffold(
      body: SafeArea(
        child: _auto != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _splash(_auto!),
                ),
              )
            : landscape
                ? (_showForm ? _phoneLandscapeForm() : _phoneLandscapeProfiles())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Align(alignment: Alignment.centerLeft, child: BrandMark()),
                      ),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                            child: _showForm ? _phonePortraitForm() : _phonePortraitProfiles(),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _phonePortraitProfiles() {
    final ordered = _ordered;
    return LayoutBuilder(builder: (context, c) {
      final cardW = ((c.maxWidth - 14) / 2).clamp(142.0, 200.0);
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_editing ? 'Silinecek kullanıcıyı seç' : 'Kullanıcı seç', textAlign: TextAlign.center, style: AppText.display(30)),
        const SizedBox(height: 6),
        Text('Açılışta son kullanılan hesapla otomatik giriş yapılır.', textAlign: TextAlign.center, style: AppText.meta(14)),
        const SizedBox(height: 24),
        Wrap(spacing: 14, runSpacing: 14, alignment: WrapAlignment.center, children: [
          for (var i = 0; i < ordered.length; i++)
            _ProfileCard(
              account: ordered[i],
              isLast: ordered[i].key == _lastKey,
              editing: _editing && _confirming == null,
              compact: true,
              width: cardW,
              onTap: _busy ? null : () => _editing ? _confirmDelete(ordered[i]) : _signIn(ordered[i]),
            ),
          if (!_editing)
            _AddCard(
              compact: true,
              width: cardW,
              onTap: () => setState(() {
                _showForm = true;
                _error = null;
              }),
            ),
        ]),
        const SizedBox(height: 24),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, textAlign: TextAlign.center, style: AppText.label(14, color: AppColors.liveText))),
        if (_busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
        AppButton(
          variant: AppButtonVariant.onPage,
          icon: _editing ? Icons.check_rounded : Icons.edit_rounded,
          label: _editing ? 'Bitti' : 'Kullanıcıları düzenle',
          onPressed: () => setState(() => _editing = !_editing),
        ),
      ]);
    });
  }

  Widget _phoneLandscapeProfiles() {
    final ordered = _ordered;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 210,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandMark(),
                  const SizedBox(height: 14),
                  Text(_editing ? 'Silinecek kullanıcı' : 'Kullanıcı seç', style: AppText.display(25)),
                  const SizedBox(height: 6),
                  Text('Son kullanılan hesapla otomatik giriş yapılır.', style: AppText.meta(13)),
                  const SizedBox(height: 14),
                  if (_error != null)
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: AppText.label(13, color: AppColors.liveText))),
                  if (_busy) const Padding(padding: EdgeInsets.only(bottom: 10), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))),
                  AppButton(
                    variant: AppButtonVariant.onPage,
                    dense: true,
                    icon: _editing ? Icons.check_rounded : Icons.edit_rounded,
                    label: _editing ? 'Bitti' : 'Kullanıcıları düzenle',
                    onPressed: () => setState(() => _editing = !_editing),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: 232,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                children: [
                  for (var i = 0; i < ordered.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    _ProfileCard(
                      account: ordered[i],
                      isLast: ordered[i].key == _lastKey,
                      editing: _editing && _confirming == null,
                      compact: true,
                      width: 152,
                      onTap: _busy ? null : () => _editing ? _confirmDelete(ordered[i]) : _signIn(ordered[i]),
                    ),
                  ],
                  if (!_editing) ...[
                    if (ordered.isNotEmpty) const SizedBox(width: 12),
                    _AddCard(
                      compact: true,
                      width: 152,
                      onTap: () => setState(() {
                        _showForm = true;
                        _error = null;
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phonePortraitForm() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_accounts.isEmpty ? 'Giriş bilgilerinizi girin' : 'Yeni kullanıcı ekle', style: AppText.display(22)),
          const SizedBox(height: 4),
          Text('Xtream Codes sunucu bilgilerini gir.', style: AppText.meta(13)),
          const SizedBox(height: 16),
          RemoteTextField(controller: _name, textInputAction: TextInputAction.next, decoration: _field('Ad (isteğe bağlı)')),
          const SizedBox(height: 10),
          RemoteTextField(
            controller: _host,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: _field('Sunucu (http://example.com:8080)'),
          ),
          const SizedBox(height: 10),
          RemoteTextField(
            controller: _user,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: _field('Kullanıcı adı'),
          ),
          const SizedBox(height: 10),
          RemoteTextField(
            controller: _pass,
            obscureText: !_showPass,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _add(),
            decoration: _field(
              'Parola',
              suffix: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: AppButton(
                  icon: _showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  tooltip: _showPass ? 'Parolayı gizle' : 'Parolayı göster',
                  variant: AppButtonVariant.onPage,
                  height: 38,
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: AppText.label(14, color: AppColors.liveText))),
          AppButton(
            variant: AppButtonVariant.primary,
            height: AppSizes.primaryHeight,
            onPressed: _busy ? null : _add,
            label: _busy ? null : 'Kullanıcı Ekle',
            child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent)) : null,
          ),
          const SizedBox(height: 10),
          AppButton(
            onPressed: _busy ? null : _fromPhone,
            icon: Icons.qr_code_2_rounded,
            label: 'Telefondan gir (QR)',
          ),
        ]),
      ),
      if (_accounts.isNotEmpty) ...[
        const SizedBox(height: 16),
        Center(
          child: AppButton(
            variant: AppButtonVariant.onPage,
            icon: Icons.arrow_back_rounded,
            label: 'Kayıtlı kullanıcılara dön',
            onPressed: () => setState(() {
              _showForm = false;
              _error = null;
            }),
          ),
        ),
      ],
    ]);
  }

  Widget _phoneLandscapeForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: AppCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 196,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandMark(),
                      const SizedBox(height: 14),
                      Text(_accounts.isEmpty ? 'Giriş bilgilerinizi girin' : 'Yeni kullanıcı ekle', style: AppText.title(18)),
                      const SizedBox(height: 6),
                      Text('Xtream Codes hesabını ekle.', style: AppText.meta(13)),
                      const SizedBox(height: 14),
                      AppButton(
                        dense: true,
                        onPressed: _busy ? null : _fromPhone,
                        icon: Icons.qr_code_2_rounded,
                        label: 'QR ile gir',
                      ),
                      if (_accounts.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        AppButton(
                          dense: true,
                          variant: AppButtonVariant.onPage,
                          icon: Icons.arrow_back_rounded,
                          label: 'Profillere dön',
                          onPressed: () => setState(() {
                            _showForm = false;
                            _error = null;
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: RemoteTextField(controller: _name, textInputAction: TextInputAction.next, decoration: _field('Ad (isteğe bağlı)'))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RemoteTextField(
                            controller: _host,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.next,
                            decoration: _field('Sunucu'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: RemoteTextField(
                            controller: _user,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.next,
                            decoration: _field('Kullanıcı adı'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RemoteTextField(
                            controller: _pass,
                            obscureText: !_showPass,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _busy ? null : _add(),
                            decoration: _field(
                              'Parola',
                              suffix: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: AppButton(
                                  icon: _showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                  tooltip: _showPass ? 'Parolayı gizle' : 'Parolayı göster',
                                  variant: AppButtonVariant.onPage,
                                  height: 36,
                                  onPressed: () => setState(() => _showPass = !_showPass),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: AppText.label(13, color: AppColors.liveText))),
                      const SizedBox(height: 12),
                      AppButton(
                        variant: AppButtonVariant.primary,
                        height: 44,
                        onPressed: _busy ? null : _add,
                        label: _busy ? null : 'Kullanıcı Ekle',
                        child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent)) : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _splash(Account a) => AppCard(
        padding: EdgeInsets.all(isPhoneLayout(context) ? 24 : 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BrandMark(),
            const SizedBox(height: 24),
            Text('${a.name} olarak giriş yapılıyor...', textAlign: TextAlign.center, style: AppText.title(16)),
            const SizedBox(height: 18),
            SizedBox(width: 220, child: ClipRRect(borderRadius: BorderRadius.circular(3), child: const LinearProgressIndicator(minHeight: 6))),
            const SizedBox(height: 24),
            AppButton(label: 'Vazgeç / kullanıcı değiştir', autofocus: AppSettings.instance.tvMode, onPressed: _cancelAuto),
          ]),
        ),
      );

  Widget _profiles() {
    final ordered = _ordered;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 980),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_editing ? 'Silinecek kullanıcıyı seç' : 'Kullanıcı seç', textAlign: TextAlign.center, style: AppText.display(40)),
        const SizedBox(height: 10),
        Text('Açılışta son kullanılan hesapla otomatik giriş yapılır.', textAlign: TextAlign.center, style: AppText.meta(16)),
        const SizedBox(height: 34),
        Wrap(spacing: 22, runSpacing: 22, alignment: WrapAlignment.center, children: [
          for (var i = 0; i < ordered.length; i++)
            _ProfileCard(
              account: ordered[i],
              isLast: ordered[i].key == _lastKey,
              editing: _editing && _confirming == null,
              autofocus: AppSettings.instance.tvMode && i == 0,
              onTap: _busy ? null : () => _editing ? _confirmDelete(ordered[i]) : _signIn(ordered[i]),
            ),
          if (!_editing)
            _AddCard(
              onTap: () => setState(() {
                _showForm = true;
                _error = null;
              }),
            ),
        ]),
        const SizedBox(height: 28),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(_error!, textAlign: TextAlign.center, style: AppText.label(15, color: AppColors.liveText))),
        if (_busy) const Padding(padding: EdgeInsets.only(bottom: 14), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
        AppButton(
          variant: AppButtonVariant.onPage,
          icon: _editing ? Icons.check_rounded : Icons.edit_rounded,
          label: _editing ? 'Bitti' : 'Kullanıcıları düzenle',
          onPressed: () => setState(() => _editing = !_editing),
        ),
      ]),
    );
  }

  InputDecoration _field(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        labelStyle: AppText.meta(15),
        floatingLabelStyle: AppText.label(13, color: AppColors.ink2),
        filled: true,
        fillColor: AppColors.surfaceAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.ink, width: AppSizes.ring)),
        suffixIcon: suffix,
      );

  Widget _form() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppCard(
        padding: const EdgeInsets.all(28),
        child: SizedBox(
          width: 364,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Center(child: BrandMark()),
            const SizedBox(height: 18),
            Text(_accounts.isEmpty ? 'Giriş bilgilerinizi girin' : 'Yeni kullanıcı ekle', textAlign: TextAlign.center, style: AppText.title(20)),
            const SizedBox(height: 16),
            // Typing with a TV remote is painful: offer entering the login on a phone first.
            AppButton(
              autofocus: AppSettings.instance.tvMode,
              onPressed: _busy ? null : _fromPhone,
              icon: Icons.qr_code_2_rounded,
              label: 'Telefondan gir (QR)',
            ),
            Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('veya elle girin', textAlign: TextAlign.center, style: AppText.meta(13))),
            RemoteTextField(controller: _name, decoration: _field('Ad (isteğe bağlı)')),
            const SizedBox(height: 10),
            RemoteTextField(controller: _host, decoration: _field('Sunucu (http://example.com:8080)')),
            const SizedBox(height: 10),
            RemoteTextField(controller: _user, decoration: _field('Kullanıcı adı')),
            const SizedBox(height: 10),
            RemoteTextField(
              controller: _pass,
              obscureText: !_showPass,
              onSubmitted: (_) => _busy ? null : _add(),
              decoration: _field(
                'Parola',
                suffix: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: AppButton(
                    icon: _showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    tooltip: _showPass ? 'Parolayı gizle' : 'Parolayı göster',
                    variant: AppButtonVariant.onPage,
                    height: 40,
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: AppText.label(14, color: AppColors.liveText))),
            if (AppSettings.instance.tvMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Bir alana OK ile girip yazın; yukarı/aşağı ile alanlar arasında gezin.', textAlign: TextAlign.center, style: AppText.meta(12)),
              ),
            AppButton(
              variant: AppButtonVariant.primary,
              height: AppSizes.primaryHeight,
              onPressed: _busy ? null : _add,
              label: _busy ? null : 'Kullanıcı Ekle',
              child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent)) : null,
            ),
          ]),
        ),
      ),
      if (_accounts.isNotEmpty) ...[
        const SizedBox(height: 20),
        AppButton(
          variant: AppButtonVariant.onPage,
          icon: Icons.arrow_back_rounded,
          label: 'Kayıtlı kullanıcılara dön',
          onPressed: () => setState(() {
            _showForm = false;
            _error = null;
          }),
        ),
      ],
    ]);
  }
}

/// A saved account as a large, focusable card (profile-picker style).
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.account, required this.isLast, required this.editing, required this.onTap, this.autofocus = false, this.compact = false, this.width = 210});

  final Account account;
  final bool isLast;
  final bool editing;
  final bool autofocus;
  final bool compact;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final initial = a.name.trim().isEmpty ? '?' : a.name.trim().characters.first.toUpperCase();
    final host = Uri.tryParse(a.host)?.host ?? a.host;
    final (bg, fg) = tintFor(a.key);
    final avatar = compact ? 64.0 : 96.0;
    return FocusRing(
      radius: compact ? AppSizes.cardRadius : AppSizes.panelRadius,
      autofocus: autofocus,
      onTap: onTap,
      enabled: onTap != null,
      child: AppCard(
        radius: compact ? AppSizes.cardRadius : AppSizes.panelRadius,
        child: SizedBox(
          width: width,
          child: Stack(alignment: Alignment.topCenter, children: [
            Padding(
              padding: compact ? const EdgeInsets.fromLTRB(12, 18, 12, 16) : const EdgeInsets.fromLTRB(16, 26, 16, 22),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: avatar,
                  height: avatar,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Text(initial, style: AppText.display(compact ? 28 : 40, color: fg)),
                ),
                SizedBox(height: compact ? 10 : 14),
                Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(compact ? 16 : 18)),
                const SizedBox(height: 2),
                Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(compact ? 12 : 13)),
                SizedBox(height: compact ? 8 : 12),
                SizedBox(height: 26, child: isLast && !editing ? const Pill('Son kullanılan', tone: PillTone.accent, height: 26) : null),
              ]),
            ),
            if (editing) Positioned(right: compact ? 10 : 14, top: compact ? 10 : 14, child: const Pill('Sil', tone: PillTone.live, height: 26, icon: Icons.delete_outline_rounded)),
          ]),
        ),
      ),
    );
  }
}

/// "Kullanıcı ekle" card with a dashed outline.
class _AddCard extends StatelessWidget {
  const _AddCard({required this.onTap, this.compact = false, this.width = 210});

  final VoidCallback onTap;
  final bool compact;
  final double width;

  @override
  Widget build(BuildContext context) {
    final avatar = compact ? 64.0 : 96.0;
    return FocusRing(
      radius: compact ? AppSizes.cardRadius : AppSizes.panelRadius,
      lift: false,
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorder(radius: compact ? AppSizes.cardRadius : AppSizes.panelRadius),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: compact ? const EdgeInsets.fromLTRB(12, 18, 12, 16) : const EdgeInsets.fromLTRB(16, 26, 16, 22),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: avatar,
                height: avatar,
                decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, boxShadow: AppShadows.chip),
                child: Icon(Icons.add_rounded, size: compact ? 30 : 40, color: AppColors.accent),
              ),
              SizedBox(height: compact ? 10 : 14),
              Text('Kullanıcı ekle', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(compact ? 16 : 18)),
              const SizedBox(height: 2),
              Text('Telefondan QR ya da elle', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(compact ? 12 : 13)),
              SizedBox(height: compact ? 34 : 40),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({this.radius = AppSizes.panelRadius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(1), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.dashed;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (double d = 0; d < metric.length; d += 14) {
        canvas.drawPath(metric.extractPath(d, d + 8), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.radius != radius;
}
