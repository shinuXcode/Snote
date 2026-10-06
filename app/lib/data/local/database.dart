import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'schema.dart';

class SnoteDatabase{
 static Database? _db;
 static Future<Database> open()async{
  if(_db!=null)return _db!;
  if(kIsWeb){databaseFactory=databaseFactoryFfiWeb;_db=await openDatabase('snote.db',version:databaseVersion,onCreate:_create,onUpgrade:_upgrade);return _db!;}
  if(defaultTargetPlatform==TargetPlatform.windows||defaultTargetPlatform==TargetPlatform.linux||defaultTargetPlatform==TargetPlatform.macOS){sqfliteFfiInit();databaseFactory=databaseFactoryFfi;}
  final dir=await getApplicationDocumentsDirectory();final path=join(dir.path,'snote.db');
  _db=await openDatabase(path,version:databaseVersion,onCreate:_create,onUpgrade:_upgrade);return _db!;
 }
 static Future<void> _create(Database db,int version)async{await db.execute(createFoldersTable);await db.execute(createNotesTable);await db.execute(createPagesTable);await db.execute(createSyncQueueTable);await db.execute(createAttachmentsTable);}
 static Future<void> _upgrade(Database db,int oldVersion,int newVersion)async{if(oldVersion<3)await db.execute('ALTER TABLE notes ADD COLUMN content_json TEXT');}
}
