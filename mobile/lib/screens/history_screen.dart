import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/file_share.dart';
import '../widgets/charts.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'certificate_create_screen.dart';
import 'measurement_detail_screen.dart';

/// Справки от историята за период от 24 часа до 3 месеца назад (изискване 5).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

enum _Preset { day, week, month, quarter, custom }

class _HistoryScreenState extends State<HistoryScreen> {
  static const maxDays = 92;
  static final _dateTime = DateFormat('dd.MM.yyyy HH:mm');
  static final _date = DateFormat('dd.MM.yyyy');

  _Preset _preset = _Preset.day;
  DateTimeRange? _custom;
  HistoryReport? _report;
  String? _error;
  bool _loading = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _period() {
    final now = DateTime.now();
    return switch (_preset) {
      _Preset.day => (now.subtract(const Duration(hours: 24)), now),
      _Preset.week => (now.subtract(const Duration(days: 7)), now),
      _Preset.month => (now.subtract(const Duration(days: 30)), now),
      _Preset.quarter => (now.subtract(const Duration(days: maxDays)), now),
      // Крайната дата се включва изцяло (до 23:59:59).
      _Preset.custom => (_custom!.start, _custom!.end.add(const Duration(days: 1))),
    };
  }

  Future<void> _load() async {
    final (from, to) = _period();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await context.read<ApiClient>().get('/api/history', query: {
        'from': from.toUtc().toIso8601String(),
        'to': (to.isAfter(DateTime.now()) ? DateTime.now() : to).toUtc().toIso8601String(),
      });
      setState(() => _report = HistoryReport.fromJson(json));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, String> _query(HistoryReport r) => {
        'from': r.from.toUtc().toIso8601String(),
        'to': r.to.toUtc().toIso8601String(),
      };

  Future<void> _exportExcel(HistoryReport r) async {
    setState(() => _exporting = true);
    try {
      final api = context.read<ApiClient>();
      final (bytes, name) = await api.download(
        Uri(path: '/api/history/xlsx', queryParameters: _query(r)).toString(),
      );
      await shareBytes(bytes, name ?? 'measurements.xlsx');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _createCertificate(HistoryReport r) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CertificateCreateScreen(measurements: r.measurements)),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сертификатът е издаден - вижте менюто "Сертификати"')),
      );
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: maxDays - 1)),
      lastDate: now,
      initialDateRange: _custom,
      helpText: 'Период (до 3 месеца назад)',
    );
    if (range == null) return;
    setState(() {
      _custom = range;
      _preset = _Preset.custom;
    });
    _load();
  }

  void _select(_Preset p) {
    if (p == _Preset.custom) {
      _pickRange();
      return;
    }
    setState(() => _preset = p);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: BandedListView(
        header: BandTitle(
          subtitle: 'Справки за измерванията до 3 месеца назад',
          bottom: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (p, label) in [
                  (_Preset.day, '24 часа'),
                  (_Preset.week, '7 дни'),
                  (_Preset.month, '30 дни'),
                  (_Preset.quarter, '3 месеца'),
                  (
                    _Preset.custom,
                    _custom == null ? 'Период…' : '${_date.format(_custom!.start)} – ${_date.format(_custom!.end)}'
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _periodChip(label, _preset == p, () => _select(p)),
                  ),
              ],
            ),
          ),
        ),
        children: [
          if (_loading && report == null)
            const SectionCard(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
          if (_error != null) InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
          if (report != null) ...[
            _buildSummary(report),
            if (report.timeline.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildTimeline(report),
            ],
            const SizedBox(height: 24),
            Text('Измервания (${report.count})', style: theme.textTheme.titleMedium),
            if (report.measurements.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Няма записани измервания за този период.', textAlign: TextAlign.center),
              ),
            for (final m in report.measurements) _buildMeasurementTile(m),
          ],
        ],
      ),
    );
  }

  /// Бутон за период върху градиентната лента: бял, когато е избран.
  static Widget _periodChip(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.12),
      shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: selected ? 1 : 0.3))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(color: selected ? AppColors.ink : Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(HistoryReport r) {
    final theme = Theme.of(context);
    Widget stat(String label, String value, {bool big = false}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(
                value,
                style: (big ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)
                    ?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
              ),
            ],
          ),
        );

    return SectionCard(
      title: 'Обобщение за периода',
      subtitle: '${_dateTime.format(r.from)} – ${_dateTime.format(r.to)}',
      icon: Icons.insights_rounded,
      trailing: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      child: Column(
        children: [
          Row(children: [
            stat('LA,eq (ср.)', formatDb(r.laeq), big: true),
            stat('LC,eq (ср.)', formatDb(r.lceq), big: true),
            stat('LZ,eq (ср.)', formatDb(r.lzeq), big: true),
          ]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
          Row(children: [
            stat('Макс. ниво', formatDb(r.laeq1sMax)),
            stat('Мин. ниво', formatDb(r.laeq1sMin)),
            stat('Общо време', formatDuration(r.totalDurationS)),
          ]),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exporting || r.count == 0 ? null : () => _exportExcel(r),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Excel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: r.count == 0 ? null : () => _createCertificate(r),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Сертификат'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(HistoryReport r) {
    final theme = Theme.of(context);
    final short = r.to.difference(r.from).inHours <= 24;
    final fmt = short ? DateFormat('HH:mm') : DateFormat('dd.MM');
    final start = r.from.millisecondsSinceEpoch.toDouble();
    double x(DateTime t) => (t.millisecondsSinceEpoch - start) / 3600000; // часове от началото
    final step = r.bucketS >= 3600 ? 'час' : '${r.bucketS ~/ 60} мин';

    return SectionCard(
      title: 'LA,eq във времето',
      subtitle: 'Стъпка: $step',
      icon: Icons.show_chart_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _legend(theme.colorScheme.primary, 'LA,eq'),
            const SizedBox(width: 12),
            _legend(theme.colorScheme.error, 'макс. LA,eq,1s'),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: LevelLineChart(
              minX: 0,
              maxX: x(r.to),
              lines: [
                ChartLine([for (final p in r.timeline) (x(p.ts), p.laeq)], theme.colorScheme.primary),
                ChartLine([for (final p in r.timeline) (x(p.ts), p.laeqMax)], theme.colorScheme.error, dashed: true),
              ],
              xLabel: (h) => fmt.format(r.from.add(Duration(minutes: (h * 60).round()))),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _legend(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 3, color: c),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );

  Widget _buildMeasurementTile(Measurement m) {
    final theme = Theme.of(context);
    final laeq = m.summary['LAeq'];
    final levelColor = AppColors.forLevel(laeq);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final deleted = await openMeasurementDetail(context, m.id);
            if (deleted == true) _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // LA,eq като цветна значка вляво.
                Container(
                  width: 58,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        laeq?.toStringAsFixed(0) ?? '–',
                        style: theme.textTheme.titleLarge?.copyWith(color: levelColor, fontWeight: FontWeight.w800),
                      ),
                      Text('dB(A)', style: theme.textTheme.labelSmall?.copyWith(color: levelColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.location ?? m.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_dateTime.format(m.startedAt)} · ${formatDuration(m.durationS)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        m.deviceTitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (m.hasWav) Icon(Icons.audio_file_outlined, color: theme.colorScheme.primary),
                Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
