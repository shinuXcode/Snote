alter table public.folders
  add column if not exists color_value bigint not null default 4284187897,
  add column if not exists icon_key text not null default 'folder',
  add column if not exists sort_order integer not null default 0;

create index if not exists folders_user_parent_order_idx
  on public.folders(user_id, parent_id, sort_order, name);
