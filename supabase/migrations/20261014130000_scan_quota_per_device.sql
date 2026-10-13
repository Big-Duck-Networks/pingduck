-- Free scans are counted per device as well as per account (security review,
-- 2026-10-13). Free users sign in anonymously, so reinstalling the app or
-- clearing its data made a new account with a fresh 3 scans. The app now
-- sends the phone's Android ID, which survives a reinstall; only its salted
-- SHA-256 is stored, and only for 7 days. A Free scan needs room under both
-- counts. Builds that send no device id (Windows, older Android builds) are
-- counted per account only, as before.
--
-- Automatic scans (on launch, on Wi-Fi reconnect) also move here from the
-- app: Free gets one every 30 minutes per account and per device, and they
-- don't use the daily allowance.

create table public.device_scans (
    device       text not null,  -- hex sha256('pingduck-device:' || Android ID)
    day          date not null,
    scans        int  not null default 0,
    last_auto_at timestamptz,
    primary key (device, day)
);
alter table public.device_scans enable row level security;
revoke all on public.device_scans from anon, authenticated;

alter table public.scan_usage add column last_auto_at timestamptz;

-- Replaced, not overloaded: claim_scan() next to claim_scan(text, bool)
-- would make PostgREST calls without arguments ambiguous. Old builds call it
-- without arguments and land on the defaults.
drop function public.claim_scan();

create function public.claim_scan(p_device text default null, p_automatic bool default false)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_user      uuid := auth.uid();
    v_day       date := (now() at time zone 'utc')::date;
    v_limit     int;
    v_device    text;
    v_used      int;
    v_dev_used  int;
    v_user_auto timestamptz;
    v_dev_auto  timestamptz;
begin
    if v_user is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;
    v_limit := (public.plan_for(v_user)).daily_scan_limit;

    if v_limit is null then
        if not coalesce(p_automatic, false) then
            insert into public.scan_usage as u (user_id, day, scans) values (v_user, v_day, 1)
            on conflict (user_id, day) do update set scans = u.scans + 1;
        end if;
        return jsonb_build_object('allowed', true, 'remaining', null, 'limit', null);
    end if;

    if nullif(btrim(p_device), '') is not null then
        v_device := encode(extensions.digest('pingduck-device:' || left(btrim(p_device), 128), 'sha256'), 'hex');
    end if;

    -- Lock both rows so two scans at once can't both take the last one.
    insert into public.scan_usage (user_id, day) values (v_user, v_day) on conflict do nothing;
    select scans, last_auto_at into v_used, v_user_auto from public.scan_usage
    where user_id = v_user and day = v_day for update;
    if v_device is not null then
        insert into public.device_scans (device, day) values (v_device, v_day) on conflict do nothing;
        select scans, last_auto_at into v_dev_used, v_dev_auto from public.device_scans
        where device = v_device and day = v_day for update;
    end if;
    v_used := greatest(v_used, coalesce(v_dev_used, 0));

    if coalesce(p_automatic, false) then
        -- greatest() skips nulls: never scanned automatically today is fine.
        if greatest(v_user_auto, v_dev_auto) > now() - interval '30 minutes' then
            return jsonb_build_object('allowed', false, 'remaining', greatest(v_limit - v_used, 0), 'limit', v_limit);
        end if;
        update public.scan_usage set last_auto_at = now() where user_id = v_user and day = v_day;
        update public.device_scans set last_auto_at = now() where device = v_device and day = v_day;
        return jsonb_build_object('allowed', true, 'remaining', greatest(v_limit - v_used, 0), 'limit', v_limit);
    end if;

    if v_used >= v_limit then
        return jsonb_build_object('allowed', false, 'remaining', 0, 'limit', v_limit);
    end if;
    update public.scan_usage set scans = scans + 1 where user_id = v_user and day = v_day;
    update public.device_scans set scans = scans + 1 where device = v_device and day = v_day;
    return jsonb_build_object('allowed', true, 'remaining', v_limit - v_used - 1, 'limit', v_limit);
end
$$;

revoke execute on function public.claim_scan(text, bool) from public, anon;
grant execute on function public.claim_scan(text, bool) to authenticated;

create or replace function public.prune_history()
returns void
language sql volatile security definer set search_path = ''
as $$
    delete from public.device_events ev
    using public.networks n
    where n.id = ev.network_id
      and (public.plan_for(n.owner_id)).history_days is not null
      and ev.created_at < now() - make_interval(days => (public.plan_for(n.owner_id)).history_days);
    delete from public.scan_usage where day < (now() at time zone 'utc')::date - 7;
    delete from public.device_scans where day < (now() at time zone 'utc')::date - 7;
    delete from public.pairing_codes where expires_at < now();
    delete from public.email_sends where sent_at < now() - interval '7 days';
    delete from public.store_notifications where received_at < now() - interval '30 days';
$$;

notify pgrst, 'reload schema';
