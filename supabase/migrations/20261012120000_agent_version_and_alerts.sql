-- The agent reports its version on every heartbeat, and agent_sync queues a
-- new-device alert (plan: .claude/plans/phase-4-sync-and-alerts.md).
--
-- Alerts: when a sync finds new MACs on a network that already had devices,
-- private.queue_new_device_alert posts once, through pg_net, to the
-- notify-new-devices Edge Function, which sends a data-only FCM message
-- (just the network id) to the owner's phones. The phone then reads the
-- details itself. The first sync after pairing never alerts: every device is
-- new then.
--
-- Needs two Vault secrets, added once by hand (not in git):
--   select vault.create_secret('https://<project>.supabase.co/functions/v1/notify-new-devices', 'notify_url');
--   select vault.create_secret('<random>', 'notify_secret');  -- same as the function's NOTIFY_SECRET
-- Without them, or without pg_net (the plain Postgres in run_tests.sh), the
-- request is skipped with a warning.

-- ---------------------------------------------------------------------------
-- Heartbeat records the version
-- ---------------------------------------------------------------------------

-- Dropped rather than replaced: an overload next to the old (text) version
-- would make PostgREST calls with only p_token ambiguous. Agents that don't
-- send p_version keep working through the default.
drop function public.agent_heartbeat(text);

create function public.agent_heartbeat(p_token text, p_version text default null)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_agent public.agents;
begin
    update public.agents set
        last_seen_at = now(),
        version      = coalesce(left(nullif(p_version, ''), 32), version)
    where token_hash = extensions.digest(coalesce(p_token, ''), 'sha256') and revoked_at is null
    returning * into v_agent;
    if v_agent.id is null then
        return jsonb_build_object('status', 'revoked');
    end if;
    return jsonb_build_object('status', 'active', 'agent_id', v_agent.id, 'network_id', v_agent.network_id);
end
$$;

revoke execute on function public.agent_heartbeat(text, text) from public;
grant execute on function public.agent_heartbeat(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- New-device alerts
-- ---------------------------------------------------------------------------

-- Returns how many of p_devices are worth an alert, and asks the Edge
-- Function to push when that's more than zero and the owner has a phone
-- registered. Nothing is alerted when the plan has no notifications, for
-- devices marked known, or for a private (locally administered) MAC whose
-- hostname matches a known device: phones rotate those MACs.
create function private.queue_new_device_alert(p_network uuid, p_owner uuid, p_devices uuid[])
returns int
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
    v_count  int;
    v_url    text;
    v_secret text;
begin
    if not (public.plan_for(p_owner)).notifications then
        return 0;
    end if;

    select count(*) into v_count
    from public.devices d
    where d.id = any(p_devices)
      and not d.is_known
      and not (
          substr(d.mac::text, 2, 1) in ('2', '3', '6', '7', 'a', 'b', 'e', 'f')
          and d.hostname is not null
          and exists (select 1 from public.devices k
                      where k.network_id = d.network_id and k.id <> d.id and k.is_known
                        and lower(k.hostname) = lower(d.hostname)));
    if v_count = 0 or not exists (select 1 from public.push_tokens where user_id = p_owner) then
        return 0;
    end if;

    if to_regproc('net.http_post') is null or to_regclass('vault.decrypted_secrets') is null then
        raise warning 'new-device alert skipped: pg_net or vault not available';
        return v_count;
    end if;
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'notify_url'$q$ into v_url;
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'notify_secret'$q$ into v_secret;
    if v_url is null or v_secret is null then
        raise warning 'new-device alert skipped: no notify_url or notify_secret in vault';
        return v_count;
    end if;
    execute $q$select net.http_post(
        url     := $1,
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-pingduck-hook', $2),
        body    := jsonb_build_object('user_id', $3, 'network_id', $4, 'count', $5))$q$
        using v_url, v_secret, p_owner, p_network, v_count;
    return v_count;
end
$fn$;

revoke execute on function private.queue_new_device_alert(uuid, uuid, uuid[]) from public;

-- agent_sync as in the initial schema, plus: remember the new devices and
-- queue one alert at the end. The result gains 'alerted'.
create or replace function public.agent_sync(
    p_token         text,
    p_devices       jsonb,
    p_offline_after interval default interval '10 minutes')
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_agent  public.agents;
    v_dev    jsonb;
    v_mac    macaddr;
    v_ip     inet;
    v_row    public.devices;
    v_new    bool;
    v_count       int := 0;
    v_new_devices int := 0;
    v_offline     int;
    v_existing    int;
    v_new_ids     uuid[] := '{}';
    v_alerted     int := 0;
begin
    select * into v_agent from public.agents
    where token_hash = extensions.digest(p_token, 'sha256') and revoked_at is null;
    if v_agent.id is null then
        raise exception 'invalid agent token' using errcode = '28000';
    end if;
    if (public.plan_for(v_agent.owner_id)).max_monitored_networks = 0 then
        raise exception 'subscription_required' using errcode = 'P0001';
    end if;
    if jsonb_typeof(p_devices) <> 'array' or jsonb_array_length(p_devices) > 4096 then
        raise exception 'devices must be an array of at most 4096 entries' using errcode = '22023';
    end if;

    update public.agents set last_seen_at = now() where id = v_agent.id;
    select count(*) into v_existing from public.devices where network_id = v_agent.network_id;

    for v_dev in select * from jsonb_array_elements(p_devices) loop
        begin
            v_mac := (v_dev->>'mac')::macaddr;
            v_ip  := nullif(v_dev->>'ip', '')::inet;
        exception when others then
            continue;  -- skip malformed entries rather than fail the batch
        end;
        if v_mac is null then continue; end if;

        select * into v_row from public.devices where network_id = v_agent.network_id and mac = v_mac;
        v_new := v_row.id is null;

        insert into public.devices as d (network_id, mac, ip, hostname, vendor, model, services)
        values (v_agent.network_id, v_mac, v_ip,
                left(nullif(v_dev->>'hostname', ''), 255), left(nullif(v_dev->>'vendor', ''), 255),
                left(nullif(v_dev->>'model', ''), 255), left(nullif(v_dev->>'services', ''), 1024))
        on conflict (network_id, mac) do update set
            ip           = coalesce(excluded.ip, d.ip),
            hostname     = coalesce(excluded.hostname, d.hostname),
            vendor       = coalesce(excluded.vendor, d.vendor),
            model        = coalesce(excluded.model, d.model),
            services     = coalesce(excluded.services, d.services),
            online       = true,
            last_seen_at = now()
        returning * into v_row;
        v_count := v_count + 1;

        if v_new then
            insert into public.device_events (network_id, device_id, kind, details)
            values (v_agent.network_id, v_row.id, 'new_device', jsonb_build_object('ip', v_ip::text));
            v_new_devices := v_new_devices + 1;
            v_new_ids := v_new_ids || v_row.id;
        end if;
    end loop;

    -- The trigger skips 'offline' so it can be recorded here in one statement.
    with went_offline as (
        update public.devices d set online = false
        where d.network_id = v_agent.network_id and d.online
          and d.last_seen_at < now() - p_offline_after
        returning d.id
    )
    insert into public.device_events (network_id, device_id, kind)
    select v_agent.network_id, id, 'offline' from went_offline;
    get diagnostics v_offline = row_count;

    -- No alert for the baseline sync (an empty network), and an alert
    -- failure never fails the sync.
    if v_existing > 0 and cardinality(v_new_ids) > 0 then
        begin
            v_alerted := private.queue_new_device_alert(v_agent.network_id, v_agent.owner_id, v_new_ids);
        exception when others then
            raise warning 'new-device alert failed: %', sqlerrm;
        end;
    end if;

    return jsonb_build_object('devices', v_count, 'new_devices', v_new_devices, 'went_offline', v_offline,
                              'alerted', v_alerted);
end
$$;
