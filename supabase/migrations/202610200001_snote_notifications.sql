-- Snote website-to-app announcement feed.
create table if not exists public.snote_notifications (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 140),
  body text not null check (char_length(body) between 1 and 4000),
  category text not null default 'update' check (category in ('update','release','maintenance','security','feature')),
  target text not null default 'all' check (target in ('all','website','app')),
  action_url text,
  published boolean not null default false,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);
create index if not exists snote_notifications_published_at_idx on public.snote_notifications (published_at desc) where published = true;
alter table public.snote_notifications enable row level security;
drop policy if exists "Public can read published notifications" on public.snote_notifications;
create policy "Public can read published notifications" on public.snote_notifications for select using (published = true and (published_at is null or published_at <= now()));
drop policy if exists "Admins can manage notifications" on public.snote_notifications;
create policy "Admins can manage notifications" on public.snote_notifications for all to authenticated using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin') with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
grant select on public.snote_notifications to anon, authenticated;
grant insert, update, delete on public.snote_notifications to authenticated;
do $$
begin
  alter publication supabase_realtime add table public.snote_notifications;
exception when duplicate_object then null; when undefined_object then null;
end $$;
