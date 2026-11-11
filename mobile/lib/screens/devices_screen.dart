import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'device_form_screen.dart';
import '../l10n/l10n.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  /// Ширини на колоните: икона, работна лента, чувствителност.
  static const _iconWidth = 40.0;
  static const _rangeWidth = 96.0;
  static const _sensWidth = 72.0;

  /// Число без излишно ".0" (напр. -18 вместо -18.0).
  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<UserData>();
    final theme = Theme.of(context);

    final List<Widget> children;
    if (data.loading && data.devices.isEmpty) {
      children = [const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))];
    } else if (data.error != null && data.devices.isEmpty) {
      // Грешка при зареждане и нищо за показване.
      children = [InfoBanner(message: data.error!, color: theme.colorScheme.error, icon: Icons.error_outline)];
    } else if (data.devices.isEmpty) {
      children = [
        EmptyState(
          icon: Icons.mic_none_rounded,
          title: tr('Няма устройства'),
          message: tr('Добавете микрофона, с който ще измервате.'),
        ),
      ];
    } else {
      children = [
        if (data.error != null) ...[
          InfoBanner(message: data.error!, color: theme.colorScheme.error, icon: Icons.error_outline),
          const SizedBox(height: 24),
        ],
        _columnHeaders(context),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppColors.line),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, d) in data.devices.indexed) ...[
                  if (i > 0) const Divider(),
                  _deviceRow(context, d),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            tr('Задръжте ред за изтриване.'),
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ),
        const SizedBox(height: 72), // място за плаващия бутон
      ];
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: data.load,
        child: BandedListView(
          header: const BandTitle(),
          children: children,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: tr('Ново устройство'),
        onPressed: () => _openForm(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Малки сиви заглавия на колоните над таблицата.
  Widget _columnHeaders(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          Expanded(child: Text(tr('Устройство'), style: style)),
          SizedBox(width: _rangeWidth, child: Text(tr('Работна лента'), style: style)),
          SizedBox(
            width: _sensWidth,
            child: Text(
              tr('Чувствителност'),
              style: style,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Ред за едно устройство: микрофон, марка и модел със серийния номер, работна лента и чувствителност.
  /// Натискане - редакция; задържане - изтриване.
  Widget _deviceRow(BuildContext context, Device d) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return InkWell(
      onTap: () => _openForm(context, d),
      onLongPress: () => _confirmDelete(context, d),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            const SizedBox(
              width: _iconWidth,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(Icons.mic, color: AppColors.ink, size: 28),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.title,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(d.serialNumber, style: secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            SizedBox(
              width: _rangeWidth,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${formatHz(d.freqMinHz)} –', style: monoStyle(13, color: AppColors.ink)),
                    Text(formatHz(d.freqMaxHz), style: monoStyle(13, color: AppColors.ink)),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _sensWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_num(d.sensitivityDbfs), style: monoStyle(16, weight: FontWeight.w500, color: AppColors.ink)),
                  Text('dBFS', style: secondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openForm(BuildContext context, Device? device) {
    final data = context.read<UserData>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(value: data, child: DeviceFormScreen(device: device)),
    ));
  }

  Future<void> _confirmDelete(BuildContext context, Device d) async {
    final data = context.read<UserData>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Изтриване на устройство')),
        content: Text(tr('Да се изтрие ли {p0} (S/N {p1})?', {'p0': d.title, 'p1': d.serialNumber})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отказ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Изтрий'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await data.deleteDevice(d);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
