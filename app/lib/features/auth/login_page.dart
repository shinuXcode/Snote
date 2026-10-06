import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../data/remote/supabase_service.dart';
import '../../ui/snote_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();

  bool loading = false;
  String? error;
  bool showLogin = true;

  Future<void> submit() async {
    final client = SnoteSupabase.client;
    if (client == null) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final response = showLogin
          ? await client.auth.signInWithPassword(
              email: email.text.trim(),
              password: password.text,
            )
          : await client.auth.signUp(
              email: email.text.trim(),
              password: password.text,
            );

      if (!showLogin && response.session == null) {
        error = 'Check your email to confirm your Snote account.';
      }
    } on AuthException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> google() async {
    final client = SnoteSupabase.client;
    if (client == null) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SnoteConfig.oauthRedirectUri,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SnoteLogo(size: 64),
                      const SizedBox(height: 24),
                      Text(
                        showLogin ? 'Welcome back' : 'Create your Snote account',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sync notes across your Snote devices.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: password,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: loading ? null : submit,
                          child: Text(showLogin ? 'Sign in' : 'Create account'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: loading ? null : google,
                          icon: const Icon(Icons.account_circle_outlined),
                          label: const Text('Continue with Google'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: loading
                            ? null
                            : () => setState(() {
                                  showLogin = !showLogin;
                                  error = null;
                                }),
                        child: Text(
                          showLogin
                              ? 'New to Snote? Create an account'
                              : 'Already have an account? Sign in',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your local notebook remains usable offline.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }
}
