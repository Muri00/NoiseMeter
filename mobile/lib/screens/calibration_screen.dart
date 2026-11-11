import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/measurement_service.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'calibration_form_screen.dart';
import '../l10n/l10n.dart';

/// Калибровка на устройствата и протоколи от калибровките (изискване 6).
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  int? _deviceId;
  List<Calibration>? _calibrations;
  String? _error;

  ApiClient get _api => context.read<ApiClient>();

  Future<void> _loadCalibrations() async {
    final id = _deviceId;
    if (id == null) return;
    try {
      final list = await _api.get('/api/devices/$id/calibrations') as List;
      if (mounted && id == _deviceId) {
        setState(() {
          _calibrations = list.map((j) => Calibration.fromJson(j)).toList();
          _error = null;
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  void _selectDevice(int? id) {
    setState(() {
      _deviceId = id;
      _calibrations = null;
    });
    _loadCalibrations();
  }

  Future<void> _pickDevice(List<Device> devices) async {
    final id = await showChoiceSheet<int?>(
      context,
      title: tr('Устройство'),
      options: [for (final d in devices) (d.id, d.title, 'S/N ${d.serialNumber}')],
      selected: _deviceId,
    );
    if (id != null && id != _deviceId) _selectDevice(id);
  }

  Future<void> _openForm(Device device, bool automatic) async {
    if (automatic && context.read<MeasurementService>().isRunning) {
      _snack(tr('Спрете текущото измерване - микрофонът се използва.'));
      return;
    }
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CalibrationFormScreen(device: device, automatic: automatic),
    ));
    if (changed == true && mounted) {
      await context.read<UserData>().load(); // новата корекция на устройството
      _loadCalibrations();
    }
  }

  Future<void> _decide(Calibration c, bool apply) async {
    try {
      await _api.post('/api/devices/$_deviceId/calibrations/${c.id}/${apply ? 'apply' : 'reject'}', {});
      if (!mounted) return;
      if (apply) await context.read<UserData>().load();
      _loadCalibrations();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final data = context.watch<UserData>();
    if (data.devices.isEmpty) {
      return BandedListView(
        children: [
          EmptyState(
            icon: Icons.mic_off_outlined,
            title: tr('Няма устройство'),
            message: tr('Добавете устройство от менюто "Устройства", за да го калибрирате.'),
          ),
        ],
      );
    }
    if (_deviceId == null || !data.devices.any((d) => d.id == _deviceId)) {
      // Първо отваряне или изтрито устройство.
      WidgetsBinding.instance.addPostFrameCallback((_) => _selectDevice(data.devices.first.id));
      return const Center(child: CircularProgressIndicator());
    }
    final device = data.devices.firstWhere((d) => d.id == _deviceId);
    final calibrations = _calibrations;
    final theme = Theme.of(context);
    final stateLine = monoStyle(14, color: AppColors.textSecondary, height: 20 / 14);

    return RefreshIndicator(
      onRefresh: _loadCalibrations,
      child: BandedListView(
        children: [
          // Избор на устройство - поле, което изглежда като падащо меню.
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              side: const BorderSide(color: AppColors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _pickDevice(data.devices),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${tr('Устройство')}: ${device.title}',
                        style: theme.textTheme.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(tr('Текущо състояние'), style: sectionLabelStyle(context)),
          const SizedBox(height: 4),
          Text('S/N ${device.serialNumber}', style: stateLine),
          Text('${tr('Чувствителност')}: ${device.sensitivityDbfs} dBFS @ 94 dB SPL', style: stateLine),
          Text('${tr('Калибровъчна корекция')}: ${_signed(device.calibrationOffsetDb)}', style: stateLine),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _openForm(device, true),
                  child: Text(tr('Автоматична')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openForm(device, false),
                  child: Text(tr('Ръчна')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            InfoBanner(message: _error!, color: AppColors.danger, icon: Icons.error_outline),
            const SizedBox(height: 16),
          ],
          if (calibrations == null && _error == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (calibrations != null)
            // Бяла карта със сива заглавна лента и протоколите, разделени с линии.
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: Border.all(color: AppColors.line),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: AppColors.surfaceHigh,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Text(tr('История на калибровките'), style: sectionLabelStyle(context)),
                    ),
                    if (calibrations.isEmpty)
                      EmptyState(icon: Icons.tune_rounded, title: tr('Няма направени калибровки.'))
                    else
                      for (final (i, c) in calibrations.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _buildProtocol(c),
                      ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static final _date = DateFormat('dd.MM.yyyy');
  static final _time = DateFormat('HH:mm');

  static String _signed(double? v) =>
      v == null ? tr('няма') : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)} dB';

  Widget _buildProtocol(Calibration c) {
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = switch (c.status) {
      'applied' => (tr('Приложена'), AppColors.success),
      'pending' => (tr('Чака'), AppColors.warning),
      _ => (tr('Отхвърлена'), AppColors.danger),
    };
    final reference = c.referenceLevelDb == null
        ? null
        : tr('Еталон: {p0} dB', {'p0': c.referenceLevelDb}) +
            (c.referenceFreqHz != null ? ' @ ${formatHz(c.referenceFreqHz!)}' : '');
    final calibrator = [
      if (c.calibrator.isNotEmpty) c.calibrator,
      if (c.calibratorSerial != null) 'S/N ${c.calibratorSerial}',
    ].join(', ');
    final details = <String>[
      if (calibrator.isNotEmpty) tr('Калибратор: {p0}', {'p0': calibrator}),
      if (c.calibratorCertificate != null) tr('Сертификат на калибратора: {p0}', {'p0': c.calibratorCertificate}),
      if (c.measuredLevelDb != null)
        tr('Показание: {p0} dB', {'p0': c.measuredLevelDb!.toStringAsFixed(2)}) +
            (c.measuredFreqHz != null ? ' @ ${c.measuredFreqHz!.toStringAsFixed(0)} Hz' : '') +
            (c.stabilityDb != null ? ', σ = ${c.stabilityDb!.toStringAsFixed(2)} dB' : ''),
      if (c.uncertaintyDb != null) tr('Неопределеност (k=2): ±{p0} dB', {'p0': c.uncertaintyDb}),
      if (c.temperatureC != null || c.humidityPct != null || c.pressureKpa != null)
        tr('Условия: {p0}', {
          'p0': [
            if (c.temperatureC != null) '${c.temperatureC} °C',
            if (c.humidityPct != null) '${c.humidityPct} %RH',
            if (c.pressureKpa != null) '${c.pressureKpa} kPa',
          ].join(', '),
        }),
      if (c.notes != null && c.notes!.isNotEmpty) tr('Бележки: {p0}', {'p0': c.notes}),
    ];
    final secondary = theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final local = c.createdAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Протокол {p0}', {'p0': _date.format(local)}),
                      style: monoStyle(15, weight: FontWeight.w500, color: AppColors.ink),
                    ),
                    Text(_time.format(local), style: monoStyle(13, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 6),
          Text([c.methodName, ?reference].join(' · '), style: secondary),
          const SizedBox(height: 4),
          Text(
            tr('Корекция: {p0} → {p1}', {'p0': _signed(c.offsetBeforeDb), 'p1': _signed(c.offsetDb)}) +
                (c.driftDb != null ? tr(' (промяна {p0})', {'p0': _signed(c.driftDb)}) : ''),
            style: monoStyle(14, weight: FontWeight.w500, color: AppColors.ink),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final l in details)
              Text(l, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
          ],
          if (c.status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: () => _decide(c, false),
                    child: Text(tr('Отхвърли')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: () => _decide(c, true),
                    child: Text(tr('Приложи')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
