create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notes (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  folder_id uuid,
  note_type text not null default 'handwriting',
  version bigint not null default 1,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.folders (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid,
  name text not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.pages (
  id uuid primary key,
  note_id uuid not null references public.notes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  page_index integer not null,
  width double precision not null,
  height double precision not null,
  background_type text,
  stroke_object_key text,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.notes enable row level security;
alter table public.folders enable row level security;
alter table public.pages enable row level security;

create policy "profiles owner select" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

create policy "profiles owner insert" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "profiles owner update" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "notes owner all" on public.notes
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "folders owner all" on public.folders
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "pages owner all" on public.pages
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create index if not exists notes_user_updated_idx
  on public.notes(user_id, updated_at desc);

create index if not exists folders_user_parent_idx
  on public.folders(user_id, parent_id);

create index if not exists pages_note_index_idx
  on public.pages(note_id, page_index);
