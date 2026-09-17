-- Paginated pull. Full-history pulls time out server-side (Postgres 57014)
-- once an account accumulates enough rows, and every retry re-attempts the
-- same giant pull, so sync can never progress. Clients page with
-- after_cursor/end_cursor until has_more is false.
--
-- Keep the original one-argument RPC for old clients. Require both arguments
-- on this overload so PostgREST can resolve legacy calls unambiguously.
-- A transaction shares one revision across many rows: never split that group.
create or replace function public.pull_golf_records(after_cursor bigint, page_limit integer)
returns jsonb
language sql stable security invoker set search_path = public, pg_temp as $$
with account as (
  select coalesce((select cursor from public.golf_sync_accounts where user_id = auth.uid()), 0) as cursor
),
page as (
  select r.*
  from public.golf_records r, account
  where r.user_id = auth.uid()
    and r.revision > after_cursor
    and r.revision <= account.cursor
  order by r.revision
  fetch first (greatest(1, least(coalesce(page_limit, 1000), 100000))) rows with ties
),
end_cursor as (
  select coalesce(max(page.revision), after_cursor) as v from page
)
select jsonb_build_object(
  'cursor', (select cursor from account),
  'end_cursor', (select v from end_cursor),
  'has_more', exists(
    select 1 from public.golf_records r, account, end_cursor
    where r.user_id = auth.uid()
      and r.revision > end_cursor.v
      and r.revision <= account.cursor),
  'records', coalesce((
    select jsonb_agg(to_jsonb(page) - 'user_id'
      order by page.revision, page.kind, page.round_id, page.id)
    from page), '[]'::jsonb)
);
$$;
revoke all on function public.pull_golf_records(bigint, integer) from public, anon;
grant execute on function public.pull_golf_records(bigint, integer) to authenticated;
