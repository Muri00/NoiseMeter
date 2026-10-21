import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';

/// Място, източник и норми на измерването - използват се в Excel и в сертификата.
/// Връща true, ако е записано.
class MeasurementPlaceScreen extends StatefulWidget {
  const MeasurementPlaceScreen({super.key, required this.measurement});

  final Measurement measurement;

  @override
  State<MeasurementPlaceScreen> createState() => _MeasurementPlaceScreenState();
}

class _MeasurementPlaceScreenState extends State<MeasurementPlaceScreen> {
  static const custom = 'custom';

  late final _name = TextEditingController(text: widget.measurement.name);
  late final _location = TextEditingController(text: widget.measurement.location);
  late final _source = TextEditingController(text: widget.measurement.source);
  late final _day = TextEditingController(text: _fmt(widget.measurement.normDay));
  late final _evening = TextEditingController(text: _fmt(widget.measurement.normEvening));
  late final _night = TextEditingController(text: _fmt(widget.measurement.normNight));
  late String? _zone = widget.measurement.zoneCode;
  List<Zone> _zones = [];
  bool _busy = false;
  String? _error;

  static String _fmt(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void initState() {
    super.initState();
    context.read<ApiClient>().get('/api/norms/zones').then((list) {
      if (mounted) setState(() => _zones = (list as List).map((j) => Zone.fromJson(j)).toList());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_name, _location, _source, _day, _evening, _night]) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectZone(String? code) {
    setState(() => _zone = code);
    final zone = _zones.where((z) => z.code == code).firstOrNull;
    if (zone != null) {
      _day.text = _fmt(zone.day);
      _evening.text = _fmt(zone.evening);
      _night.text = _fmt(zone.night);
    }
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().patch('/api/measurements/${widget.measurement.id}', {
        'name': _name.text,
        'location': _location.text,
        'source': _source.text,
        'zone_code': _zone,
        'norm_day': _num(_day),
        'norm_evening': _num(_evening),
        'norm_night': _num(_night),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    Widget norm(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, suffixText: 'dB(A)'),
            // Ръчна промяна на норма означава собствени норми.
            onChanged: (_) => setState(() => _zone = _zone == null ? null : custom),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Място и норми')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Наименование')),
          gap,
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Точка / място на измерване', hintText: 'т. 1, бул. Витоша 10'),
          ),
          gap,
          TextField(
            controller: _source,
            decoration: const InputDecoration(labelText: 'Източник / режим', hintText: 'Автомобилен трафик'),
          ),
          const SizedBox(height: 20),
          Text('Гранични стойности (Наредба № 6/2006)', style: Theme.of(context).textTheme.titleSmall),
          gap,
          DropdownButtonFormField<String?>(
            initialValue: _zone,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Зона'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Без норма')),
              for (final z in _zones)
                DropdownMenuItem(value: z.code, child: Text('${z.code}. ${z.name}', overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(value: custom, child: Text('Собствени норми')),
            ],
            onChanged: _selectZone,
          ),
          gap,
          Row(children: [norm(_day, 'Ден'), const SizedBox(width: 8), norm(_evening, 'Вечер'), const SizedBox(width: 8), norm(_night, 'Нощ')]),
          const SizedBox(height: 8),
          Text(
            'Ден 07–19 ч, вечер 19–23 ч, нощ 23–07 ч. Стойностите от таблицата сверете с действащата редакция на наредбата.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            gap,
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Запази')),
        ],
      ),
    );
  }
}
