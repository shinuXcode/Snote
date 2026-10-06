class SnoteConfig {
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: '');

  static bool get cloudEnabled =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
