import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
class SnoteSupabase {
  static Future<void> initialize() async {if(!SnoteConfig.cloudEnabled)return;await Supabase.initialize(url:SnoteConfig.supabaseUrl,publishableKey:SnoteConfig.supabasePublishableKey);}
  static SupabaseClient? get client=>SnoteConfig.cloudEnabled?Supabase.instance.client:null;
}
