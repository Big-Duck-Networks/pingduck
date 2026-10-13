-- Security review fixes (2026-10-13).
--
-- 1. claim_pairing_code checks the plan's monitored-network limit again.
--    create_pairing_code counts only paired agents, so a user could hold
--    codes for more networks than the plan allows and redeem them all. A
--    refused claim rolls back, so the code stays usable until it expires
--    (for instance after an upgrade).
-- 2. agent_sync caps devices per network at 4096 and clamps the caller's
--    offline threshold to between 1 minute and 1 day, so a buggy or stolen
--    agent token cannot grow the table without bound or flip every device
--    offline. Devices past the cap are reported back as 'capped'.
--
-- Both functions are redefined whole; their grants carry over.

create or replace function public.claim_pairing_code(p_code text, p_name text, p_version text default null)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_pc     public.pairing_codes;
    v_token  text := encode(extensions.gen_random_bytes(32), 'hex');
    v_agent  uuid;
    v_max    int;
    v_others int;
begin
    delete from public.pairing_codes
    where code = upper(btrim(p_code)) and expires_at > now()
    returning * into v_pc;
    if v_pc.code is null then
        raise exception 'invalid or expired pairing code' using errcode = '28000';
    end if;

    -- Same rule as create_pairing_code: re-pairing this network doesn't count.
    v_max := (public.plan_for(v_pc.owner_id)).max_monitored_networks;
    select count(*) into v_others from public.agents
    where owner_id = v_pc.owner_id and revoked_at is null and network_id <> v_pc.network_id;
    if v_others >= v_max then
        raise exception 'plan_limit: % monitored network(s) allowed', v_max using errcode = 'P0001';
    end if;

    update public.agents set revoked_at = now()
    where network_id = v_pc.network_id and revoked_at is null;
    insert into public.agents (owner_id, network_id, name, version, token_hash, last_seen_at)
    values (v_pc.owner_id, v_pc.network_id, left(coalesce(nullif(btrim(p_name), ''), 'agent'), 64),
            left(p_version, 32), extensions.digest(v_token, 'sha256'), now())
    returning id into v_agent;

    return jsonb_build_object('agent_id', v_agent, 'network_id', v_pc.network_id, 'token', v_token);
end
$$;

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
