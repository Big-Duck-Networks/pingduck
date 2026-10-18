-- Launch waitlist for pingduck.app (2026-10-18). The website calls
-- join_waitlist with the publishable key; nobody can read the table through
-- the API. Emails are only for the launch announcement (see /privacy).
--
-- join_waitlist never says whether an email was already on the list, and
-- caps sign-ups at 500 an hour overall, so a script can't fill the table.

create table public.waitlist (
    email      text primary key check (email = lower(email) and length(email) <= 254),
    source     text check (length(source) <= 32),
    created_at timestamptz not null default now()
);

alter table public.waitlist enable row level security;
revoke all on public.waitlist from anon, authenticated;

create index waitlist_created_at on public.waitlist (created_at);

create or replace function public.join_waitlist(p_email text, p_source text default 'website')
returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_email text := lower(btrim(p_email));
begin
    if v_email is null or length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        raise exception 'invalid email' using errcode = '22023';
    end if;
    if (select count(*) from public.waitlist where created_at > now() - interval '1 hour') >= 500 then
        raise exception 'busy: try again later' using errcode = 'P0001';
    end if;
    insert into public.waitlist (email, source)
    values (v_email, left(nullif(btrim(p_source), ''), 32))
    on conflict (email) do nothing;
end
$$;

revoke execute on function public.join_waitlist(text, text) from public;
grant execute on function public.join_waitlist(text, text) to anon, authenticated;
