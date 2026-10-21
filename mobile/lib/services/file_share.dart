import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';

/// Изтегля файл от сървъра и отваря системното меню "Сподели"
/// (запис във Files/Drive, изпращане по имейл и т.н.).
Future<void> downloadAndShare(ApiClient api, String path, String fallbackName) async {
  final (bytes, name) = await api.download(path);
  await shareBytes(bytes, name ?? fallbackName);
}

Future<void> shareBytes(List<int> bytes, String fileName) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
}
