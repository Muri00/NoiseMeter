import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/measurement_service.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import '../l10n/l10n.dart';
import 'admin_screen.dart';
import 'calibration_screen.dart';
import 'certificates_screen.dart';
import 'devices_screen.dart';
import 'history_screen.dart';
import 'indicators_screen.dart';
import 'measurement_screen.dart';
import 'profile_screen.dart';

/// Основен екран с навигацията към разделите на приложението.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Getter, а не константа - заглавията се превеждат при смяна на езика.
  List<String> get _titles => [
    tr('Измерване'),
    tr('История'),
    tr('Сертификати'),
    tr('Устройства'),
    tr('Калибровка'),
    tr('Настройки'),
    tr('Профил'),
  ];
  static const _profileIndex = 6;
  static const _certificatesIndex = 2;

  final _certificatesKey = GlobalKey<CertificatesScreenState>();

  // UserData живее, докато потребителят е влязъл; при изход екранът се затваря и данните се създават наново.
  // Държи се тук, а не само в Provider-а, за да може да се подаде и на екраните, отворени с Navigator.push.
  late final UserData _data = UserData(context.read<ApiClient>())..load();

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isAdmin = auth.user?.isAdmin ?? false;
    final pages = [
      const MeasurementScreen(),
      const HistoryScreen(),
      CertificatesScreen(key: _certificatesKey),
      const DevicesScreen(),
      const CalibrationScreen(),
      const IndicatorsScreen(),
      const ProfileScreen(),
      // Администрацията е раздел като останалите - менюто остава видимо.
      if (isAdmin) const AdminScreen(),
    ];
    if (_index >= pages.length) _index = 0;

    return ChangeNotifierProvider.value(
      value: _data,
      child: _buildScaffold(context, auth, pages),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AuthService auth,
    List<Widget> pages,
  ) {
    final measurement = context.watch<MeasurementService>();
    final navTheme = AppTheme.navigation();

    // Адаптивна навигация: телефон - долна лента; таблет в портрет - лента с икони;
    // широк екран (таблет в пейзаж) - постоянно видимо меню. Навигацията е тъмносива.
    final width = MediaQuery.sizeOf(context).width;
    final nav = width >= 1000
        ? _Nav.permanent
        : (width >= 600 ? _Nav.rail : _Nav.bottom);

    final content = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_index == _adminIndex ? tr('Администрация') : _titles[_index]),
        // "Измерване": заглавие в центъра, меню отляво; на телефон менюто отваря "Още".
        centerTitle: _index == 0,
        titleTextStyle: _index == 0
            ? Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontSize: 20, fontWeight: FontWeight.w600)
            : null,
        leading: _index == 0 && nav == _Nav.bottom
            ? IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: _showMore,
              )
            : null,
        actions: [
          if (_index == 0 &&
              measurement.isRunning &&
              measurement.recordingId != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                ),
              ),
            )
          else if (_index == 0 && nav == _Nav.bottom)
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: _showMore,
            ),
          // Измерването продължава и при смяна на екрана - показваме го навсякъде.
          if (measurement.isRunning && _index != 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ActionChip(
                avatar: Icon(
                  Icons.circle,
                  size: 10,
                  color: measurement.recordingId != null
                      ? AppColors.danger
                      : AppColors.success,
                ),
                label: Text(
                  measurement.recordingId != null
                      ? tr('Запис')
                      : tr('Измерване'),
                ),
                onPressed: () => setState(() => _index = 0),
              ),
            ),
        ],
      ),
      // IndexedStack запазва състоянието на екраните при превключване.
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: nav == _Nav.bottom
          ? Theme(data: navTheme, child: _buildBottomBar())
          : null,
    );

    return switch (nav) {
      _Nav.bottom => content,
      _Nav.rail => Row(
        children: [
          Theme(
            data: navTheme,
            child: Builder(builder: (ctx) => _buildRail(ctx, auth)),
          ),
          Expanded(child: content),
        ],
      ),
      _Nav.permanent => Row(
        children: [
          SizedBox(
            width: 260,
            child: Theme(
              data: navTheme,
              child: Builder(builder: (ctx) => _buildDrawer(ctx, auth)),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    };
  }

  /// Разделите в долната лента на телефона; останалите са под "Още".
  static const _bottomCount = 4;

  Widget _buildBottomBar() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: NavigationBar(
        selectedIndex: _index < _bottomCount ? _index : _bottomCount,
        onDestinationSelected: (i) =>
            i < _bottomCount ? _select(i) : _showMore(),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.graphic_eq_rounded),
            label: tr('Измерване'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_rounded),
            label: tr('История'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.verified_outlined),
            selectedIcon: const Icon(Icons.verified),
            label: tr('Сертификати'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.mic_none_rounded),
            selectedIcon: const Icon(Icons.mic_rounded),
            label: tr('Устройства'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz_rounded),
            label: tr('Още'),
          ),
        ],
      ),
    );
  }

  /// "Още" на телефона: калибровка, настройки, профил, администрация и изход.
  void _showMore() {
    final isAdmin = _isAdmin;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        Widget item(
          IconData icon,
          String label,
          VoidCallback onTap, {
          bool selected = false,
        }) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: Icon(icon, color: selected ? AppColors.accent : null),
          title: Text(
            label,
            style: TextStyle(fontWeight: selected ? FontWeight.w500 : null),
          ),
          onTap: () {
            Navigator.pop(sheetContext);
            onTap();
          },
        );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                item(
                  Icons.tune_rounded,
                  tr('Калибровка'),
                  () => _select(4),
                  selected: _index == 4,
                ),
                item(
                  Icons.settings_outlined,
                  tr('Настройки'),
                  () => _select(5),
                  selected: _index == 5,
                ),
                item(
                  Icons.person_outline_rounded,
                  tr('Профил'),
                  () => _select(_profileIndex),
                  selected: _index == _profileIndex,
                ),
                if (isAdmin)
                  item(
                    Icons.admin_panel_settings_outlined,
                    tr('Администрация'),
                    () => _select(_adminIndex),
                    selected: _index == _adminIndex,
                  ),
                const Divider(),
                item(Icons.logout_rounded, tr('Изход'), _logout),
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _isAdmin => context.read<AuthService>().user?.isAdmin ?? false;

  /// Индексите след разделите: [Администрация (само за администратор)], Изход.
  int get _adminIndex => _titles.length;
  int get _logoutIndex => _titles.length + (_isAdmin ? 1 : 0);

  void _select(int i) {
    if (i == _logoutIndex) {
      _logout();
      return;
    }
    setState(() => _index = i);
    // Списъкът се опреснява, защото сертификатите се издават от "История".
    if (i == _certificatesIndex) _certificatesKey.currentState?.reload();
  }

  /// Лента с разделите за таблет в портрет: логото горе, разделите, профилът и изходът долу.
  Widget _buildRail(BuildContext context, AuthService auth) {
    final theme = Theme.of(context);
    final isAdmin = auth.user?.isAdmin ?? false;

    Widget item(
      int index,
      IconData icon,
      IconData selectedIcon,
      String label, {
      VoidCallback? onTap,
    }) {
      final selected = _index == index && onTap == null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap ?? () => _select(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 56,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    selected ? selectedIcon : icon,
                    size: 24,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                // Цялата дума на един ред - при нужда се смалява, вместо да се пренася по средата.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final initial = (auth.user?.displayName ?? '?').characters.first
        .toUpperCase();
    final profileSelected = _index == _profileIndex;
    return Container(
      width: 96,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 18),
            // Логото с името под вълната; страничната лента е широка 96 px.
            const AppLogo(size: 50, withName: true),
            const SizedBox(height: 22),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    item(
                      0,
                      Icons.graphic_eq_rounded,
                      Icons.graphic_eq_rounded,
                      tr('Измерване'),
                    ),
                    item(
                      1,
                      Icons.history_rounded,
                      Icons.history_rounded,
                      tr('История'),
                    ),
                    item(
                      2,
                      Icons.verified_outlined,
                      Icons.verified,
                      tr('Сертификати'),
                    ),
                    item(
                      3,
                      Icons.mic_none_rounded,
                      Icons.mic_rounded,
                      tr('Устройства'),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 18,
                      ),
                      child: Divider(),
                    ),
                    item(
                      4,
                      Icons.tune_rounded,
                      Icons.tune_rounded,
                      tr('Калибровка'),
                    ),
                    item(
                      5,
                      Icons.settings_outlined,
                      Icons.settings,
                      tr('Настройки'),
                    ),
                    if (isAdmin)
                      item(
                        _adminIndex,
                        Icons.admin_panel_settings_outlined,
                        Icons.admin_panel_settings,
                        tr('Администрация'),
                      ),
                  ],
                ),
              ),
            ),
            // Профилът (инициалът) и изходът - долу.
            Tooltip(
              message: tr('Профил'),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _select(_profileIndex),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: profileSelected
                          ? AppColors.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: profileSelected
                        ? theme.colorScheme.primaryContainer
                        : AppColors.surfaceHigh,
                    child: Text(
                      initial,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: profileSelected
                            ? AppColors.primary
                            : AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            IconButton(
              tooltip: tr('Изход'),
              icon: const Icon(
                Icons.logout_rounded,
                color: AppColors.textSecondary,
              ),
              onPressed: _logout,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Постоянно видимото меню на широк екран.
  Widget _buildDrawer(BuildContext context, AuthService auth) {
    Widget groupLabel(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
      child: Text(text.toUpperCase(), style: sectionLabelStyle(context)),
    );
    return NavigationDrawer(
      selectedIndex: _index,
      elevation: 0,
      onDestinationSelected: _select,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
          child: const Align(alignment: Alignment.centerLeft, child: AppLogo(size: 52, withName: true)),
        ),
        groupLabel(tr('Измервания')),
        NavigationDrawerDestination(
          icon: Icon(Icons.graphic_eq_rounded),
          selectedIcon: Icon(Icons.graphic_eq_rounded),
          label: Text(tr('Измерване')),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.history_rounded),
          selectedIcon: Icon(Icons.history_rounded),
          label: Text(tr('История')),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.verified_outlined),
          selectedIcon: Icon(Icons.verified),
          label: Text(tr('Сертификати')),
        ),
        groupLabel(tr('Оборудване')),
        NavigationDrawerDestination(
          icon: Icon(Icons.mic_none_rounded),
          selectedIcon: Icon(Icons.mic_rounded),
          label: Text(tr('Устройства')),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.tune_rounded),
          selectedIcon: Icon(Icons.tune_rounded),
          label: Text(tr('Калибровка')),
        ),
        groupLabel(tr('Акаунт')),
        NavigationDrawerDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text(tr('Настройки')),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: Text(tr('Профил')),
        ),
        if (auth.user?.isAdmin ?? false)
          NavigationDrawerDestination(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: const Icon(Icons.admin_panel_settings),
            label: Text(tr('Администрация')),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Divider(),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.logout_rounded),
          label: Text(tr('Изход')),
        ),
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

enum _Nav { bottom, rail, permanent }
