import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'device_form_screen.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<UserData>();
    final theme = Theme.of(context);

    final List<Widget> children;
    if (data.loading && data.devices.isEmpty) {
      children = [const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))];
    } else if (data.error != null || data.devices.isEmpty) {
      children = [
        SectionCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const IconBadge(icon: Icons.mic_none_rounded, size: 72),
                const SizedBox(height: 16),
                Text(
                  data.error ?? 'Нямате добавени устройства.\nДобавете микрофона, с който ще измервате.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      ];
    } else {
      children = [
        for (final d in data.devices) ...[_buildDeviceCard(context, d), const SizedBox(height: 12)],
        const SizedBox(height: 72), // място за плаващия бутон
      ];
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: data.load,
        child: BandedListView(
          header: const BandTitle(subtitle: 'Измервателни микрофони и срокът на тяхната калибровка'),
          children: children,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Устройство'),
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, Device d) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openForm(context, d),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(
            children: [
              const IconBadge(icon: Icons.mic_rounded, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title, style: theme.textTheme.titleMedium),
                    Text(
                      'S/N ${d.serialNumber}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusPill(label: '${d.sensitivityDbfs} dBFS', color: theme.colorScheme.primary),
                        StatusPill(
                          label: '${formatHz(d.freqMinHz)} – ${formatHz(d.freqMaxHz)}',
                          color: theme.colorScheme.secondary,
                        ),
                        StatusPill(
                          label: d.calibrationStatusName,
                          color: AppColors.forCalibration(d.calibrationStatus),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Изтрий',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _confirmDelete(context, d),
              ),
            ],
          ),
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
        title: const Text('Изтриване на устройство'),
        content: Text('Да се изтрие ли ${d.title} (S/N ${d.serialNumber})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Изтрий')),
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
