import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

Future<String> saveTextFile(
  String fileName,
  String content, {
  bool documents = false,
  String? subdirectory,
}) async {
  final directory = documents
      ? await getApplicationDocumentsDirectory()
      : await getTemporaryDirectory();
  final targetDirectory = await _targetDirectory(directory, subdirectory);
  final file = File('${targetDirectory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(content, flush: true);
  return file.path;
}

Future<String> saveBytesFile(
  String fileName,
  List<int> bytes, {
  bool documents = false,
  String? subdirectory,
}) async {
  final directory = documents
      ? await getApplicationDocumentsDirectory()
      : await getTemporaryDirectory();
  final targetDirectory = await _targetDirectory(directory, subdirectory);
  final file = File('${targetDirectory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Directory> _targetDirectory(Directory directory, String? subdirectory) async {
  if (subdirectory == null || subdirectory.trim().isEmpty) {
    return directory;
  }
  final target = Directory('${directory.path}${Platform.pathSeparator}$subdirectory');
  if (!await target.exists()) {
    await target.create(recursive: true);
  }
  return target;
}

String fileNameFromPath(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

bool localFileExists(String path) {
  if (path.trim().isEmpty) {
    return false;
  }
  return File(path).existsSync();
}

Widget localImageFromPath(String path, {required BoxFit fit}) =>
    Image.file(File(path), fit: fit);
