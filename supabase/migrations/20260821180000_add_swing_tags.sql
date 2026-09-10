-- Tags for filtering swings in the library. Local copies keep tags in swings.json;
-- this column lets uploaded swings carry the same metadata across devices.

alter table public.swings
  add column if not exists tags_json text not null default '[]';
