import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/ui.dart';
import 'register_screen.dart' show validatePassword;
import '../l10n/l10n.dart';

/// Смяна на паролата. Връща true при успех.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _new, _confirm]) {
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
      await context.read<AuthService>().changePassword(
        _current.text,
        _new.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    final toggle = IconButton(
      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      tooltip: _obscure ? tr('Покажи паролите') : tr('Скрий паролите'),
      onPressed: () => setState(() => _obscure = !_obscure),
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Смяна на паролата'))),
      body: Form(
        key: _form,
        child: BandedListView(
          children: [
            TextFormField(
              controller: _current,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: tr('Текуща парола'),
                suffixIcon: toggle,
              ),
              validator: (v) => (v == null || v.isEmpty)
                  ? tr('Въведете текущата парола')
                  : null,
            ),
            gap,
            TextFormField(
              controller: _new,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: tr('Нова парола'),
                helperText:
                    tr('Поне 8 символа, с поне една буква и една цифра'),
              ),
              validator: validatePassword,
            ),
            gap,
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: tr('Повторете новата парола'),
              ),
              validator: (v) =>
                  v != _new.text ? tr('Паролите не съвпадат') : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              gap,
              InfoBanner(
                message: _error!,
                color: Theme.of(context).colorScheme.error,
                icon: Icons.error_outline_rounded,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr('Смени паролата')),
            ),
          ],
        ),
      ),
    );
  }
}
