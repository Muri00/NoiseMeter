import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/file_share.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
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

  Future<void> _share(String kind) async {
    setState(() => _busy = true);
    try {
      await downloadAndShare(_api, '$_base/$kind', 'measurement_${widget.measurementId}.$kind');
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Файлът не може да бъде споделен: $e');
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
    if (m.normDay == null && m.normEvening == null && m.normNight == null) return 'не са зададени';
    return 'ден ${f(m.normDay)} / вечер ${f(m.normEvening)} / нощ ${f(m.normNight)} dB(A)';
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Изтриване на запис'),
        content: const Text('Записът и WAV файлът ще бъдат изтрити окончателно.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отказ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Изтрий')),
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
      appBar: bandAppBar(
        actions: [
          if (m != null) ...[
            IconButton(
              tooltip: 'Сподели като Excel',
              icon: const Icon(Icons.share_outlined),
              onPressed: _busy ? null : () => _share('xlsx'),
            ),
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (v) => v == 'delete' ? _delete() : _share(v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'xlsx', child: Text('Сподели като Excel')),
                const PopupMenuItem(value: 'csv', child: Text('Сподели данните (CSV)')),
                if (m.hasWav) const PopupMenuItem(value: 'wav', child: Text('Сподели сигнала (WAV)')),
                const PopupMenuItem(value: 'delete', child: Text('Изтрий')),
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

  Widget _buildBody(Measurement m) {
    final theme = Theme.of(context);
    final d = m.deviceInfo;
    final cal = d['calibration_offset_db'] as num?;
    final calDate = d['calibration_date'] as String?;
    final laeq = m.summary['LAeq'];

    return BandedListView(
      header: BandTitle(
        title: m.location ?? m.title,
        subtitle: '${_dateTime.format(m.startedAt)}  ·  ${formatDuration(m.durationS)}',
        bottom: Row(
          children: [
            StatusPill(label: 'LA,eq ${formatDb(laeq)}', color: AppColors.forLevel(laeq), onDark: true),
            const SizedBox(width: 8),
            if (m.hasWav) const StatusPill(label: 'WAV', color: Colors.white, icon: Icons.audio_file_outlined, onDark: true),
          ],
        ),
      ),
      children: [
        SectionCard(
          title: 'Техническа информация',
          icon: Icons.tune_rounded,
          child: Column(
            children: [
              InfoRow(label: 'Устройство', value: m.deviceTitle),
              InfoRow(label: 'Сериен №', value: '${d['serial_number']}'),
              InfoRow(label: 'Чувствителност', value: '${d['sensitivity_dbfs']} dBFS'),
              InfoRow(
                label: 'Калибровъчна корекция',
                value: cal == null ? 'няма' : '${cal >= 0 ? '+' : ''}${cal.toStringAsFixed(2)} dB',
              ),
              if (calDate != null)
                InfoRow(label: 'Калибриран на', value: DateFormat('dd.MM.yyyy').format(DateTime.parse(calDate).toLocal())),
              InfoRow(label: 'Измервателен интервал', value: '${formatHz(m.fMinHz)} – ${formatHz(m.fMaxHz)}'),
              InfoRow(label: 'Октавни ленти', value: m.bandMode == 'off' ? 'без' : '${m.bandMode} октава'),
              InfoRow(label: 'Записани секунди', value: '${m.frameCount ?? 0}', divider: false),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Място и норми',
          icon: Icons.place_outlined,
          trailing: IconButton(
            tooltip: 'Редактирай',
            icon: Icon(Icons.edit_outlined, color: theme.colorScheme.primary),
            onPressed: () => _editPlace(m),
          ),
          child: Column(
            children: [
              InfoRow(label: 'Точка', value: m.location ?? '–'),
              InfoRow(label: 'Източник', value: m.source ?? '–'),
              InfoRow(label: 'Норми', value: _norms(m), divider: false),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Резултати',
          subtitle: 'За цялото измерване',
          icon: Icons.analytics_outlined,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in {...m.indicators, 'LAeq', 'LAFmax', 'LAFmin'})
                Chip(label: Text('${indicatorName(code)}  ${formatDb(m.summary[code])}')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Във времето',
          subtitle: 'По секунди',
          icon: Icons.show_chart_rounded,
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _seriesCode,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
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
              xLabel: (s) => formatDuration(s).replaceAll(RegExp(r'[.,]\d с'), ' с'),
            ),
          ),
        ),
        if (m.averageBands != null) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: 'Среден спектър',
            subtitle: '${m.bandMode} октава, Z',
            icon: Icons.bar_chart_rounded,
            child: SizedBox(height: 200, child: BandChart(spectrum: m.averageBands!)),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
