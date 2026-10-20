create table if not exists public.website_notifications (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 2000),
  category text not null default 'announcement' check (char_length(category) <= 40),
  action_url text,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists website_notifications_published_idx
  on public.website_notifications (published_at desc)
  where published_at is not null;

alter table public.website_notifications enable row level security;
revoke all on public.website_notifications from anon, authenticated;
grant select on public.website_notifications to anon, authenticated;

drop policy if exists "published website notifications are readable" on public.website_notifications;
create policy "published website notifications are readable"
  on public.website_notifications for select to anon, authenticated
  using (published_at is not null and published_at <= now()
    and (expires_at is null or expires_at > now()));

-- Inserts, edits and deletes are performed only by the server-side Control Room
-- using a service-role key. Never expose that key to the browser or Flutter app.
