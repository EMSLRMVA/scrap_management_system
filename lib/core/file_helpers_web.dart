import 'package:flutter/widgets.dart';

Future<String> saveTextFile(
  String fileName,
  String content, {
  bool documents = false,
  String? subdirectory,
}) {
  throw UnsupportedError('File saving is not available in the browser.');
}

Future<String> saveBytesFile(
  String fileName,
  List<int> bytes, {
  bool documents = false,
  String? subdirectory,
}) {
  throw UnsupportedError('File saving is not available in the browser.');
}

String fileNameFromPath(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

bool localFileExists(String path) {
  final trimmed = path.trim();
  return trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      trimmed.startsWith('blob:') ||
      trimmed.startsWith('data:');
}

Widget localImageFromPath(String path, {required BoxFit fit}) =>
    Image.network(path, fit: fit);
