import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import '../l10n/l10n.dart';

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
  bool _busy = false;
  String? _error;

  static String _num(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  static double? _parse(String? v) => double.tryParse((v ?? '').trim().replaceAll(',', '.'));

  @override
  void dispose() {
    for (final c in [_brand, _model, _serial, _sensitivity, _fMin, _fMax]) {
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
          ));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Изтриване на редактираното устройство (същото като задържане на реда в списъка).
  Future<void> _delete(Device d) async {
    final data = context.read<UserData>();
    final navigator = Navigator.of(context);
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await data.deleteDevice(d);
      navigator.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? tr('Задължително поле') : null;

  String? _frequency(String? v) {
    final f = _parse(v);
    if (f == null) return tr('Въведете число');
    if (f < absFMinHz || f > absFMaxHz) return tr('Между {p0} и {p1} Hz', {'p0': absFMinHz.toInt(), 'p1': absFMaxHz.toInt()});
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    const groupGap = SizedBox(height: 24);
    final numberKeyboard = const TextInputType.numberWithOptions(decimal: true, signed: true);
    final numberFilter = [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))];
    final device = widget.device;

    Widget sectionTitle(String text) => Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(text, style: sectionLabelStyle(context)),
        );

    return Scaffold(
      appBar: bandAppBar(
        title: Text(device == null ? tr('Ново устройство') : tr('Редакция на устройство')),
        actions: [
          if (device != null)
            IconButton(
              tooltip: tr('Изтрий'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _busy ? null : () => _delete(device),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _form,
        child: BandedListView(
          children: [
            sectionTitle(tr('Устройство')),
            TextFormField(
              controller: _brand,
              decoration: InputDecoration(labelText: tr('Марка *'), hintText: 'miniDSP'),
              validator: _required,
            ),
            gap,
            TextFormField(
              controller: _model,
              decoration: InputDecoration(labelText: tr('Модел *'), hintText: 'UMIK-1'),
              validator: _required,
            ),
            gap,
            TextFormField(
              controller: _serial,
              decoration: InputDecoration(labelText: tr('Сериен номер *')),
              validator: _required,
            ),
            groupGap,
            sectionTitle(tr('Чувствителност')),
            TextFormField(
              controller: _sensitivity,
              keyboardType: numberKeyboard,
              inputFormatters: numberFilter,
              decoration: InputDecoration(
                labelText: tr('Чувствителност *'),
                suffixText: 'dBFS',
                helperText: tr('При 94 dB SPL, напр. -18'),
              ),
              validator: (v) {
                final s = _parse(v);
                if (s == null) return tr('Въведете число');
                if (s < -80 || s > 0) return tr('Между -80 и 0 dBFS');
                return null;
              },
            ),
            groupGap,
            sectionTitle(tr('Работна честотна лента')),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _fMin,
                    keyboardType: numberKeyboard,
                    inputFormatters: numberFilter,
                    decoration: InputDecoration(labelText: tr('Мин. честота *'), suffixText: 'Hz'),
                    validator: _frequency,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _fMax,
                    keyboardType: numberKeyboard,
                    inputFormatters: numberFilter,
                    decoration: InputDecoration(labelText: tr('Макс. честота *'), suffixText: 'Hz'),
                    validator: (v) {
                      final err = _frequency(v);
                      if (err != null) return err;
                      final min = _parse(_fMin.text);
                      if (min != null && _parse(v)! <= min) return tr('Трябва да е > мин.');
                      return null;
                    },
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              groupGap,
              InfoBanner(message: _error!, color: AppColors.danger, icon: Icons.error_outline),
            ],
            groupGap,
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr('Запази')),
            ),
          ],
        ),
      ),
    );
  }
}
