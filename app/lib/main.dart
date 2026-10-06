import 'package:flutter/material.dart';
import 'app/auth_gate.dart';
import 'data/remote/supabase_service.dart';
Future<void> main()async{WidgetsFlutterBinding.ensureInitialized();await SnoteSupabase.initialize();runApp(const SnoteApp());}
class SnoteApp extends StatelessWidget{const SnoteApp({super.key});@override Widget build(BuildContext context)=>MaterialApp(title:'Snote',debugShowCheckedModeBanner:false,theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF7567FF)),useMaterial3:true),home:const AuthGate());}
