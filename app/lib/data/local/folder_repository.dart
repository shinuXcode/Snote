import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/config/account_scope.dart';
import 'database.dart';

class LocalFolder {
  final String id;
  final String? parentId;
  final String name;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  const LocalFolder({required this.id, this.parentId, required this.name, required this.createdAt, required this.updatedAt, this.deletedAt});
  factory LocalFolder.fromMap(Map<String,Object?> map)=>LocalFolder(id:map['id']! as String,parentId:map['parent_id'] as String?,name:map['name']! as String,createdAt:(map['created_at']! as num).toInt(),updatedAt:(map['updated_at']! as num).toInt(),deletedAt:(map['deleted_at'] as num?)?.toInt());
  Map<String,Object?> toExport()=>{'id':id,'parentId':parentId,'name':name,'createdAt':createdAt,'updatedAt':updatedAt};
}

class FolderRepository {
  static const _uuid=Uuid();
  Future<Database> get _db=>SnoteDatabase.open();
  Future<LocalFolder> create({required String name,String? parentId}) async { final n=name.trim(); if(n.isEmpty) throw ArgumentError.value(name,'name','Folder name cannot be empty.'); final now=DateTime.now().millisecondsSinceEpoch; final f=LocalFolder(id:_uuid.v4(),parentId:parentId,name:n,createdAt:now,updatedAt:now); final db=await _db; await db.transaction((tx) async{ await tx.insert('folders',{'id':f.id,'owner_id':SnoteAccountScope.ownerId,'parent_id':parentId,'name':n,'created_at':now,'updated_at':now,'deleted_at':null}); await _queue(tx,f.id,'upsert');}); return f; }
  Future<List<LocalFolder>> list({String? parentId}) async { final db=await _db; final rows=await db.query('folders',where:parentId==null?'owner_id=? AND parent_id IS NULL AND deleted_at IS NULL':'owner_id=? AND parent_id=? AND deleted_at IS NULL',whereArgs:parentId==null?[SnoteAccountScope.ownerId]:[SnoteAccountScope.ownerId,parentId],orderBy:'name COLLATE NOCASE ASC'); return rows.map(LocalFolder.fromMap).toList(); }
  Future<List<LocalFolder>> listAllVisible() async { final db=await _db; final rows=await db.query('folders',where:'owner_id=? AND deleted_at IS NULL',whereArgs:[SnoteAccountScope.ownerId],orderBy:'name COLLATE NOCASE ASC'); return rows.map(LocalFolder.fromMap).toList(); }
  Future<LocalFolder?> get(String id) async { final db=await _db; final rows=await db.query('folders',where:'id=? AND owner_id=?',whereArgs:[id,SnoteAccountScope.ownerId],limit:1); return rows.isEmpty?null:LocalFolder.fromMap(rows.first); }
  Future<void> rename(String id,String name) async { final n=name.trim(); if(n.isEmpty)return; final db=await _db; await db.transaction((tx) async{ await tx.update('folders',{'name':n,'updated_at':DateTime.now().millisecondsSinceEpoch},where:'id=? AND owner_id=?',whereArgs:[id,SnoteAccountScope.ownerId]); await _queue(tx,id,'upsert');}); }
  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((tx) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final folderIds = <String>[];
      await _collectDescendants(tx, id, folderIds);
      if (folderIds.isNotEmpty) {
        final placeholders = List.filled(folderIds.length, '?').join(',');
        await tx.update(
          'notes',
          {'folder_id': null, 'updated_at': now, 'sync_state': 'pending'},
          where: 'owner_id=? AND deleted_at IS NULL AND folder_id IN ($placeholders)',
          whereArgs: [SnoteAccountScope.ownerId, ...folderIds],
        );
      }
      await _deleteRecursive(tx, id, now);
    });
  }

  Future<void> _collectDescendants(DatabaseExecutor tx, String id, List<String> output) async {
    final rows = await tx.query(
      'folders',
      columns: ['id'],
      where: 'owner_id=? AND (id=? OR parent_id=?) AND deleted_at IS NULL',
      whereArgs: [SnoteAccountScope.ownerId, id, id],
    );
    for (final row in rows) {
      final childId = row['id']! as String;
      if (output.contains(childId)) continue;
      output.add(childId);
      await _collectDescendants(tx, childId, output);
    }
  }
  Future<void> _deleteRecursive(DatabaseExecutor tx,String id,int now) async { final kids=await tx.query('folders',columns:['id'],where:'owner_id=? AND parent_id=? AND deleted_at IS NULL',whereArgs:[SnoteAccountScope.ownerId,id]); for(final k in kids) await _deleteRecursive(tx,k['id']! as String,now); await tx.update('folders',{'deleted_at':now,'updated_at':now},where:'id=? AND owner_id=?',whereArgs:[id,SnoteAccountScope.ownerId]); await _queue(tx,id,'delete'); }
  Future<void> _queue(DatabaseExecutor db,String id,String operation) async { await db.delete('sync_queue',where:'entity_type=? AND entity_id=? AND owner_id=?',whereArgs:['folder',id,SnoteAccountScope.ownerId]); await db.insert('sync_queue',{'id':_uuid.v4(),'owner_id':SnoteAccountScope.ownerId,'entity_type':'folder','entity_id':id,'operation':operation,'created_at':DateTime.now().millisecondsSinceEpoch,'attempts':0}); }
  Future<void> queueNote(DatabaseExecutor db,String noteId,String operation) async { await db.delete('sync_queue',where:'entity_type=? AND entity_id=? AND owner_id=?',whereArgs:['note',noteId,SnoteAccountScope.ownerId]); await db.insert('sync_queue',{'id':_uuid.v4(),'owner_id':SnoteAccountScope.ownerId,'entity_type':'note','entity_id':noteId,'operation':operation,'created_at':DateTime.now().millisecondsSinceEpoch,'attempts':0}); }
}
