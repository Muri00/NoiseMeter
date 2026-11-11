import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../widgets/ui.dart';

/// Място, зона, период и норми на записано измерване. Отваря се само от администратор:
/// обикновеният потребител задава тези данни при самото измерване и не може да ги променя.
/// Връща true, ако е записано.
class MeasurementPlaceScreen extends StatefulWidget {
  const MeasurementPlaceScreen({super.key, required this.measurement});

  final Measurement measurement;

  @override
  State<MeasurementPlaceScreen> createState() => _MeasurementPlaceScreenState();
}

class _MeasurementPlaceScreenState extends State<MeasurementPlaceScreen> {
  late final _name = TextEditingController(text: widget.measurement.name);
  late final _location = TextEditingController(text: widget.measurement.location);
  late final _source = TextEditingController(text: widget.measurement.source);
  late final _day = TextEditingController(text: _fmt(widget.measurement.normDay));
  late final _evening = TextEditingController(text: _fmt(widget.measurement.normEvening));
  late final _night = TextEditingController(text: _fmt(widget.measurement.normNight));
  late String? _zone = widget.measurement.zoneCode;
  late String? _period = widget.measurement.period;
  late String _placeType = widget.measurement.placeType ?? 'indoor';
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
    _day.text = _fmt(zone?.day);
    _evening.text = _fmt(zone?.evening);
    _night.text = _fmt(zone?.night);
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
        'place_type': _placeType,
        'source': _source.text,
        'zone_code': _zone,
        'period': _period,
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
    final theme = Theme.of(context);
    Widget norm(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, suffixText: 'dB(A)'),
          ),
        );

    return Scaffold(
      appBar: bandAppBar(),
      body: BandedListView(
        header: BandTitle(
          title: tr('Място и норми'),
        ),
        children: [
          SectionCard(
            title: tr('Място на измерване'),
            icon: Icons.place_outlined,
            child: Column(
              children: [
                TextField(controller: _name, decoration: InputDecoration(labelText: tr('Наименование'))),
                gap,
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'indoor', label: Text(tr('Закрито помещение'))),
                      ButtonSegment(value: 'outdoor', label: Text(tr('Открито място'))),
                    ],
                    selected: {_placeType},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _placeType = v.first),
                  ),
                ),
                gap,
                TextField(
                  controller: _location,
                  decoration: InputDecoration(labelText: tr('Място на измерване'), hintText: tr('Зала 2, бул. Витоша 10')),
                ),
                gap,
                TextField(
                  controller: _source,
                  decoration: InputDecoration(labelText: tr('Източник / режим'), hintText: tr('Автомобилен трафик')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('Норми (Наредба № 6/2006)'),
            icon: Icons.rule_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: _zones.any((z) => z.code == _zone) ? _zone : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Зона')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('Без норма'))),
                    for (final z in _zones.where((z) => z.category == _placeType || z.code == _zone))
                      DropdownMenuItem(
                        value: z.code,
                        child: Text('${z.category == 'indoor' ? '${tr('Помещение')}: ' : '${z.code}. '}${z.name}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _selectZone,
                ),
                gap,
                DropdownButtonFormField<String?>(
                  initialValue: _period,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Период от денонощието')),
                  items: [for (final p in [null, ...periods]) DropdownMenuItem(value: p, child: Text(periodName(p)))],
                  onChanged: (v) => setState(() => _period = v),
                ),
                gap,
                Row(children: [
                  norm(_day, tr('Ден')),
                  const SizedBox(width: 8),
                  norm(_evening, tr('Вечер')),
                  const SizedBox(width: 8),
                  norm(_night, tr('Нощ')),
                ]),
              ],
            ),
          ),
          if (_error != null) ...[
            gap,
            InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Запази'))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
