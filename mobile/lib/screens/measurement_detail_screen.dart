import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/file_share.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/recording_player.dart';
import '../widgets/ui.dart';
import 'measurement_place_screen.dart';

/// Отваря детайлите на запис. Връща true, ако записът е изтрит.
Future<bool?> openMeasurementDetail(BuildContext context, int id) => Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MeasurementDetailScreen(measurementId: id)),
    );

class MeasurementDetailScreen extends StatefulWidget {
  const MeasurementDetailScreen({super.key, required this.measurementId});

  final int measurementId;

  @override
  State<MeasurementDetailScreen> createState() => _MeasurementDetailScreenState();
}

class _MeasurementDetailScreenState extends State<MeasurementDetailScreen> {
  static final _dateTime = DateFormat('dd.MM.yyyy HH:mm:ss');

  Measurement? _m;
  String? _error;
  String? _seriesCode;
  List<(double, double)> _series = [];
  bool _busy = false;

  ApiClient get _api => context.read<ApiClient>();
  String get _base => '/api/measurements/${widget.measurementId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = Measurement.fromJson(await _api.get(_base));
      setState(() => _m = m);
      await _loadSeries(m.indicators.first);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _loadSeries(String code) async {
    setState(() => _seriesCode = code);
    try {
      final json = await _api.get('$_base/series', query: {'codes': [code]});
      final t = (json['t'] as List).map((v) => (v as num).toDouble()).toList();
      final v = (json['series'][code] as List).map((v) => (v as num).toDouble()).toList();
      if (mounted && _seriesCode == code) setState(() => _series = [for (var i = 0; i < t.length; i++) (t[i], v[i])]);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Отваря файла в приложение за преглед или (share = true) отваря менюто "Сподели".
  Future<void> _share(String kind, {bool share = true}) async {
    setState(() => _busy = true);
    try {
      final name = 'measurement_${widget.measurementId}.$kind';
      await (share ? downloadAndShare(_api, '$_base/$kind', name) : downloadAndOpen(_api, '$_base/$kind', name));
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(tr('Файлът не може да бъде отворен: {p0}', {'p0': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editPlace(Measurement m) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MeasurementPlaceScreen(measurement: m)),
    );
    if (saved == true) {
      final updated = Measurement.fromJson(await _api.get(_base));
      if (mounted) setState(() => _m = updated);
    }
  }

  static String _norms(Measurement m) {
    String f(double? v) => v == null ? '–' : v.toStringAsFixed(0);
    if (m.normDay == null && m.normEvening == null && m.normNight == null) return tr('не са зададени');
    return tr('ден {p0} / вечер {p1} / нощ {p2} dB(A)', {'p0': f(m.normDay), 'p1': f(m.normEvening), 'p2': f(m.normNight)});
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Изтриване на запис')),
        content: Text(tr('Записът и WAV файлът ще бъдат изтрити окончателно.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отказ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Изтрий'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.delete(_base);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          tr('Детайли на измерване'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
        actions: [
          if (m != null) ...[
            IconButton(
              tooltip: tr('Отвори в Excel'),
              icon: const Icon(Icons.table_view_outlined),
              onPressed: _busy ? null : () => _share('xlsx', share: false),
            ),
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (v) => v == 'delete' ? _delete() : _share(v),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'xlsx', child: Text(tr('Сподели като Excel'))),
                PopupMenuItem(value: 'csv', child: Text(tr('Сподели данните (CSV)'))),
                if (m.hasWav) PopupMenuItem(value: 'wav', child: Text(tr('Сподели сигнала (WAV)'))),
                // Само администраторът може да трие записи от историята.
                if (_isAdmin) PopupMenuItem(value: 'delete', child: Text(tr('Изтрий'))),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : m == null
                    ? const Center(child: CircularProgressIndicator())
                    : _buildBody(m),
          ),
        ],
      ),
    );
  }

  bool get _isAdmin => context.read<AuthService>().user?.isAdmin ?? false;

  /// Период от денонощието по часа (Наредба № 6): ден 07-19, вечер 19-23, нощ 23-07.
  static String _periodAt(DateTime t) => t.hour >= 7 && t.hour < 19
      ? 'day'
      : t.hour >= 19 && t.hour < 23
          ? 'evening'
          : 'night';

  /// Периодът, спрямо който се оценява записът: зададеният или - при автоматичен -
  /// периодът по часа, ако целият запис е в него. null, ако записът обхваща няколко периода.
  static String? _effectivePeriod(Measurement m) {
    if (m.period != null) return m.period;
    final start = m.startedAt;
    final end = m.endedAt ?? start.add(Duration(milliseconds: (m.durationS * 1000).round()));
    final day0 = DateTime(start.year, start.month, start.day);
    final boundaries = [
      for (final d in [0, 1]) ...[
        for (final h in [7, 19, 23]) DateTime(day0.year, day0.month, day0.day + d, h),
      ],
    ];
    final next = boundaries.firstWhere((b) => b.isAfter(start));
    return end.isAfter(next) ? null : _periodAt(start);
  }

  /// Оценка спрямо нормата за периода: "В норма" или "Превишение (+x.x dB)"; null, ако не може да се определи.
  static Widget? _assessment(Measurement m) {
    final laeq = m.summary['LAeq'];
    final period = _effectivePeriod(m);
    if (laeq == null || period == null) return null;
    final norm = switch (period) {
      'day' => m.normDay,
      'evening' => m.normEvening,
      _ => m.normNight,
    };
    if (norm == null) return null;
    final excess = ((laeq - norm) * 10).round() / 10;
    // Цветен текст (като StatusPill), но с пренасяне - колоната в таблицата е тясна.
    final (label, color) = excess > 0
        ? (tr('Превишение (+{p0} dB)', {'p0': excess.toStringAsFixed(1)}), AppColors.danger)
        : (tr('В норма'), AppColors.success);
    return Text(
      label,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color, fontFeatures: const [AppFonts.noLocalForms]),
    );
  }

  Widget _buildBody(Measurement m) {
    final theme = Theme.of(context);
    final d = m.deviceInfo;
    final cal = d['calibration_offset_db'] as num?;
    // Избраните показатели плюс основните, които винаги се показват.
    final summaryCodes = {...m.indicators, 'LAeq', 'LAFmax', 'LAFmin'}.toList();
    final calDate = d['calibration_date'] as String?;
    final laeq = m.summary['LAeq'];
    final assessment = _assessment(m);

    final gray = theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);

    final timeChart = SectionCard(
      title: tr('Във времето'),
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _seriesCode,
          isDense: true,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          items: [
            for (final c in {...m.indicators, 'LAeq', 'LCeq', 'LZeq'})
              DropdownMenuItem(value: c, child: Text(indicatorName(c))),
          ],
          onChanged: (c) => c == null ? null : _loadSeries(c),
        ),
      ),
      child: SizedBox(
        height: 200,
        child: LevelLineChart(
          lines: [ChartLine(_series, theme.colorScheme.primary)],
          // Кратко "м:сс" - дългите надписи ("1 мин 0 с") се застъпваха.
          xLabel: (s) {
            final t = s.round();
            return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
          },
        ),
      ),
    );
    final spectrum = m.averageBands == null
        ? null
        : SectionCard(
            title: tr('Спектър'),
            subtitle: tr('{p0} октава, Z', {'p0': m.bandMode}),
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
            child: SizedBox(height: 200, child: BandChart(spectrum: m.averageBands!)),
          );

    // Двойки "етикет - стойност" за таблицата "Място и норми".
    final placeRows = <(String, Widget)>[
      if (m.placeType != null)
        (tr('Вид'), _value(m.placeType == 'indoor' ? tr('Закрито помещение') : tr('Открито място'))),
      (tr('Място'), _value(m.location ?? '–')),
      if (m.isSeries) (tr('Точка'), _value(tr('{p0} от {p1}', {'p0': m.pointNo, 'p1': m.pointCount}))),
      (tr('Източник'), _value(m.source ?? '–')),
      (tr('Зона'), _value(m.zoneCode ?? '–')),
      (tr('Период'), _value(periodName(m.period))),
      (tr('Норми'), _value(_norms(m))),
      if (assessment != null) (tr('Оценка'), assessment),
    ];

    final calText = cal == null ? tr('няма') : '${cal >= 0 ? '+' : ''}${cal.toStringAsFixed(2)} dB';
    final techRows = <(String, String)>[
      if (m.ownerUsername != null && _isAdmin) (tr('Потребител'), m.ownerUsername!),
      (tr('Устройство'), m.deviceTitle),
      (tr('Сериен №'), '${d['serial_number']}'),
      (tr('Чувствителност'), '${d['sensitivity_dbfs']} dBFS'),
      (tr('Калибровъчна корекция'), calText),
      if (calDate != null) (tr('Калибриран на'), DateFormat('dd.MM.yyyy').format(DateTime.parse(calDate).toLocal())),
      (tr('Стандарт'), m.standardName ?? 'IEC 61672-1'),
      (tr('Измервателен интервал'), '${formatHz(m.fMinHz)} – ${formatHz(m.fMaxHz)}'),
      (tr('Октавни ленти'), m.bandMode == 'off' ? tr('без') : tr('{p0} октава', {'p0': m.bandMode})),
      (tr('Записани секунди'), '${m.frameCount ?? 0}'),
    ];

    return BandedListView(
      // Центрирано заглавие: място/име, дата и продължителност, голямо LA,eq.
      header: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
        child: Column(
          children: [
            Text(
              [m.location ?? m.title, if (m.isSeries) m.pointLabel].join(' · '),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${_dateTime.format(m.startedAt)} · ${formatDuration(m.durationS)}',
              textAlign: TextAlign.center,
              style: gray,
            ),
            const SizedBox(height: 10),
            Text('LA,eq', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textSecondary)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: laeq?.toStringAsFixed(1) ?? '–'),
                  TextSpan(text: ' dB', style: monoStyle(28, weight: FontWeight.w500, color: AppColors.ink)),
                ]),
                style: monoStyle(48, weight: FontWeight.w500, color: AppColors.ink, height: 1.1),
              ),
            ),
          ],
        ),
      ),
      children: [
        if (m.outOfBand) ...[
          InfoBanner(
            message: tr('Измервателният интервал излиза извън работната лента на микрофона - резултатите са ненадеждни.'),
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 24),
        ],
        if (m.hasWav) ...[
          RecordingPlayer(measurementId: m.id),
          const SizedBox(height: 24),
        ],
        SectionCard(
          title: tr('Място и норми'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          // Само администраторът може да променя мястото и нормите в историята.
          trailing: _isAdmin
              ? TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _editPlace(m),
                  child: Text(tr('Редактирай')),
                )
              : null,
          child: _PairTable(rows: placeRows),
        ),
        const SizedBox(height: 24),
        if (m.isSeries && m.seriesPoints.isNotEmpty) ...[
          _buildSeries(m),
          const SizedBox(height: 24),
        ],
        SectionCard(
          title: tr('Резултати'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (final (i, code) in summaryCodes.indexed)
                _SummaryRow(code: code, value: m.summary[code], divider: i < summaryCodes.length - 1),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Графиката във времето и спектърът един до друг на широк екран, един под друг на тесен.
        LayoutBuilder(
          builder: (context, c) => spectrum != null && c.maxWidth >= 560
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: timeChart),
                    const SizedBox(width: 12),
                    Expanded(child: spectrum),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    timeChart,
                    if (spectrum != null) ...[const SizedBox(height: 24), spectrum],
                  ],
                ),
        ),
        const SizedBox(height: 24),
        // Техническа информация: бяла карта с таблица "етикет - стойност", като "Резултати".
        SectionCard(
          title: tr('Техническа информация'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (final (i, (label, value)) in techRows.indexed)
                InfoRow(label: label, value: value, divider: i < techRows.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  /// Точките от същото помещение и енергийното средно LAeq от тях. Натискане отваря точката.
  Widget _buildSeries(Measurement m) {
    final theme = Theme.of(context);
    final rows = [
      for (final p in m.seriesPoints)
        (
          label: tr('Точка {p0}', {'p0': p.pointNo ?? '–'}),
          value: p.laeq == null ? '–' : '${p.laeq!.toStringAsFixed(1)} dB(A)',
          id: p.id,
        ),
    ];
    return SectionCard(
      title: tr('Помещение'),
      subtitle: tr('Записани {p0} от {p1} точки', {'p0': m.seriesPoints.length, 'p1': m.pointCount}),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final r in rows)
            InkWell(
              onTap: r.id == m.id ? null : () => openMeasurementDetail(context, r.id),
              child: InfoRow(
                label: r.id == m.id ? '${r.label} (${tr('тази')})' : r.label,
                value: r.value,
                valueColor: r.id == m.id ? AppColors.primary : null,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text(tr('Средно за помещението (LA,eq)'), style: theme.textTheme.bodyMedium)),
                Text(m.seriesLaeq == null ? '–' : '${m.seriesLaeq!.toStringAsFixed(1)} dB(A)',
                    style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _value(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.ink),
      );
}

/// Компактна таблица от двойки "етикет - стойност": две двойки на ред (4 колони),
/// на много тесен екран - по една.
class _PairTable extends StatelessWidget {
  const _PairTable({required this.rows});

  final List<(String, Widget)> rows;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return LayoutBuilder(builder: (context, c) {
      // На телефон по една двойка на ред - иначе етикетите се пренасят по средата на думата.
      final perRow = c.maxWidth >= 520 ? 2 : 1;
      Widget pair((String, Widget)? p) => Expanded(
            child: p == null
                ? const SizedBox.shrink()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: Text(p.$1, style: label)),
                      const SizedBox(width: 8),
                      Expanded(flex: 3, child: p.$2),
                    ],
                  ),
          );
      return Column(
        children: [
          for (var i = 0; i < rows.length; i += perRow)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: i + perRow < rows.length ? const Border(bottom: BorderSide(color: AppColors.line)) : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  pair(rows[i]),
                  if (perRow == 2) ...[
                    const SizedBox(width: 16),
                    pair(i + 1 < rows.length ? rows[i + 1] : null),
                  ],
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// Ред с резултат: съкращение и описание вляво, стойност вдясно.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.code, required this.value, required this.divider});

  final String code;
  final double? value;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = indicatorDescription(code);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: AppColors.line)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  indicatorName(code),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [AppFonts.noLocalForms]),
                ),
                if (description.isNotEmpty)
                  Text(description, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(formatDb(value), style: monoStyle(16, weight: FontWeight.w500, color: AppColors.ink)),
        ],
      ),
    );
  }
}
