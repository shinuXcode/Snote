import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';

class SnoteSupabase {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!SnoteConfig.cloudEnabled || _initialized) return;

    await Supabase.initialize(
      url: SnoteConfig.supabaseUrl,
      publishableKey: SnoteConfig.supabasePublishableKey,
    );
    _initialized = true;
  }

  static SupabaseClient? get client {
    if (!SnoteConfig.cloudEnabled || !_initialized) return null;
    return Supabase.instance.client;
  }
}
