import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/user_data.dart';

/// Добавяне / редакция на входно устройство (изискване 2).
class DeviceFormScreen extends StatefulWidget {
  const DeviceFormScreen({super.key, this.device});

  final Device? device;

  @override
  State<DeviceFormScreen> createState() => _DeviceFormScreenState();
}

class _DeviceFormScreenState extends State<DeviceFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _brand = TextEditingController(text: widget.device?.brand);
  late final _model = TextEditingController(text: widget.device?.model);
  late final _serial = TextEditingController(text: widget.device?.serialNumber);
  late final _sensitivity = TextEditingController(text: _num(widget.device?.sensitivityDbfs));
  late final _fMin = TextEditingController(text: _num(widget.device?.freqMinHz ?? 20));
  late final _fMax = TextEditingController(text: _num(widget.device?.freqMaxHz ?? 20000));
  late final _interval = TextEditingController(
    text: widget.device == null ? '12' : (widget.device!.calibrationIntervalMonths?.toString() ?? ''),
  );
  bool _busy = false;
  String? _error;

  static String _num(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  static double? _parse(String? v) => double.tryParse((v ?? '').trim().replaceAll(',', '.'));

  @override
  void dispose() {
    for (final c in [_brand, _model, _serial, _sensitivity, _fMin, _fMax, _interval]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<UserData>().saveDevice(Device(
            id: widget.device?.id,
            brand: _brand.text.trim(),
            model: _model.text.trim(),
            serialNumber: _serial.text.trim(),
            sensitivityDbfs: _parse(_sensitivity.text)!,
            freqMinHz: _parse(_fMin.text)!,
            freqMaxHz: _parse(_fMax.text)!,
            calibrationIntervalMonths: int.tryParse(_interval.text.trim()),
          ));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Задължително поле' : null;

  String? _frequency(String? v) {
    final f = _parse(v);
    if (f == null) return 'Въведете число';
    if (f < absFMinHz || f > absFMaxHz) return 'Между ${absFMinHz.toInt()} и ${absFMaxHz.toInt()} Hz';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    final numberKeyboard = const TextInputType.numberWithOptions(decimal: true, signed: true);
    final numberFilter = [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))];

    return Scaffold(
      appBar: AppBar(title: Text(widget.device == null ? 'Ново устройство' : 'Редакция на устройство')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _brand,
                decoration: const InputDecoration(labelText: 'Марка *', hintText: 'miniDSP'),
                validator: _required,
              ),
              gap,
              TextFormField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'Модел *', hintText: 'UMIK-1'),
                validator: _required,
              ),
              gap,
              TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'Сериен номер *'), validator: _required),
              gap,
              TextFormField(
                controller: _sensitivity,
                keyboardType: numberKeyboard,
                inputFormatters: numberFilter,
                decoration: const InputDecoration(
                  labelText: 'Чувствителност *',
                  suffixText: 'dBFS',
                  helperText: 'Ниво на цифровия сигнал при 94 dB SPL (1 Pa), напр. -18',
                  helperMaxLines: 2,
                ),
                validator: (v) {
                  final s = _parse(v);
                  if (s == null) return 'Въведете число';
                  if (s < -80 || s > 0) return 'Между -80 и 0 dBFS';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text('Работна честотна лента', style: Theme.of(context).textTheme.titleSmall),
              gap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fMin,
                      keyboardType: numberKeyboard,
                      inputFormatters: numberFilter,
                      decoration: const InputDecoration(labelText: 'Мин. честота *', suffixText: 'Hz'),
                      validator: _frequency,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _fMax,
                      keyboardType: numberKeyboard,
                      inputFormatters: numberFilter,
                      decoration: const InputDecoration(labelText: 'Макс. честота *', suffixText: 'Hz'),
                      validator: (v) {
                        final err = _frequency(v);
                        if (err != null) return err;
                        final min = _parse(_fMin.text);
                        if (min != null && _parse(v)! <= min) return 'Трябва да е > мин.';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Калибровка', style: Theme.of(context).textTheme.titleSmall),
              gap,
              TextFormField(
                controller: _interval,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Интервал между калибровките',
                  suffixText: 'месеца',
                  helperText: 'Срокът за следваща калибровка се смята от последната. Празно - без срок.',
                  helperMaxLines: 2,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 1 || n > 120) return 'Между 1 и 120 месеца';
                  return null;
                },
              ),
              if (_error != null) ...[
                gap,
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Запази'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
