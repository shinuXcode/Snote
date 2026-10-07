import 'dart:typed_data';

final Map<String, Uint8List> _memoryFiles = <String, Uint8List>{};

Future<String> writeLocalFile(String folder, String name, List<int> bytes) async {
  final key = 'memory://$folder/$name';
  _memoryFiles[key] = Uint8List.fromList(bytes);
  return key;
}

Future<Uint8List> readLocalFile(String path) async {
  final data = _memoryFiles[path];
  if (data == null) throw StateError('Local file is not available in this session.');
  return Uint8List.fromList(data);
}

Future<void> deleteLocalFile(String path) async {
  _memoryFiles.remove(path);
}

Future<String> copyLocalFile(String path, String folder, String name) async {
  return writeLocalFile(folder, name, await readLocalFile(path));
}
