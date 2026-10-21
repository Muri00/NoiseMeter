import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/ui.dart';

/// Същите изисквания като на сървъра - използва се и при смяна на паролата.
String? validatePassword(String? v) {
  if (v == null || v.length < 8) return 'Поне 8 символа';
  if (v.length > 72) return 'Най-много 72 символа';
  if (!RegExp(r'[A-Za-zА-Яа-я]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
    return 'Трябва да съдържа поне една буква и една цифра';
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
    const gap = SizedBox(height: 12);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Нов акаунт')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Създайте акаунт, за да записвате измервания, да калибрирате устройствата си '
                    'и да издавате сертификати.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Акаунт',
                    icon: Icons.alternate_email_rounded,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _username,
                          decoration: const InputDecoration(
                            labelText: 'Потребителско име *',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length < 3) return 'Поне 3 символа';
                            if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(v.trim())) {
                              return 'Само латински букви, цифри и _ . -';
                            }
                            return null;
                          },
                        ),
                        gap,
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Имейл *', prefixIcon: Icon(Icons.mail_outline_rounded)),
                          validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                              ? 'Невалиден имейл'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'Лични данни',
                    subtitle: 'По желание - използват се в сертификатите',
                    icon: Icons.badge_outlined,
                    child: Row(
                      children: [
                        Expanded(child: TextFormField(controller: _firstName, decoration: const InputDecoration(labelText: 'Име'))),
                        const SizedBox(width: 12),
                        Expanded(child: TextFormField(controller: _lastName, decoration: const InputDecoration(labelText: 'Фамилия'))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'Парола',
                    subtitle: 'Поне 8 символа, с буква и цифра',
                    icon: Icons.lock_outline_rounded,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'Парола *', prefixIcon: Icon(Icons.key_outlined)),
                          validator: validatePassword,
                        ),
                        gap,
                        TextFormField(
                          controller: _confirm,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Повторете паролата *',
                            prefixIcon: Icon(Icons.key_outlined),
                          ),
                          validator: (v) => v != _password.text ? 'Паролите не съвпадат' : null,
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                        : const Text('Създай акаунт'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
