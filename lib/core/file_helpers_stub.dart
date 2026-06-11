import 'package:flutter/widgets.dart';

Future<String> saveTextFile(
  String fileName,
  String content, {
  bool documents = false,
  String? subdirectory,
}) {
  throw UnsupportedError('File saving is not available on this platform.');
}

Future<String> saveBytesFile(
  String fileName,
  List<int> bytes, {
  bool documents = false,
  String? subdirectory,
}) {
  throw UnsupportedError('File saving is not available on this platform.');
}

String fileNameFromPath(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

bool localFileExists(String path) => false;

Widget localImageFromPath(String path, {required BoxFit fit}) => const SizedBox.shrink();
