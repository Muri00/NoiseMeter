import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/measurement_service.dart';
import 'login_screen.dart' show showServerDialog;
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'change_password_screen.dart';

/// Профил: лични данни, смяна на паролата, изход и изтриване на акаунта.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileForm = GlobalKey<FormState>();
  late final AuthService _auth = context.read<AuthService>();
  late final _email = TextEditingController(text: _auth.user?.email);
  late final _firstName = TextEditingController(text: _auth.user?.firstName);
  late final _lastName = TextEditingController(text: _auth.user?.lastName);
  bool _savingProfile = false;

  @override
  void dispose() {
    for (final c in [_email, _firstName, _lastName]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _saveProfile() async {
    if (!_profileForm.currentState!.validate()) return;
    setState(() => _savingProfile = true);
    try {
      await _auth.updateProfile(email: _email.text, firstName: _firstName.text, lastName: _lastName.text);
      _snack('Данните са запазени');
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
    if (changed == true) _snack('Паролата е сменена. Излязохте от акаунта на другите устройства.');
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
        title: const Text('Изтриване на акаунта'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ще бъдат изтрити окончателно всички устройства, измервания, WAV записи, '
              'калибровки и сертификати. Това не може да бъде отменено.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Парола за потвърждение'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Изтрий'),
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
    final theme = Theme.of(context);
    const gap = SizedBox(height: 12);
    final initial = (auth.user?.displayName ?? '?').characters.first.toUpperCase();

    // На таблет страницата е центрирана; отстъпът отстрани расте с ширината.
    final side = ((MediaQuery.sizeOf(context).width - 760) / 2).clamp(16.0, double.infinity);
    return ListView(
      padding: EdgeInsets.fromLTRB(side, 4, side, 32),
      children: [
        // Заглавна карта с аватар.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: Color(0x330B2545), blurRadius: 20, offset: Offset(0, 8))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Text(
                    initial,
                    style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.user?.displayName ?? '',
                      style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    StatusPill(
                      label: '@${auth.user?.username ?? ''}',
                      color: Colors.white,
                      icon: Icons.person_outline_rounded,
                      onDark: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Лични данни',
          subtitle: 'Името се използва в сертификатите',
          icon: Icons.badge_outlined,
          child: Form(
            key: _profileForm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Имейл', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                      ? 'Невалиден имейл'
                      : null,
                ),
                gap,
                Row(
                  children: [
                    Expanded(child: TextFormField(controller: _firstName, decoration: const InputDecoration(labelText: 'Име'))),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(controller: _lastName, decoration: const InputDecoration(labelText: 'Фамилия'))),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: _savingProfile ? null : _saveProfile,
                  icon: _savingProfile
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: const Text('Запази данните'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Акаунт и сигурност',
          icon: Icons.shield_outlined,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              _tile(
                icon: Icons.lock_outline_rounded,
                title: 'Смяна на паролата',
                subtitle: 'Излизане от другите устройства',
                onTap: _changePassword,
              ),
              _tile(
                icon: Icons.dns_outlined,
                title: 'Сървър',
                subtitle: auth.serverUrl,
                onTap: () => showServerDialog(context),
              ),
              _tile(icon: Icons.logout_rounded, title: 'Изход', onTap: _logout, showChevron: false),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Опасна зона - отделена визуално от останалото.
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.error.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.25)),
          ),
          padding: const EdgeInsets.all(8),
          child: _tile(
            icon: Icons.delete_forever_outlined,
            title: 'Изтриване на акаунта',
            subtitle: 'Окончателно, заедно с всички данни',
            onTap: _deleteAccount,
            color: theme.colorScheme.error,
          ),
        ),
      ],
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? color,
    bool showChevron = true,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: IconBadge(icon: icon, color: color ?? theme.colorScheme.secondary, size: 40),
      title: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: color)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      trailing: showChevron ? Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant) : null,
      onTap: onTap,
    );
  }
}
