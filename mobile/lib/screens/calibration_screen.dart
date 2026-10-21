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

/// Калибровка на устройствата и протоколи от калибровките (изискване 6).
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static final _dateTime = DateFormat('dd.MM.yyyy HH:mm');

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

  Future<void> _openForm(Device device, bool automatic) async {
    if (automatic && context.read<MeasurementService>().isRunning) {
      _snack('Спрете текущото измерване - микрофонът се използва.');
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
      return const BandedListView(
        children: [
          SectionCard(
            title: 'Няма устройство',
            icon: Icons.mic_off_outlined,
            child: Text('Добавете устройство от менюто "Устройства", за да го калибрирате.'),
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
    final applied = _calibrations?.where((c) => c.status == 'applied').firstOrNull;
    final theme = Theme.of(context);
    final date = DateFormat('dd.MM.yyyy');
    final statusColor = AppColors.forCalibration(device.calibrationStatus);

    return RefreshIndicator(
      onRefresh: _loadCalibrations,
      child: BandedListView(
        header: BandTitle(
          subtitle: 'Калибровка по EN ISO/IEC 17025 с протокол за всяка калибровка',
          bottom: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _deviceId,
                isExpanded: true,
                dropdownColor: AppColors.ink,
                iconEnabledColor: Colors.white,
                borderRadius: BorderRadius.circular(14),
                style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
                items: [
                  for (final d in data.devices)
                    DropdownMenuItem(
                      value: d.id,
                      child: Row(
                        children: [
                          const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text('${d.title}  ·  S/N ${d.serialNumber}', overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
                onChanged: _selectDevice,
              ),
            ),
          ),
        ),
        children: [
          SectionCard(
            title: 'Текущо състояние',
            icon: Icons.sensors_rounded,
            trailing: StatusPill(label: device.calibrationStatusName.toUpperCase(), color: statusColor),
            child: Column(
              children: [
                InfoRow(label: 'Чувствителност', value: '${device.sensitivityDbfs} dBFS @ 94 dB SPL'),
                InfoRow(label: 'Калибровъчна корекция', value: _signed(device.calibrationOffsetDb)),
                InfoRow(
                  label: 'Последна калибровка',
                  value: device.lastCalibrationAt == null
                      ? 'няма'
                      : '${date.format(device.lastCalibrationAt!)}'
                          '${applied != null ? ' (${applied.methodName.toLowerCase()})' : ''}',
                ),
                InfoRow(
                  label: 'Следваща калибровка',
                  value: device.nextCalibrationDue == null
                      ? (device.calibrationIntervalMonths == null ? 'без срок' : '–')
                      : date.format(device.nextCalibrationDue!),
                  valueColor: device.calibrationStatus == 'valid' ? null : statusColor,
                  divider: false,
                ),
                if (device.calibrationStatus == 'expired' || device.calibrationStatus == 'none') ...[
                  const SizedBox(height: 8),
                  InfoBanner(
                    message: device.calibrationStatus == 'expired'
                        ? 'Срокът на калибровката е изтекъл. Калибрирайте уреда преди измерване.'
                        : 'Уредът не е калибриран. Резултатите разчитат само на номиналната чувствителност.',
                    color: statusColor,
                    icon: Icons.warning_amber_rounded,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openForm(device, true),
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('Автоматична'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openForm(device, false),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Ръчна'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('История на протоколите', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (_error != null) InfoBanner(message: _error!, color: theme.colorScheme.error, icon: Icons.error_outline),
          if (_calibrations == null && _error == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_calibrations?.isEmpty ?? false)
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Няма направени калибровки.')),
          for (final c in _calibrations ?? <Calibration>[]) _buildProtocol(c),
        ],
      ),
    );
  }

  static String _signed(double? v) =>
      v == null ? 'няма' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)} dB';

  Widget _buildProtocol(Calibration c) {
    final theme = Theme.of(context);
    final color = switch (c.status) {
      'applied' => AppColors.success,
      'pending' => AppColors.warning,
      _ => theme.disabledColor,
    };
    final lines = <String>[
      if (c.referenceLevelDb != null)
        'Еталон: ${c.referenceLevelDb} dB'
            '${c.referenceFreqHz != null ? ' @ ${formatHz(c.referenceFreqHz!)}' : ''}'
            '${c.calibrator.isNotEmpty ? ', ${c.calibrator}' : ''}'
            '${c.calibratorSerial != null ? ', S/N ${c.calibratorSerial}' : ''}',
      if (c.calibratorCertificate != null) 'Сертификат на калибратора: ${c.calibratorCertificate}',
      if (c.measuredLevelDb != null) 'Показание: ${c.measuredLevelDb!.toStringAsFixed(2)} dB'
          '${c.measuredFreqHz != null ? ' при ${c.measuredFreqHz!.toStringAsFixed(0)} Hz' : ''}'
          '${c.stabilityDb != null ? ', σ = ${c.stabilityDb!.toStringAsFixed(2)} dB' : ''}',
      'Корекция: ${_signed(c.offsetBeforeDb)} → ${_signed(c.offsetDb)}'
          '${c.driftDb != null ? ' (промяна ${_signed(c.driftDb)})' : ''}',
      if (c.uncertaintyDb != null) 'Неопределеност (k=2): ±${c.uncertaintyDb} dB',
      if (c.temperatureC != null || c.humidityPct != null || c.pressureKpa != null)
        'Условия: ${[
          if (c.temperatureC != null) '${c.temperatureC} °C',
          if (c.humidityPct != null) '${c.humidityPct} %RH',
          if (c.pressureKpa != null) '${c.pressureKpa} kPa',
        ].join(', ')}',
      if (c.notes != null && c.notes!.isNotEmpty) 'Бележки: ${c.notes}',
    ];

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${c.methodName} • ${_dateTime.format(c.createdAt)}', style: theme.textTheme.titleSmall),
                ),
                Text(c.statusName, style: theme.textTheme.bodySmall?.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 6),
            for (final l in lines) Text(l, style: theme.textTheme.bodySmall),
            if (c.status == 'pending')
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => _decide(c, false), child: const Text('Отхвърли')),
                  FilledButton(onPressed: () => _decide(c, true), child: const Text('Приложи')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
