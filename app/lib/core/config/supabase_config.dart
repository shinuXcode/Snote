class SnoteConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  static const oauthRedirectUri = String.fromEnvironment(
    'SUPABASE_REDIRECT_URI',
    defaultValue: 'com.snote://auth-callback',
  );

  static bool get cloudEnabled =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
