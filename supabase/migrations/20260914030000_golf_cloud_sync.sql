-- Versioned account snapshot: complete Codable golf data, including unknown/new fields.
create table public.golf_sync_state (
    user_id uuid primary key references auth.users(id) on delete cascade,
    revision bigint not null default 1 check (revision > 0),
    payload jsonb not null check (jsonb_typeof(payload) = 'object'),
    updated_at timestamptz not null default now()
);
alter table public.golf_sync_state enable row level security;
create policy golf_sync_read_own on public.golf_sync_state for select to authenticated
    using (auth.uid() = user_id);
revoke all on public.golf_sync_state from anon, authenticated;
grant select on public.golf_sync_state to authenticated;

-- Compare-and-swap prevents a stale device from blindly replacing newer data.
create function public.sync_golf_state(expected_revision bigint, new_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
    owner_id uuid := auth.uid();
    current_row public.golf_sync_state;
begin
    if owner_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    if expected_revision < 0 or jsonb_typeof(new_payload) is distinct from 'object'
       or jsonb_typeof(new_payload->'rounds') is distinct from 'array'
       or jsonb_typeof(new_payload->'bag') is distinct from 'object'
       or jsonb_typeof(new_payload->'practice') is distinct from 'array' then
        raise exception 'Invalid golf snapshot' using errcode = '22023';
    end if;
    if expected_revision = 0 then
        insert into public.golf_sync_state(user_id, payload) values(owner_id, new_payload)
        on conflict do nothing returning * into current_row;
        if found then return jsonb_build_object('accepted', true, 'revision', current_row.revision, 'payload', current_row.payload); end if;
    else
        update public.golf_sync_state set payload = new_payload, revision = revision + 1, updated_at = now()
        where user_id = owner_id and revision = expected_revision returning * into current_row;
        if found then return jsonb_build_object('accepted', true, 'revision', current_row.revision, 'payload', current_row.payload); end if;
    end if;
    select * into current_row from public.golf_sync_state where user_id = owner_id;
    return jsonb_build_object('accepted', false, 'revision', coalesce(current_row.revision, 0), 'payload', current_row.payload);
end;
$$;
revoke all on function public.sync_golf_state(bigint, jsonb) from public, anon;
grant execute on function public.sync_golf_state(bigint, jsonb) to authenticated;
