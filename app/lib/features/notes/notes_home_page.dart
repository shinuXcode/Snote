import 'package:flutter/material.dart';
import '../../canvas_engine/models/pen_config.dart';
import '../../canvas_engine/widgets/snote_canvas.dart';
import '../../data/local/note_repository.dart';
import '../../data/remote/supabase_service.dart';
import '../../sync/sync_engine.dart';

class NotesHomePage extends StatefulWidget{final bool localOnly;const NotesHomePage({super.key,this.localOnly=false});@override State<NotesHomePage> createState()=>_NotesHomePageState();}
class _NotesHomePageState extends State<NotesHomePage>{
 final repo=NoteRepository();late Future<List<LocalNote>> notes;
 @override void initState(){super.initState();notes=repo.list();SyncEngine().start();}
 Future<void> newNote()async{await repo.create();setState(()=>notes=repo.list());}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Snote'),actions:[if(!widget.localOnly)IconButton(onPressed:()=>SnoteSupabase.client?.auth.signOut(),icon:const Icon(Icons.logout))]),body:LayoutBuilder(builder:(context,c)=>c.maxWidth<760?const SnoteCanvas(pen:PenConfig(type:PenType.ballpoint,color:Colors.black,size:3)):Row(children:[SizedBox(width:270,child:Card(margin:const EdgeInsets.all(12),child:Column(children:[ListTile(title:const Text('Notes'),trailing:IconButton(onPressed:newNote,icon:const Icon(Icons.add))),Expanded(child:FutureBuilder<List<LocalNote>>(future:notes,builder:(context,s)=>!s.hasData?const Center(child:CircularProgressIndicator()):ListView(children:s.data!.map((n)=>ListTile(title:Text(n.title),subtitle:Text(n.noteType))).toList())))]))),const Expanded(child:SnoteCanvas(pen:PenConfig(type:PenType.ballpoint,color:Colors.black,size:3))) ])));
}
