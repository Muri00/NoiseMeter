import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import '../l10n/l10n.dart';
import '../widgets/language_dialog.dart';
import 'register_screen.dart';
import 'server_settings_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().login(_login.text, _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = context.watch<AuthService>().serverUrl;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Горе вдясно: език, сървър и текущият адрес на сървъра.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const LanguageButton(),
                    const ServerButton(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Align(alignment: Alignment.centerRight, child: _serverPill(theme, server)),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: AppLogo(size: 120, withName: true)),
                          const SizedBox(height: 40),
                          _buildForm(theme),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                tr('Нямате акаунт?'),
                                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.ink),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  minimumSize: const Size(0, 40),
                                  textStyle: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                                ),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                ),
                                child: Text(tr('Регистрация')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Адресът на сървъра като малко сиво хапче; отваря настройките на сървъра.
  Widget _serverPill(ThemeData theme, String server) {
    return Material(
      color: AppColors.surfaceHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showServerDialog(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            server,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(12.5, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _login,
              decoration: InputDecoration(labelText: tr('Потребителско име или имейл')),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              validator: (v) => (v == null || v.trim().isEmpty) ? tr('Въведете потребителско име') : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: tr('Парола'),
                suffixIcon: IconButton(
                  tooltip: _obscure ? tr('Покажи паролите') : tr('Скрий паролите'),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              validator: (v) => (v == null || v.isEmpty) ? tr('Въведете парола') : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              InfoBanner(
                message: _error!,
                color: theme.colorScheme.error,
                icon: Icons.error_outline,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(tr('Вход')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Иконата "глобус" горе вдясно: отваря екрана за адреса на сървъра.
class ServerButton extends StatelessWidget {
  const ServerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr('Адрес на сървъра'),
      color: AppColors.ink,
      icon: const Icon(Icons.language_rounded),
      onPressed: () => showServerDialog(context),
    );
  }
}

/// Отваря екрана за адреса на сървъра (името е запазено от по-ранния диалог).
Future<void> showServerDialog(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServerSettingsScreen()));
}
