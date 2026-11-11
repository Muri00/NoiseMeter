import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import '../l10n/l10n.dart';

/// Форма за автоматична или ръчна калибровка. Връща true, ако е създадена калибровка.
class CalibrationFormScreen extends StatefulWidget {
  const CalibrationFormScreen({super.key, required this.device, required this.automatic});

  final Device device;
  final bool automatic;

  @override
  State<CalibrationFormScreen> createState() => _CalibrationFormScreenState();
}

class _CalibrationFormScreenState extends State<CalibrationFormScreen> {
  final _form = GlobalKey<FormState>();
  final _c = {
    for (final k in [
      'reference_level_db', 'reference_freq_hz', 'duration_s', 'measured_level_db', 'offset_db',
      'calibrator_brand', 'calibrator_model', 'calibrator_serial', 'calibrator_certificate',
      'temperature_c', 'humidity_pct', 'pressure_kpa', 'uncertainty_db', 'notes',
    ])
      k: TextEditingController(),
  };

  // Ръчна калибровка: по показание на уреда или директно въвеждане на корекция.
  bool _byReading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c['reference_level_db']!.text = '94';
    _c['reference_freq_hz']!.text = '1000';
    _c['duration_s']!.text = '5';
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(String key) => double.tryParse(_c[key]!.text.trim().replaceAll(',', '.'));

  String? _text(String key) {
    final v = _c[key]!.text.trim();
    return v.isEmpty ? null : v;
  }

  Map<String, dynamic> _meta() => {
        for (final k in ['calibrator_brand', 'calibrator_model', 'calibrator_serial', 'calibrator_certificate', 'notes'])
          if (_text(k) != null) k: _text(k),
        for (final k in ['temperature_c', 'humidity_pct', 'pressure_kpa', 'uncertainty_db'])
          if (_num(k) != null) k: _num(k),
      };

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    final base = '/api/devices/${widget.device.id}/calibrations';
    try {
      if (widget.automatic) {
        final duration = _num('duration_s')!;
        final json = await api.postLong('$base/auto', {
          ..._meta(),
          'reference_level_db': _num('reference_level_db'),
          'reference_freq_hz': _num('reference_freq_hz'),
          'duration_s': duration,
        }, Duration(seconds: duration.ceil() + 30));
        if (!mounted) return;
        await _confirmAuto(api, base, Calibration.fromJson(json));
      } else {
        await api.post('$base/manual', {
          ..._meta(),
          if (_byReading) ...{
            'reference_level_db': _num('reference_level_db'),
            'reference_freq_hz': _num('reference_freq_hz'),
            'measured_level_db': _num('measured_level_db'),
          } else
            'offset_db': _num('offset_db'),
        });
        if (mounted) Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Показва резултата от автоматичната калибровка и пита дали да се приложи.
  Future<void> _confirmAuto(ApiClient api, String base, Calibration c) async {
    final bigDrift = (c.driftDb ?? 0).abs() > 1.0;
    final apply = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Резултат от калибровката')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Еталон: {p0} dB @ {p1}', {'p0': c.referenceLevelDb, 'p1': formatHz(c.referenceFreqHz ?? 1000)})),
            Text(tr('Измерено (без корекция): {p0} dB', {'p0': c.measuredLevelDb?.toStringAsFixed(2)})),
            Text(tr('Честота на тона: {p0} Hz', {'p0': c.measuredFreqHz?.toStringAsFixed(1)})),
            Text(tr('Стабилност (σ): {p0} dB', {'p0': c.stabilityDb?.toStringAsFixed(3)})),
            const Divider(),
            Text(tr('Нова корекция: {p0} dB', {'p0': '${c.offsetDb >= 0 ? '+' : ''}${c.offsetDb.toStringAsFixed(2)}'}),
                style: monoStyle(15, weight: FontWeight.w500)),
            Text(tr('Промяна спрямо текущата: {p0} dB', {'p0': c.driftDb?.toStringAsFixed(2)})),
            if (bigDrift) ...[
              const SizedBox(height: 8),
              Text(
                tr('Промяната е над 1 dB. Проверете чувствителността на устройството и калибратора, '
                'преди да приложите корекцията.'),
                style: const TextStyle(color: AppColors.warning),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отхвърли'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Приложи'))),
        ],
      ),
    );
    await api.post('$base/${c.id}/${apply == true ? 'apply' : 'reject'}', {});
    if (mounted) Navigator.of(context).pop(true);
  }

  String? Function(String?) _range(double min, double max, {bool required = false}) => (v) {
        if (v == null || v.trim().isEmpty) return required ? tr('Задължително поле') : null;
        final n = double.tryParse(v.trim().replaceAll(',', '.'));
        if (n == null) return tr('Въведете число');
        if (n < min || n > max) return tr('Между {p0} и {p1}', {'p0': _fmt(min), 'p1': _fmt(max)});
        return null;
      };

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Widget _field(String key, String label,
      {String? suffix, String? Function(String?)? validator, String? helper, bool number = true, int? minLines}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _c[key],
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : (minLines != null ? TextInputType.multiline : TextInputType.text),
        minLines: minLines,
        maxLines: minLines == null ? 1 : null,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          helperText: helper,
          helperMaxLines: 3,
          alignLabelWithHint: minLines != null,
        ),
        validator: validator,
      ),
    );
  }

  /// Секция: удебелено заглавие и полетата направо на фона.
  Widget _section(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
            child: Text(title, style: sectionLabelStyle(context)),
          ),
          ...children,
        ],
      );

  /// Бутон-хапче за избор: избраният е запълнен, другият - с контур.
  Widget _choice(String label, bool selected, VoidCallback onTap) => selected
      ? FilledButton(onPressed: onTap, child: Text(label))
      : OutlinedButton(onPressed: onTap, child: Text(label));

  Widget _pair(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auto = widget.automatic;
    final showReference = auto || _byReading;
    // Полетата завършват с отстъп 12, така между секциите остават 24.
    const sectionGap = SizedBox(height: 12);

    return Scaffold(
      appBar: AppBar(
        title: Text(auto ? tr('Автоматична калибровка') : tr('Ръчна калибровка')),
        titleTextStyle: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            ReadableWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.device.title, style: sectionLabelStyle(context)),
                  Text('S/N ${widget.device.serialNumber}', style: monoStyle(14, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  if (auto) ...[
                    InfoBanner(icon: Icons.mic_none_rounded, message: tr('Поставете микрофона в калибратора и го включете.')),
                    const SizedBox(height: 24),
                  ],
                  if (!auto) ...[
                    Row(
                      children: [
                        Expanded(child: _choice(tr('По показание'), _byReading, () => setState(() => _byReading = true))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _choice(tr('Директна корекция'), !_byReading, () => setState(() => _byReading = false)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (showReference)
                    _section(tr('Еталон'), [
                      _pair(
                        _field('reference_level_db', tr('Ниво на калибратора *'), suffix: 'dB', validator: _range(70, 140, required: true)),
                        _field('reference_freq_hz', tr('Честота'), suffix: 'Hz', validator: _range(100, 10000, required: auto)),
                      ),
                      if (auto)
                        _field('duration_s', tr('Продължителност на записа'), suffix: 's', validator: _range(2, 30, required: true)),
                      if (!auto)
                        _field(
                          'measured_level_db', tr('Показание на уреда *'), suffix: 'dB',
                          validator: _range(0, 160, required: true),
                          helper: tr('LZ,eq от екрана „Измерване“'),
                        ),
                    ])
                  else
                    _section(tr('Корекция'), [
                      _field('offset_db', tr('Корекция *'), suffix: 'dB', validator: _range(-30, 30, required: true)),
                    ]),
                  sectionGap,
                  _section(tr('Калибратор'), [
                    _pair(_field('calibrator_brand', tr('Марка'), number: false), _field('calibrator_model', tr('Модел'), number: false)),
                    _pair(
                      _field('calibrator_serial', tr('Сериен №'), number: false),
                      _field('calibrator_certificate', tr('№ на сертификат'), number: false),
                    ),
                  ]),
                  sectionGap,
                  _section(tr('Условия на средата'), [
                    _pair(
                      _field('temperature_c', tr('Температура'), suffix: '°C', validator: _range(-20, 60)),
                      _field('humidity_pct', tr('Влажност'), suffix: '%', validator: _range(0, 100)),
                    ),
                    _pair(
                      _field('pressure_kpa', tr('Налягане'), suffix: 'kPa', validator: _range(50, 120)),
                      _field('uncertainty_db', tr('Неопределеност (k=2)'), suffix: 'dB', validator: _range(0, 5)),
                    ),
                    _field('notes', tr('Бележки'), number: false, minLines: 4),
                  ]),
                  sectionGap,
                  if (_error != null) ...[
                    InfoBanner(message: _error!, color: AppColors.danger, icon: Icons.error_outline),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(auto ? Icons.play_arrow_rounded : Icons.save_outlined),
                    label: Text(_busy && auto ? tr('Записване от калибратора…') : (auto ? tr('Започни') : tr('Запази'))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
