import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

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
      final source = body['audio_source'] == 'simulator' ? 'симулатор (без микрофон)' : 'USB микрофон';
      setState(() {
        _state = _TestState.ok;
        _message = 'Връзката е успешна. Сървър v${body['version'] ?? '?'}, източник: $source.';
      });
      return true;
    } catch (_) {
      setState(() {
        _state = _TestState.failed;
        _message = 'Няма отговор от $_url. Проверете адреса, порта и дали телефонът е в същата Wi-Fi мрежа.';
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
    const gap = SizedBox(height: 12);
    final busy = _state == _TestState.testing;

    return Scaffold(
      appBar: bandAppBar(),
      body: Form(
        key: _form,
        child: BandedListView(
          header: const BandTitle(
            title: 'Адрес на сървъра',
            subtitle: 'Raspberry Pi 5 с USB микрофона и базата данни',
          ),
          children: [
            SectionCard(
              title: 'Мрежова конфигурация',
              subtitle: 'IP адрес и порт на сървъра',
              icon: Icons.wifi_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const InfoBanner(
                    message: 'Телефонът и Raspberry Pi трябва да са свързани към една и съща Wi-Fi мрежа.',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _host,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'IP адрес',
                            hintText: '192.168.1.150',
                            prefixIcon: Icon(Icons.router_outlined),
                          ),
                          onChanged: (_) => setState(() => _state = _TestState.idle),
                          validator: (v) => (v == null || v.trim().isEmpty || v.contains('/') || v.contains(' '))
                              ? 'Въведете IP адрес или име'
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
                          decoration: const InputDecoration(labelText: 'Порт', helperText: 'FastAPI: 8000'),
                          onChanged: (_) => setState(() => _state = _TestState.idle),
                          validator: (v) {
                            final p = int.tryParse(v ?? '');
                            return (p == null || p < 1 || p > 65535) ? '1–65535' : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Защитена връзка (HTTPS)'),
                    subtitle: const Text('За връзка през интернет'),
                    value: _https,
                    onChanged: (v) => setState(() {
                      _https = v;
                      _state = _TestState.idle;
                    }),
                  ),
                  if (_message != null) ...[
                    gap,
                    InfoBanner(
                      message: _message!,
                      color: _state == _TestState.ok ? AppColors.success : theme.colorScheme.error,
                      icon: _state == _TestState.ok ? Icons.check_circle_outline_rounded : Icons.wifi_off_rounded,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy ? null : () => _saveAndConnect(),
                    icon: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link_rounded),
                    label: const Text('Запази и свържи'),
                  ),
                  gap,
                  OutlinedButton.icon(
                    onPressed: busy ? null : _test,
                    icon: const Icon(Icons.network_check_rounded),
                    label: const Text('Само провери връзката'),
                  ),
                  if (_state == _TestState.failed)
                    TextButton(
                      onPressed: () => _saveAndConnect(force: true),
                      child: const Text('Запази въпреки това'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Как да намеря адреса?',
              icon: Icons.help_outline_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _helpStep(
                    '1',
                    'В локална мрежа',
                    'На Raspberry Pi отворете Terminal и изпълнете:',
                    code: 'hostname -I',
                  ),
                  _helpStep(
                    '2',
                    'Pi като точка за достъп',
                    'Свържете телефона към Wi-Fi мрежата на Pi. Адресът е винаги:',
                    host: '10.42.0.1',
                  ),
                  _helpStep(
                    '3',
                    'Android емулатор',
                    'Сървърът работи на същия компютър:',
                    host: '10.0.2.2',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _helpStep(String number, String title, String text, {String? code, String? host}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Text(number, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                if (code != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
                    child: Text(code, style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
                  ),
                if (host != null)
                  ActionChip(
                    avatar: const Icon(Icons.input_rounded, size: 16),
                    label: Text('Използвай $host'),
                    onPressed: () => _useHost(host),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
