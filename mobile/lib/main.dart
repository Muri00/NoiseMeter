import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/l10n.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/measurement_service.dart';
import 'theme/app_theme.dart';
import 'widgets/ui.dart';

void main() {
  final api = ApiClient(AuthService.defaultServerUrl);
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: api),
        ChangeNotifierProvider(create: (_) => AppLanguage()..load()),
        ChangeNotifierProvider(create: (_) => AuthService(api)..init()),
        ChangeNotifierProvider(create: (_) => MeasurementService(api)),
      ],
      child: const NoiseMeterApp(),
    ),
  );
}

class NoiseMeterApp extends StatelessWidget {
  const NoiseMeterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final language = context.watch<AppLanguage>();
    final Widget home;
    if (!auth.initialized) {
      // Начален екран, докато се проверява запазеният вход.
      home = const Scaffold(backgroundColor: Colors.white, body: Center(child: AppLogo(size: 110, withName: true)));
    } else if (auth.isLoggedIn) {
      home = const HomeShell();
    } else {
      home = const LoginScreen();
    }

    // При смяна на езика цялото приложение се изгражда наново (ключът е езикът),
    // за да се преведат всички текстове. Текущото измерване продължава.
    return MaterialApp(
      key: ValueKey(language.code),
      title: 'METRAVA',
      debugShowCheckedModeBanner: false,
      // Език и на системните елементи (календар, бутони и др.).
      locale: Locale(language.code),
      supportedLocales: const [Locale('bg'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light(),
      // Android 15 рисува приложението и под системната лента долу (навигация / лента с приложения
      // на таблет). Без това отместване краят на всеки екран остава скрит под нея.
      builder: (context, child) => _TabletScale(
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(top: false, child: child!),
        ),
      ),
      home: home,
    );
  }
}

/// Таблетите с ниска плътност на екрана (напр. Teclast P30T, 10" при 160 dpi) показват всичко
/// в "телефонни" размери и интерфейсът изглежда дребен и разтегнат. На таблет целият интерфейс
/// (текст, икони, отстояния) се увеличава еднакво, така че съдържанието е с ширината на голям телефон.
class _TabletScale extends StatelessWidget {
  const _TabletScale({required this.child});

  final Widget child;

  /// Логическа ширина (по-късата страна), към която се мащабира таблетът.
  static const _targetShortestSide = 640.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final shortest = mq.size.shortestSide;
    if (shortest < 600) return child;
    final scale = (shortest / _targetShortestSide).clamp(1.0, 1.4);
    if (scale == 1.0) return child;
    final size = mq.size / scale;
    return MediaQuery(
      data: mq.copyWith(
        size: size,
        devicePixelRatio: mq.devicePixelRatio * scale,
        padding: mq.padding / scale,
        viewPadding: mq.viewPadding / scale,
        viewInsets: mq.viewInsets / scale,
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(width: size.width, height: size.height, child: child),
          ),
        ),
      ),
    );
  }
}
