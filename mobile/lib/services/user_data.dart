import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Устройствата и настройките на влезлия потребител, общи за всички екрани.
class UserData extends ChangeNotifier {
  UserData(this.api);

  final ApiClient api;

  List<Device> devices = [];
  MeterSettings? settings;
  List<Zone> zones = [];
  List<Standard> standards = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.get('/api/devices'),
        api.get('/api/settings'),
        api.get('/api/norms/zones'),
        api.get('/api/standards'),
      ]);
      devices = (results[0] as List).map((j) => Device.fromJson(j)).toList();
      settings = MeterSettings.fromJson(results[1]);
      zones = (results[2] as List).map((j) => Zone.fromJson(j)).toList();
      standards = (results[3] as List).map((j) => Standard.fromJson(j)).toList();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> reloadZonesAndStandards() async {
    final results = await Future.wait([api.get('/api/norms/zones'), api.get('/api/standards')]);
    zones = (results[0] as List).map((j) => Zone.fromJson(j)).toList();
    standards = (results[1] as List).map((j) => Standard.fromJson(j)).toList();
    notifyListeners();
  }

  Standard? get defaultStandard => standards.where((s) => s.isDefault).firstOrNull ?? standards.firstOrNull;

  Zone? zoneByCode(String? code) => zones.where((z) => z.code == code).firstOrNull;

  Future<void> saveDevice(Device device) async {
    final json = device.id == null
        ? await api.post('/api/devices', device.toJson())
        : await api.put('/api/devices/${device.id}', device.toJson());
    final saved = Device.fromJson(json);
    final i = devices.indexWhere((d) => d.id == saved.id);
    if (i >= 0) {
      devices[i] = saved;
    } else {
      devices.add(saved);
    }
    notifyListeners();
  }

  Future<void> deleteDevice(Device device) async {
    await api.delete('/api/devices/${device.id}');
    devices.removeWhere((d) => d.id == device.id);
    notifyListeners();
  }

  Future<void> saveSettings(MeterSettings s) async {
    settings = MeterSettings.fromJson(await api.put('/api/settings', s.toJson()));
    notifyListeners();
  }

  Future<List<String>> availableIndicators() async {
    final list = await api.get('/api/settings/indicators') as List;
    return list.map((e) => e['code'] as String).toList();
  }
}
