import '../l10n/l10n.dart';

class User {
  User({
    required this.id,
    required this.username,
    required this.email,
    this.firstName,
    this.lastName,
    this.isAdmin = false,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        username: j['username'],
        email: j['email'],
        firstName: j['first_name'],
        lastName: j['last_name'],
        isAdmin: j['is_admin'] == true,
      );

  final int id;
  final String username;
  final String email;
  final String? firstName;
  final String? lastName;

  /// Администраторът вижда историята на всички, редактира и трие записи и управлява нормите.
  final bool isAdmin;

  String get displayName {
    final full = [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return full.isEmpty ? username : full;
  }
}

/// Входно устройство (измервателен микрофон).
class Device {
  Device({
    this.id,
    required this.brand,
    required this.model,
    required this.serialNumber,
    required this.sensitivityDbfs,
    required this.freqMinHz,
    required this.freqMaxHz,
    this.calibrationOffsetDb,
    this.calibrationIntervalMonths = 12,
    this.lastCalibrationAt,
    this.nextCalibrationDue,
    this.calibrationStatus = 'none',
  });

  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: j['id'],
        brand: j['brand'],
        model: j['model'],
        serialNumber: j['serial_number'],
        sensitivityDbfs: (j['sensitivity_dbfs'] as num).toDouble(),
        freqMinHz: (j['freq_min_hz'] as num).toDouble(),
        freqMaxHz: (j['freq_max_hz'] as num).toDouble(),
        calibrationOffsetDb: (j['calibration_offset_db'] as num?)?.toDouble(),
        calibrationIntervalMonths: j['calibration_interval_months'] as int?,
        lastCalibrationAt: j['last_calibration_at'] == null ? null : DateTime.parse(j['last_calibration_at']).toLocal(),
        nextCalibrationDue: j['next_calibration_due'] == null ? null : DateTime.parse(j['next_calibration_due']).toLocal(),
        calibrationStatus: j['calibration_status'] as String? ?? 'none',
      );

  final int? id;
  final String brand;
  final String model;
  final String serialNumber;
  final double sensitivityDbfs;
  final double freqMinHz;
  final double freqMaxHz;
  final double? calibrationOffsetDb;
  final int? calibrationIntervalMonths;
  final DateTime? lastCalibrationAt;
  final DateTime? nextCalibrationDue;

  /// "none", "valid", "due_soon" (до 30 дни) или "expired".
  final String calibrationStatus;

  String get title => '$brand $model';

  String get calibrationStatusName => switch (calibrationStatus) {
        'valid' => tr('калибриран'),
        'due_soon' => tr('калибровката изтича'),
        'expired' => tr('калибровката е изтекла'),
        _ => tr('некалибриран'),
      };

  Map<String, dynamic> toJson() => {
        'brand': brand,
        'model': model,
        'serial_number': serialNumber,
        'sensitivity_dbfs': sensitivityDbfs,
        'freq_min_hz': freqMinHz,
        'freq_max_hz': freqMaxHz,
        'calibration_interval_months': calibrationIntervalMonths,
      };
}

/// Лични настройки за измерване и избраните показатели.
class MeterSettings {
  MeterSettings({required this.indicators, required this.fMinHz, required this.fMaxHz, required this.bandMode});

  factory MeterSettings.fromJson(Map<String, dynamic> j) => MeterSettings(
        indicators: List<String>.from(j['indicators']),
        fMinHz: (j['f_min_hz'] as num).toDouble(),
        fMaxHz: (j['f_max_hz'] as num).toDouble(),
        bandMode: j['band_mode'],
      );

  final List<String> indicators;
  final double fMinHz;
  final double fMaxHz;
  final String bandMode;

  Map<String, dynamic> toJson() => {
        'indicators': indicators,
        'f_min_hz': fMinHz,
        'f_max_hz': fMaxHz,
        'band_mode': bandMode,
      };
}

/// Граници на измервателния интервал според заданието.
const double absFMinHz = 3;
const double absFMaxHz = 80000;
const int minIndicators = 5;

final _indicatorPattern = RegExp(r'^L([ACZ])(F|S|I|eq)(max|min)?$');

/// Ниво без честотен и без времеви филтър и неговите max/min.
const unweightedIndicators = ['Lp', 'Lpmax', 'Lpmin'];

/// Описание на показателя с думи, например LAFmax -> "Максимално ниво, филтър A, бързо (F)".
String indicatorDescription(String code) {
  switch (code) {
    case 'Lp':
      return tr('Звуково налягане без филтри');
    case 'Lpmax':
      return tr('Максимално звуково налягане без филтри');
    case 'Lpmin':
      return tr('Минимално звуково налягане без филтри');
  }
  final m = _indicatorPattern.firstMatch(code);
  if (m == null) return '';
  final kind = switch (m[3]) {
    'max' => tr('Максимално ниво'),
    'min' => tr('Минимално ниво'),
    _ => m[2] == 'eq' ? tr('Еквивалентно ниво') : tr('Текущо ниво'),
  };
  final frequency = m[1] == 'Z' ? tr('без честотен филтър (Z)') : tr('филтър {fw}', {'fw': m[1]});
  final time = switch (m[2]) {
    'F' => tr('бързо (F)'),
    'S' => tr('бавно (S)'),
    'I' => tr('импулсно (I)'),
    _ => null,
  };
  return [kind, frequency, ?time].join(', ');
}

/// LAFmax -> LA,F,max (запис по IEC 61672-1).
String indicatorName(String code) {
  switch (code) {
    case 'Lp':
      return 'Lp';
    case 'Lpmax':
      return 'Lp,max';
    case 'Lpmin':
      return 'Lp,min';
  }
  final m = _indicatorPattern.firstMatch(code);
  if (m == null) return code;
  return ['L${m[1]}', m[2]!, if (m[3] != null) m[3]!].join(',');
}

String formatHz(double hz) {
  if (hz >= 1000) {
    final k = hz / 1000;
    return '${k == k.roundToDouble() ? k.toInt() : k.toStringAsFixed(1)} kHz';
  }
  return '${hz == hz.roundToDouble() ? hz.toInt() : hz} Hz';
}

double? _d(dynamic v) => (v as num?)?.toDouble();

Map<String, double> _levels(dynamic m) =>
    m == null ? {} : (m as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));

/// Записано измерване (изискване 4).
class Measurement {
  Measurement.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        startedAt = DateTime.parse(j['started_at']).toLocal(),
        endedAt = j['ended_at'] == null ? null : DateTime.parse(j['ended_at']).toLocal(),
        durationS = _d(j['duration_s'])!,
        fMinHz = _d(j['f_min_hz'])!,
        fMaxHz = _d(j['f_max_hz'])!,
        bandMode = j['band_mode'],
        deviceInfo = j['device_info'] as Map<String, dynamic>,
        indicators = List<String>.from(j['indicators']),
        summary = _levels(j['summary']),
        hasWav = j['has_wav'],
        location = j['location'],
        placeType = j['place_type'],
        pointNo = j['point_no'],
        pointCount = j['point_count'],
        seriesId = j['series_id'],
        source = j['source'],
        zoneCode = j['zone_code'],
        normDay = _d(j['norm_day']),
        normEvening = _d(j['norm_evening']),
        normNight = _d(j['norm_night']),
        period = j['period'],
        standardName = j['standard_name'],
        outOfBand = j['out_of_band'] == true,
        ownerUsername = j['owner_username'],
        frameCount = j['frame_count'],
        averageBands = j['average_bands'] == null ? null : BandsData.fromJson(j['average_bands']),
        seriesPoints = [
          for (final p in (j['series_points'] as List? ?? const []))
            (id: p['id'] as int, pointNo: p['point_no'] as int?, laeq: _d(p['laeq'])),
        ],
        seriesLaeq = _d(j['series_laeq']);

  final int id;
  final String? name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double durationS;
  final double fMinHz;
  final double fMaxHz;
  final String bandMode;
  final Map<String, dynamic> deviceInfo;
  final List<String> indicators;
  final Map<String, double> summary;
  final bool hasWav;
  // Място и норми (за отчетите и сертификатите)
  final String? location;

  /// "indoor" - закрито помещение, "outdoor" - открито място (фонов шум).
  final String? placeType;

  /// Точка от серия в едно помещение: № на точката и брой точки (избира се на място).
  final int? pointNo;
  final int? pointCount;
  final String? seriesId;
  final String? source;
  final String? zoneCode;
  final double? normDay;
  final double? normEvening;
  final double? normNight;

  /// "day", "evening", "night" или null - по часа на измерването.
  final String? period;
  final String? standardName;

  /// Интервалът излиза извън работната лента на микрофона - резултатът е ненадежден.
  final bool outOfBand;
  final String? ownerUsername;
  // Само в детайлния изглед:
  final int? frameCount;
  final BandsData? averageBands;

  /// Всички точки от серията и енергийното средно LAeq от тях.
  final List<({int id, int? pointNo, double? laeq})> seriesPoints;
  final double? seriesLaeq;

  bool get isSeries => (pointCount ?? 1) > 1 && pointNo != null;

  /// "т. 2/5" за точка от серия, иначе празно.
  String get pointLabel => isSeries ? tr('т. {p0}/{p1}', {'p0': pointNo, 'p1': pointCount}) : '';

  String get deviceTitle => '${deviceInfo['brand']} ${deviceInfo['model']}';
  String get title => (name == null || name!.isEmpty) ? tr('Измерване №{p0}', {'p0': id}) : name!;
}

class BandsData {
  BandsData(this.mode, this.centers, this.levels);

  BandsData.fromJson(Map<String, dynamic> j)
      : mode = j['mode'],
        centers = (j['centers'] as List).map((v) => (v as num).toDouble()).toList(),
        levels = (j['levels'] as List).map((v) => (v as num).toDouble()).toList();

  final String mode;
  final List<double> centers;
  final List<double> levels;
}

class TimelinePoint {
  TimelinePoint.fromJson(Map<String, dynamic> j)
      : ts = DateTime.parse(j['ts']).toLocal(),
        laeq = _d(j['LAeq'])!,
        lceq = _d(j['LCeq'])!,
        lzeq = _d(j['LZeq'])!,
        laeqMax = _d(j['LAeq_max'])!;

  final DateTime ts;
  final double laeq;
  final double lceq;
  final double lzeq;
  final double laeqMax;
}

/// Справка за период от историята (изискване 5).
class HistoryReport {
  HistoryReport.fromJson(Map<String, dynamic> j)
      : from = DateTime.parse(j['period_from']).toLocal(),
        to = DateTime.parse(j['period_to']).toLocal(),
        count = j['count'],
        totalDurationS = _d(j['total_duration_s'])!,
        laeq = _d(j['LAeq']),
        lceq = _d(j['LCeq']),
        lzeq = _d(j['LZeq']),
        laeq1sMax = _d(j['LAeq_1s_max']),
        laeq1sMin = _d(j['LAeq_1s_min']),
        bucketS = j['bucket_s'],
        timeline = (j['timeline'] as List).map((e) => TimelinePoint.fromJson(e)).toList(),
        measurements = (j['measurements'] as List).map((e) => Measurement.fromJson(e)).toList();

  final DateTime from;
  final DateTime to;
  final int count;
  final double totalDurationS;
  final double? laeq;
  final double? lceq;
  final double? lzeq;
  final double? laeq1sMax;
  final double? laeq1sMin;
  final int bucketS;
  final List<TimelinePoint> timeline;
  final List<Measurement> measurements;
}

/// Протокол от калибровка (изискване 6).
class Calibration {
  Calibration.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        createdAt = DateTime.parse(j['created_at']).toLocal(),
        appliedAt = j['applied_at'] == null ? null : DateTime.parse(j['applied_at']).toLocal(),
        method = j['method'],
        status = j['status'],
        referenceLevelDb = _d(j['reference_level_db']),
        referenceFreqHz = _d(j['reference_freq_hz']),
        measuredLevelDb = _d(j['measured_level_db']),
        measuredFreqHz = _d(j['measured_freq_hz']),
        stabilityDb = _d(j['stability_db']),
        offsetBeforeDb = _d(j['offset_before_db']),
        offsetDb = _d(j['offset_db'])!,
        driftDb = _d(j['drift_db']),
        uncertaintyDb = _d(j['uncertainty_db']),
        calibrator = [j['calibrator_brand'], j['calibrator_model']].whereType<String>().join(' '),
        calibratorSerial = j['calibrator_serial'],
        calibratorCertificate = j['calibrator_certificate'],
        temperatureC = _d(j['temperature_c']),
        humidityPct = _d(j['humidity_pct']),
        pressureKpa = _d(j['pressure_kpa']),
        notes = j['notes'];

  final int id;
  final DateTime createdAt;
  final DateTime? appliedAt;
  final String method;
  final String status;
  final double? referenceLevelDb;
  final double? referenceFreqHz;
  final double? measuredLevelDb;
  final double? measuredFreqHz;
  final double? stabilityDb;
  final double? offsetBeforeDb;
  final double offsetDb;
  final double? driftDb;
  final double? uncertaintyDb;
  final String calibrator;
  final String? calibratorSerial;
  final String? calibratorCertificate;
  final double? temperatureC;
  final double? humidityPct;
  final double? pressureKpa;
  final String? notes;

  String get methodName => method == 'auto' ? tr('Автоматична') : tr('Ръчна');

  String get statusName => switch (status) {
        'applied' => tr('Приложена'),
        'pending' => tr('Чака потвърждение'),
        _ => tr('Отхвърлена'),
      };
}

String formatDuration(double seconds) {
  final d = Duration(milliseconds: (seconds * 1000).round());
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) return tr('{p0} ч {p1} мин', {'p0': h, 'p1': m});
  if (m > 0) return tr('{p0} мин {p1} с', {'p0': m, 'p1': s});
  return tr('{p0} с', {'p0': seconds.toStringAsFixed(1)});
}

String formatDb(double? v, {int digits = 1}) => v == null ? '–' : '${v.toStringAsFixed(digits)} dB';

/// Зона с гранични стойности по Наредба № 6/2006, Прил. 2, табл. 2.
class Zone {
  Zone({
    this.id,
    required this.code,
    required this.name,
    this.category = 'outdoor',
    this.day,
    this.evening,
    this.night,
    this.sortOrder = 0,
  });

  Zone.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        code = j['code'],
        name = j['name'],
        category = j['category'] ?? 'outdoor',
        day = _d(j['day']),
        evening = _d(j['evening']),
        night = _d(j['night']),
        sortOrder = j['sort_order'] ?? 0;

  final int? id;
  final String code;
  final String name;

  /// "outdoor" - открити територии, "indoor" - помещения.
  final String category;
  final double? day;
  final double? evening;
  final double? night;
  final int sortOrder;

  double? normFor(String period) => switch (period) {
        'day' => day,
        'evening' => evening,
        _ => night,
      };

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'category': category,
        'day': day,
        'evening': evening,
        'night': night,
        'sort_order': sortOrder,
      };
}

/// Стандарт за измерване - от него се вземат коефициентите на филтрите.
class Standard {
  Standard.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        code = j['code'],
        name = j['name'],
        isDefault = j['is_default'] == true,
        sortOrder = j['sort_order'] ?? 0,
        params = Map<String, dynamic>.from(j['params']);

  final int id;
  final String code;
  final String name;
  final bool isDefault;
  final int sortOrder;

  /// poles: [f1, f2, f3, f4] в Hz; fast, slow, impulse_rise, impulse_decay в секунди.
  final Map<String, dynamic> params;

  List<double> get poles => (params['poles'] as List).map((v) => (v as num).toDouble()).toList();
}

/// Периодите от денонощието по Наредба № 6.
const periods = ['day', 'evening', 'night'];

/// Издаден сертификат (изискване 8).
class CertificateInfo {
  CertificateInfo.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        number = j['number'],
        issuedAt = DateTime.parse(j['issued_at']).toLocal(),
        pointCount = (j['data']['rows'] as List).length,
        conclusion = j['data']['conclusion'],
        title = j['data']['title'];

  final int id;
  final String number;
  final DateTime issuedAt;
  final int pointCount;
  final String conclusion;
  final String? title;
}
