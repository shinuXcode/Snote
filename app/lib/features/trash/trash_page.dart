import 'package:flutter/material.dart';
import '../../data/local/note_repository.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});
  @override State<TrashPage> createState()=>_TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  final _repo=NoteRepository();
  List<LocalNote> _items=[];
  bool _loading=true;

  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    final items=await _repo.listTrash();
    if(!mounted)return;
    setState(()=>_items=items..sort((a,b)=>(b.deletedAt??0).compareTo(a.deletedAt??0)));
    setState(()=>_loading=false);
  }

  Future<void> _restore(LocalNote note) async { await _repo.restore(note.id); await _load(); }
  Future<void> _purge(LocalNote note) async { await _repo.permanentlyDelete(note.id); await _load(); }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Bin / Recently deleted'),actions:[
      IconButton(tooltip:'Refresh',onPressed:_load,icon:const Icon(Icons.refresh_rounded)),
    ]),
    body:_loading?const Center(child:CircularProgressIndicator()):
      _items.isEmpty?const Center(child:Text('Bin is empty')):
      ListView.builder(
        padding:const EdgeInsets.all(16),itemCount:_items.length,
        itemBuilder:(_,i){
          final n=_items[i];
          final deleted=n.deletedAt==null?DateTime.now():DateTime.fromMillisecondsSinceEpoch(n.deletedAt!);
          final days=DateTime.now().difference(deleted).inDays;
          final left=(30-days).clamp(0,30);
          return Card(
            child:ListTile(
              leading:const CircleAvatar(child:Icon(Icons.delete_outline_rounded)),
              title:Text(n.title,maxLines:1,overflow:TextOverflow.ellipsis),
              subtitle:Text(left==0?'Expires today':'Expires in '+left.toString()+' day(s)'),
              trailing:Wrap(spacing:0,children:[
                IconButton(tooltip:'Restore',onPressed:()=>_restore(n),icon:const Icon(Icons.restore_rounded)),
                IconButton(tooltip:'Delete permanently',onPressed:()=>_purge(n),icon:const Icon(Icons.delete_forever_outlined)),
              ]),
            ),
          );
        },
      ),
  );
}
