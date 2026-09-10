-- Pinpoint cloud storage: swings table, RLS, and private storage bucket.

create table public.swings (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  created_at timestamptz not null default now(),
  duration double precision not null,
  frame_rate double precision not null,
  width integer not null,
  height integer not null,
  file_name text not null,
  thumbnail_file_name text not null,
  annotations_json text not null default '[]',
  video_path text not null,
  thumbnail_path text not null
);

create index swings_user_id_created_at_idx
  on public.swings (user_id, created_at desc);

alter table public.swings enable row level security;

create policy "Users can read own swings"
  on public.swings for select
  using (auth.uid() = user_id);

create policy "Users can insert own swings"
  on public.swings for insert
  with check (auth.uid() = user_id);

create policy "Users can update own swings"
  on public.swings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own swings"
  on public.swings for delete
  using (auth.uid() = user_id);

insert into storage.buckets (id, name, public, file_size_limit)
values ('swings', 'swings', false, 524288000);

create policy "Users can upload own swing files"
  on storage.objects for insert
  with check (
    bucket_id = 'swings'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

create policy "Users can read own swing files"
  on storage.objects for select
  using (
    bucket_id = 'swings'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

create policy "Users can update own swing files"
  on storage.objects for update
  using (
    bucket_id = 'swings'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

create policy "Users can delete own swing files"
  on storage.objects for delete
  using (
    bucket_id = 'swings'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );
