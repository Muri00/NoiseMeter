class User {
  User({required this.id, required this.username, required this.email, this.firstName, this.lastName});

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        username: j['username'],
        email: j['email'],
        firstName: j['first_name'],
        lastName: j['last_name'],
      );

  final int id;
  final String username;
  final String email;
  final String? firstName;
  final String? lastName;

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
        'valid' => 'калибриран',
        'due_soon' => 'калибровката изтича',
        'expired' => 'калибровката е изтекла',
        _ => 'некалибриран',
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

/// LAFmax -> LA,F,max (запис по IEC 61672-1).
String indicatorName(String code) {
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
        source = j['source'],
        zoneCode = j['zone_code'],
        normDay = _d(j['norm_day']),
        normEvening = _d(j['norm_evening']),
        normNight = _d(j['norm_night']),
        frameCount = j['frame_count'],
        averageBands = j['average_bands'] == null ? null : BandsData.fromJson(j['average_bands']);

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
  final String? source;
  final String? zoneCode;
  final double? normDay;
  final double? normEvening;
  final double? normNight;
  // Само в детайлния изглед:
  final int? frameCount;
  final BandsData? averageBands;

  String get deviceTitle => '${deviceInfo['brand']} ${deviceInfo['model']}';
  String get title => (name == null || name!.isEmpty) ? 'Измерване №$id' : name!;
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

  String get methodName => method == 'auto' ? 'Автоматична' : 'Ръчна';

  String get statusName => switch (status) {
        'applied' => 'Приложена',
        'pending' => 'Чака потвърждение',
        _ => 'Отхвърлена',
      };
}

String formatDuration(double seconds) {
  final d = Duration(milliseconds: (seconds * 1000).round());
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) return '$h ч $m мин';
  if (m > 0) return '$m мин $s с';
  return '${seconds.toStringAsFixed(1)} с';
}

String formatDb(double? v, {int digits = 1}) => v == null ? '–' : '${v.toStringAsFixed(digits)} dB';

/// Зона с гранични стойности по Наредба № 6/2006, Прил. 2, табл. 2.
class Zone {
  Zone.fromJson(Map<String, dynamic> j)
      : code = j['code'],
        name = j['name'],
        day = _d(j['day'])!,
        evening = _d(j['evening'])!,
        night = _d(j['night'])!;

  final String code;
  final String name;
  final double day;
  final double evening;
  final double night;
}

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
