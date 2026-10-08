-- Deletes the caller's account, anonymous or not. Every user-owned table
-- references auth.users on delete cascade, so this one row takes the
-- entitlement, scan counts, networks, agents, pairing codes, devices, events
-- and push tokens with it. Store subscriptions are billed by Apple/Google and
-- must be cancelled there; the app says so before calling this.

create function public.delete_account()
returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
begin
    if v_user is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;
    delete from auth.users where id = v_user;
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
