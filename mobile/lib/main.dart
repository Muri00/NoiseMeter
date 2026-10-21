import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

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
    final Widget home;
    if (!auth.initialized) {
      // Начален екран, докато се проверява запазеният вход.
      home = const Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.heroGradient),
          child: Center(child: AppLogo(size: 88)),
        ),
      );
    } else if (auth.isLoggedIn) {
      home = const HomeShell();
    } else {
      home = const LoginScreen();
    }

    return MaterialApp(
      title: 'Шумомер',
      debugShowCheckedModeBanner: false,
      // Български език за системните елементи (календар, бутони и др.).
      locale: const Locale('bg'),
      supportedLocales: const [Locale('bg'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: home,
    );
  }
}
