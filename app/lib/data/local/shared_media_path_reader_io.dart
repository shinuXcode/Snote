import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readSharedMediaBytes(String path) async {
  return Uint8List.fromList(await File(path).readAsBytes());
}
