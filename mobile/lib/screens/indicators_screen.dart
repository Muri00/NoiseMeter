import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
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
      messenger.showSnackBar(SnackBar(content: Text(tr('Въведете честотите като числа'))));
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<UserData>().saveSettings(
            MeterSettings(indicators: _selected!, fMinHz: fMin, fMaxHz: fMax, bandMode: _bandMode),
          );
      messenger.showSnackBar(SnackBar(content: Text(tr('Настройките са запазени'))));
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
      messenger.showSnackBar(SnackBar(content: Text(tr('Данните за организацията са запазени'))));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static String _bandLabel(String mode) => switch (mode) {
        'off' => tr('Без'),
        '1/1' => tr('1/1 окт.'),
        _ => tr('1/3 окт.'),
      };

  String _intervalLabel() {
    final fMin = double.tryParse(_fMin.text.replaceAll(',', '.'));
    final fMax = double.tryParse(_fMax.text.replaceAll(',', '.'));
    if (fMin == null || fMax == null) return '${_fMin.text} – ${_fMax.text} Hz';
    return '${formatHz(fMin)} – ${formatHz(fMax)}';
  }

  Future<void> _pickBandMode() async {
    final mode = await showChoiceSheet<String>(
      context,
      title: tr('Октавни ленти'),
      options: [for (final m in ['off', '1/1', '1/3']) (m, _bandLabel(m), null)],
      selected: _bandMode,
    );
    if (mode != null) setState(() => _bandMode = mode);
  }

  /// Долен лист с полета "От" и "До"; стойностите се проверяват при запазване.
  Future<void> _editInterval() async {
    final from = TextEditingController(text: _fMin.text);
    final to = TextEditingController(text: _fMax.text);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Интервал'), style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: from,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('От'), suffixText: 'Hz'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: to,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('До'), suffixText: 'Hz'),
                    onSubmitted: (_) => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Готово'))),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _fMin.text = from.text.trim();
        _fMax.text = to.text.trim();
      });
    }
    from.dispose();
    to.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<UserData>();
    if (_selected == null && data.settings != null) _initFrom(data.settings!);

    if (_loadError != null) {
      return BandedListView(
        children: [InfoBanner(message: _loadError!, color: AppColors.danger, icon: Icons.error_outline)],
      );
    }
    if (_selected == null || _available.isEmpty) return const Center(child: CircularProgressIndicator());

    final selected = _selected!;
    final theme = Theme.of(context);
    // Групиране по честотен филтър за по-лесен избор.
    final groups = {
      tr('Без честотен и времеви филтър'): _available.where(unweightedIndicators.contains).toList(),
      for (final fw in ['A', 'C', 'Z'])
        tr('Честотен филтър {fw}', {'fw': fw}): _available.where((c) => c.length > 1 && c[1] == fw).toList(),
    };
    final groupLabel = theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);

    final title = sectionLabelStyle(context);

    return BandedListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          child: Text(tr('Избрани показатели (мин. {p0})', {'p0': minIndicators}), style: title),
        ),
        for (final (i, entry) in groups.entries.where((e) => e.value.isNotEmpty).indexed) ...[
          if (i > 0) const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(entry.key, style: groupLabel),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in entry.value)
                Tooltip(
                  message: indicatorDescription(code),
                  triggerMode: TooltipTriggerMode.longPress,
                  child: _CheckChip(
                    label: indicatorName(code),
                    selected: selected.contains(code),
                    onChanged: (on) => setState(() => on ? selected.add(code) : selected.remove(code)),
                  ),
                ),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
          child: Text(
            tr('Избрани: {p1} (мин. {p0})', {'p0': minIndicators, 'p1': selected.length}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: selected.length < minIndicators ? AppColors.danger : AppColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: 24),
        RowGroup(
          title: tr('Параметри по подразбиране'),
          children: [
            ValueRow(label: tr('Интервал'), value: _intervalLabel(), onTap: _editInterval),
            ValueRow(label: tr('Октавни ленти'), value: _bandLabel(_bandMode), onTap: _pickBandMode),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || selected.length < minIndicators ? null : _save,
          child: Text(tr('Запази')),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          child: Text(tr('Данни за организацията'), style: title),
        ),
        TextField(controller: _orgName, decoration: InputDecoration(labelText: tr('Наименование'))),
        const SizedBox(height: 12),
        TextField(controller: _orgAddress, decoration: InputDecoration(labelText: tr('Адрес и контакти'))),
        const SizedBox(height: 12),
        TextField(
          controller: _orgAccreditation,
          minLines: 3,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: tr('Акредитация'),
            alignLabelWithHint: true,
            hintText: tr('Сертификат за акредитация рег. № ..., издаден от ИА БСА, съгласно БДС EN ISO/IEC 17025'),
            hintMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _saveOrganization,
          child: Text(tr('Запази данните за организацията')),
        ),
      ],
    );
  }
}

/// Показател за избор: светлосив заоблен правоъгълник с отметка и кода (както на екрана "Измерване").
class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.label, required this.selected, required this.onChanged});

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!selected),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: selected,
                onChanged: (v) => onChanged(v ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Text(label, style: monoStyle(14, weight: FontWeight.w500, color: AppColors.ink)),
            ],
          ),
        ),
      ),
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
      segments: [
        ButtonSegment(value: 'off', label: Text(tr('Без'))),
        ButtonSegment(value: '1/1', label: Text(tr('1/1 окт.'))),
        ButtonSegment(value: '1/3', label: Text(tr('1/3 окт.'))),
      ],
      selected: {value},
      onSelectionChanged: onChanged == null ? null : (s) => onChanged!(s.first),
    );
  }
}
