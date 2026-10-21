import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Състояние на входа: адрес на сървъра, JWT токен и текущ потребител.
class AuthService extends ChangeNotifier {
  AuthService(this.api);

  final ApiClient api;
  final _secure = const FlutterSecureStorage();

  // 10.0.2.2 е компютърът, на който работи Android емулаторът.
  static const defaultServerUrl = 'http://10.0.2.2:8000';
  static const _serverKey = 'server_url';
  static const _tokenKey = 'access_token';

  User? user;
  bool initialized = false;

  bool get isLoggedIn => user != null;
  String get serverUrl => api.baseUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    api.baseUrl = prefs.getString(_serverKey) ?? defaultServerUrl;
    api.token = await _secure.read(key: _tokenKey);
    // Сървърът може да се стартира в момента - опитваме няколко пъти.
    for (var attempt = 0; api.token != null && user == null && attempt < 3; attempt++) {
      try {
        user = User.fromJson(await api.get('/api/auth/me'));
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          // Изтекъл или обезсилен токен - потребителят влиза отново.
          api.token = null;
          await _secure.delete(key: _tokenKey);
        } else {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }
    initialized = true;
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    api.baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, api.baseUrl);
    notifyListeners();
  }

  Future<void> login(String login, String password) async {
    final res = await api.post('/api/auth/login', {'login': login.trim(), 'password': password});
    await _handleToken(res);
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    final res = await api.post('/api/auth/register', {
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
      if (firstName != null && firstName.isNotEmpty) 'first_name': firstName.trim(),
      if (lastName != null && lastName.isNotEmpty) 'last_name': lastName.trim(),
    });
    await _handleToken(res);
  }

  Future<void> updateProfile({required String email, String? firstName, String? lastName}) async {
    final res = await api.put('/api/auth/me', {'email': email.trim(), 'first_name': firstName, 'last_name': lastName});
    user = User.fromJson(res);
    notifyListeners();
  }

  /// Сменя паролата. Сървърът обезсилва старите сесии и връща нов токен за това устройство.
  Future<void> changePassword(String current, String newPassword) async {
    final res = await api.post('/api/auth/change-password', {'current_password': current, 'new_password': newPassword});
    await _handleToken(res);
  }

  Future<void> deleteAccount(String password) async {
    await api.post('/api/auth/delete-account', {'password': password});
    await logout();
  }

  Future<void> logout() async {
    api.token = null;
    user = null;
    await _secure.delete(key: _tokenKey);
    notifyListeners();
  }

  Future<void> _handleToken(Map<String, dynamic> res) async {
    api.token = res['access_token'];
    user = User.fromJson(res['user']);
    await _secure.write(key: _tokenKey, value: api.token);
    notifyListeners();
  }
}
