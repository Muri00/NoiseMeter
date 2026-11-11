import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';

/// Изтегля файл от сървъра и го отваря в приложение за преглед (PDF, Excel).
/// Ако на устройството няма такова приложение, се отваря менюто "Сподели".
Future<void> downloadAndOpen(ApiClient api, String path, String fallbackName) async {
  final (bytes, name) = await api.download(path);
  await openBytes(bytes, name ?? fallbackName);
}

/// Изтегля файл от сървъра и отваря системното меню "Сподели"
/// (запис във Files/Drive, изпращане по имейл и т.н.).
Future<void> downloadAndShare(ApiClient api, String path, String fallbackName) async {
  final (bytes, name) = await api.download(path);
  await shareBytes(bytes, name ?? fallbackName);
}

Future<void> openBytes(List<int> bytes, String fileName) async {
  final file = await _save(bytes, fileName);
  final result = await OpenFilex.open(file.path, type: _mimeType(fileName));
  if (result.type != ResultType.done) {
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }
}

Future<void> shareBytes(List<int> bytes, String fileName) async {
  final file = await _save(bytes, fileName);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
}

Future<File> _save(List<int> bytes, String fileName) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

String? _mimeType(String fileName) => switch (fileName.split('.').last.toLowerCase()) {
      'pdf' => 'application/pdf',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv' => 'text/csv',
      'wav' => 'audio/wav',
      _ => null,
    };
