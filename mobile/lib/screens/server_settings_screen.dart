import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/language_dialog.dart';
import '../widgets/ui.dart';
import '../l10n/l10n.dart';

/// Мрежова конфигурация: адрес на Raspberry Pi и проверка на връзката.
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

enum _TestState { idle, testing, ok, failed }

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _host;
  late final TextEditingController _port;
  bool _https = false;
  _TestState _state = _TestState.idle;
  String? _message;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(context.read<AuthService>().serverUrl);
    _host = TextEditingController(text: uri?.host ?? '');
    _port = TextEditingController(text: uri == null || !uri.hasPort ? '8000' : '${uri.port}');
    _https = uri?.scheme == 'https';
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  String get _url => '${_https ? 'https' : 'http'}://${_host.text.trim()}:${_port.text.trim()}';

  /// Проверява дали на адреса отговаря сървърът на шумомера (/api/health).
  Future<bool> _test() async {
    if (!_form.currentState!.validate()) return false;
    setState(() {
      _state = _TestState.testing;
      _message = null;
    });
    try {
      final res = await http.get(Uri.parse('$_url/api/health')).timeout(const Duration(seconds: 5));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode != 200 || body['status'] != 'ok') throw const FormatException();
      final source = body['audio_source'] == 'simulator' ? tr('симулатор (без микрофон)') : tr('USB микрофон');
      setState(() {
        _state = _TestState.ok;
        _message = tr('Връзката е успешна. Сървър v{p0}, източник: {p1}.', {'p0': body['version'] ?? '?', 'p1': source});
      });
      return true;
    } catch (_) {
      setState(() {
        _state = _TestState.failed;
        _message = tr('Няма отговор от {p0}. Проверете адреса, порта и дали телефонът е в същата Wi-Fi мрежа.', {'p0': _url});
      });
      return false;
    }
  }

  Future<void> _saveAndConnect({bool force = false}) async {
    final auth = context.read<AuthService>();
    if (!force && !await _test()) return;
    await auth.setServerUrl(_url);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _useHost(String host) {
    setState(() {
      _host.text = host;
      _state = _TestState.idle;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gap = SizedBox(height: 16);
    final busy = _state == _TestState.testing;

    final ok = _state == _TestState.ok;

    return Scaffold(
      appBar: bandAppBar(actions: const [LanguageButton(), SizedBox(width: 8)]),
      body: Form(
        key: _form,
        child: BandedListView(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Адрес на сървъра'),
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _host,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: tr('IP адрес'),
                          hintText: '192.168.1.150',
                        ),
                        onChanged: (_) => setState(() => _state = _TestState.idle),
                        validator: (v) => (v == null || v.trim().isEmpty || v.contains('/') || v.contains(' '))
                            ? tr('Въведете IP адрес или име')
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(labelText: tr('Порт')),
                        onChanged: (_) => setState(() => _state = _TestState.idle),
                        validator: (v) {
                          final p = int.tryParse(v ?? '');
                          return (p == null || p < 1 || p > 65535) ? '1–65535' : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchRow(
                  icon: Icons.lock_outline_rounded,
                  label: 'HTTPS',
                  value: _https,
                  onChanged: (v) => setState(() {
                    _https = v;
                    _state = _TestState.idle;
                  }),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : _test,
                  child: busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(tr('Провери връзката')),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        ok ? Icons.check_circle_rounded : Icons.error_rounded,
                        size: 18,
                        color: ok ? AppColors.success : theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _message!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            color: ok ? AppColors.success : theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                gap,
                OutlinedButton(
                  onPressed: busy ? null : () => _saveAndConnect(),
                  child: Text(tr('Запази и свържи')),
                ),
                if (_state == _TestState.failed)
                  TextButton(
                    onPressed: () => _saveAndConnect(force: true),
                    child: Text(tr('Запази въпреки това')),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _helpBox(theme),
          ],
        ),
      ),
    );
  }

  /// Сива кутия "Помощ" с кратки указания как да се намери адресът.
  Widget _helpBox(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(tr('Помощ'), style: sectionLabelStyle(context)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
            child: Text(
              tr('Как да намеря адреса?'),
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          _helpStep(
            tr('В локална мрежа'),
            tr('На Raspberry Pi отворете Terminal и изпълнете:'),
            code: 'hostname -I',
          ),
          _helpStep(
            tr('Pi като точка за достъп'),
            tr('Свържете телефона към Wi-Fi мрежата на Pi. Адресът е винаги:'),
            host: '10.42.0.1',
          ),
          _helpStep(
            tr('Android емулатор'),
            tr('Сървърът работи на същия компютър:'),
            host: '10.0.2.2',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(
              tr('Телефонът и Raspberry Pi трябва да са свързани към една и съща Wi-Fi мрежа.'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpStep(String title, String text, {String? code, String? host}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(text, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                if (code != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(code, style: monoStyle(13, color: AppColors.ink)),
                  ),
                ],
                if (host != null) ...[
                  const SizedBox(height: 2),
                  Text(host, style: monoStyle(15, weight: FontWeight.w500, color: AppColors.ink)),
                ],
              ],
            ),
          ),
          if (host != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _useHost(host),
              child: Text(tr('Използвай')),
            ),
          ],
        ],
      ),
    );
  }
}
