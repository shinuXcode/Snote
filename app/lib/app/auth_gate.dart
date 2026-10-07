import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../core/config/account_scope.dart';
import '../data/remote/supabase_service.dart';
import '../features/auth/login_page.dart';
import '../features/notes/notes_home_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SnoteConfig.cloudEnabled) {
      SnoteAccountScope.setAuthenticatedUser(null);
      return const NotesHomePage(localOnly: true);
    }

    final client = SnoteSupabase.client!;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, _) {
        final session = client.auth.currentSession;
        SnoteAccountScope.setAuthenticatedUser(session?.user.id);
        if (session == null) return const LoginPage();
        return const NotesHomePage();
      },
    );
  }
}
