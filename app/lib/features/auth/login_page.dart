import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../data/remote/supabase_service.dart';
import '../../ui/snote_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false, showLogin = true, obscure = true;
  String? error;

  Future<void> submit() async {
    final client = SnoteSupabase.client;
    if (client == null) {
      setState(() => error = 'Cloud accounts are not configured in this build. Your local notebook still works offline.');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final response = showLogin
          ? await client.auth.signInWithPassword(email: email.text.trim(), password: password.text)
          : await client.auth.signUp(email: email.text.trim(), password: password.text);
      if (!showLogin && response.session == null) {
        setState(() => error = 'Account created. Check your email to confirm it.');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> google() async {
    final client = SnoteSupabase.client;
    if (client == null) {
      setState(() => error = 'Google sign-in is unavailable because cloud accounts are not configured.');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      await client.auth.signInWithOAuth(OAuthProvider.google, redirectTo: SnoteConfig.oauthRedirectUri);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: Card(
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 720;
            final form = Padding(padding: EdgeInsets.all(wide ? 42 : 26), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SnoteLogo(size: 42), const SizedBox(height: 28),
              Text(showLogin ? 'Welcome back.' : 'Create your notebook.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1)),
              const SizedBox(height: 8),
              Text(showLogin ? 'Sign in to keep your notes available across your devices.' : 'Create an account when cloud sync is enabled. Local notes stay on your device.', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 28),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.mail_outline_rounded))),
              const SizedBox(height: 12),
              TextField(controller: password, obscureText: obscure, autofillHints: const [AutofillHints.password], decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline_rounded), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
              if (error != null) ...[
                const SizedBox(height: 14),
                Container(width: double.infinity, padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(14)), child: Text(error!, style: TextStyle(color: scheme.onErrorContainer))),
              ],
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: loading ? null : submit, child: Text(showLogin ? 'Sign in' : 'Create account'))),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: loading ? null : google, icon: const Icon(Icons.g_mobiledata_rounded), label: const Text('Continue with Google'))),
              const SizedBox(height: 8),
              Center(child: TextButton(onPressed: loading ? null : () => setState(() { showLogin = !showLogin; error = null; }), child: Text(showLogin ? 'Create a new account' : 'I already have an account'))),
            ]));
            if (!wide) return form;
            return Row(children: [
              Expanded(child: Container(color: scheme.primaryContainer.withValues(alpha: .42), padding: const EdgeInsets.all(42), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.auto_stories_rounded, size: 58, color: scheme.primary),
                const SizedBox(height: 22),
                const Text('A notebook that feels like yours.', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.05)),
                const SizedBox(height: 12),
                const Text('Write by hand. Type rich text. Annotate PDFs. Keep your everyday notes local-first.', style: TextStyle(fontSize: 15, height: 1.5)),
              ]))), Expanded(child: form),
            ]);
          }),
        )),
      ))),
    );
  }

  @override void dispose() { email.dispose(); password.dispose(); super.dispose(); }
}
