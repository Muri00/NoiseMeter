import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Устройствата и настройките на влезлия потребител, общи за всички екрани.
class UserData extends ChangeNotifier {
  UserData(this.api);

  final ApiClient api;

  List<Device> devices = [];
  MeterSettings? settings;
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([api.get('/api/devices'), api.get('/api/settings')]);
      devices = (results[0] as List).map((j) => Device.fromJson(j)).toList();
      settings = MeterSettings.fromJson(results[1]);
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

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
