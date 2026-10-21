import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/measurement_service.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/ui.dart';
import 'indicators_screen.dart' show BandModeSelector;
import 'measurement_detail_screen.dart';

/// Измерване в реално време (изискване 3).
class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  int? _deviceId;
  String _bandMode = '1/3';
  final _fMin = TextEditingController();
  final _fMax = TextEditingController();
  final _name = TextEditingController();
  bool _record = false;
  bool _saveWav = false;
  bool _initialized = false;
  String? _validationError;
  String? _chartIndicator;

  @override
  void dispose() {
    _fMin.dispose();
    _fMax.dispose();
    _name.dispose();
    super.dispose();
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Попълва полетата от настройките на потребителя, след като се заредят.
  void _initFrom(UserData data) {
    final s = data.settings;
    if (_initialized || s == null) return;
    _initialized = true;
    _bandMode = s.bandMode;
    _fMin.text = _fmt(s.fMinHz);
    _fMax.text = _fmt(s.fMaxHz);
    if (data.devices.isNotEmpty) _deviceId = data.devices.first.id;
  }

  void _start(UserData data) {
    final device = data.devices.where((d) => d.id == _deviceId).firstOrNull;
    final fMin = double.tryParse(_fMin.text.replaceAll(',', '.'));
    final fMax = double.tryParse(_fMax.text.replaceAll(',', '.'));

    String? error;
    if (device == null) {
      error = 'Изберете устройство';
    } else if (fMin == null || fMax == null) {
      error = 'Въведете измервателния интервал';
    } else if (fMin < absFMinHz || fMax > absFMaxHz || fMin >= fMax) {
      error = 'Интервалът трябва да е между ${absFMinHz.toInt()} Hz и ${absFMaxHz.toInt()} Hz';
    } else if (fMin < device.freqMinHz || fMax > device.freqMaxHz) {
      // Изискване 3: не може да се излиза извън работната лента на устройството.
      error = 'Интервалът трябва да е в работната лента на устройството '
          '(${formatHz(device.freqMinHz)} – ${formatHz(device.freqMaxHz)})';
    }
    setState(() => _validationError = error);
    if (error != null) return;

    context.read<MeasurementService>().start(
          deviceId: device!.id!,
          fMin: fMin!,
          fMax: fMax!,
          bandMode: _bandMode,
          record: _record,
          saveWav: _saveWav,
          name: _name.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<UserData>();
    final m = context.watch<MeasurementService>();
    _initFrom(data);

    if (data.loading && data.settings == null) return const Center(child: CircularProgressIndicator());
    if (data.settings == null) {
      return Center(child: Text(data.error ?? 'Настройките не са заредени'));
    }

    // Устройството може да е изтрито от екрана "Устройства".
    if (_deviceId != null && !data.devices.any((d) => d.id == _deviceId)) {
      _deviceId = data.devices.firstOrNull?.id;
    }
    _deviceId ??= data.devices.firstOrNull?.id;

    final indicators = data.settings!.indicators;
    final chartIndicator = indicators.contains(_chartIndicator) ? _chartIndicator! : indicators.first;
    final running = m.isRunning;

    // Лявата част: показание, съобщения и параметри.
    final controls = <Widget>[
      _buildHero(data, m, indicators),
      if (!running && m.lastSavedId != null) _buildSavedBanner(m.lastSavedId!),
      if (_validationError != null || m.error != null) ...[
        const SizedBox(height: 12),
        InfoBanner(
          message: _validationError ?? m.error!,
          color: Theme.of(context).colorScheme.error,
          icon: Icons.error_outline_rounded,
        ),
      ],
      const SizedBox(height: 16),
      _buildConfigCard(data, running),
    ];
    // Дясната част: плочките с показателите и графиките.
    final results = <Widget>[
      _buildIndicatorGrid(indicators, m.levels),
      const SizedBox(height: 16),
      _section(
        title: 'Във времето',
        icon: Icons.show_chart_rounded,
        trailing: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: chartIndicator,
            isDense: true,
            borderRadius: BorderRadius.circular(12),
            items: [for (final c in indicators) DropdownMenuItem(value: c, child: Text(indicatorName(c)))],
            onChanged: (v) => setState(() => _chartIndicator = v),
          ),
        ),
        child: SizedBox(height: 180, child: LevelHistoryChart(points: m.history[chartIndicator] ?? const [])),
      ),
      if (m.bands != null) ...[
        const SizedBox(height: 16),
        _section(
          title: 'Спектър ${m.bands!.mode} октава',
          icon: Icons.bar_chart_rounded,
          trailing: Text('Z', style: Theme.of(context).textTheme.labelLarge),
          child: SizedBox(height: 200, child: BandChart(spectrum: m.bands!)),
        ),
      ],
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // Широк екран (таблет в пейзаж): две колони, всяка със собствено превъртане.
      if (constraints.maxWidth >= 900) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 8, 24), children: controls),
            ),
            Expanded(
              flex: 6,
              child: ListView(padding: const EdgeInsets.fromLTRB(8, 4, 16, 24), children: results),
            ),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          ReadableWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...controls, const SizedBox(height: 16), ...results],
            ),
          ),
        ],
      );
    });
  }

  /// Основното показание: първият избран показател, голям и с цветна скала.
  Widget _buildHero(UserData data, MeasurementService m, List<String> indicators) {
    final theme = Theme.of(context);
    final main = indicators.first;
    final value = m.levels[main];
    final recording = m.recordingId != null;
    final (statusLabel, statusColor) = switch (m.status) {
      MeasurementStatus.connecting => ('СВЪРЗВАНЕ', AppColors.accent),
      MeasurementStatus.running when recording => ('ЗАПИС', const Color(0xFFFF6B6B)),
      MeasurementStatus.running => ('ИЗМЕРВАНЕ', const Color(0xFF5BE3A0)),
      MeasurementStatus.error => ('ГРЕШКА', const Color(0xFFFF6B6B)),
      MeasurementStatus.idle => ('ГОТОВ', Colors.white70),
    };
    // Скала 20-120 dB за лентата под числото.
    final fraction = value == null ? 0.0 : ((value - 20) / 100).clamp(0.0, 1.0);
    final white70 = Colors.white.withValues(alpha: 0.72);

    Widget miniStat(String code) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(indicatorName(code), style: theme.textTheme.labelMedium?.copyWith(color: white70)),
              const SizedBox(height: 2),
              Text(
                m.levels[code]?.toStringAsFixed(1) ?? '--.-',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontFeatures: tabularFigures,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x400B2545), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusPill(label: statusLabel, color: statusColor, onDark: true),
              const Spacer(),
              if (m.isRunning)
                Text(
                  formatDuration(m.elapsed),
                  style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontFeatures: tabularFigures),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(indicatorName(main), style: theme.textTheme.titleMedium?.copyWith(color: white70)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value?.toStringAsFixed(1) ?? '--.-',
                style: theme.textTheme.displayLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 76,
                  height: 1.05,
                  letterSpacing: -2,
                  fontFeatures: tabularFigures,
                ),
              ),
              const SizedBox(width: 8),
              Text('dB', style: theme.textTheme.headlineSmall?.copyWith(color: white70, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Stack(
              children: [
                Container(height: 8, color: Colors.white.withValues(alpha: 0.15)),
                AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 120),
                  widthFactor: fraction,
                  child: Container(height: 8, color: AppColors.forLevel(value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [miniStat('LAeq'), miniStat('LAFmax'), miniStat('LAFmin')]),
          const SizedBox(height: 20),
          _buildStartButton(data, m),
        ],
      ),
    );
  }

  Widget _buildConfigCard(UserData data, bool running) {
    final theme = Theme.of(context);
    if (data.devices.isEmpty) {
      return const SectionCard(
        title: 'Няма устройство',
        icon: Icons.mic_off_outlined,
        child: Text('Добавете микрофона от менюто "Устройства", за да започнете измерване.'),
      );
    }
    final device = data.devices.where((d) => d.id == _deviceId).firstOrNull;
    final calibrationWarning = device == null || device.calibrationStatus == 'valid'
        ? null
        : switch (device.calibrationStatus) {
            'expired' => 'Срокът на калибровката на устройството е изтекъл.',
            'due_soon' => 'Калибровката изтича скоро (${device.nextCalibrationDue == null ? '' : '${device.nextCalibrationDue!.day}.${device.nextCalibrationDue!.month}.${device.nextCalibrationDue!.year}'}).',
            _ => 'Устройството не е калибрирано.',
          };

    // По време на измерване параметрите не могат да се променят - показваме кратко обобщение.
    if (running) {
      Widget chip(IconData icon, String text) => Chip(
            avatar: Icon(icon, size: 16, color: theme.colorScheme.primary),
            label: Text(text),
            visualDensity: VisualDensity.compact,
          );
      return SectionCard(
        title: 'Параметри',
        icon: Icons.tune_rounded,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (device != null) chip(Icons.mic_rounded, device.title),
            chip(Icons.straighten_rounded, '${_fMin.text}–${_fMax.text} Hz'),
            if (_bandMode != 'off') chip(Icons.bar_chart_rounded, '$_bandMode октава'),
            if (_record) chip(Icons.save_outlined, _saveWav ? 'Запис + WAV' : 'Запис'),
          ],
        ),
      );
    }

    return SectionCard(
      title: 'Параметри',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Устройство',
              prefixIcon: const Icon(Icons.mic_rounded),
              helperText: device == null
                  ? null
                  : 'Работна лента: ${formatHz(device.freqMinHz)} – ${formatHz(device.freqMaxHz)}',
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _deviceId,
                isExpanded: true,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                items: [
                  for (final d in data.devices)
                    DropdownMenuItem(value: d.id, child: Text('${d.title}  ·  S/N ${d.serialNumber}')),
                ],
                onChanged: running ? null : (v) => setState(() => _deviceId = v),
              ),
            ),
          ),
          if (calibrationWarning != null) ...[
            const SizedBox(height: 12),
            InfoBanner(
              message: calibrationWarning,
              color: AppColors.forCalibration(device!.calibrationStatus),
              icon: Icons.warning_amber_rounded,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fMin,
                  enabled: !running,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'От', suffixText: 'Hz'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _fMax,
                  enabled: !running,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'До', suffixText: 'Hz'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Октавни ленти', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          BandModeSelector(value: _bandMode, onChanged: running ? null : (v) => setState(() => _bandMode = v)),
          const SizedBox(height: 16),
          // Изискване 4: запис на нивата с филтрите, октавните ленти и (по желание) WAV.
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _record ? AppColors.danger.withValues(alpha: 0.06) : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _record ? AppColors.danger.withValues(alpha: 0.3) : theme.colorScheme.outlineVariant,
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.fiber_manual_record_rounded, color: _record ? AppColors.danger : null),
                  title: const Text('Запис на измерването'),
                  subtitle: const Text('Нивата и лентите се записват в историята всяка секунда'),
                  value: _record,
                  onChanged: running ? null : (v) => setState(() => _record = v),
                ),
                if (_record) ...[
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Необработен сигнал (WAV)'),
                    subtitle: const Text('≈ 690 MB на час при 48 kHz'),
                    value: _saveWav,
                    onChanged: running ? null : (v) => setState(() => _saveWav = v ?? false),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: TextField(
                      controller: _name,
                      enabled: !running,
                      decoration: const InputDecoration(
                        labelText: 'Наименование (по желание)',
                        prefixIcon: Icon(Icons.label_outline_rounded),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton(UserData data, MeasurementService m) {
    if (m.isRunning) {
      final recording = m.recordingId != null;
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.danger,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.15),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size.fromHeight(56),
        ),
        onPressed: m.status == MeasurementStatus.running ? m.stop : null,
        icon: Icon(recording ? Icons.stop_circle_outlined : Icons.stop_rounded),
        label: Text(m.status == MeasurementStatus.connecting
            ? 'Свързване…'
            : (recording ? 'Спри записа' : 'Спри измерването')),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.15),
        disabledForegroundColor: Colors.white60,
        minimumSize: const Size.fromHeight(56),
      ),
      onPressed: data.devices.isEmpty ? null : () => _start(data),
      icon: Icon(
        _record ? Icons.fiber_manual_record_rounded : Icons.play_arrow_rounded,
        color: _record && data.devices.isNotEmpty ? AppColors.danger : null,
      ),
      label: Text(_record ? 'Старт със запис' : 'Старт'),
    );
  }

  Widget _buildSavedBanner(int measurementId) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InfoBanner(
        message: 'Записът е запазен в историята',
        color: AppColors.success,
        icon: Icons.check_circle_outline_rounded,
        action: TextButton(
          onPressed: () => openMeasurementDetail(context, measurementId),
          child: const Text('Отвори'),
        ),
      ),
    );
  }

  Widget _buildIndicatorGrid(List<String> indicators, Map<String, double> levels) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 600 ? 4 : (constraints.maxWidth > 480 ? 3 : 2);
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final code in indicators)
            Container(
              width: width,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: isDark ? 1 : 0.5)),
                boxShadow: isDark ? null : softShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Цветна лента вляво - от зелено (тихо) до червено (шумно).
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 5,
                      color: levels[code] == null ? theme.colorScheme.outlineVariant : AppColors.forLevel(levels[code]),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              indicatorName(code),
                              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  levels[code]?.toStringAsFixed(1) ?? '--.-',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontFeatures: tabularFigures,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'dB',
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _section({required String title, IconData? icon, Widget? trailing, required Widget child}) {
    return SectionCard(title: title, icon: icon, trailing: trailing, child: child);
  }
}
