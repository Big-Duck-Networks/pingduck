-- Device recognition signals (.claude/plans/device-recognition-slice.md).
-- The agent reports two raw signals the app turns into an OS guess: the TTL
-- of the device's ping reply and its SSDP SERVER header. Only signals are
-- stored; brand, family and OS are worked out in the app, so a rules update
-- relabels every device without touching this table.

alter table public.devices
    add column ttl    smallint check (ttl between 1 and 255),
    add column server text check (char_length(server) <= 255);

create or replace function public.agent_sync(
    p_token         text,
    p_devices       jsonb,
    p_offline_after interval default interval '10 minutes')
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_cap    constant int := 4096;
    v_agent  public.agents;
    v_dev    jsonb;
    v_mac    macaddr;
    v_ip     inet;
    v_ttl    smallint;
    v_row    public.devices;
    v_new    bool;
    v_count       int := 0;
    v_new_devices int := 0;
    v_capped      int := 0;
    v_offline     int;
    v_existing    int;
    v_total       int;
    v_new_ids     uuid[] := '{}';
    v_alerted     int := 0;
    v_after       interval := greatest(interval '1 minute', least(coalesce(p_offline_after, interval '10 minutes'), interval '1 day'));
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
    v_total := v_existing;

    for v_dev in select * from jsonb_array_elements(p_devices) loop
        begin
            v_mac := (v_dev->>'mac')::macaddr;
            v_ip  := nullif(v_dev->>'ip', '')::inet;
            -- A bad or out-of-range TTL is dropped, not the device.
            v_ttl := case when (v_dev->>'ttl') ~ '^[0-9]{1,3}$' and (v_dev->>'ttl')::int between 1 and 255
                          then (v_dev->>'ttl')::smallint end;
        exception when others then
            continue;  -- skip malformed entries rather than fail the batch
        end;
        if v_mac is null then continue; end if;

        select * into v_row from public.devices where network_id = v_agent.network_id and mac = v_mac;
        v_new := v_row.id is null;
        if v_new and v_total >= v_cap then
            v_capped := v_capped + 1;
            continue;  -- known devices still update; new ones wait for room
        end if;

        insert into public.devices as d (network_id, mac, ip, hostname, vendor, model, services, ttl, server)
        values (v_agent.network_id, v_mac, v_ip,
                left(nullif(v_dev->>'hostname', ''), 255), left(nullif(v_dev->>'vendor', ''), 255),
                left(nullif(v_dev->>'model', ''), 255), left(nullif(v_dev->>'services', ''), 1024),
                v_ttl, left(nullif(v_dev->>'server', ''), 255))
        on conflict (network_id, mac) do update set
            ip           = coalesce(excluded.ip, d.ip),
            hostname     = coalesce(excluded.hostname, d.hostname),
            vendor       = coalesce(excluded.vendor, d.vendor),
            model        = coalesce(excluded.model, d.model),
            services     = coalesce(excluded.services, d.services),
            ttl          = coalesce(excluded.ttl, d.ttl),
            server       = coalesce(excluded.server, d.server),
            online       = true,
            last_seen_at = now()
        returning * into v_row;
        v_count := v_count + 1;

        if v_new then
            insert into public.device_events (network_id, device_id, kind, details)
            values (v_agent.network_id, v_row.id, 'new_device', jsonb_build_object('ip', v_ip::text));
            v_new_devices := v_new_devices + 1;
            v_total := v_total + 1;
            v_new_ids := v_new_ids || v_row.id;
        end if;
    end loop;

    -- The trigger skips 'offline' so it can be recorded here in one statement.
    with went_offline as (
        update public.devices d set online = false
        where d.network_id = v_agent.network_id and d.online
          and d.last_seen_at < now() - v_after
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
                              'alerted', v_alerted, 'capped', v_capped);
end
$$;

notify pgrst, 'reload schema';
