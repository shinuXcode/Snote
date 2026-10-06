import 'package:flutter/material.dart';
import 'canvas_engine/widgets/snote_canvas.dart';
import 'canvas_engine/models/pen_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SnoteApp());
}

class SnoteApp extends StatelessWidget {
  const SnoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const SnoteHomePage(),
    );
  }
}

class SnoteHomePage extends StatefulWidget {
  const SnoteHomePage({super.key});

  @override
  State<SnoteHomePage> createState() => _SnoteHomePageState();
}

class _SnoteHomePageState extends State<SnoteHomePage> {
  PenConfig pen = const PenConfig(
    type: PenType.ballpoint,
    color: Colors.black,
    size: 3,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Snote'),
        actions: [
          IconButton(
            tooltip: 'Ballpoint',
            onPressed: () => setState(() {
              pen = const PenConfig(
                type: PenType.ballpoint,
                color: Colors.black,
                size: 3,
              );
            }),
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: 'Highlighter',
            onPressed: () => setState(() {
              pen = const PenConfig(
                type: PenType.highlighter,
                color: Colors.yellow,
                size: 18,
                opacity: .35,
              );
            }),
            icon: const Icon(Icons.highlight),
          ),
        ],
      ),
      body: SnoteCanvas(pen: pen),
    );
  }
}
