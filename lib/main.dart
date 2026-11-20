import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app_nav.dart';
import 'src/login_page.dart';
import 'src/phone_remote.dart';
import 'src/player_page.dart';
import 'src/ui_scale.dart';
import 'src/settings.dart';
import 'src/ui/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isAndroid) {
    // low-RAM TV sticks: keep decoded images small
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 32 << 20
      ..maximumSize = 120;
  }
  if (Platform.isIOS) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  await AppSettings.instance.load();
  if (AppSettings.instance.phoneRemote) PhoneRemote.instance.setEnabled(true);
  PlayerSession.instance.onRequestExpandFromPip = () {
    final nav = appNavigatorKey.currentState;
    if (nav != null && PlayerSession.instance.active && PlayerSession.instance.minimized) {
      nav.push(expandMiniPlayerRoute());
    }
  };
  runApp(const IptvApp());
}

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'IPTV',
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          // Dark "Kömür" ground: white status bar icons on iOS & Android OLED displays.
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarBrightness: Brightness.dark, // iOS: dark background -> white text/icons
              statusBarIconBrightness: Brightness.light, // Android: light icons
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.light,
            ),
            child: UiScale(scale: AppSettings.instance.uiScale, child: child!),
          ),
          home: const LoginPage(autoLogin: true),
        );
      },
    );
  }
}
