# Snote Supabase setup

1. Create a free Supabase project.
2. Run the SQL files in migrations/ in order.
3. Enable Email/Password and Google providers in Supabase Auth.
4. Configure the redirect URL used by the app:
   - Native: com.snote://auth-callback
   - Web: your deployed Snote website /account
5. Add the same project URL and publishable key to Flutter release secrets and the website environment.

Use only the publishable key in public clients. Never put the service-role key in the app or website.

Note content is protected by per-user RLS. Larger attachments use the private note-assets storage bucket.
