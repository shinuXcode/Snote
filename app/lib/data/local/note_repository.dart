import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'database.dart';

class LocalNote {
  final String id;
  final String title;
  final String? folderId;
  final String noteType;
  final int createdAt;
  final int updatedAt;
  const LocalNote({required this.id,required this.title,this.folderId,required this.noteType,required this.createdAt,required this.updatedAt});
  Map<String,Object?> toMap()=>{'id':id,'title':title,'folder_id':folderId,'note_type':noteType,'created_at':createdAt,'updated_at':updatedAt,'version':1,'sync_state':'pending'};
  factory LocalNote.fromMap(Map<String,Object?> m)=>LocalNote(id:m['id']! as String,title:m['title']! as String,folderId:m['folder_id'] as String?,noteType:m['note_type']! as String,createdAt:m['created_at']! as int,updatedAt:m['updated_at']! as int);
}

class NoteRepository {
  static const _uuid=Uuid();
  Future<Database> get _db=>SnoteDatabase.open();
  Future<LocalNote> create({String title='Untitled note'}) async {final now=DateTime.now().millisecondsSinceEpoch;final note=LocalNote(id:_uuid.v4(),title:title,noteType:'handwriting',createdAt:now,updatedAt:now);final db=await _db;await db.insert('notes',note.toMap());await _queue(db,note.id,'upsert');return note;}
  Future<List<LocalNote>> list() async {final db=await _db;final rows=await db.query('notes',where:'deleted_at IS NULL',orderBy:'updated_at DESC');return rows.map(LocalNote.fromMap).toList();}
  Future<void> rename(String id,String title) async {final db=await _db;final now=DateTime.now().millisecondsSinceEpoch;await db.update('notes',{'title':title,'updated_at':now,'sync_state':'pending'},where:'id=?',whereArgs:[id]);await _queue(db,id,'upsert');}
  Future<void> delete(String id) async {final db=await _db;final now=DateTime.now().millisecondsSinceEpoch;await db.update('notes',{'deleted_at':now,'updated_at':now,'sync_state':'pending'},where:'id=?',whereArgs:[id]);await _queue(db,id,'delete');}
  Future<void> _queue(Database db,String id,String operation) async {await db.insert('sync_queue',{'id':_uuid.v4(),'entity_type':'note','entity_id':id,'operation':operation,'created_at':DateTime.now().millisecondsSinceEpoch});}
}
