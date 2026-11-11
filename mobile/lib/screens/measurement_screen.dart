import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/measurement_service.dart';
import '../services/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/ui.dart';
import 'calibration_form_screen.dart';
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
  final _location = TextEditingController();
  final _source = TextEditingController();
  // Записът е включен по подразбиране - така мястото и нормите се попълват при всяко измерване.
  bool _record = true;
  bool _saveWav = false;
  bool _initialized = false;
  String? _validationError;
  final List<String> _chartCodes = [];
  String? _standardCode;
  String? _zoneCode;
  String? _period; // null - по часа на измерването

  /// Вид на мястото: закрито помещение (акустичен шум) или открито място (фонов шум).
  String _placeType = 'indoor';

  /// Брой точки в помещението - избира се на място според големината му - и текущата точка.
  int _pointCount = 1;
  int _pointNo = 1;

  /// Общ идентификатор на точките от едно помещение.
  String? _seriesId;

  /// Последният запис, след който вече е избрана следващата точка.
  int? _advancedAfter;

  /// Устройството и работната му лента, за които е попълнен интервалът. При смяна на
  /// устройството или на лентата му интервалът се попълва наново.
  String? _bandKey;

  @override
  void dispose() {
    for (final c in [_fMin, _fMax, _name, _location, _source]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  /// Попълва полетата от настройките на потребителя, след като се заредят.
  void _initFrom(UserData data) {
    final s = data.settings;
    if (_initialized || s == null) return;
    _initialized = true;
    _bandMode = s.bandMode;
    if (data.devices.isNotEmpty) _deviceId = data.devices.first.id;
  }

  /// Измервателният интервал по подразбиране е работната лента на микрофона
  /// (при първо зареждане - пресечена с интервала от настройките).
  void _syncInterval(UserData data, Device? device, bool running) {
    if (device == null || running) return;
    final key = '${device.id}:${device.freqMinHz}-${device.freqMaxHz}';
    if (key == _bandKey) return;
    final first = _bandKey == null;
    _bandKey = key;
    var fMin = device.freqMinHz;
    var fMax = device.freqMaxHz;
    final s = data.settings;
    if (first && s != null) {
      final lo = s.fMinHz > fMin ? s.fMinHz : fMin;
      final hi = s.fMaxHz < fMax ? s.fMaxHz : fMax;
      if (lo < hi) {
        fMin = lo;
        fMax = hi;
      }
    }
    _fMin.text = _fmt(fMin);
    _fMax.text = _fmt(fMax);
  }

  /// true, ако интервалът излиза извън работната лента на микрофона.
  bool _outOfBand(Device? device) {
    final fMin = _num(_fMin);
    final fMax = _num(_fMax);
    if (device == null || fMin == null || fMax == null) return false;
    return fMin < device.freqMinHz || fMax > device.freqMaxHz;
  }

  Future<void> _start(UserData data) async {
    final device = data.devices.where((d) => d.id == _deviceId).firstOrNull;
    final fMin = _num(_fMin);
    final fMax = _num(_fMax);

    String? error;
    if (device == null) {
      error = tr('Изберете устройство');
    } else if (fMin == null || fMax == null) {
      error = tr('Въведете измервателния интервал');
    } else if (fMin < absFMinHz || fMax > absFMaxHz || fMin >= fMax) {
      error = tr('Интервалът трябва да е между {min} Hz и {max} Hz', {'min': absFMinHz.toInt(), 'max': absFMaxHz.toInt()});
    }
    setState(() => _validationError = error);
    if (error != null) return;

    // Калибровката се прави преди всяко измерване със запис.
    if (_record && !await _confirmCalibration(data, device!)) return;
    if (!mounted) return;
    // Новата серия от точки получава свой идентификатор при първата точка.
    if (_pointCount > 1 && (_seriesId == null || _pointNo == 1)) {
      _seriesId = '${DateTime.now().microsecondsSinceEpoch}-${device!.id}';
    }

    context.read<MeasurementService>().start(
          deviceId: device!.id!,
          fMin: fMin!,
          fMax: fMax!,
          bandMode: _bandMode,
          record: _record,
          saveWav: _saveWav,
          name: _name.text,
          location: _location.text,
          placeType: _placeType,
          pointNo: _pointCount > 1 ? _pointNo : null,
          pointCount: _pointCount > 1 ? _pointCount : null,
          seriesId: _pointCount > 1 ? _seriesId : null,
          source: _source.text,
          zoneCode: _zoneCode,
          period: _period,
          standardCode: _standardCode ?? data.defaultStandard?.code,
        );
  }

  /// Подкана за калибровка преди запис. Не се показва, ако уредът е калибриран през последния час.
  /// Връща true, ако измерването да започне.
  Future<bool> _confirmCalibration(UserData data, Device device) async {
    final last = device.lastCalibrationAt;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 1)) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Затваряне (отказ) с X в горния десен ъгъл.
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(tr('Калибровка преди измерване'))),
            IconButton(
              tooltip: tr('Отказ'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
        content: Text(
          last == null
              ? tr('Калибрирайте микрофона с акустичния калибратор преди всяко измерване, '
                  'за да са резултатите проследими.')
              : tr('Последната калибровка на {device} е преди {days} дни ({date}). Да се направи ли нова преди записа?', {
                  'device': device.title,
                  'days': DateTime.now().difference(last).inDays,
                  'date': '${last.day.toString().padLeft(2, '0')}.${last.month.toString().padLeft(2, '0')}.${last.year}',
                }),
          style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: Text(tr('Без калибровка'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, 'calibrate'),
            child: Text(tr('Калибрирай')),
          ),
        ],
      ),
    );
    if (choice == 'skip') return true;
    if (choice != 'calibrate' || !mounted) return false;
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CalibrationFormScreen(device: device, automatic: true),
    ));
    if (done != true) return false;
    await data.load(); // новата корекция на устройството
    return mounted;
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<UserData>();
    final m = context.watch<MeasurementService>();
    _initFrom(data);

    if (data.loading && data.settings == null) return const Center(child: CircularProgressIndicator());
    if (data.settings == null) {
      return Center(child: Text(data.error ?? tr('Настройките не са заредени')));
    }

    // Устройството може да е изтрито от екрана "Устройства".
    if (_deviceId != null && !data.devices.any((d) => d.id == _deviceId)) {
      _deviceId = data.devices.firstOrNull?.id;
    }
    _deviceId ??= data.devices.firstOrNull?.id;

    final indicators = data.settings!.indicators;
    // Показателите в графиката "Във времето" - избират се с отметките под дисплея.
    _chartCodes.retainWhere(indicators.contains);
    if (_chartCodes.isEmpty) _chartCodes.add(indicators.first);
    final running = m.isRunning;
    final device = data.devices.where((d) => d.id == _deviceId).firstOrNull;
    _syncInterval(data, device, running);
    final outOfBand = running ? m.outOfBand : _outOfBand(device);
    _advancePoint(m);
    const gap = SizedBox(height: 24);

    final instrument = <Widget>[
      _buildHero(data, m, indicators),
      // Предупреждението за интервала - червен банер точно под дисплея.
      if (outOfBand && device != null) ...[
        const SizedBox(height: 12),
        _buildOutOfBandBanner(device, running),
      ],
      if (!running && m.lastSavedId != null) _buildSavedBanner(m.lastSavedId!),
      if (_validationError != null || m.error != null) ...[
        const SizedBox(height: 12),
        InfoBanner(message: _validationError ?? m.error!, color: AppColors.danger, icon: Icons.error_outline_rounded),
      ],
    ];

    // По време на измерване: отметки за графиката, графика във времето и спектър.
    final results = <Widget>[
      _buildSeriesChips(indicators, m.levels),
      gap,
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(tr('Във времето'), style: sectionLabelStyle(context))),
          Text(tr('(посл. {p0} s)', {'p0': MeasurementService.historySeconds.toInt()}),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(height: 180, child: _buildHistoryChart(m)),
      if (m.bands != null) ...[
        gap,
        Text(tr('Спектър {p0} октава', {'p0': m.bands!.mode}), style: sectionLabelStyle(context)),
        const SizedBox(height: 8),
        SizedBox(height: 200, child: BandChart(spectrum: m.bands!)),
      ],
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final twoColumns = constraints.maxWidth >= 600;

      final List<Widget> config;
      if (data.devices.isEmpty) {
        config = [
          SectionCard(
            title: tr('Няма устройство'),
            child: Text(tr('Добавете микрофона от менюто "Устройства", за да започнете измерване.')),
          ),
        ];
      } else if (running) {
        config = [_buildRunningSummary(data, device)];
      } else if (twoColumns && !wide) {
        // Таблет в портрет: параметри и място една до друга, записът отдолу.
        config = [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildParams(data, device)),
              const SizedBox(width: 24),
              Expanded(child: _record ? _buildPlace(data, device) : _buildRecording()),
            ],
          ),
          if (_record) ...[gap, _buildRecording()],
        ];
      } else {
        // Записът е преди мястото и нормите - превключвателят решава дали те се показват.
        config = [
          _buildParams(data, device),
          gap,
          _buildRecording(),
          if (_record) ...[gap, _buildPlace(data, device)],
        ];
      }

      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 32),
                children: [...instrument, gap, if (running) ...results else _buildSystemInfo(device)],
              ),
            ),
            Expanded(flex: 4, child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 20, 32), children: config)),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ReadableWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...instrument, gap, if (running) ...[...results, gap], ...config],
            ),
          ),
        ],
      );
    });
  }

  /// Мерната единица на основния показател: dB(A), dB(C), dB(Z) или dB (Lp без филтър).
  static String _unit(String code) => switch (code.length > 1 ? code[1] : '') {
        'A' => 'dB(A)',
        'C' => 'dB(C)',
        'Z' => 'dB(Z)',
        _ => 'dB',
      };

  /// Дисплеят: състояние, показанието, цветна скала и бутонът за старт/стоп.
  Widget _buildHero(UserData data, MeasurementService m, List<String> indicators) {
    final main = indicators.first;
    final value = m.levels[main];
    final recording = m.recordingId != null;
    final running = m.isRunning;
    final (statusLabel, statusColor) = switch (m.status) {
      MeasurementStatus.connecting => (tr('Свързване…'), const Color(0xFFF0C93A)),
      MeasurementStatus.running when recording => (tr('Запис'), const Color(0xFFFF5A52)),
      MeasurementStatus.running => (tr('Измерване'), AppColors.displayAccent),
      MeasurementStatus.error => (tr('Грешка'), const Color(0xFFFF5A52)),
      MeasurementStatus.idle => (tr('Готов'), AppColors.displayAccent),
    };

    final status = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (recording) ...[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Text(
          running ? '$statusLabel ${formatDuration(m.elapsed)}' : statusLabel,
          style: monoStyle(15, weight: FontWeight.w500, color: statusColor),
        ),
      ],
    );

    Widget subMetric(String code) => Expanded(
          child: Tooltip(
            message: indicatorDescription(code),
            triggerMode: TooltipTriggerMode.tap,
            child: Column(
              children: [
                Text(indicatorName(code), style: monoStyle(13, weight: FontWeight.w500, color: AppColors.displayText)),
                const SizedBox(height: 2),
                Text(m.levels[code]?.toStringAsFixed(1) ?? '—', style: monoStyle(13, color: AppColors.displayLabel)),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(color: AppColors.display, borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          status,
          const SizedBox(height: 10),
          Center(
            child: Tooltip(
              message: '${indicatorName(main)} - ${indicatorDescription(main)}',
              triggerMode: TooltipTriggerMode.tap,
              child: value == null
                  // Без показание - къса бяла черта, както на уред в покой.
                  ? Container(width: 44, height: 5, margin: const EdgeInsets.symmetric(vertical: 26), color: AppColors.displayText)
                  : Text('${value.toStringAsFixed(1)} ${_unit(main)}',
                      style: monoStyle(56, weight: FontWeight.w500, color: AppColors.displayValue, height: 1.1)),
            ),
          ),
          if (running) ...[
            const SizedBox(height: 12),
            _LevelScale(value: value),
            const SizedBox(height: 12),
            Row(children: [subMetric('LAeq'), subMetric('LAFmax'), subMetric('LAFmin')]),
          ],
          const SizedBox(height: 16),
          _buildStartButton(data, m),
        ],
      ),
    );
  }

  Widget _buildOutOfBandBanner(Device device, bool running) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
      child: Column(
        children: [
          Text(
            tr('Интервалът излиза извън работната лента на микрофона ({min} – {max}). '
                'Измерването е ненадеждно.', {'min': formatHz(device.freqMinHz), 'max': formatHz(device.freqMaxHz)}),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          if (!running)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => setState(() {
                _fMin.text = _fmt(device.freqMinHz);
                _fMax.text = _fmt(device.freqMaxHz);
              }),
              child: Text(tr('Поправи')),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _footnote(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
      );

  /// Параметрите по време на измерване - само за справка.
  Widget _buildRunningSummary(UserData data, Device? device) {
    final standard = data.standards.where((s) => s.code == _standardCode).firstOrNull ?? data.defaultStandard;
    return RowGroup(
      title: tr('Параметри'),
      children: [
        if (device != null) ValueRow(label: tr('Устройство'), value: device.title),
        ValueRow(label: tr('Интервал'), value: '${_hz(_fMin)} – ${_hz(_fMax)}'),
        if (standard != null) ValueRow(label: tr('Стандарт'), value: standard.name),
        ValueRow(label: tr('Октавни ленти'), value: _bandLabel),
        if (_record && _location.text.isNotEmpty) ValueRow(label: tr('Място'), value: _location.text),
        if (_record && _pointCount > 1)
          ValueRow(label: tr('Точка'), value: tr('{p0} от {p1}', {'p0': _pointNo, 'p1': _pointCount})),
      ],
    );
  }

  String get _bandLabel => _bandMode == 'off' ? tr('Без') : tr('{mode} октава', {'mode': _bandMode});

  Widget _buildParams(UserData data, Device? device) {
    final standard = data.standards.where((s) => s.code == _standardCode).firstOrNull ?? data.defaultStandard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RowGroup(
          title: tr('Параметри'),
          children: [
            ValueRow(label: tr('Устройство'), value: device?.title, onTap: () => _chooseDevice(data)),
            ValueRow(
              label: tr('Интервал'),
              value: '${_hz(_fMin)} – ${_hz(_fMax)}',
              valueColor: _outOfBand(device) ? AppColors.warning : null,
              onTap: device == null ? null : () => _editInterval(device),
            ),
            ValueRow(label: tr('Стандарт'), value: standard?.name, onTap: () => _chooseStandard(data, standard?.code)),
            ValueRow(label: tr('Октавни ленти'), value: _bandLabel, onTap: _chooseBandMode),
          ],
        ),
        if (device != null && !_record)
          _footnote(tr('Работна лента на микрофона: {min} – {max}',
              {'min': formatHz(device.freqMinHz), 'max': formatHz(device.freqMaxHz)})),
      ],
    );
  }

  /// Изискване 4: запис на нивата с филтрите, октавните ленти и (по желание) WAV.
  Widget _buildRecording() {
    return RowGroup(
      title: tr('Запис'),
      children: [
        SwitchRow(label: tr('Запис на измерването'), value: _record, onChanged: (v) => setState(() => _record = v)),
        if (_record)
          SwitchRow(
            label: tr('Необработен сигнал (WAV)'),
            detail: tr('≈ 690 MB на час при 48 kHz'),
            value: _saveWav,
            onChanged: (v) => setState(() => _saveWav = v),
          ),
      ],
    );
  }

  /// Място и норми - задават се при измерването. След това само администраторът може да ги промени.
  /// Редовете са като "Параметри"; празните текстови полета показват синьо "Добави".
  Widget _buildPlace(UserData data, Device? device) {
    final theme = Theme.of(context);
    final zone = data.zoneByCode(_zoneCode);
    String f(double? v) => v == null ? '–' : v.toStringAsFixed(0);

    Widget textRow(String label, TextEditingController c, String title, {String? hint}) => ValueRow(
          label: label,
          value: c.text.isEmpty ? tr('Добави') : c.text,
          valueColor: c.text.isEmpty ? AppColors.primary : null,
          onTap: () => _editText(c, title, hint: hint),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RowGroup(
          title: tr('Място и норми'),
          children: [
            textRow(tr('Наименование'), _name, tr('Наименование')),
            ValueRow(label: tr('Вид на мястото'), value: _placeTypeName(_placeType), onTap: () => _choosePlaceType(data)),
            textRow(tr('Място'), _location, tr('Място на измерване'),
                hint: _placeType == 'indoor' ? tr('Зала 2, бул. Витоша 10') : tr('бул. Витоша 10, пред вх. А')),
            ValueRow(label: tr('Брой точки'), value: '$_pointCount', onTap: _choosePointCount),
            if (_pointCount > 1)
              ValueRow(
                label: tr('Текуща точка'),
                value: tr('{p0} от {p1}', {'p0': _pointNo, 'p1': _pointCount}),
                onTap: _choosePointNo,
              ),
            textRow(tr('Източник'), _source, tr('Източник / режим'), hint: tr('Автомобилен трафик')),
            ValueRow(
              label: tr('Зона'),
              value: zone == null ? tr('Без норма') : _zoneLabel(zone),
              onTap: () => _chooseZone(data),
            ),
            ValueRow(label: tr('Период'), value: periodName(_period), onTap: _choosePeriod),
          ],
        ),
        const SizedBox(height: 4),
        if (device != null)
          Text('* ${tr('Работна лента на микрофона: {min} – {max}', {'min': formatHz(device.freqMinHz), 'max': formatHz(device.freqMaxHz)})}',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
        if (zone != null)
          Text('** ${tr('Норми (ден / вечер / нощ): {d} / {e} / {n} dB(A)', {'d': f(zone.day), 'e': f(zone.evening), 'n': f(zone.night)})}',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }

  /// Таблет в пейзаж, преди измерване: към кой сървър и с кой микрофон се мери.
  Widget _buildSystemInfo(Device? device) {
    return SectionCard(
      title: tr('Система'),
      child: Column(
        children: [
          InfoRow(label: tr('Сървър'), value: context.read<AuthService>().serverUrl),
          InfoRow(
            label: tr('Микрофон'),
            value: device == null ? '–' : '${device.title} (S/N ${device.serialNumber})',
            divider: false,
          ),
        ],
      ),
    );
  }

  String _hz(TextEditingController c) {
    final v = _num(c);
    return v == null ? '–' : formatHz(v);
  }

  String _placeTypeName(String type) => type == 'indoor' ? tr('Закрито помещение') : tr('Открито място');

  /// След запазване на точка от серията се избира следващата; след последната - нова серия.
  void _advancePoint(MeasurementService m) {
    final saved = m.lastSavedId;
    if (saved == null || saved == _advancedAfter || m.isRunning) return;
    _advancedAfter = saved;
    if (_pointCount <= 1) return;
    if (_pointNo < _pointCount) {
      _pointNo++;
    } else {
      _pointNo = 1;
      _seriesId = null;
    }
  }

  Future<void> _choosePlaceType(UserData data) async {
    final type = await showChoiceSheet<String>(
      context,
      title: tr('Вид на мястото'),
      selected: _placeType,
      options: [
        ('indoor', tr('Закрито помещение'), tr('Акустичен шум в зала, стая, офис')),
        ('outdoor', tr('Открито място'), tr('Фонов шум на открито')),
      ],
    );
    if (type == null || type == _placeType) return;
    setState(() {
      _placeType = type;
      // Зоната трябва да е от същия вид (помещения или открити територии).
      if (data.zoneByCode(_zoneCode)?.category != type) _zoneCode = null;
    });
  }

  /// Максимален брой точки в едно помещение (същото ограничение има и сървърът).
  static const _maxPoints = 100;

  /// Число, въведено от клавиатурата; null при отказ или невалидна стойност (тогава се показва съобщение).
  Future<int?> _askNumber(String title, int current, int max) async {
    final text = await showTextSheet(
      context,
      title: title,
      initial: '$current',
      hint: tr('От 1 до {p0}', {'p0': max}),
      keyboardType: TextInputType.number,
      confirmLabel: tr('Запази'),
    );
    if (text == null || !mounted) return null;
    final n = int.tryParse(text);
    if (n == null || n < 1 || n > max) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Въведете цяло число от 1 до {p0}', {'p0': max}))));
      return null;
    }
    return n;
  }

  /// Броят на точките се въвежда на място според големината на помещението.
  Future<void> _choosePointCount() async {
    final n = await _askNumber(tr('Брой точки'), _pointCount, _maxPoints);
    if (n == null || n == _pointCount) return;
    setState(() {
      _pointCount = n;
      _pointNo = 1;
      _seriesId = null;
    });
  }

  /// Точката, която ще се измерва; може да се смени, напр. за повторение на точка.
  Future<void> _choosePointNo() async {
    final n = await _askNumber(tr('Текуща точка'), _pointNo, _pointCount);
    if (n != null) setState(() => _pointNo = n);
  }

  // Видът на мястото е избран отделно, затова помещенията се показват само с името си.
  String _zoneLabel(Zone z) => z.category == 'indoor' ? z.name : '${z.code}. ${z.name}';

  Future<void> _chooseDevice(UserData data) async {
    final id = await showChoiceSheet<int>(
      context,
      title: tr('Устройство'),
      selected: _deviceId,
      options: [
        for (final d in data.devices)
          (d.id!, d.title, 'S/N ${d.serialNumber}  ·  ${formatHz(d.freqMinHz)} – ${formatHz(d.freqMaxHz)}'),
      ],
    );
    if (id != null) setState(() => _deviceId = id);
  }

  Future<void> _chooseStandard(UserData data, String? current) async {
    final code = await showChoiceSheet<String>(
      context,
      title: tr('Стандарт'),
      selected: current,
      options: [for (final s in data.standards) (s.code, s.name, null)],
    );
    if (code != null) setState(() => _standardCode = code);
  }

  Future<void> _chooseBandMode() async {
    final mode = await showChoiceSheet<String>(
      context,
      title: tr('Октавни ленти'),
      selected: _bandMode,
      options: [
        ('off', tr('Без'), null),
        ('1/1', tr('{mode} октава', {'mode': '1/1'}), null),
        ('1/3', tr('{mode} октава', {'mode': '1/3'}), null),
      ],
    );
    if (mode != null) setState(() => _bandMode = mode);
  }

  Future<void> _chooseZone(UserData data) async {
    // '' означава "без норма" - null е отказ от избора.
    final code = await showChoiceSheet<String>(
      context,
      title: tr('Зона (Наредба № 6/2006)'),
      selected: _zoneCode ?? '',
      options: [
        ('', tr('Без норма'), null),
        for (final z in data.zones.where((z) => z.category == _placeType)) (z.code, _zoneLabel(z), null),
      ],
    );
    if (code != null) setState(() => _zoneCode = code.isEmpty ? null : code);
  }

  Future<void> _choosePeriod() async {
    final period = await showChoiceSheet<String>(
      context,
      title: tr('Период от денонощието'),
      selected: _period ?? '',
      options: [for (final p in [null, ...periods]) (p ?? '', periodName(p), null)],
    );
    if (period != null) setState(() => _period = period.isEmpty ? null : period);
  }

  Future<void> _editText(TextEditingController c, String title, {String? hint}) async {
    final value = await showTextSheet(context, title: title, initial: c.text, hint: hint, confirmLabel: tr('Запази'));
    if (value != null) setState(() => c.text = value);
  }

  /// Измервателният интервал - в долен лист с двете граници и работната лента на микрофона.
  Future<void> _editInterval(Device device) async {
    final from = TextEditingController(text: _fMin.text);
    final to = TextEditingController(text: _fMax.text);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        InputDecoration deco(String label) => InputDecoration(labelText: label, suffixText: 'Hz');
        const number = TextInputType.numberWithOptions(decimal: true);
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Измервателен интервал'), style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                tr('Честотите, които се включват в измерването. Сигналът извън интервала се филтрира. '
                    'По подразбиране е работната лента на микрофона.'),
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(controller: from, keyboardType: number, decoration: deco(tr('От')))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: to, keyboardType: number, decoration: deco(tr('До')))),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    from.text = _fmt(device.freqMinHz);
                    to.text = _fmt(device.freqMaxHz);
                  },
                  child: Text(tr('Работна лента на микрофона: {min} – {max}',
                      {'min': formatHz(device.freqMinHz), 'max': formatHz(device.freqMaxHz)})),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Запази'))),
            ],
          ),
        );
      },
    );
    if (saved == true) {
      setState(() {
        _fMin.text = from.text.trim();
        _fMax.text = to.text.trim();
      });
    }
    from.dispose();
    to.dispose();
  }

  Widget _buildStartButton(UserData data, MeasurementService m) {
    if (m.isRunning) {
      final recording = m.recordingId != null;
      return FilledButton(
        style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
        onPressed: m.status == MeasurementStatus.running ? m.stop : null,
        child: Text(m.status == MeasurementStatus.connecting
            ? tr('Свързване…')
            : (recording ? tr('Спри записа') : tr('Спри измерването'))),
      );
    }
    return FilledButton(
      onPressed: data.devices.isEmpty ? null : () => _start(data),
      child: Text(_record ? tr('Старт със запис') : tr('Старт')),
    );
  }

  Widget _buildSavedBanner(int measurementId) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InfoBanner(
        // При серия от точки: коя е следващата точка или че помещението е завършено.
        message: _pointCount <= 1
            ? tr('Записът е запазен в историята')
            : _pointNo == 1
                ? tr('Всички {p0} точки са записани', {'p0': _pointCount})
                : tr('Точката е записана. Следва точка {p0} от {p1}', {'p0': _pointNo, 'p1': _pointCount}),
        color: AppColors.success,
        icon: Icons.check_circle_outline_rounded,
        action: TextButton(
          onPressed: () => openMeasurementDetail(context, measurementId),
          child: Text(tr('Отвори')),
        ),
      ),
    );
  }

  /// Цветовете на кривите в графиката - в реда на отметките.
  static const _seriesColors = [
    AppColors.primary,
    AppColors.danger,
    AppColors.success,
    AppColors.warning,
    Color(0xFF7B4FD0),
    Color(0xFF0097A7),
  ];

  /// Отметки под дисплея: кои показатели да се чертаят в графиката "Във времето".
  Widget _buildSeriesChips(List<String> indicators, Map<String, double> levels) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 600 ? 4 : 3;
      const spacing = 8.0;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final code in indicators)
            SizedBox(
              width: width,
              child: Material(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() {
                    if (_chartCodes.contains(code)) {
                      if (_chartCodes.length > 1) _chartCodes.remove(code);
                    } else {
                      _chartCodes.add(code);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _chartCodes.contains(code),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          activeColor: _chartCodes.contains(code)
                              ? _seriesColors[_chartCodes.indexOf(code) % _seriesColors.length]
                              : null,
                          onChanged: null,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(indicatorName(code), style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13.5)),
                              Text(levels[code]?.toStringAsFixed(1) ?? '—', style: monoStyle(13, weight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  /// Графиката във времето с избраните показатели.
  Widget _buildHistoryChart(MeasurementService m) {
    final lines = [
      for (final (i, c) in _chartCodes.indexed) ChartLine(m.history[c] ?? const [], _seriesColors[i % _seriesColors.length]),
    ];
    var last = 0.0;
    for (final l in lines) {
      if (l.points.isNotEmpty && l.points.last.$1 > last) last = l.points.last.$1;
    }
    final maxX = last == 0 ? MeasurementService.historySeconds : last;
    return LevelLineChart(
      lines: lines,
      minX: maxX - MeasurementService.historySeconds < 0 ? 0 : maxX - MeasurementService.historySeconds,
      maxX: maxX < 1 ? 1 : maxX,
      xInterval: 10,
      xLabel: (v) => '${v.toInt()} s',
    );
  }

}

/// Цветна скала 20-120 dB (синьо - зелено - жълто - червено) с маркер на текущото ниво.
class _LevelScale extends StatelessWidget {
  const _LevelScale({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final fraction = value == null ? 0.0 : ((value! - 20) / 100).clamp(0.0, 1.0);
    final label = monoStyle(11, color: AppColors.displayLabel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final x = constraints.maxWidth * fraction;
          return SizedBox(
            height: 14,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 3,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(colors: AppColors.scale),
                    ),
                  ),
                ),
                // Частта над текущото ниво е затъмнена.
                Positioned(
                  left: x,
                  right: 0,
                  top: 3,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.display.withValues(alpha: 0.72),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                    ),
                  ),
                ),
                if (value != null)
                  Positioned(
                    left: (x - 1.5).clamp(0, constraints.maxWidth - 3),
                    top: 0,
                    width: 3,
                    height: 14,
                    child: const DecoratedBox(decoration: BoxDecoration(color: Colors.white)),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('20', style: label),
            Expanded(
              child: Text(value == null ? '' : value!.toStringAsFixed(1), textAlign: TextAlign.center, style: label),
            ),
            Text('120', style: label),
          ],
        ),
      ],
    );
  }
}
