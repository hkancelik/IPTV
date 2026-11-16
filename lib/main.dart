import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app_nav.dart';
import 'src/login_page.dart';
import 'src/phone_remote.dart';
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
  await AppSettings.instance.load();
  if (AppSettings.instance.phoneRemote) PhoneRemote.instance.setEnabled(true);
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
          // Light ground: dark status bar icons on Android.
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark,
            child: UiScale(scale: AppSettings.instance.uiScale, child: child!),
          ),
          home: const LoginPage(autoLogin: true),
        );
      },
    );
  }
}
