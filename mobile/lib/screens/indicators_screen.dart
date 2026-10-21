import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/user_data.dart';
import '../widgets/ui.dart';

/// Избор на показателите, които потребителят наблюдава (изискване 3.9),
/// и настройките по подразбиране за измервателния интервал и октавните ленти.
class IndicatorsScreen extends StatefulWidget {
  const IndicatorsScreen({super.key});

  @override
  State<IndicatorsScreen> createState() => _IndicatorsScreenState();
}

class _IndicatorsScreenState extends State<IndicatorsScreen> {
  List<String> _available = [];
  List<String>? _selected;
  String _bandMode = '1/3';
  final _fMin = TextEditingController();
  final _fMax = TextEditingController();
  // Данни за организацията - заглавна част на сертификатите.
  final _orgName = TextEditingController();
  final _orgAddress = TextEditingController();
  final _orgAccreditation = TextEditingController();
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadAvailable();
  }

  @override
  void dispose() {
    _fMin.dispose();
    _fMax.dispose();
    _orgName.dispose();
    _orgAddress.dispose();
    _orgAccreditation.dispose();
    super.dispose();
  }

  Future<void> _loadAvailable() async {
    try {
      final org = await context.read<ApiClient>().get('/api/settings/organization');
      _orgName.text = org['org_name'] ?? '';
      _orgAddress.text = org['org_address'] ?? '';
      _orgAccreditation.text = org['org_accreditation'] ?? '';
      if (!mounted) return;
      final list = await context.read<UserData>().availableIndicators();
      setState(() => _available = list);
    } on ApiException catch (e) {
      setState(() => _loadError = e.message);
    }
  }

  void _initFrom(MeterSettings s) {
    _selected = List.of(s.indicators);
    _bandMode = s.bandMode;
    _fMin.text = _fmt(s.fMinHz);
    _fMax.text = _fmt(s.fMaxHz);
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final fMin = double.tryParse(_fMin.text.replaceAll(',', '.'));
    final fMax = double.tryParse(_fMax.text.replaceAll(',', '.'));
    if (fMin == null || fMax == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Въведете честотите като числа')));
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<UserData>().saveSettings(
            MeterSettings(indicators: _selected!, fMinHz: fMin, fMaxHz: fMax, bandMode: _bandMode),
          );
      messenger.showSnackBar(const SnackBar(content: Text('Настройките са запазени')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveOrganization() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<ApiClient>().put('/api/settings/organization', {
        'org_name': _orgName.text,
        'org_address': _orgAddress.text,
        'org_accreditation': _orgAccreditation.text,
      });
      messenger.showSnackBar(const SnackBar(content: Text('Данните за организацията са запазени')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<UserData>();
    if (_selected == null && data.settings != null) _initFrom(data.settings!);

    if (_loadError != null) return Center(child: Text(_loadError!));
    if (_selected == null || _available.isEmpty) return const Center(child: CircularProgressIndicator());

    final selected = _selected!;
    final theme = Theme.of(context);
    // Групиране по честотен филтър за по-лесен избор.
    final groups = {for (final fw in ['A', 'C', 'Z']) fw: _available.where((c) => c[1] == fw).toList()};

    return BandedListView(
      header: const BandTitle(subtitle: 'Показатели, интервал по подразбиране и данни за организацията'),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
        Text('Наблюдавани показатели', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Изберете поне $minIndicators. Избрани: ${selected.length}. '
          'Редът на избор определя реда на екрана за измерване.',
          style: theme.textTheme.bodySmall,
        ),
        for (final entry in groups.entries) ...[
          const SizedBox(height: 12),
          Text('Честотен филтър ${entry.key}', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final code in entry.value)
                FilterChip(
                  label: Text(indicatorName(code)),
                  selected: selected.contains(code),
                  onSelected: (on) => setState(() => on ? selected.add(code) : selected.remove(code)),
                ),
            ],
          ),
        ],
        const Divider(height: 32),
        Text('Измервателен интервал по подразбиране', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fMin,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'От', suffixText: 'Hz'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _fMax,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'До', suffixText: 'Hz'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Октавни ленти', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        BandModeSelector(value: _bandMode, onChanged: (v) => setState(() => _bandMode = v)),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy || selected.length < minIndicators ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Запази'),
        ),
        const Divider(height: 40),
        Text('Организация (за сертификатите)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(controller: _orgName, decoration: const InputDecoration(labelText: 'Наименование')),
        const SizedBox(height: 8),
        TextField(controller: _orgAddress, decoration: const InputDecoration(labelText: 'Адрес и контакти')),
        const SizedBox(height: 8),
        TextField(
          controller: _orgAccreditation,
          maxLines: null,
          decoration: const InputDecoration(
            labelText: 'Акредитация',
            hintText: 'Сертификат за акредитация рег. № ..., издаден от ИА БСА, съгласно БДС EN ISO/IEC 17025',
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _saveOrganization,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Запази данните за организацията'),
        ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class BandModeSelector extends StatelessWidget {
  const BandModeSelector({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'off', label: Text('Без')),
        ButtonSegment(value: '1/1', label: Text('1/1 окт.')),
        ButtonSegment(value: '1/3', label: Text('1/3 окт.')),
      ],
      selected: {value},
      onSelectionChanged: onChanged == null ? null : (s) => onChanged!(s.first),
    );
  }
}
