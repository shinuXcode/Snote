# Snote Website Notifications and Admin Publishing

## Intended flow

1. An administrator signs in with Supabase Auth.
2. Only users whose server-managed `app_metadata.role` is `admin` can create, edit, publish, or delete notices.
3. Published rows in `public.snote_notifications` are readable by the website and Snote app.
4. The Flutter service at `app/lib/core/notifications/snote_notification_service.dart` fetches notices targeted to `all` or `app` and can listen for realtime change signals.
5. A client refreshes the list after a realtime signal; row-level security remains authoritative.

## Required setup before enabling

- Confirm the correct Supabase project; do not use an unrelated or inactive project.
- Apply `supabase/migrations/202610200001_snote_notifications.sql` to the intended project.
- Enable Realtime for `public.snote_notifications` in Supabase.
- Configure `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` in Vercel and matching `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` build values for Flutter.
- Grant admin role only using trusted server-side Supabase administration. Never let a browser client set its own `app_metadata`.
- Integrate the service into the app notification UI and add an app-level unread/read model if needed. The service alone does not display a notification screen or deliver OS push notifications.
- For push notifications while the app is closed, configure a trusted server-side push provider (such as FCM/APNs) and securely store device tokens. Realtime is not a replacement for OS push delivery.

## Security

Public clients can read published notices only. Admin writes require a JWT claim in `app_metadata`, not editable user metadata. Keep service-role credentials out of client bundles, repository files, logs, and `NEXT_PUBLIC_*` variables.

## Verification checklist

- Anonymous users can read published rows but cannot read drafts or write.
- Authenticated non-admin users cannot create, edit, publish, or delete rows.
- Admin can draft, publish, edit, and unpublish.
- Website and app both point to the same Supabase project.
- Realtime updates trigger refresh without duplicate subscriptions or leaked listeners.
- Test empty, long, malformed URL, offline, and revoked-session states.
