import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';

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
        title: const Text('Резултат от калибровката'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Еталон: ${c.referenceLevelDb} dB @ ${formatHz(c.referenceFreqHz ?? 1000)}'),
            Text('Измерено (без корекция): ${c.measuredLevelDb?.toStringAsFixed(2)} dB'),
            Text('Честота на тона: ${c.measuredFreqHz?.toStringAsFixed(1)} Hz'),
            Text('Стабилност (σ): ${c.stabilityDb?.toStringAsFixed(3)} dB'),
            const Divider(),
            Text('Нова корекция: ${c.offsetDb >= 0 ? '+' : ''}${c.offsetDb.toStringAsFixed(2)} dB',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Промяна спрямо текущата: ${c.driftDb?.toStringAsFixed(2)} dB'),
            if (bigDrift) ...[
              const SizedBox(height: 8),
              const Text(
                'Промяната е над 1 dB. Проверете чувствителността на устройството и калибратора, '
                'преди да приложите корекцията.',
                style: TextStyle(color: Colors.orange),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отхвърли')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Приложи')),
        ],
      ),
    );
    await api.post('$base/${c.id}/${apply == true ? 'apply' : 'reject'}', {});
    if (mounted) Navigator.of(context).pop(true);
  }

  String? Function(String?) _range(double min, double max, {bool required = false}) => (v) {
        if (v == null || v.trim().isEmpty) return required ? 'Задължително поле' : null;
        final n = double.tryParse(v.trim().replaceAll(',', '.'));
        if (n == null) return 'Въведете число';
        if (n < min || n > max) return 'Между ${_fmt(min)} и ${_fmt(max)}';
        return null;
      };

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Widget _field(String key, String label, {String? suffix, String? Function(String?)? validator, String? helper, bool number = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _c[key],
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: helper, helperMaxLines: 3),
        validator: validator,
      ),
    );
  }

  Widget _pair(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auto = widget.automatic;
    final showReference = auto || _byReading;

    return Scaffold(
      appBar: AppBar(title: Text(auto ? 'Автоматична калибровка' : 'Ръчна калибровка')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${widget.device.title}, S/N ${widget.device.serialNumber}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              auto
                  ? 'Поставете микрофона в акустичния калибратор и го включете. Сървърът записва сигнала, '
                      'проверява честотата и стабилността и изчислява корекцията. '
                      'Корекцията се прилага едва след потвърждение.'
                  : 'Корекцията се прилага веднага и се записва в протокол.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (!auto) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('По показание')),
                  ButtonSegment(value: false, label: Text('Директна корекция')),
                ],
                selected: {_byReading},
                onSelectionChanged: (s) => setState(() => _byReading = s.first),
              ),
              const SizedBox(height: 16),
            ],
            if (showReference) ...[
              Text('Еталон', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _pair(
                _field('reference_level_db', 'Ниво на калибратора *', suffix: 'dB', validator: _range(70, 140, required: true)),
                _field('reference_freq_hz', 'Честота', suffix: 'Hz', validator: _range(100, 10000, required: auto)),
              ),
            ],
            if (auto) _field('duration_s', 'Продължителност на записа', suffix: 's', validator: _range(2, 30, required: true)),
            if (!auto && _byReading)
              _field(
                'measured_level_db', 'Показание на уреда *', suffix: 'dB',
                validator: _range(0, 160, required: true),
                helper: 'Пуснете "Измерване" с микрофона в калибратора и въведете показаното LZ,eq (или LA,eq при 1 kHz).',
              ),
            if (!auto && !_byReading)
              _field(
                'offset_db', 'Корекция *', suffix: 'dB', validator: _range(-30, 30, required: true),
                helper: 'Напр. от сертификат за калибровка от акредитирана лаборатория.',
              ),
            Text('Калибратор', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _pair(_field('calibrator_brand', 'Марка', number: false), _field('calibrator_model', 'Модел', number: false)),
            _pair(
              _field('calibrator_serial', 'Сериен №', number: false),
              _field('calibrator_certificate', '№ на сертификат', number: false),
            ),
            Text('Условия на средата', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _pair(
              _field('temperature_c', 'Температура', suffix: '°C', validator: _range(-20, 60)),
              _field('humidity_pct', 'Влажност', suffix: '%', validator: _range(0, 100)),
            ),
            _pair(
              _field('pressure_kpa', 'Налягане', suffix: 'kPa', validator: _range(50, 120)),
              _field('uncertainty_db', 'Неопределеност (k=2)', suffix: 'dB', validator: _range(0, 5)),
            ),
            _field('notes', 'Бележки', number: false),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(auto ? Icons.play_arrow : Icons.save_outlined),
              label: Text(_busy && auto ? 'Записване от калибратора…' : (auto ? 'Започни' : 'Запази')),
            ),
          ],
        ),
      ),
    );
  }
}
