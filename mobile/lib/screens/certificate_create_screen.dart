import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/file_share.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

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
        'methods': _lines(_methods),
        if (_lines(_normative).isNotEmpty) 'normative': _lines(_normative),
        if (_remarks.text.trim().isNotEmpty) 'remarks': _remarks.text.trim(),
        if (_lines(_performedBy).isNotEmpty) 'performed_by': _lines(_performedBy),
      });
      final cert = CertificateInfo.fromJson(json);
      await downloadAndShare(api, '/api/certificates/${cert.id}/pdf', 'certificate_${cert.number}.pdf');
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Сертификатът е издаден, но не може да бъде споделен: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gap = SizedBox(height: 12);
    final missingNorms = _finished
        .where((m) => _selected.contains(m.id) && m.normDay == null && m.normEvening == null && m.normNight == null)
        .length;

    return Scaffold(
      appBar: bandAppBar(),
      body: BandedListView(
        header: const BandTitle(
          title: 'Нов сертификат',
          subtitle: 'Генериране на PDF протокол от измерване',
        ),
        children: [
          SectionCard(
            title: 'Общи данни',
            subtitle: 'Номерът и датата се задават автоматично',
            icon: Icons.description_outlined,
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Обект / предмет (по желание)',
                    hintText: 'напр. Шумомерен анализ - бул. Витоша 10',
                  ),
                ),
                gap,
                TextField(
                  controller: _methods,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: 'Методи за измерване (по един на ред)'),
                ),
                gap,
                TextField(
                  controller: _normative,
                  maxLines: null,
                  decoration: const InputDecoration(
                    labelText: 'Нормативни изисквания (по един на ред)',
                    helperText: 'Празно - автоматично: Наредба № 6/2006, Прил. 2, табл. 2 и точките на зоните',
                    helperMaxLines: 2,
                  ),
                ),
              ],
            ),
          ),
          if (missingNorms > 0) ...[
            const SizedBox(height: 16),
            InfoBanner(
              message: '$missingNorms от избраните измервания нямат зададени гранични стойности '
                  '(ден/вечер/нощ). Това ще се отрази в заключението на сертификата.',
              color: AppColors.warning,
              icon: Icons.warning_amber_rounded,
            ),
          ],
          const SizedBox(height: 16),
          SectionCard(
            title: 'Избор на точки',
            subtitle: 'Всяко избрано измерване е ред в таблицата с резултати',
            icon: Icons.checklist_rounded,
            child: Column(
              children: [
                for (final m in _finished) ...[
                  _pointCard(m),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Допълнително',
            icon: Icons.edit_note_rounded,
            child: Column(
              children: [
                TextField(controller: _remarks, maxLines: null, decoration: const InputDecoration(labelText: 'Забележки')),
                gap,
                TextField(
                  controller: _performedBy,
                  maxLines: null,
                  decoration: const InputDecoration(
                    labelText: 'Извършил(и) измерването (по един на ред)',
                    helperText: 'Празно - вашето име',
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy || _selected.isEmpty ? null : _create,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text('Издай сертификат (${_selected.length} ${_selected.length == 1 ? 'точка' : 'точки'})'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Карта за избор на измерване: отметка, място, време и LA,eq.
  Widget _pointCard(Measurement m) {
    final theme = Theme.of(context);
    final selected = _selected.contains(m.id);
    final noNorms = m.normDay == null && m.normEvening == null && m.normNight == null;
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.06) : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => selected ? _selected.remove(m.id) : _selected.add(m.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (v) => setState(() => v == true ? _selected.add(m.id) : _selected.remove(m.id)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.location ?? m.title, style: theme.textTheme.titleSmall),
                    Text(
                      '${_dateTime.format(m.startedAt)}${noNorms ? ' · без норма' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: noNorms ? AppColors.warning : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatDb(m.summary['LAeq']),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.forLevel(m.summary['LAeq']),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
