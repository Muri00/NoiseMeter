import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
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

    // Светли икони в статус лентата върху тъмния градиент.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          children: [
            // Градиентна заглавна част в горната половина.
            Container(
              height: MediaQuery.sizeOf(context).height * 0.42,
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 40),
                        const Center(child: AppLogo(size: 72)),
                        const SizedBox(height: 16),
                        Text(
                          'Шумомер',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Измерване на шум по IEC 61672',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _buildFormCard(theme),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Нямате акаунт?',
                              style: theme.textTheme.bodyMedium,
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              ),
                              child: const Text('Регистрация'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: ActionChip(
                            avatar: Icon(
                              Icons.circle,
                              size: 10,
                              color: theme.colorScheme.primary,
                            ),
                            label: Text(
                              server,
                              style: theme.textTheme.bodySmall,
                            ),
                            onPressed: () => showServerDialog(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Адрес на сървъра - отгоре, за да не се закрива от формата, и на телефон, и на таблет.
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    tooltip: 'Адрес на сървъра',
                    color: Colors.white,
                    icon: const Icon(Icons.dns_outlined),
                    onPressed: () => showServerDialog(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260B2545),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Добре дошли', style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                'Влезте в акаунта си, за да продължите',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _login,
                decoration: const InputDecoration(
                  labelText: 'Потребителско име или имейл',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Въведете потребителско име'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Парола',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Въведете парола' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                InfoBanner(
                  message: _error!,
                  color: theme.colorScheme.error,
                  icon: Icons.error_outline,
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('Вход'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Отваря екрана за адреса на сървъра (името е запазено от по-ранния диалог).
Future<void> showServerDialog(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServerSettingsScreen()));
}
