-- Emails never have anon/authenticated read or write access. Only the server calls the RPC.
create table public.tradekarma_waitlist (
  email text primary key check (email = lower(btrim(email)) and length(email) between 3 and 254 and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  created_at timestamptz not null default now(),
  consent_version text not null default 'waitlist-2026-09-07'
);
alter table public.tradekarma_waitlist enable row level security;
revoke all on public.tradekarma_waitlist from public, anon, authenticated;
grant select, insert on public.tradekarma_waitlist to service_role;

create table public.tradekarma_waitlist_limits (
  rate_key text not null check (rate_key ~ '^[0-9a-f]{64}$'),
  window_start timestamptz not null,
  attempts integer not null check (attempts > 0),
  primary key (rate_key, window_start)
);
create index tradekarma_waitlist_limits_expiry on public.tradekarma_waitlist_limits (window_start);
alter table public.tradekarma_waitlist_limits enable row level security;
revoke all on public.tradekarma_waitlist_limits from public, anon, authenticated;
grant select, insert, update, delete on public.tradekarma_waitlist_limits to service_role;

-- SECURITY INVOKER: no definer function exposed through PostgREST.
create function public.join_tradekarma_waitlist(p_email text, p_rate_key text)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare hits integer;
begin
  delete from public.tradekarma_waitlist_limits where window_start < now() - interval '24 hours';
  insert into public.tradekarma_waitlist_limits (rate_key, window_start, attempts)
    values (p_rate_key, date_trunc('hour', now()), 1)
    on conflict (rate_key, window_start) do update set attempts = least(public.tradekarma_waitlist_limits.attempts + 1, 100)
    returning attempts into hits;
  if hits > 5 then return false; end if;
  insert into public.tradekarma_waitlist(email) values (lower(btrim(p_email))) on conflict (email) do nothing;
  return true;
end;
$$;
revoke all on function public.join_tradekarma_waitlist(text, text) from public, anon, authenticated;
grant execute on function public.join_tradekarma_waitlist(text, text) to service_role;
