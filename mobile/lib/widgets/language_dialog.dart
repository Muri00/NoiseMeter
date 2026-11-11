import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';

/// Избор на език на приложението: български или английски.
Future<void> showLanguageDialog(BuildContext context) async {
  final language = context.read<AppLanguage>();
  final selected = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('Език')),
      children: [
        for (final (code, name) in [('bg', 'Български'), ('en', 'English')])
          ListTile(
            leading: Icon(code == AppLanguage.current ? Icons.radio_button_checked : Icons.radio_button_off),
            title: Text(name),
            onTap: () => Navigator.pop(ctx, code),
          ),
      ],
    ),
  );
  if (selected != null) await language.set(selected);
}

/// Бутон "BG/EN" горе вдясно: текущият език е с удебелен шрифт; отваря избора на език.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final current = AppLanguage.current;
    final color = Theme.of(context).colorScheme.onSurface;
    TextStyle style(String code) => TextStyle(
          color: code == current ? color : color.withValues(alpha: 0.55),
          fontWeight: code == current ? FontWeight.w600 : FontWeight.w500,
          fontSize: 15,
        );
    return TextButton(
      style: TextButton.styleFrom(foregroundColor: color, minimumSize: const Size(48, 40)),
      onPressed: () => showLanguageDialog(context),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: 'BG', style: style('bg')),
          TextSpan(text: '/', style: style('')),
          TextSpan(text: 'EN', style: style('en')),
        ]),
        semanticsLabel: tr('Език'),
      ),
    );
  }
}
