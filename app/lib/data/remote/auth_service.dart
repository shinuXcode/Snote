import 'package:supabase_flutter/supabase_flutter.dart';

class SnoteAuthService {
  final SupabaseClient client;

  const SnoteAuthService(this.client);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return client.auth.signUp(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<bool> signInWithGoogle({
    required String redirectTo,
  }) {
    return client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
    );
  }

  Future<void> signOut() => client.auth.signOut();

  User? get currentUser => client.auth.currentUser;
}
