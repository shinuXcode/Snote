import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_file_store_path.dart';

Future<Directory> _root() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'Snote', 'Files'));
  await dir.create(recursive: true);
  return dir;
}

Future<String> writeLocalFile(String folder, String name, List<int> bytes) async {
  final root = await _root();
  final dir = Directory(p.join(root.path, sanitizeLocalFileSegment(folder)));
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, sanitizeLocalFileSegment(name)));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Uint8List> readLocalFile(String path) async {
  return Uint8List.fromList(await File(path).readAsBytes());
}

Future<void> deleteLocalFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

Future<String> copyLocalFile(String path, String folder, String name) async {
  final root = await _root();
  final dir = Directory(p.join(root.path, sanitizeLocalFileSegment(folder)));
  await dir.create(recursive: true);
  final target = p.join(dir.path, sanitizeLocalFileSegment(name));
  await File(path).copy(target);
  return target;
}
