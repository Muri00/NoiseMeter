import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/measurement_service.dart';
import 'login_screen.dart' show showServerDialog;
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import '../l10n/l10n.dart';
import '../widgets/language_dialog.dart';
import 'change_password_screen.dart';

/// Профил: лични данни, смяна на паролата, изход и изтриване на акаунта.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

enum _Field { email, firstName, lastName }

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthService _auth = context.read<AuthService>();
  bool _savingProfile = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Редакция на едно поле в долен лист; записва веднага.
  Future<void> _editField(_Field field) async {
    if (_savingProfile) return;
    final user = _auth.user;
    final (title, initial) = switch (field) {
      _Field.email => (tr('Имейл'), user?.email ?? ''),
      _Field.firstName => (tr('Име'), user?.firstName ?? ''),
      _Field.lastName => (tr('Фамилия'), user?.lastName ?? ''),
    };
    final value = await showTextSheet(context, title: title, confirmLabel: tr('Запази'), initial: initial);
    if (value == null || value == initial || !mounted) return;
    if (field == _Field.email && !_emailPattern.hasMatch(value.trim())) {
      _snack(tr('Невалиден имейл'));
      return;
    }
    await _saveProfile(
      email: field == _Field.email ? value : (user?.email ?? ''),
      firstName: field == _Field.firstName ? value : user?.firstName,
      lastName: field == _Field.lastName ? value : user?.lastName,
    );
  }

  Future<void> _saveProfile({required String email, String? firstName, String? lastName}) async {
    setState(() => _savingProfile = true);
    try {
      await _auth.updateProfile(email: email, firstName: firstName, lastName: lastName);
      _snack(tr('Данните са запазени'));
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
    );
    if (changed == true) _snack(tr('Паролата е сменена. Излязохте от акаунта на другите устройства.'));
  }

  void _logout() {
    final measurement = context.read<MeasurementService>();
    if (measurement.isRunning) measurement.stop();
    _auth.logout();
  }

  Future<void> _deleteAccount() async {
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Изтриване на акаунта')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('Ще бъдат изтрити окончателно всички устройства, измервания, WAV записи, '
              'калибровки и сертификати. Това не може да бъде отменено.'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('Парола за потвърждение')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отказ'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Изтрий')),
          ),
        ],
      ),
    );
    final value = password.text;
    password.dispose();
    if (confirmed != true) return;
    try {
      await _auth.deleteAccount(value);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    final theme = Theme.of(context);
    const groupGap = SizedBox(height: 24);
    final handle = [
      '@${user?.username ?? ''}',
      if ((user?.email ?? '').isNotEmpty) user!.email,
    ].join(' · ');

    return BandedListView(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user?.displayName ?? '',
              style: theme.textTheme.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              handle,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      children: [
        RowGroup(
          title: tr('Лични данни'),
          trailing: _savingProfile
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          children: [
            ValueRow(label: tr('Имейл'), value: user?.email, onTap: () => _editField(_Field.email)),
            ValueRow(label: tr('Име'), value: user?.firstName, onTap: () => _editField(_Field.firstName)),
            ValueRow(label: tr('Фамилия'), value: user?.lastName, onTap: () => _editField(_Field.lastName)),
            ValueRow(label: tr('Смяна на паролата'), onTap: _changePassword),
          ],
        ),
        groupGap,
        RowGroup(
          title: tr('Система и език'),
          children: [
            ValueRow(label: tr('Сървър'), value: auth.serverUrl, onTap: () => showServerDialog(context)),
            ValueRow(
              label: tr('Език'),
              value: AppLanguage.current == 'en' ? 'English' : 'Български',
              onTap: () => showLanguageDialog(context),
            ),
          ],
        ),
        groupGap,
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded),
          label: Text(tr('Изход')),
        ),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: _deleteAccount,
          child: Text(tr('Изтриване на акаунта')),
        ),
      ],
    );
  }
}
