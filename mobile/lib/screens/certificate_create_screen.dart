import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/file_share.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import '../l10n/l10n.dart';

/// Издаване на сертификат от избрани измервания (изискване 8).
class CertificateCreateScreen extends StatefulWidget {
  const CertificateCreateScreen({super.key, required this.measurements});

  /// Измерванията, от които може да се избира (напр. от текущата справка).
  final List<Measurement> measurements;

  @override
  State<CertificateCreateScreen> createState() => _CertificateCreateScreenState();
}

class _CertificateCreateScreenState extends State<CertificateCreateScreen> {
  static final _dateTime = DateFormat('dd.MM.yyyy HH:mm');

  late final Set<int> _selected = {for (final m in _finished) m.id};
  final _title = TextEditingController();
  // Стандартите за метода на измерване (как се измерва) - по подразбиране ISO 1996.
  final _methods = TextEditingController(text: 'БДС ISO 1996-1:2016\nБДС ISO 1996-2:2018');
  final _normative = TextEditingController();
  final _remarks = TextEditingController();
  final _performedBy = TextEditingController();
  bool _busy = false;
  String? _error;

  List<Measurement> get _finished =>
      widget.measurements.where((m) => m.endedAt != null).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  @override
  void dispose() {
    for (final c in [_title, _methods, _normative, _remarks, _performedBy]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Стандартите на шумомера, по които са изчислени избраните измервания - сървърът ги вписва
  /// в т. 5 „Технически средства“.
  List<String> _standards(UserData data) {
    final fallback = data.defaultStandard?.name ?? 'IEC 61672-1';
    return {
      for (final m in _finished)
        if (_selected.contains(m.id)) m.standardName ?? fallback,
    }.toList();
  }

  static List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final json = await api.post('/api/certificates', {
        'measurement_ids': [for (final m in _finished) if (_selected.contains(m.id)) m.id],
        if (_title.text.trim().isNotEmpty) 'title': _title.text.trim(),
        if (_lines(_methods).isNotEmpty) 'methods': _lines(_methods),
        if (_lines(_normative).isNotEmpty) 'normative': _lines(_normative),
        if (_remarks.text.trim().isNotEmpty) 'remarks': _remarks.text.trim(),
        if (_lines(_performedBy).isNotEmpty) 'performed_by': _lines(_performedBy),
      });
      final cert = CertificateInfo.fromJson(json);
      await downloadAndOpen(api, '/api/certificates/${cert.id}/pdf', 'certificate_${cert.number}.pdf');
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = tr('Сертификатът е издаден, но не може да бъде отворен: {p0}', {'p0': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gap = SizedBox(height: 16);
    const groupGap = SizedBox(height: 24);
    final points = _finished;
    final standards = _standards(context.watch<UserData>());

    return Scaffold(
      appBar: bandAppBar(title: Text(tr('Нов сертификат'))),
      body: BandedListView(
        children: [
          TextField(
            onChanged: (_) => setState(() {}),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr('Обект / предмет *'),
              hintText: tr('напр. Шумомерен анализ - бул. Витоша 10'),
            ),
          ),
          gap,
          // Методи за измерване - стандартите, които описват как се измерва. Стандартът на
          // шумомера не е метод и се вписва автоматично в техническите средства.
          TextField(
            controller: _methods,
            maxLines: null,
            decoration: InputDecoration(
              labelText: tr('Методи за измерване (по един на ред)'),
              helperText: standards.isEmpty
                  ? null
                  : tr('Шумомерът ({p0}) се вписва в т. 5 „Технически средства“', {'p0': standards.join(', ')}),
              helperMaxLines: 3,
            ),
          ),
          gap,
          TextField(
            controller: _normative,
            maxLines: null,
            decoration: InputDecoration(
              labelText: tr('Нормативни изисквания (по един на ред)'),
              helperText: tr('Празно - автоматично'),
            ),
          ),
          groupGap,
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(tr('Изберете точки:'), style: sectionLabelStyle(context)),
          ),
          Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final m in points) _pointRow(m)],
            ),
          ),
          groupGap,
          TextField(
            controller: _remarks,
            minLines: 5,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Забележки'), alignLabelWithHint: true),
          ),
          gap,
          TextField(
            controller: _performedBy,
            maxLines: null,
            decoration: InputDecoration(
              labelText: tr('Извършил(и) измерването (по един на ред)'),
              helperText: tr('Празно - вашето име'),
            ),
          ),
          if (_error != null) ...[
            groupGap,
            InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
          ],
          groupGap,
          FilledButton(
            onPressed: _busy || _selected.isEmpty || _title.text.trim().isEmpty ? null : _create,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_selected.length == 1
                    ? tr('Издай сертификат (1 точка)')
                    : tr('Издай сертификат ({p0} точки)', {'p0': _selected.length})),
          ),
        ],
      ),
    );
  }

  /// Ред за избор на измерване: отметка, място, време, LA,eq и предупреждение при липсващи норми.
  Widget _pointRow(Measurement m) {
    final theme = Theme.of(context);
    final selected = _selected.contains(m.id);
    final noNorms = m.normDay == null && m.normEvening == null && m.normNight == null;
    void toggle(bool on) => setState(() => on ? _selected.add(m.id) : _selected.remove(m.id));
    return InkWell(
      onTap: () => toggle(!selected),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 2, 2),
        child: Row(
          children: [
            Checkbox(value: selected, onChanged: (v) => toggle(v == true)),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text([m.location ?? m.title, if (m.isSeries) m.pointLabel].join(' · '), style: theme.textTheme.bodyLarge),
                  Text(
                    _dateTime.format(m.startedAt),
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                  if (noNorms)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              tr('Точка без зададени норми'),
                              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatDb(m.summary['LAeq']),
              style: monoStyle(15, weight: FontWeight.w500, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}
