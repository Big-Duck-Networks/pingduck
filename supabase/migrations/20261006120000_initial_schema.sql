-- PingDuck initial schema: plans and entitlements, the daily scan quota,
-- networks, agents and pairing, devices, device events and push tokens.
--
-- Tiers mirror Fing (docs/ROADMAP.md, Decisions): Free gets 3 scans a day and
-- no monitoring; Premium and Pro unlock unlimited scans and 24/7 agents.
-- Limits live in `plans`, so changing them is an UPDATE, not a migration.
--
-- Agents never hold a Supabase key with privileges. They pair with a short
-- code and then call the security-definer RPCs below with a random token, of
-- which only the SHA-256 hash is stored.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Plans and entitlements
-- ---------------------------------------------------------------------------

create table public.plans (
    code                   text primary key,
    name                   text not null,
    sort_order             int  not null,
    daily_scan_limit       int,           -- null = unlimited
    max_monitored_networks int  not null, -- networks with an active agent
    history_days           int,           -- device_events kept; null = forever
    notifications          bool not null,
    security_checks        bool not null,
    scheduled_speed_tests  bool not null
);

insert into public.plans values
    ('free',    'Free',    0, 3,    0, 0,    false, false, false),
    ('premium', 'Premium', 1, null, 2, null, true,  true,  true),
    ('pro',     'Pro',     2, null, 3, null, true,  true,  true);

-- One row per user, written only by the billing webhook (service role).
-- No row, or a lapsed one, means Free.
create table public.entitlements (
    user_id        uuid primary key references auth.users on delete cascade,
    plan_code      text not null references public.plans,
    status         text not null check (status in ('active', 'trialing', 'grace', 'expired', 'revoked')),
    period_ends_at timestamptz,
    source         text not null check (source in ('revenuecat', 'manual')),
    updated_at     timestamptz not null default now()
);

create function public.plan_for(p_user uuid)
returns public.plans
language sql stable security definer set search_path = ''
as $$
    select p.* from public.plans p
    where p.code = coalesce(
        (select e.plan_code from public.entitlements e
         where e.user_id = p_user
           and e.status in ('active', 'trialing', 'grace')
           and (e.period_ends_at is null or e.period_ends_at > now())),
        'free')
$$;

create function public.my_plan()
returns public.plans
language sql stable security definer set search_path = ''
as $$ select * from public.plan_for(auth.uid()) $$;

-- ---------------------------------------------------------------------------
-- Daily scan quota (Free: 3 a day, counted per UTC day)
-- ---------------------------------------------------------------------------
-- Scans run on the phone, so this cannot stop a modified client. The app
-- claims a scan before starting one and keeps a local count for offline use.
-- Free users sign in anonymously so the count follows the install.

create table public.scan_usage (
    user_id uuid not null references auth.users on delete cascade,
    day     date not null,
    scans   int  not null default 0,
    primary key (user_id, day)
);

create function public.claim_scan()
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_user  uuid := auth.uid();
    v_limit int;
    v_used  int;
begin
    if v_user is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;
    v_limit := (public.plan_for(v_user)).daily_scan_limit;

    insert into public.scan_usage as u (user_id, day, scans)
    values (v_user, (now() at time zone 'utc')::date, 1)
    on conflict (user_id, day) do update
        set scans = u.scans + 1
        where v_limit is null or u.scans < v_limit
    returning u.scans into v_used;

    if v_used is null then  -- the WHERE above refused the increment
        return jsonb_build_object('allowed', false, 'remaining', 0, 'limit', v_limit);
    end if;
    return jsonb_build_object(
        'allowed', true,
        'remaining', case when v_limit is null then null else v_limit - v_used end,
        'limit', v_limit);
end
$$;

-- ---------------------------------------------------------------------------
-- Networks, agents and pairing
-- ---------------------------------------------------------------------------

create table public.networks (
    id          uuid primary key default gen_random_uuid(),
    owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
    name        text,
    cidr        cidr not null,
    gateway_ip  inet,
    gateway_mac macaddr,
    ssid        text,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);
create index networks_owner_idx on public.networks (owner_id);

create table public.agents (
    id           uuid primary key default gen_random_uuid(),
    owner_id     uuid not null references auth.users on delete cascade,
    network_id   uuid not null references public.networks on delete cascade,
    name         text not null,
    version      text,
    token_hash   bytea not null unique,
    last_seen_at timestamptz,
    created_at   timestamptz not null default now(),
    revoked_at   timestamptz
);
create index agents_owner_idx on public.agents (owner_id);
-- One live agent per network; pairing a new one revokes the old.
create unique index agents_one_active_per_network on public.agents (network_id) where revoked_at is null;

-- Short-lived codes the app shows and the agent redeems. RPC access only.
create table public.pairing_codes (
    code       text primary key,
    owner_id   uuid not null references auth.users on delete cascade,
    network_id uuid not null references public.networks on delete cascade,
    expires_at timestamptz not null,
    created_at timestamptz not null default now()
);

create function public.create_pairing_code(p_network_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_user     uuid := auth.uid();
    v_max      int;
    v_others   int;
    v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';  -- no 0/O, 1/I/L
    v_bytes    bytea;
    v_code     text := '';
begin
    if not exists (select 1 from public.networks where id = p_network_id and owner_id = v_user) then
        raise exception 'network not found' using errcode = 'P0002';
    end if;

    -- Re-pairing a network that already has an agent does not count twice.
    v_max := (public.plan_for(v_user)).max_monitored_networks;
    select count(*) into v_others from public.agents
    where owner_id = v_user and revoked_at is null and network_id <> p_network_id;
    if v_others >= v_max then
        raise exception 'plan_limit: % monitored network(s) allowed', v_max using errcode = 'P0001';
    end if;

    v_bytes := extensions.gen_random_bytes(8);
    for i in 0..7 loop
        v_code := v_code || substr(v_alphabet, 1 + get_byte(v_bytes, i) % length(v_alphabet), 1);
    end loop;

    delete from public.pairing_codes where network_id = p_network_id or expires_at < now();
    insert into public.pairing_codes (code, owner_id, network_id, expires_at)
    values (v_code, v_user, p_network_id, now() + interval '10 minutes');
    return jsonb_build_object('code', v_code, 'expires_at', now() + interval '10 minutes');
end
$$;

-- Called by the agent with the anon key. Returns the agent's token once.
create function public.claim_pairing_code(p_code text, p_name text, p_version text default null)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_pc    public.pairing_codes;
    v_token text := encode(extensions.gen_random_bytes(32), 'hex');
    v_agent uuid;
begin
    delete from public.pairing_codes
    where code = upper(btrim(p_code)) and expires_at > now()
    returning * into v_pc;
    if v_pc.code is null then
        raise exception 'invalid or expired pairing code' using errcode = '28000';
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

create function public.revoke_agent(p_agent_id uuid)
returns void
language sql volatile security definer set search_path = ''
as $$
    update public.agents set revoked_at = now()
    where id = p_agent_id and owner_id = auth.uid() and revoked_at is null
$$;

-- ---------------------------------------------------------------------------
-- Devices and events
-- ---------------------------------------------------------------------------

create table public.devices (
    id            uuid primary key default gen_random_uuid(),
    network_id    uuid not null references public.networks on delete cascade,
    mac           macaddr not null,
    ip            inet,
    hostname      text,
    vendor        text,
    model         text,
    services      text,
    custom_name   text,
    notes         text,
    is_known      bool not null default false,
    online        bool not null default true,
    first_seen_at timestamptz not null default now(),
    last_seen_at  timestamptz not null default now(),
    unique (network_id, mac)
);

create table public.device_events (
    id          bigint generated always as identity primary key,
    network_id  uuid not null references public.networks on delete cascade,
    device_id   uuid not null references public.devices on delete cascade,
    kind        text not null check (kind in ('new_device', 'online', 'offline', 'ip_changed')),
    details     jsonb not null default '{}',
    created_at  timestamptz not null default now()
);
create index device_events_network_time_idx on public.device_events (network_id, created_at desc);
create index device_events_device_idx on public.device_events (device_id);

-- The agent's report after each scan. Upserts every device it saw (by MAC),
-- records events, and marks devices offline once unseen for p_offline_after.
-- A missed reply in one scan is common (Wi-Fi power save), so a single
-- absence must not flap a device offline.
create function public.agent_sync(
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

    return jsonb_build_object('devices', v_count, 'new_devices', v_new_devices, 'went_offline', v_offline);
end
$$;

-- Online and IP-change events are recorded by trigger, so they also cover
-- any future writer, not only agent_sync.
create function public.devices_state_events()
returns trigger
language plpgsql set search_path = ''
as $$
begin
    if new.online and not old.online then
        insert into public.device_events (network_id, device_id, kind)
        values (new.network_id, new.id, 'online');
    end if;
    if new.ip is distinct from old.ip and old.ip is not null and new.ip is not null then
        insert into public.device_events (network_id, device_id, kind, details)
        values (new.network_id, new.id, 'ip_changed',
                jsonb_build_object('from', old.ip::text, 'to', new.ip::text));
    end if;
    return new;
end
$$;

create trigger devices_state_events
after update of online, ip on public.devices
for each row execute function public.devices_state_events();

-- ---------------------------------------------------------------------------
-- Push tokens
-- ---------------------------------------------------------------------------

create table public.push_tokens (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null default auth.uid() references auth.users on delete cascade,
    token        text not null unique,
    platform     text not null check (platform in ('ios', 'android')),
    created_at   timestamptz not null default now(),
    last_used_at timestamptz
);
create index push_tokens_user_idx on public.push_tokens (user_id);

-- ---------------------------------------------------------------------------
-- Retention (schedule with pg_cron once the project exists)
-- ---------------------------------------------------------------------------

create function public.prune_history()
returns void
language sql volatile security definer set search_path = ''
as $$
    delete from public.device_events ev
    using public.networks n
    where n.id = ev.network_id
      and (public.plan_for(n.owner_id)).history_days is not null
      and ev.created_at < now() - make_interval(days => (public.plan_for(n.owner_id)).history_days);
    delete from public.scan_usage where day < (now() at time zone 'utc')::date - 7;
    delete from public.pairing_codes where expires_at < now();
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.plans          enable row level security;
alter table public.entitlements   enable row level security;
alter table public.scan_usage     enable row level security;
alter table public.networks       enable row level security;
alter table public.agents         enable row level security;
alter table public.pairing_codes  enable row level security;
alter table public.devices        enable row level security;
alter table public.device_events  enable row level security;
alter table public.push_tokens    enable row level security;

create policy plans_read on public.plans for select to anon, authenticated using (true);

create policy entitlements_own on public.entitlements for select to authenticated
    using (user_id = (select auth.uid()));

create policy scan_usage_own on public.scan_usage for select to authenticated
    using (user_id = (select auth.uid()));

create policy networks_own on public.networks for all to authenticated
    using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

create policy agents_own on public.agents for select to authenticated
    using (owner_id = (select auth.uid()));

-- pairing_codes: RLS on, no policies. Only the RPCs touch it.

create policy devices_own_read on public.devices for select to authenticated
    using (exists (select 1 from public.networks n where n.id = network_id and n.owner_id = (select auth.uid())));
create policy devices_own_update on public.devices for update to authenticated
    using (exists (select 1 from public.networks n where n.id = network_id and n.owner_id = (select auth.uid())));
create policy devices_own_delete on public.devices for delete to authenticated
    using (exists (select 1 from public.networks n where n.id = network_id and n.owner_id = (select auth.uid())));

create policy device_events_own on public.device_events for select to authenticated
    using (exists (select 1 from public.networks n where n.id = network_id and n.owner_id = (select auth.uid())));

create policy push_tokens_own on public.push_tokens for all to authenticated
    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Users edit only their own labels on devices; the agent owns the rest.
revoke insert, update on public.devices from anon, authenticated;
grant update (custom_name, notes, is_known) on public.devices to authenticated;

-- Writes to these go through RPCs or the billing webhook only.
revoke insert, update, delete on public.plans, public.entitlements, public.scan_usage,
    public.agents, public.pairing_codes, public.device_events from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Function access
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.my_plan()                       to authenticated;
grant execute on function public.claim_scan()                    to authenticated;
grant execute on function public.create_pairing_code(uuid)       to authenticated;
grant execute on function public.revoke_agent(uuid)              to authenticated;
grant execute on function public.claim_pairing_code(text, text, text)   to anon, authenticated;
grant execute on function public.agent_sync(text, jsonb, interval)      to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        alter publication supabase_realtime add table public.devices, public.device_events;
    end if;
end
$$;
