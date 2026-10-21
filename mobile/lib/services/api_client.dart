import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Тънък слой над REST API на сървъра: добавя адреса, JWT токена и обработката на грешки.
class ApiClient {
  ApiClient(this.baseUrl);

  String baseUrl;
  String? token;

  static const _timeout = Duration(seconds: 10);

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  /// Адрес за WebSocket връзка (http -> ws, https -> wss).
  Uri wsUri(String path) {
    final http = _uri(path);
    return http.replace(scheme: http.scheme == 'https' ? 'wss' : 'ws');
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// [query] може да съдържа и списъци, напр. {'codes': ['LAF', 'LAS']}.
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, Object body) =>
      _send(() => http.post(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> put(String path, Object body) =>
      _send(() => http.put(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> patch(String path, Object body) =>
      _send(() => http.patch(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> delete(String path) => _send(() => http.delete(_uri(path), headers: _headers));

  /// Изтегля файл (CSV, WAV). Връща съдържанието и името от Content-Disposition.
  Future<(List<int>, String?)> download(String path) async {
    final res = await _request(() => http.get(_uri(path), headers: _headers), const Duration(minutes: 5));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(_errorMessage(_tryJson(res)) ?? 'Грешка ${res.statusCode}', res.statusCode);
    }
    final disposition = res.headers['content-disposition'] ?? '';
    final name = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition)?.group(1);
    return (res.bodyBytes as List<int>, name);
  }

  /// [timeout] е по-дълъг за заявки, които чакат запис от микрофона (калибровка).
  Future<dynamic> postLong(String path, Object body, Duration timeout) => _send(
        () => http.post(_uri(path), headers: _headers, body: jsonEncode(body)),
        timeout,
      );

  Future<http.Response> _request(Future<http.Response> Function() request, Duration timeout) async {
    try {
      return await request().timeout(timeout);
    } on FormatException {
      throw ApiException('Невалиден адрес на сървъра');
    } catch (_) {
      throw ApiException('Няма връзка със сървъра ($baseUrl)');
    }
  }

  Future<dynamic> _send(Future<http.Response> Function() request, [Duration timeout = _timeout]) async {
    final res = await _request(request, timeout);
    final body = _tryJson(res);
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    throw ApiException(_errorMessage(body) ?? 'Грешка ${res.statusCode}', res.statusCode);
  }

  static dynamic _tryJson(http.Response res) {
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  /// FastAPI връща {"detail": "текст"} или {"detail": [{"msg": ..., "loc": [...]}, ...]}.
  static String? _errorMessage(dynamic body) {
    if (body is! Map || body['detail'] == null) return null;
    final detail = body['detail'];
    if (detail is String) return detail;
    if (detail is List) {
      return detail
          .map((e) => (e['msg'] as String? ?? '').replaceFirst('Value error, ', ''))
          .join('\n');
    }
    return detail.toString();
  }
}
