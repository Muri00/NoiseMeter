import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/measurement_service.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'calibration_screen.dart';
import 'certificates_screen.dart';
import 'devices_screen.dart';
import 'history_screen.dart';
import 'indicators_screen.dart';
import 'measurement_screen.dart';
import 'profile_screen.dart';

/// Основен екран с меню (Drawer) към разделите на приложението.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['Измерване', 'История', 'Сертификати', 'Устройства', 'Калибровка', 'Настройки', 'Профил'];
  static const _profileIndex = 6;
  static const _certificatesIndex = 2;

  final _certificatesKey = GlobalKey<CertificatesScreenState>();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final pages = [
      const MeasurementScreen(),
      const HistoryScreen(),
      CertificatesScreen(key: _certificatesKey),
      const DevicesScreen(),
      const CalibrationScreen(),
      const IndicatorsScreen(),
      const ProfileScreen(),
    ];

    // UserData живее, докато потребителят е влязъл; при изход се създава наново.
    return ChangeNotifierProvider(
      create: (ctx) => UserData(ctx.read<ApiClient>())..load(),
      child: _buildScaffold(context, auth, pages),
    );
  }

  Widget _buildScaffold(BuildContext context, AuthService auth, List<Widget> pages) {
    final theme = Theme.of(context);
    final measurement = context.watch<MeasurementService>();

    Widget groupLabel(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
          child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

    // Екраните с градиентна лента отгоре (История ... Настройки) имат горна лента в същия цвят.
    final banded = _index >= 1 && _index <= 5;

    // Адаптивна навигация: телефон - скрито меню; таблет в портрет - лента с икони;
    // широк екран (таблет в пейзаж) - постоянно видимо меню.
    final width = MediaQuery.sizeOf(context).width;
    final nav = width >= 1000 ? _Nav.permanent : (width >= 600 ? _Nav.rail : _Nav.modal);

    final content = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: nav == _Nav.modal,
        title: Text(_titles[_index]),
        backgroundColor: banded ? AppColors.ink : null,
        foregroundColor: banded ? Colors.white : null,
        scrolledUnderElevation: banded ? 0 : null,
        systemOverlayStyle: banded ? SystemUiOverlayStyle.light : null,
        titleTextStyle: banded
            ? theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)
            : null,
        actions: [
          // Измерването продължава и при смяна на екрана - показваме го навсякъде.
          if (measurement.isRunning && _index != 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ActionChip(
                avatar: Icon(Icons.circle, size: 10, color: measurement.recordingId != null ? AppColors.danger : AppColors.success),
                label: Text(measurement.recordingId != null ? 'Запис' : 'Измерване'),
                onPressed: () => setState(() => _index = 0),
              ),
            ),
        ],
      ),
      drawer: nav == _Nav.modal ? _buildDrawer(auth, groupLabel, modal: true) : null,
      // IndexedStack запазва състоянието на екраните при превключване.
      body: IndexedStack(index: _index, children: pages),
    );

    return switch (nav) {
      _Nav.modal => content,
      _Nav.rail => Row(
          children: [
            _buildRail(auth),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      _Nav.permanent => Row(
          children: [
            SizedBox(width: 300, child: _buildDrawer(auth, groupLabel, modal: false)),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
    };
  }

  void _select(int i) {
    if (i == _titles.length) {
      _logout();
      return;
    }
    setState(() => _index = i);
    // Списъкът се опреснява, защото сертификатите се издават от "История".
    if (i == _certificatesIndex) _certificatesKey.currentState?.reload();
  }

  /// Тясна лента с икони за таблет в портрет.
  Widget _buildRail(AuthService auth) {
    final theme = Theme.of(context);
    return NavigationRail(
      selectedIndex: _index,
      labelType: NavigationRailLabelType.all,
      backgroundColor: theme.colorScheme.surface,
      indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      selectedIconTheme: IconThemeData(color: theme.colorScheme.primary),
      selectedLabelTextStyle: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
      onDestinationSelected: _select,
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _select(_profileIndex),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.ink,
            child: Text(
              (auth.user?.displayName ?? '?').characters.first.toUpperCase(),
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: IconButton(tooltip: 'Изход', icon: const Icon(Icons.logout_rounded), onPressed: _logout),
          ),
        ),
      ),
      destinations: const [
        NavigationRailDestination(icon: Icon(Icons.graphic_eq_rounded), label: Text('Измерване')),
        NavigationRailDestination(icon: Icon(Icons.history_rounded), label: Text('История')),
        NavigationRailDestination(
            icon: Icon(Icons.verified_outlined), selectedIcon: Icon(Icons.verified), label: Text('Сертификати')),
        NavigationRailDestination(
            icon: Icon(Icons.mic_none_rounded), selectedIcon: Icon(Icons.mic_rounded), label: Text('Устройства')),
        NavigationRailDestination(icon: Icon(Icons.tune_rounded), label: Text('Калибровка')),
        NavigationRailDestination(
            icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Настройки')),
        NavigationRailDestination(
            icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: Text('Профил')),
      ],
    );
  }

  /// Менюто: изскачащо (телефон) или постоянно видимо (широк екран).
  Widget _buildDrawer(AuthService auth, Widget Function(String) groupLabel, {required bool modal}) {
    final theme = Theme.of(context);
    return NavigationDrawer(
        selectedIndex: _index,
        elevation: modal ? null : 0,
        onDestinationSelected: (i) {
          if (modal) Navigator.pop(context);
          if (i == _titles.length) {
            _logout();
          } else {
            setState(() => _index = i);
            // Списъкът се опреснява, защото сертификатите се издават от "История".
            if (i == _certificatesIndex) _certificatesKey.currentState?.reload();
          }
        },
        children: [
          // Натискането върху името отваря профила.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Material(
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: const BoxDecoration(gradient: AppColors.heroGradient),
                child: InkWell(
                  onTap: () {
                    if (modal) Navigator.pop(context);
                    setState(() => _index = _profileIndex);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AppLogo(size: 36),
                            const SizedBox(width: 10),
                            Text(
                              'Шумомер',
                              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.white,
                              child: Text(
                                (auth.user?.displayName ?? '?').characters.first.toUpperCase(),
                                style: theme.textTheme.titleMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    auth.user?.displayName ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
                                  ),
                                  Text(
                                    auth.user?.email ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.8)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          groupLabel('Измервания'),
          const NavigationDrawerDestination(
            icon: Icon(Icons.graphic_eq_rounded), selectedIcon: Icon(Icons.graphic_eq_rounded), label: Text('Измерване')),
          const NavigationDrawerDestination(
            icon: Icon(Icons.history_rounded), selectedIcon: Icon(Icons.history_rounded), label: Text('История')),
          const NavigationDrawerDestination(
            icon: Icon(Icons.verified_outlined), selectedIcon: Icon(Icons.verified), label: Text('Сертификати')),
          groupLabel('Оборудване'),
          const NavigationDrawerDestination(
            icon: Icon(Icons.mic_none_rounded), selectedIcon: Icon(Icons.mic_rounded), label: Text('Устройства')),
          const NavigationDrawerDestination(
            icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: Text('Калибровка')),
          groupLabel('Акаунт'),
          const NavigationDrawerDestination(
            icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Настройки')),
          const NavigationDrawerDestination(
            icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: Text('Профил')),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8), child: Divider()),
          const NavigationDrawerDestination(icon: Icon(Icons.logout_rounded), label: Text('Изход')),
          const SizedBox(height: 16),
        ],
      );
  }

  void _logout() {
    final measurement = context.read<MeasurementService>();
    if (measurement.isRunning) measurement.stop();
    context.read<AuthService>().logout();
  }
}

enum _Nav { modal, rail, permanent }
