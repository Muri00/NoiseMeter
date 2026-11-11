import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/language_dialog.dart';
import '../widgets/ui.dart';
import '../l10n/l10n.dart';
import 'login_screen.dart' show ServerButton;

/// Същите изисквания като на сървъра - използва се и при смяна на паролата.
String? validatePassword(String? v) {
  if (v == null || v.length < 8) return tr('Поне 8 символа');
  if (v.length > 72) return tr('Най-много 72 символа');
  if (!RegExp(r'[A-Za-zА-Яа-я]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
    return tr('Трябва да съдържа поне една буква и една цифра');
  }
  return null;
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_username, _email, _firstName, _lastName, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().register(
            username: _username.text,
            email: _email.text,
            password: _password.text,
            firstName: _firstName.text,
            lastName: _lastName.text,
          );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(actions: const [LanguageButton(), ServerButton(), SizedBox(width: 8)]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr('Регистрация'),
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _username,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newUsername],
                      decoration: InputDecoration(labelText: tr('Потребителско име')),
                      validator: (v) {
                        if (v == null || v.trim().length < 3) return tr('Поне 3 символа');
                        if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(v.trim())) {
                          return tr('Само латински букви, цифри и _ . -');
                        }
                        return null;
                      },
                    ),
                    gap,
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(labelText: tr('Имейл')),
                      validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                          ? tr('Невалиден имейл')
                          : null,
                    ),
                    gap,
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(labelText: tr('Парола')),
                      validator: validatePassword,
                    ),
                    gap,
                    TextFormField(
                      controller: _confirm,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: tr('Повторете паролата'),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? tr('Покажи паролите') : tr('Скрий паролите'),
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => v != _password.text ? tr('Паролите не съвпадат') : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                      child: Text(
                        tr('Поне 8 символа, с буква и цифра'),
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    gap,
                    TextFormField(
                      controller: _firstName,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.givenName],
                      decoration: InputDecoration(labelText: tr('Име (по избор)')),
                    ),
                    gap,
                    TextFormField(
                      controller: _lastName,
                      autofillHints: const [AutofillHints.familyName],
                      decoration: InputDecoration(labelText: tr('Фамилия (по избор)')),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      gap,
                      InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                          : Text(tr('Създай акаунт')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
