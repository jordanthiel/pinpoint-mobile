-- Recover the 39 original shots hidden by the pre-build-28 reader bug.
-- This only clears the known erroneous tombstones; shot details are untouched.
-- Lock the account and advance its cursor in the same transaction so every
-- client sees the repair. Never restore a subsequently deleted round or hole.
do $$
declare
  owner_id uuid := '26df7343-187e-446d-999b-ca8d34f438d5';
  target_round uuid := 'fa0201ea-d2f2-468a-b186-de1440329a0b';
  next_cursor bigint;
  restored integer;
begin
  select cursor + 1 into next_cursor from public.golf_sync_accounts
    where user_id = owner_id for update;
  if not found then return; end if;
  update public.shots s set deleted_at = null, revision = next_cursor, updated_at = now()
    where s.user_id = owner_id and s.round_id = target_round
      and s.revision = 143 and s.deleted_at = '2026-09-16T12:33:41.889518+00:00'::timestamptz
      and exists (select 1 from public.rounds r where r.user_id = s.user_id and r.id = s.round_id and r.deleted_at is null)
      and exists (select 1 from public.hole_scores h where h.user_id = s.user_id and h.round_id = s.round_id and h.id = s.hole_id and h.deleted_at is null);
  get diagnostics restored = row_count;
  if restored = 0 then return; end if;
  if restored <> 39 then raise exception 'Shot recovery expected 39 original rows, found %', restored; end if;
  update public.golf_sync_accounts set cursor = next_cursor where user_id = owner_id;
end $$;
