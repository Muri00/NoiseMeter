import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/file_share.dart';
import '../services/user_data.dart';
import '../widgets/charts.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'certificate_create_screen.dart';
import 'measurement_detail_screen.dart';
import '../l10n/l10n.dart';

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
  static final _time = DateFormat('HH:mm');

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

  Future<void> _exportExcel(HistoryReport r, {bool share = false}) async {
    setState(() => _exporting = true);
    try {
      final api = context.read<ApiClient>();
      final (bytes, name) = await api.download(
        Uri(path: '/api/history/xlsx', queryParameters: _query(r)).toString(),
      );
      await (share ? shareBytes : openBytes)(bytes, name ?? 'measurements.xlsx');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _createCertificate(HistoryReport r) async {
    final created = await Navigator.of(context).push<bool>(
      // UserData е над разделите, не над навигатора - подава се изрично (стандартът по подразбиране).
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<UserData>(),
          child: CertificateCreateScreen(measurements: r.measurements),
        ),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Сертификатът е издаден - вижте менюто "Сертификати"'))),
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
      helpText: tr('Период (до 3 месеца назад)'),
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
        header: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (p, label) in [
                        (_Preset.day, tr('24 часа')),
                        (_Preset.week, tr('7 дни')),
                        (_Preset.month, tr('30 дни')),
                        (_Preset.quarter, tr('3 месеца')),
                        (
                          _Preset.custom,
                          _custom == null ? tr('Период…') : '${_date.format(_custom!.start)} – ${_date.format(_custom!.end)}'
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
              const SizedBox(width: 4),
              IconButton(
                tooltip: tr('Период (до 3 месеца назад)'),
                onPressed: _pickRange,
                icon: const Icon(Icons.calendar_month_outlined, color: AppColors.ink),
              ),
            ],
          ),
        ),
        children: [
          if (_loading && report == null)
            const SectionCard(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
          if (_error != null) ...[
            InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
            const SizedBox(height: 24),
          ],
          if (report != null)
            if (report.measurements.isEmpty)
              EmptyState(
                icon: Icons.description_outlined,
                title: tr('Няма намерени измервания'),
                message: tr('За избрания период няма записани данни.'),
                action: OutlinedButton(onPressed: _pickRange, child: Text(tr('Промени периода'))),
              )
            else ...[
              _buildSummary(report),
              const SizedBox(height: 16),
              _buildActions(report),
              if (report.timeline.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildTimeline(report),
              ],
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                child: Text(tr('Измервания ({p0})', {'p0': report.count}), style: sectionLabelStyle(context)),
              ),
              for (final (i, m) in report.measurements.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                _buildMeasurementCard(m),
              ],
            ],
        ],
      ),
    );
  }

  /// Чип за период: сиво хапче; избраният е с по-тъмен сив фон и удебелен текст.
  static Widget _periodChip(String label, bool selected, VoidCallback onTap) {
    const shape = StadiumBorder();
    return Material(
      color: selected ? const Color(0xFFD5DAE0) : AppColors.surfaceHigh,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              fontFeatures: const [AppFonts.noLocalForms],
            ),
          ),
        ),
      ),
    );
  }

  /// Обобщение: сив блок с 3 колони (етикет отгоре, стойност отдолу) в два реда.
  Widget _buildSummary(HistoryReport r) {
    final theme = Theme.of(context);
    final gray = theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    Widget stat(String label, String value) => Expanded(
          child: Column(
            children: [
              Text(label, style: gray, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: monoStyle(17, weight: FontWeight.w600, color: AppColors.ink)),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_dateTime.format(r.from)} – ${_dateTime.format(r.to)}',
                  style: gray,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Column(
            children: [
              Row(children: [
                stat(tr('LA,eq (ср.)'), formatDb(r.laeq)),
                stat(tr('LC,eq (ср.)'), formatDb(r.lceq)),
                stat(tr('LZ,eq (ср.)'), formatDb(r.lzeq)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                stat(tr('Макс. ниво'), formatDb(r.laeq1sMax)),
                stat(tr('Мин. ниво'), formatDb(r.laeq1sMin)),
                stat(tr('Общо време'), formatDuration(r.totalDurationS)),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  /// "Excel" (задържане - споделяне) и "Сертификат" един до друг; до тях малък бутон "Сподели".
  Widget _buildActions(HistoryReport r) {
    final canExport = !_exporting && r.count > 0;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: canExport ? () => _exportExcel(r) : null,
            onLongPress: canExport ? () => _exportExcel(r, share: true) : null,
            child: const Text('Excel'),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: tr('Сподели'),
          onPressed: canExport ? () => _exportExcel(r, share: true) : null,
          icon: const Icon(Icons.share_outlined, size: 20),
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: FilledButton(
            onPressed: r.count == 0 ? null : () => _createCertificate(r),
            child: Text(tr('Сертификат')),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline(HistoryReport r) {
    final theme = Theme.of(context);
    final short = r.to.difference(r.from).inHours <= 24;
    final fmt = short ? DateFormat('HH:mm') : DateFormat('dd.MM');
    final start = r.from.millisecondsSinceEpoch.toDouble();
    double x(DateTime t) => (t.millisecondsSinceEpoch - start) / 3600000; // часове от началото
    final step = r.bucketS >= 3600 ? tr('час') : tr('{p0} мин', {'p0': r.bucketS ~/ 60});

    return SectionCard(
      title: tr('LA,eq във времето'),
      subtitle: tr('Стъпка: {p0}', {'p0': step}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _legend(theme.colorScheme.primary, 'LA,eq'),
            const SizedBox(width: 16),
            _legend(theme.colorScheme.error, tr('макс. LA,eq,1s')),
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

  /// Продължителност във вид Ч:ММ:СС / М:СС - побира се в тясна колона.
  static String _clock(double seconds) {
    final d = Duration(seconds: seconds.round());
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s';
    return '${d.inMinutes}:$s';
  }

  /// Карта на измерване: удебелено заглавие (място или име), сив ред с дата (и потребител за
  /// администратора) и час вдясно, под тях малка таблица с 5 колони.
  Widget _buildMeasurementCard(Measurement m) {
    final theme = Theme.of(context);
    final gray = theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    final showOwner = m.ownerUsername != null && context.read<AuthService>().user?.isAdmin == true;
    String db(String code) => formatDb(m.summary[code]);

    Widget cell(String label, Widget value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 3),
              value,
            ],
          ),
        );
    Widget val(String v) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(v, style: monoStyle(14, weight: FontWeight.w600, color: AppColors.ink)),
        );

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final deleted = await openMeasurementDetail(context, m.id);
          if (deleted == true) _load();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                [m.location ?? m.title, if (m.isSeries) m.pointLabel].join(' · '),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      showOwner
                          ? '${_date.format(m.startedAt)} · ${tr('Потребител: {p0}', {'p0': m.ownerUsername})}'
                          : _date.format(m.startedAt),
                      style: gray,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_time.format(m.startedAt), style: monoStyle(12, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cell(indicatorName('LAeq'), val(db('LAeq'))),
                  const SizedBox(width: 8),
                  cell(indicatorName('LAFmax'), val(db('LAFmax'))),
                  const SizedBox(width: 8),
                  cell(indicatorName('LAFmin'), val(db('LAFmin'))),
                  const SizedBox(width: 8),
                  cell(tr('Продълж.'), val(_clock(m.durationS))),
                  const SizedBox(width: 8),
                  cell(
                    'WAV',
                    m.hasWav
                        ? const Icon(Icons.check_rounded, size: 18, color: AppColors.success)
                        : val('–'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
