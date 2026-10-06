create table if not exists public.note_assets (
  id uuid primary key,
  note_id uuid not null references public.notes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  object_key text not null,
  mime_type text not null,
  byte_size bigint,
  created_at timestamptz not null default now()
);

alter table public.note_assets enable row level security;

drop policy if exists "note_assets_select_owner" on public.note_assets;
create policy "note_assets_select_owner"
  on public.note_assets for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "note_assets_insert_owner" on public.note_assets;
create policy "note_assets_insert_owner"
  on public.note_assets for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "note_assets_update_owner" on public.note_assets;
create policy "note_assets_update_owner"
  on public.note_assets for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "note_assets_delete_owner" on public.note_assets;
create policy "note_assets_delete_owner"
  on public.note_assets for delete to authenticated
  using ((select auth.uid()) = user_id);

insert into storage.buckets (id, name, public)
values ('note-assets', 'note-assets', false)
on conflict (id) do nothing;

drop policy if exists "note_assets_storage_select" on storage.objects;
create policy "note_assets_storage_select"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'note-assets' and
    (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "note_assets_storage_insert" on storage.objects;
create policy "note_assets_storage_insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'note-assets' and
    (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "note_assets_storage_update" on storage.objects;
create policy "note_assets_storage_update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'note-assets' and
    (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'note-assets' and
    (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "note_assets_storage_delete" on storage.objects;
create policy "note_assets_storage_delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'note-assets' and
    (storage.foldername(name))[1] = (select auth.uid())::text
  );
