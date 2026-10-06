import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../local/database.dart';

class NoteSyncService {
  final SupabaseClient client;
  const NoteSyncService(this.client);
  Future<void> flush() async {
    final user=client.auth.currentUser;if(user==null)return;
    final db=await SnoteDatabase.open();
    final queue=await db.query('sync_queue',orderBy:'created_at ASC',limit:50);
    for(final item in queue){try{await _process(db,user.id,item);await db.delete('sync_queue',where:'id=?',whereArgs:[item['id']]);}catch(e){await db.update('sync_queue',{'attempts':((item['attempts'] as int?)??0)+1,'last_error':e.toString()},where:'id=?',whereArgs:[item['id']]);}}
  }
  Future<void> _process(Database db,String userId,Map<String,Object?> item) async {
    if(item['entity_type']!='note')return;
    final id=item['entity_id']! as String;
    final rows=await db.query('notes',where:'id=?',whereArgs:[id],limit:1);if(rows.isEmpty)return;
    final n=rows.first;
    final payload={'id':id,'user_id':userId,'title':n['title'],'folder_id':n['folder_id'],'note_type':n['note_type'],'version':n['version'],'updated_at':DateTime.fromMillisecondsSinceEpoch(n['updated_at']! as int).toUtc().toIso8601String(),'deleted_at':n['deleted_at']==null?null:DateTime.fromMillisecondsSinceEpoch(n['deleted_at']! as int).toUtc().toIso8601String()};
    await client.from('notes').upsert(payload);
    await db.update('notes',{'sync_state':'synced'},where:'id=?',whereArgs:[id]);
  }
  Future<String> exportRemoteNotes() async {final user=client.auth.currentUser;if(user==null)throw StateError('Authentication required');final rows=await client.from('notes').select().eq('user_id',user.id).order('updated_at',ascending:false);return const JsonEncoder.withIndent('  ').convert({'format':'snote-json-v1','exportedAt':DateTime.now().toUtc().toIso8601String(),'notes':rows});}
}
