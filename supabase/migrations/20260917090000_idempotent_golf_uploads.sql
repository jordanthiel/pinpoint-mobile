-- A receipt and its writes commit in the same transaction. Replaying a batch
-- after the server committed but the phone lost the response is harmless.
create table public.golf_upload_receipts (
    user_id uuid not null references auth.users(id) on delete cascade,
    batch_id uuid not null,
    accepted boolean not null,
    created_at timestamptz not null default now(),
    primary key (user_id, batch_id)
);
alter table public.golf_upload_receipts enable row level security;
revoke all on public.golf_upload_receipts from public, anon, authenticated;

create function public.commit_golf_batch(batch_id uuid, changes jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
    owner_id uuid := auth.uid();
    result jsonb;
    prior boolean;
begin
    if owner_id is null then raise exception 'Authentication required' using errcode='42501'; end if;
    if batch_id is null then raise exception 'Batch ID required' using errcode='22023'; end if;
    -- Same lock as commit_golf_records, serializing both old and new clients.
    insert into public.golf_sync_accounts(user_id) values(owner_id) on conflict do nothing;
    perform 1 from public.golf_sync_accounts where user_id=owner_id for update;
    select r.accepted into prior from public.golf_upload_receipts r
        where r.user_id=owner_id and r.batch_id=commit_golf_batch.batch_id;
    if found then return jsonb_build_object('accepted', prior); end if;
    result := public.commit_golf_records(changes);
    insert into public.golf_upload_receipts(user_id, batch_id, accepted)
        values(owner_id, batch_id, (result->>'accepted')::boolean);
    return result;
end;
$$;
revoke all on function public.commit_golf_batch(uuid,jsonb) from public, anon;
grant execute on function public.commit_golf_batch(uuid,jsonb) to authenticated;
