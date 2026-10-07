import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../../canvas_engine/models/pen_config.dart';
import '../../canvas_engine/widgets/page_background.dart';
import '../../canvas_engine/widgets/snote_canvas.dart';
import '../../canvas_engine/widgets/snote_canvas_controller.dart';
import '../../core/security/note_lock_service.dart';
import '../../data/local/note_repository.dart';

class NoteEditorPage extends StatefulWidget {
  final LocalNote note;
  const NoteEditorPage({super.key, required this.note});
  @override State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final _repo = NoteRepository();
  final _canvas = SnoteCanvasController();
  final _title = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _quill = QuillController.basic();
  final _lock = NoteLockService();

  Timer? _saveTimer;
  List<Map<String,Object?>> _pages = [];
  int _page = 0;
  PageTemplate _template = PageTemplate.dotted;
  CanvasTool _tool = CanvasTool.ballpoint;
  Color _color = const Color(0xff263238);
  double _size = 3;
  bool _drawing = true, _pan = false, _locked = false, _unlocked = true;
  bool _loading = true, _toolbar = true, _shapes = false, _previews = false, _full = false;
  int _selected = 0;

  Map<String,Object?> get _current => _pages[_page];
  PenConfig get _pen => PenConfig(
    type: _tool.penType,
    color: _color,
    size: _size,
    opacity: _tool == CanvasTool.highlighter ? .30 : 1,
  );

  @override void initState() {
    super.initState();
    _title.text = widget.note.title;
    _quill.addListener(_scheduleSave);
    _prepare();
  }

  Future<void> _prepare() async {
    final locked = await _lock.isLocked(widget.note.id);
    if (!mounted) return;
    if (locked) {
      setState(() { _locked = true; _unlocked = false; _loading = false; });
      final ok = await _lock.authenticate();
      if (!mounted) return;
      setState(() => _unlocked = ok);
      if (ok) await _load();
    } else {
      await _load();
    }
  }

  Future<void> _load() async {
    final note = await _repo.get(widget.note.id);
    final pages = <Map<String,Object?>>[];
    if (note?.contentJson != null) {
      try {
        final d = jsonDecode(note!.contentJson!);
        if (d is Map<String,dynamic>) {
          final raw = d['pages'];
          if (raw is List) {
            for (final p in raw) if (p is Map) pages.add(p.cast<String,Object?>());
          }
          if (pages.isEmpty) pages.add(d.cast<String,Object?>());
          if (d['text_delta'] is List) {
            try { _quill.document = Document.fromJson(d['text_delta'] as List); } catch (_) {}
          }
        }
      } catch (_) {}
    }
    if (pages.isEmpty) pages.add(_newPage());
    final name = pages.first['template']?.toString();
    _template = PageTemplate.values.firstWhere((e) => e.name == name, orElse: () => PageTemplate.dotted);
    if (!mounted) return;
    setState(() { _pages = pages; _page = 0; _loading = false; });
  }

  Map<String,Object?> _newPage() => {
    'id': DateTime.now().microsecondsSinceEpoch.toString(),
    'template': PageTemplate.dotted.name,
    'strokes': <Object?>[],
    'version': 2,
  };

  void _scheduleSave() {
    if (_locked && !_unlocked) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), _save);
  }

  Future<void> _save() async {
    if (_loading || _pages.isEmpty || (_locked && !_unlocked)) return;
    await _repo.saveContent(widget.note.id, {
      'version': 3, 'pages': _pages, 'text_delta': _quill.document.toDelta().toJson(),
    });
    final title = _title.text.trim();
    if (title.isNotEmpty && title != widget.note.title) await _repo.rename(widget.note.id, title);
  }

  void _canvasChanged(Map<String,Object?> value) {
    final next = Map<String,Object?>.from(_current)..addAll(value);
    next['template'] = _template.name;
    setState(() => _pages[_page] = next);
    _scheduleSave();
  }

  void _toolSelect(CanvasTool tool) => setState(() { _tool = tool; _pan = false; _shapes = false; });
  void _addPage() { setState(() { _pages.add(_newPage()); _page = _pages.length - 1; _template = PageTemplate.dotted; }); _scheduleSave(); }
  void _selectPage(int i) {
    final name = _pages[i]['template']?.toString();
    setState(() {
      _page = i;
      _template = PageTemplate.values.firstWhere((e) => e.name == name, orElse: () => PageTemplate.dotted);
    });
  }

  Future<void> _templatePicker() async {
    final selected = await showModalBottomSheet<PageTemplate>(
      context: context, showDragHandle: true,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children:
        PageTemplate.values.map((t) => ListTile(
          leading: Icon(t == _template ? Icons.check_circle : Icons.circle_outlined),
          title: Text(t.name.toUpperCase()),
          onTap: () => Navigator.pop(context,t),
        )).toList())),
    );
    if (selected == null) return;
    setState(() {
      _template = selected;
      _pages[_page] = Map<String,Object?>.from(_current)..['template'] = selected.name;
    });
    _scheduleSave();
  }

  Future<void> _toggleLock() async {
    if (_locked) {
      final ok = await _lock.authenticate();
      if (!mounted || !ok) return;
      await _lock.setLocked(widget.note.id, false);
      setState(() { _locked = false; _unlocked = true; });
    } else {
      await _save();
      await _lock.setLocked(widget.note.id, true);
      if (mounted) setState(() => _locked = true);
    }
  }

  void _fullScreen() {
    setState(() => _full = !_full);
    SystemChrome.setEnabledSystemUIMode(_full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  @override Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_locked && !_unlocked) return Scaffold(appBar: AppBar(title: Text(widget.note.title)), body: _lockedView());

    return Scaffold(
      backgroundColor: const Color(0xffedf2f7),
      body: SafeArea(child: Stack(children: [
        Positioned.fill(child: InteractiveViewer(
          minScale: .55, maxScale: 4, boundaryMargin: const EdgeInsets.all(450),
          panEnabled: _pan, scaleEnabled: _pan,
          child: Center(child: AspectRatio(aspectRatio: 210/297, child: Material(
            elevation: 6, color: Colors.white,
            child: Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: PageBackground(template: _template)),
              if (_drawing) IgnorePointer(
                ignoring: _pan,
                child: SnoteCanvas(
                  key: ValueKey(widget.note.id + '-' + _page.toString()),
                  pen: _pen, tool: _tool, controller: _canvas, initialDocument: _current,
                  backgroundColor: Colors.transparent, onChanged: _canvasChanged,
                  onSelectionChanged: (n) => setState(() => _selected = n),
                ),
              ) else Padding(
                padding: const EdgeInsets.all(26),
                child: QuillEditor(focusNode: _focus, scrollController: _scroll, controller: _quill,
                  config: const QuillEditorConfig(placeholder: 'Start writing…')),
              ),
            ]),
          ))),
        )),
        if (!_full) _header(),
        if (!_full) _tabs(),
        if (_previews) _previewRail(),
        if (_toolbar && _drawing) _floatingTools(),
        if (_shapes && _drawing) _shapeBox(),
        if (_selected > 0 && _drawing) _selectionBar(),
        Positioned(right: 10, top: MediaQuery.sizeOf(context).height * .45,
          child: FloatingActionButton.small(
            heroTag: 'snote-tools',
            onPressed: () => setState(() => _toolbar = !_toolbar),
            child: Icon(_toolbar ? Icons.chevron_right_rounded : Icons.edit_rounded),
          )),
      ])),
    );
  }

  Widget _header() => Positioned(left:0,right:0,top:0,child: Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha:.97),
    child: SizedBox(height:58,child: Row(children:[
      IconButton(tooltip:'Note list',onPressed:()=>Navigator.maybePop(context),icon:const Icon(Icons.menu_rounded)),
      Expanded(child:TextField(controller:_title,onSubmitted:(_)=>_save(),decoration:const InputDecoration(hintText:'Untitled note',border:InputBorder.none),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:18))),
      IconButton(tooltip:'Page preview',onPressed:()=>setState(()=>_previews=!_previews),icon:const Icon(Icons.view_sidebar_outlined)),
      IconButton(tooltip:'Template',onPressed:_templatePicker,icon:const Icon(Icons.grid_4x4_rounded)),
      IconButton(tooltip:_locked?'Unlock note':'Lock note',onPressed:_toggleLock,icon:Icon(_locked?Icons.lock_open_rounded:Icons.lock_outline_rounded)),
      IconButton(tooltip:'Undo',onPressed:_canvas.canUndo?_canvas.undo:null,icon:const Icon(Icons.undo_rounded)),
      IconButton(tooltip:'Redo',onPressed:_canvas.canRedo?_canvas.redo:null,icon:const Icon(Icons.redo_rounded)),
      IconButton(tooltip:'Full screen',onPressed:_fullScreen,icon:Icon(_full?Icons.fullscreen_exit_rounded:Icons.fullscreen_rounded)),
      IconButton(tooltip:'Settings',onPressed:()=>showModalBottomSheet(context:context,showDragHandle:true,builder:(_)=>const SafeArea(child:Padding(padding:EdgeInsets.all(22),child:Text('Editor settings',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800))))),icon:const Icon(Icons.settings_outlined)),
    ])),
  ));

  Widget _tabs() => Positioned(left:0,right:0,top:58,child:Material(
    color:Theme.of(context).colorScheme.surface.withValues(alpha:.94),
    child:SizedBox(height:38,child:ListView.separated(
      padding:const EdgeInsets.symmetric(horizontal:10),scrollDirection:Axis.horizontal,
      itemCount:_pages.length+1,separatorBuilder:(_,__)=>const SizedBox(width:5),
      itemBuilder:(_,i)=>i==_pages.length
        ? IconButton(tooltip:'Add page',onPressed:_addPage,icon:const Icon(Icons.add_rounded,size:20))
        : ChoiceChip(label:Text('Page '+(i+1).toString()),selected:i==_page,onSelected:(_)=>_selectPage(i),
            visualDensity:VisualDensity.compact),
    )),
  ));

  Widget _floatingTools() => Positioned(left:12,right:12,bottom:16,child:Center(child:Material(
    elevation:14,borderRadius:BorderRadius.circular(26),color:Theme.of(context).colorScheme.surface.withValues(alpha:.98),
    child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:7),child:Wrap(
      alignment:WrapAlignment.center,crossAxisAlignment:WrapCrossAlignment.center,spacing:3,children:[
        _toolButton(CanvasTool.ballpoint,Icons.edit_rounded),_toolButton(CanvasTool.fountain,Icons.gesture_rounded),
        _toolButton(CanvasTool.pencil,Icons.brush_rounded),_toolButton(CanvasTool.highlighter,Icons.highlight_rounded),
        _toolButton(CanvasTool.eraser,Icons.auto_fix_normal_rounded),_toolButton(CanvasTool.lasso,Icons.gesture_rounded),
        IconButton.filledTonal(tooltip:'Shapes',onPressed:()=>setState(()=>_shapes=!_shapes),icon:const Icon(Icons.category_outlined)),
        _colorDot(const Color(0xff263238)),_color(const Color(0xff2563eb)),_color(const Color(0xffdc2626)),
        _color(const Color(0xff16a34a)),_color(const Color(0xff7c3aed)),
        IconButton(tooltip:'Stroke size',onPressed:_sizePicker,icon:const Icon(Icons.line_weight_rounded)),
        IconButton(tooltip:'Hand / pan',onPressed:()=>setState(()=>_pan=!_pan),icon:Icon(_pan?Icons.pan_tool_rounded:Icons.pan_tool_outlined)),
        IconButton(tooltip:'Text mode',onPressed:()=>setState(()=>_drawing=false),icon:const Icon(Icons.text_fields_rounded)),
      ],
    )),
  )));

  Widget _toolButton(CanvasTool tool,IconData icon)=>IconButton.filledTonal(
    tooltip:tool.label,onPressed:()=>_toolSelect(tool),
    style:IconButton.styleFrom(backgroundColor:_tool==tool?Theme.of(context).colorScheme.primaryContainer:null),
    icon:Icon(icon));

  Widget _colorDot(Color c)=>InkWell(borderRadius:BorderRadius.circular(20),onTap:()=>setState(()=>_color=c),child:Padding(
    padding:const EdgeInsets.all(5),child:CircleAvatar(radius:_color==c?13:11,backgroundColor:c,
      child:_color==c?const Icon(Icons.check,size:14,color:Colors.white):null)));

  void _sizePicker()=>showModalBottomSheet(context:context,showDragHandle:true,builder:(_)=>StatefulBuilder(
    builder:(context,setModal)=>Padding(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text('Stroke '+_size.toStringAsFixed(1)+' px',style:const TextStyle(fontWeight:FontWeight.w800)),
      Slider(min:1,max:14,divisions:26,value:_size,onChanged:(v){setModal((){});setState(()=>_size=v);}),
    ])));

  Widget _shapeBox()=>Positioned(right:18,bottom:92,child:Material(
    elevation:14,borderRadius:BorderRadius.circular(20),color:Theme.of(context).colorScheme.surface,
    child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[
      _shape(CanvasTool.line,Icons.horizontal_rule_rounded),_shape(CanvasTool.arrow,Icons.arrow_forward_rounded),
      _shape(CanvasTool.rectangle,Icons.crop_square_rounded),_shape(CanvasTool.ellipse,Icons.circle_outlined),
      _shape(CanvasTool.triangle,Icons.change_history_outlined),
    ])));

  Widget _shape(CanvasTool t,IconData i)=>IconButton(tooltip:t.label,onPressed:()=>_toolSelect(t),
    style:IconButton.styleFrom(backgroundColor:_tool==t?Theme.of(context).colorScheme.primaryContainer:null),icon:Icon(i));

  Widget _selectionBar()=>Positioned(left:0,right:0,bottom:90,child:Center(child:Material(
    elevation:12,borderRadius:BorderRadius.circular(22),child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
      child:Row(mainAxisSize:MainAxisSize.min,children:[
        Text(_selected.toString()+' selected',style:const TextStyle(fontWeight:FontWeight.w700)),
        IconButton(tooltip:'Left',onPressed:()=>_canvas.moveSelection(-8,0),icon:const Icon(Icons.arrow_back_rounded)),
        IconButton(tooltip:'Right',onPressed:()=>_canvas.moveSelection(8,0),icon:const Icon(Icons.arrow_forward_rounded)),
        IconButton(tooltip:'Duplicate',onPressed:_canvas.duplicateSelection,icon:const Icon(Icons.copy_rounded)),
        IconButton(tooltip:'Delete',onPressed:_canvas.deleteSelection,icon:const Icon(Icons.delete_outline_rounded)),
        IconButton(tooltip:'Close',onPressed:_canvas.clearSelection,icon:const Icon(Icons.close_rounded)),
      ])))));

  Widget _previewRail()=>Positioned(left:0,top:0,bottom:0,width:116,child:Material(
    elevation:16,color:Theme.of(context).colorScheme.surface,child:SafeArea(child:Column(children:[
      const SizedBox(height:10),const Text('Pages',style:TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:8),
      Expanded(child:ListView.builder(padding:const EdgeInsets.all(8),itemCount:_pages.length,itemBuilder:(_,i)=>Padding(
        padding:const EdgeInsets.only(bottom:8),child:InkWell(onTap:()=>_selectPage(i),child:AspectRatio(aspectRatio:210/297,
          child:Container(decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(9),
            border:Border.all(color:i==_page?Theme.of(context).colorScheme.primary:Colors.black12,width:i==_page?2:1)),
            child:Center(child:Text((i+1).toString(),style:const TextStyle(fontWeight:FontWeight.w800))))))))),
      IconButton(tooltip:'Add page',onPressed:_addPage,icon:const Icon(Icons.add_box_outlined)),
    ])));

  Widget _lockedView()=>Center(child:Card(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Icon(Icons.lock_rounded,size:60),const SizedBox(height:14),const Text('Note locked',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
    const SizedBox(height:8),const Text('Authenticate on this device to open the note.',textAlign:TextAlign.center),const SizedBox(height:18),
    FilledButton.icon(onPressed:()async{final ok=await _lock.authenticate();if(!mounted)return;setState(()=>_unlocked=ok);if(ok)await _load();},
      icon:const Icon(Icons.fingerprint_rounded),label:const Text('Unlock')),
  ])));

  @override void dispose(){
    _saveTimer?.cancel();if(!_locked||_unlocked)unawaited(_save());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _title.dispose();_focus.dispose();_scroll.dispose();_quill.dispose();_canvas.dispose();super.dispose();
  }
}
