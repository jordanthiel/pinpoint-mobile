-- On-course rounds (local-first in the app; this table backs future cloud sync).
create table if not exists public.rounds (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.rounds enable row level security;

drop policy if exists "rounds_owner_rw" on public.rounds;
create policy "rounds_owner_rw" on public.rounds
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists rounds_user_started_idx
  on public.rounds (user_id, started_at desc);
