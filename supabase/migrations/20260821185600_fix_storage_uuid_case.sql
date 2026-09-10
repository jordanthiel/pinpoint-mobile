-- Swift UUID.uuidString is uppercase; auth.uid()::text is lowercase.
-- Storage RLS compared those strings, so uploads were rejected.

drop policy if exists "Users can upload own swing files" on storage.objects;
drop policy if exists "Users can read own swing files" on storage.objects;
drop policy if exists "Users can update own swing files" on storage.objects;
drop policy if exists "Users can delete own swing files" on storage.objects;

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
