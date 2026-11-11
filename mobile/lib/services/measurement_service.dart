import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';
import '../l10n/l10n.dart';
import 'api_client.dart';

enum MeasurementStatus { idle, connecting, running, error }

/// Измерване в реално време: WebSocket връзка към сървъра, който чете USB микрофона.
class MeasurementService extends ChangeNotifier {
  MeasurementService(this.api);

  final ApiClient api;

  /// Колко секунди история да се пазят за графиката.
  static const historySeconds = 60.0;

  MeasurementStatus status = MeasurementStatus.idle;
  String? error;
  double elapsed = 0;
  Map<String, double> levels = {};
  BandsData? bands;
  double? effectiveFMax;

  /// Интервалът излиза извън работната лента на микрофона - измерването е ненадеждно.
  bool outOfBand = false;

  /// Стандартът, по който се изчисляват филтрите в текущото измерване.
  String? standardName;

  /// id на записа в базата, ако текущото измерване се записва.
  int? recordingId;

  /// id на последния завършен запис - за бутона "Отвори" след спиране.
  int? lastSavedId;

  /// История на всички стойности: код на показател -> списък (време, ниво).
  final Map<String, List<(double, double)>> history = {};

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  bool get isRunning => status == MeasurementStatus.running || status == MeasurementStatus.connecting;

  Future<void> start({
    required int deviceId,
    required double fMin,
    required double fMax,
    required String bandMode,
    bool record = false,
    bool saveWav = false,
    String? name,
    String? location,
    String? placeType,
    int? pointNo,
    int? pointCount,
    String? seriesId,
    String? source,
    String? zoneCode,
    String? period,
    String? standardCode,
  }) async {
    await _close();
    status = MeasurementStatus.connecting;
    error = null;
    elapsed = 0;
    levels = {};
    bands = null;
    recordingId = null;
    lastSavedId = null;
    outOfBand = false;
    standardName = null;
    history.clear();
    notifyListeners();

    try {
      final channel = WebSocketChannel.connect(api.wsUri('/ws/measure'));
      await channel.ready.timeout(const Duration(seconds: 10));
      _channel = channel;
      _sub = channel.stream.listen(_onMessage, onError: (_) => _fail(tr('Връзката със сървъра прекъсна')), onDone: _onDone);
      // Токенът се праща в първото съобщение, за да не попада в логовете на сървъра.
      channel.sink.add(jsonEncode({'action': 'auth', 'token': api.token ?? '', 'lang': AppLanguage.current}));
      channel.sink.add(jsonEncode({
        'action': 'start',
        'device_id': deviceId,
        'f_min': fMin,
        'f_max': fMax,
        'band_mode': bandMode,
        'record': record,
        'save_wav': record && saveWav,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (record && location != null && location.trim().isNotEmpty) 'location': location.trim(),
        if (record && placeType != null) 'place_type': placeType,
        if (record && pointNo != null) 'point_no': pointNo,
        if (record && pointCount != null) 'point_count': pointCount,
        if (record && seriesId != null) 'series_id': seriesId,
        if (record && source != null && source.trim().isNotEmpty) 'source': source.trim(),
        if (record && zoneCode != null) 'zone_code': zoneCode,
        if (record && period != null) 'period': period,
        'standard_code': ?standardCode,
      }));
    } catch (_) {
      _fail(tr('Няма връзка със сървъра ({p0})', {'p0': api.baseUrl}));
    }
  }

  void stop() {
    _channel?.sink.add(jsonEncode({'action': 'stop'}));
  }

  void _onMessage(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'auth_ok':
        return;
      case 'started':
        status = MeasurementStatus.running;
        effectiveFMax = (msg['f_max'] as num).toDouble();
        recordingId = msg['measurement_id'] as int?;
        outOfBand = msg['out_of_band'] == true;
        standardName = msg['standard'] as String?;
      case 'frame':
        _applyFrame(msg);
      case 'stopped':
        status = MeasurementStatus.idle;
        lastSavedId = msg['measurement_id'] as int?;
        recordingId = null;
        _close();
      case 'error':
        _fail(msg['message'] as String);
        return;
    }
    notifyListeners();
  }

  void _applyFrame(Map<String, dynamic> msg) {
    elapsed = (msg['t'] as num).toDouble();
    levels = (msg['levels'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));
    for (final e in levels.entries) {
      final list = history.putIfAbsent(e.key, () => []);
      list.add((elapsed, e.value));
      while (list.isNotEmpty && list.first.$1 < elapsed - historySeconds) {
        list.removeAt(0);
      }
    }
    final b = msg['bands'] as Map<String, dynamic>?;
    if (b != null) {
      bands = BandsData.fromJson(b);
    }
  }

  void _onDone() {
    if (status == MeasurementStatus.running || status == MeasurementStatus.connecting) {
      final code = _channel?.closeCode;
      _fail(code == 4401 ? tr('Сесията е изтекла - влезте отново') : tr('Връзката със сървъра прекъсна'));
    }
  }

  void _fail(String message) {
    status = MeasurementStatus.error;
    error = message;
    _close();
    notifyListeners();
  }

  Future<void> _close() async {
    final sub = _sub;
    final channel = _channel;
    _sub = null;
    _channel = null;
    await sub?.cancel();
    await channel?.sink.close();
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }
}
