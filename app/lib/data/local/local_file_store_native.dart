import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Directory> _root() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'Snote', 'Files'));
  await dir.create(recursive: true);
  return dir;
}

String _safe(String name) {
  final clean = name.replaceAll(RegExp(r'[<>:"/\\\\|?*\\x00-\\x1F]'), '_').trim();
  return clean.isEmpty ? 'untitled' : clean;
}

Future<String> writeLocalFile(String folder, String name, List<int> bytes) async {
  final root = await _root();
  final dir = Directory(p.join(root.path, _safe(folder)));
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, _safe(name)));
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
  final dir = Directory(p.join(root.path, _safe(folder)));
  await dir.create(recursive: true);
  final target = p.join(dir.path, _safe(name));
  await File(path).copy(target);
  return target;
}
