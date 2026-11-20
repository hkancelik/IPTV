import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'lan_sync.dart';
import 'tv_text_field.dart';
import 'ui/basics.dart';
import 'ui/focus_ring.dart';
import 'ui/layout.dart';
import 'ui/tokens.dart';
import 'xtream.dart';

/// Opens the cloud-free local-network sync flow (Dialog on desktop/TV, full route on phone).
Future<void> showLanSyncSheet(
  BuildContext context, {
  required Account account,
  bool? startNetworkServices,
}) {
  final phone = isPhoneLayout(context);
  if (phone) {
    return Navigator.of(context).push(
      appRoute(
        context,
        (_) => _LanSyncScaffold(account: account, startNetworkServices: startNetworkServices),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.ground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.panelRadius)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: _LanSyncBody(
          account: account,
          isDialog: true,
          startNetworkServices: startNetworkServices,
        ),
      ),
    ),
  );
}

class _LanSyncScaffold extends StatelessWidget {
  const _LanSyncScaffold({required this.account, this.startNetworkServices});

  final Account account;
  final bool? startNetworkServices;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.ground,
        body: SafeArea(
          child: _LanSyncBody(
            account: account,
            isDialog: false,
            startNetworkServices: startNetworkServices,
          ),
        ),
      );
}

class _LanSyncBody extends StatefulWidget {
  const _LanSyncBody({
    required this.account,
    required this.isDialog,
    this.startNetworkServices,
  });

  final Account account;
  final bool isDialog;
  final bool? startNetworkServices;

  @override
  State<_LanSyncBody> createState() => _LanSyncBodyState();
}

class _LanSyncBodyState extends State<_LanSyncBody> {
  int _mode = 0; // 0 = host (share), 1 = connect
  LanSyncServer? _server;
  LanSyncDiscovery? _discovery;

  Uri? _shareUrl;
  String? _hostError;
  SyncMergeResult? _lastHostSync;

  final _addressCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _syncing = false;
  String? _connectError;
  SyncMergeResult? _lastConnectSync;
  String? _backupNotice;
  bool _backupIsError = false;

  bool get _shouldStartNetwork =>
      widget.startNetworkServices ?? (!kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST'));

  @override
  void initState() {
    super.initState();
    if (_shouldStartNetwork) {
      _startHostAndDiscovery();
    }
  }

  Future<void> _startHostAndDiscovery() async {
    final server = LanSyncServer(
      account: widget.account,
      onPeerSynced: (res) {
        if (mounted) setState(() => _lastHostSync = res);
      },
    );
    _server = server;
    try {
      final url = await server.start();
      if (!mounted) return;
      if (url == null) {
        setState(() => _hostError = 'Yerel ağ adresi bulunamadı. Wi-Fi veya Ethernet bağlı mı?');
      } else {
        setState(() => _shareUrl = url);
      }
    } catch (e) {
      if (mounted) setState(() => _hostError = 'Eşitleme sunucusu başlatılamadı: $e');
    }

    if (!mounted) return;
    final discovery = LanSyncDiscovery(
      account: widget.account,
      ignoreHost: server.advertisedHost,
      ignorePort: server.port,
    );
    _discovery = discovery;
    discovery.addListener(_onPeersUpdated);
    await discovery.start();
  }

  void _onPeersUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _discovery?.removeListener(_onPeersUpdated);
    _discovery?.dispose();
    _server?.stop();
    _addressCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _runConnectSync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _connectError = null;
      _lastConnectSync = null;
    });
    try {
      final target = LanSyncClient.parseTarget(_addressCtrl.text, pin: _pinCtrl.text);
      final result = await LanSyncClient.syncWith(account: widget.account, target: target);
      if (!mounted) return;
      setState(() => _lastConnectSync = result);
    } on LanSyncException catch (e) {
      if (mounted) setState(() => _connectError = e.message);
    } catch (e) {
      if (mounted) setState(() => _connectError = 'Eşitleme başarısız: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _copyBackupJson() async {
    try {
      final snap = await SyncSnapshot.capture(widget.account);
      await Clipboard.setData(ClipboardData(text: snap.toJsonString()));
      if (!mounted) return;
      setState(() {
        _backupIsError = false;
        _backupNotice = 'Parolasız yedek panoya kopyalandı. Diğer cihazda "Yedekten birleştir" diyebilirsin.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backupIsError = true;
        _backupNotice = 'Yedek kopyalanamadı: $e';
      });
    }
  }

  Future<void> _pasteBackupJson() async {
    String? raw;
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      raw = clip?.text?.trim();
    } catch (_) {}

    if (raw == null || !raw.startsWith('{')) {
      if (!mounted) return;
      raw = await _promptPasteJsonDialog();
      if (raw == null || raw.trim().isEmpty) return;
    }

    try {
      final snap = SyncSnapshot.fromJsonString(raw);
      final res = await SyncSnapshot.applyAndMerge(widget.account, snap);
      if (!mounted) return;
      setState(() {
        _backupIsError = false;
        _backupNotice = 'Yedek birleştirildi (${res.peerDeviceName}): ${res.summaryText}';
      });
    } on LanSyncException catch (e) {
      if (!mounted) return;
      setState(() {
        _backupIsError = true;
        _backupNotice = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backupIsError = true;
        _backupNotice = 'Yedek okunamadı: $e';
      });
    }
  }

  Future<String?> _promptPasteJsonDialog() async {
    final ctrl = TextEditingController();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('JSON yedeği yapıştır'),
        content: SizedBox(
          width: 420,
          child: RemoteTextField(
            controller: ctrl,
            decoration: InputDecoration(
              hintText: '{"v":1,...}',
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        actions: [
          AppButton(label: 'İptal', onPressed: () => Navigator.pop(ctx)),
          AppButton(label: 'Birleştir', variant: AppButtonVariant.primary, onPressed: () => Navigator.pop(ctx, ctrl.text)),
        ],
      ),
    );
    ctrl.dispose();
    return picked;
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.isDialog ? 22.0 : 16.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 10),
          child: Row(
            children: [
              if (!widget.isDialog) ...[
                AppButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Geri',
                  variant: AppButtonVariant.onPage,
                  height: 40,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Yerel Ağ Eşitleme', style: AppText.title(20)),
                    Text(
                      'PC · iPhone · TV arasında bulutsuz, parolasız eşitleme',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.meta(12.5),
                    ),
                  ],
                ),
              ),
              if (widget.isDialog)
                AppButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Kapat',
                  height: 36,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Row(
            children: [
              Expanded(
                child: _modeTab(
                  key: const ValueKey('lan-sync-tab-host'),
                  icon: Icons.wifi_tethering_rounded,
                  label: 'Bu cihazı aç',
                  selected: _mode == 0,
                  onTap: () => setState(() => _mode = 0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _modeTab(
                  key: const ValueKey('lan-sync-tab-connect'),
                  icon: Icons.sync_rounded,
                  label: 'Cihaza bağlan',
                  selected: _mode == 1,
                  onTap: () => setState(() => _mode = 1),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_mode == 0) _hostPane() else _connectPane(),
                const SizedBox(height: 16),
                _offlineBackupCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeTab({
    required Key key,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      FocusRing(
        key: key,
        radius: 14,
        lift: false,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.accent.withValues(alpha: 0.45) : AppColors.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: selected ? AppColors.accentInk : AppColors.ink2),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: selected ? AppText.title(13.5, color: AppColors.accentInk) : AppText.label(13.5, color: AppColors.ink2),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _hostPane() {
    final pin = _server != null ? formatSyncPin(_server!.pin) : '— — —';
    final hostAddr = _server?.advertisedHost != null && _server?.port != null
        ? '${_server!.advertisedHost}:${_server!.port}'
        : null;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Diğer cihazda Ayarlar → Eşitleme → Cihaza bağlan bölümünden bu cihazı seç ve aşağıdaki kodu gir (veya QR\'ı okut):',
            style: AppText.meta(13.5),
          ),
          const SizedBox(height: 14),
          if (_hostError != null)
            Text(_hostError!, style: AppText.label(14, color: AppColors.liveText))
          else if (_shareUrl == null && _shouldStartNetwork)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  Text('EŞİTLEME KODU', style: AppText.meta(11)),
                  const SizedBox(height: 4),
                  SelectableText(
                    pin,
                    key: const ValueKey('lan-sync-host-pin'),
                    style: AppText.display(30).copyWith(
                      letterSpacing: 4,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (hostAddr != null) ...[
                    const SizedBox(height: 4),
                    SelectableText(hostAddr, style: AppText.meta(13)),
                  ],
                ],
              ),
            ),
            if (_shareUrl != null) ...[
              const SizedBox(height: 14),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSizes.itemRadius),
                  child: Container(
                    color: AppColors.qrGround,
                    padding: const EdgeInsets.all(10),
                    child: QrImageView(
                      data: _shareUrl.toString(),
                      size: 156,
                      backgroundColor: AppColors.qrGround,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: AppButton(
                  icon: Icons.copy_rounded,
                  label: 'Eşitleme bağlantısını kopyala',
                  dense: true,
                  height: 36,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _shareUrl.toString()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Eşitleme bağlantısı kopyalandı')),
                    );
                  },
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          if (_lastHostSync != null)
            Pill(
              '✓ ${_lastHostSync!.peerDeviceName} ile eşitlendi · ${_lastHostSync!.summaryText}',
              tone: PillTone.accent,
            )
          else
            const Pill(
              'Aynı Wi-Fi\'deki diğer cihaz bekleniyor...',
              tone: PillTone.neutral,
              icon: Icons.wifi_rounded,
            ),
        ],
      ),
    );
  }

  Widget _connectPane() {
    final peers = _discovery?.peers ?? const <LanSyncPeer>[];
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (peers.isNotEmpty) ...[
            Text('Aynı Wi-Fi\'de bulunan cihazlar', style: AppText.title(14.5)),
            const SizedBox(height: 8),
            for (final peer in peers) ...[
              FocusRing(
                radius: 12,
                lift: false,
                onTap: () {
                  _addressCtrl.text = peer.addressLabel;
                  setState(() => _connectError = null);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.devices_rounded, size: 18, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(14)),
                            Text(peer.addressLabel, style: AppText.meta(12)),
                          ],
                        ),
                      ),
                      Text('Seç', style: AppText.label(13, color: AppColors.accentInk)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Diğer cihazda "Bu cihazı aç" ekranını aç. Otomatik görünmezse IP:port veya kopyaladığın bağlantıyı aşağıya gir.',
                style: AppText.meta(13),
              ),
            ),
          Text('Cihaz adresi veya bağlantı', style: AppText.label(13)),
          const SizedBox(height: 6),
          RemoteTextField(
            key: const ValueKey('lan-sync-address'),
            controller: _addressCtrl,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: '192.168.1.15:51234 veya http://.../s/...',
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Text('6 haneli eşitleme kodu', style: AppText.label(13)),
          const SizedBox(height: 6),
          RemoteTextField(
            key: const ValueKey('lan-sync-pin'),
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _runConnectSync(),
            decoration: InputDecoration(
              hintText: '482 915 (bağlantı yapıştırdıysan boş bırak)',
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),
          AppButton(
            key: const ValueKey('lan-sync-submit'),
            variant: AppButtonVariant.primary,
            icon: _syncing ? null : Icons.sync_rounded,
            label: _syncing ? 'Eşitleniyor...' : 'İki yönlü eşitle',
            onPressed: _syncing ? null : _runConnectSync,
          ),
          if (_connectError != null) ...[
            const SizedBox(height: 10),
            Text(_connectError!, style: AppText.label(13.5, color: AppColors.liveText)),
          ],
          if (_lastConnectSync != null) ...[
            const SizedBox(height: 10),
            Pill(
              '✓ ${_lastConnectSync!.peerDeviceName} ile eşitlendi · ${_lastConnectSync!.summaryText}',
              tone: PillTone.accent,
            ),
          ],
        ],
      ),
    );
  }

  Widget _offlineBackupCard() => AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Çevrimdışı JSON yedek (pano)', style: AppText.title(14.5)),
            const SizedBox(height: 4),
            Text(
              'Favoriler, izleme geçmişi, ses/altyazı seçimleri ve kategori düzenini parolasız olarak kopyala veya başka cihazdan yapıştırıp birleştir.',
              style: AppText.meta(12.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  key: const ValueKey('lan-sync-copy-json'),
                  icon: Icons.copy_all_rounded,
                  label: 'Yedeği kopyala',
                  dense: true,
                  height: 36,
                  onPressed: _copyBackupJson,
                ),
                AppButton(
                  key: const ValueKey('lan-sync-paste-json'),
                  icon: Icons.content_paste_go_rounded,
                  label: 'Yedekten birleştir',
                  dense: true,
                  height: 36,
                  onPressed: _pasteBackupJson,
                ),
              ],
            ),
            if (_backupNotice != null) ...[
              const SizedBox(height: 10),
              Text(
                _backupNotice!,
                style: AppText.label(13, color: _backupIsError ? AppColors.liveText : AppColors.accentInk),
              ),
            ],
          ],
        ),
      );
}
