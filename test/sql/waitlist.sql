-- Run against an isolated Postgres/Supabase test database after the migration.
begin;
set local role anon;
do $$ begin
  begin perform email from public.tradekarma_waitlist; raise exception 'anon read unexpectedly allowed';
  exception when insufficient_privilege then null; end;
  begin perform public.join_tradekarma_waitlist('test@example.invalid', repeat('a',64)); raise exception 'anon RPC unexpectedly allowed';
  exception when insufficient_privilege then null; end;
end $$;
set local role authenticated;
do $$ begin
  begin perform email from public.tradekarma_waitlist; raise exception 'authenticated read unexpectedly allowed';
  exception when insufficient_privilege then null; end;
end $$;
set local role service_role;
do $$ declare i integer; begin
  for i in 1..5 loop
    if not public.join_tradekarma_waitlist('Test@Example.invalid',repeat('a',64)) then raise exception 'valid signup refused'; end if;
  end loop;
  if public.join_tradekarma_waitlist('another@example.invalid',repeat('a',64)) then raise exception 'rate limit bypassed'; end if;
  if (select count(*) from public.tradekarma_waitlist where email='test@example.invalid') != 1 then raise exception 'duplicate or normalization failure'; end if;
  if exists(select 1 from public.tradekarma_waitlist where email='another@example.invalid') then raise exception 'limited email was saved'; end if;
end $$;
reset role;
do $$ begin
  if not (select relrowsecurity from pg_class where oid='public.tradekarma_waitlist'::regclass) then raise exception 'RLS disabled'; end if;
end $$;
rollback;
