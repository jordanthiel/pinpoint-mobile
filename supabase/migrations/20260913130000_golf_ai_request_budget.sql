create table if not exists public.golf_ai_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null default (now() at time zone 'utc')::date,
  request_count integer not null default 0,
  primary key (user_id, usage_day)
);
alter table public.golf_ai_daily_usage enable row level security;
revoke all on public.golf_ai_daily_usage from anon, authenticated;

create or replace function public.consume_golf_ai_request()
returns boolean language plpgsql security definer set search_path = '' as $$
declare used integer;
begin
  if auth.uid() is null then return false; end if;
  insert into public.golf_ai_daily_usage(user_id, usage_day, request_count)
  values (auth.uid(), (now() at time zone 'utc')::date, 1)
  on conflict (user_id, usage_day) do update
    set request_count = public.golf_ai_daily_usage.request_count + 1
    where public.golf_ai_daily_usage.request_count < 100
  returning request_count into used;
  return used is not null;
end;
$$;
revoke all on function public.consume_golf_ai_request() from public, anon;
grant execute on function public.consume_golf_ai_request() to authenticated;
