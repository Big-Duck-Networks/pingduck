-- Behaviour tests for the initial schema. Plain SQL, so it runs in the
-- Supabase SQL editor as well as through run_tests.sh (Docker). Everything
-- happens in one transaction that is rolled back, so the test users,
-- networks and devices never persist. Every check raises on failure; if the
-- script finishes, the last result reads 'ALL SCHEMA TESTS PASSED'.
begin;

insert into auth.users (id) values
    ('11111111-1111-1111-1111-111111111111'),
    ('22222222-2222-2222-2222-222222222222');

create function pg_temp.expect_error(p_sql text, p_fragment text) returns void language plpgsql as $$
begin
    execute p_sql;
    raise exception 'expected error containing "%" from: %', p_fragment, p_sql;
exception when others then
    if position(p_fragment in sqlerrm) = 0 then
        raise exception 'wrong error for %: got "%", wanted "%"', p_sql, sqlerrm, p_fragment;
    end if;
end $$;
grant execute on function pg_temp.expect_error(text, text) to anon, authenticated;

create function pg_temp.check(p_ok bool, p_what text) returns void language plpgsql as $$
begin
    if p_ok is not true then raise exception 'FAILED: %', p_what; end if;
    raise notice 'ok: %', p_what;
end $$;
grant execute on function pg_temp.check(bool, text) to anon, authenticated;

-- Values carried between steps (pairing codes, the agent token).
create temp table vars (k text primary key, v text);
grant select, insert on vars to anon, authenticated;
create function pg_temp.v(p_k text) returns text language sql as $$ select v from vars where k = p_k $$;
grant execute on function pg_temp.v(text) to anon, authenticated;

-- ---- Free user: 3 scans a day, no monitoring ------------------------------
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select pg_temp.check((my_plan()).code = 'free', 'no entitlement means free');
select pg_temp.check((claim_scan()->>'remaining')::int = 2, 'free scan 1 leaves 2');
select pg_temp.check((claim_scan()->>'remaining')::int = 1, 'free scan 2 leaves 1');
select pg_temp.check((claim_scan()->>'remaining')::int = 0, 'free scan 3 leaves 0');
select pg_temp.check((claim_scan()->>'allowed')::bool = false, 'free scan 4 is refused');
select pg_temp.check((select scans from scan_usage) = 3, 'refused scan is not counted');

insert into networks (id, cidr, gateway_ip) values
    ('aaaaaaaa-0000-0000-0000-000000000001', '10.42.0.0/24', '10.42.0.1');
select pg_temp.expect_error($$select create_pairing_code('aaaaaaaa-0000-0000-0000-000000000001')$$, 'plan_limit');
select pg_temp.expect_error($$insert into entitlements values (auth.uid(), 'premium', 'active', null, 'manual')$$, 'permission denied');
reset role;

-- ---- Upgrade to Premium (what the billing webhook will do) ----------------
insert into entitlements values ('11111111-1111-1111-1111-111111111111', 'premium', 'active', now() + interval '30 days', 'revenuecat');

set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.check((my_plan()).code = 'premium', 'active entitlement means premium');
select pg_temp.check(claim_scan()->>'remaining' is null and (claim_scan()->>'allowed')::bool, 'premium scans are unlimited');

insert into vars select 'code', create_pairing_code('aaaaaaaa-0000-0000-0000-000000000001')->>'code';
select pg_temp.check(length(pg_temp.v('code')) = 8, 'pairing code has 8 characters');
reset role;

-- ---- Agent pairs with the anon key ----------------------------------------
set role anon;
reset request.jwt.claim.sub;
insert into vars select 'token', claim_pairing_code(lower(pg_temp.v('code')), 'homelab', '0.1.0')->>'token';
select pg_temp.check(length(pg_temp.v('token')) = 64, 'agent gets a 64-hex token (code is case-insensitive)');
select pg_temp.expect_error(format($$select claim_pairing_code(%L, 'again')$$, pg_temp.v('code')), 'invalid or expired');
select pg_temp.check((select count(*) from agents) = 0, 'anon cannot read agents');
select pg_temp.check((select count(*) from devices) = 0, 'anon cannot read devices');

-- ---- Agent reports ---------------------------------------------------------
select pg_temp.check(agent_sync(pg_temp.v('token'), $$[
    {"mac":"b8:fb:b3:00:00:01","ip":"10.42.0.1","vendor":"TP-Link"},
    {"mac":"34:13:43:00:00:02","ip":"10.42.0.106","hostname":"phone"},
    {"mac":"not-a-mac","ip":"10.42.0.9"},
    {"ip":"10.42.0.8"}
]$$) = '{"devices": 2, "new_devices": 2, "went_offline": 0, "alerted": 0, "capped": 0}', 'first sync adds 2 devices and skips malformed ones');

select pg_temp.check(agent_sync(pg_temp.v('token'), $$[
    {"mac":"b8:fb:b3:00:00:01","ip":"10.42.0.1"},
    {"mac":"34:13:43:00:00:02","ip":"10.42.0.107"}
]$$)->>'new_devices' = '0', 'second sync adds nothing new');
select pg_temp.expect_error($$select agent_sync('deadbeef', '[]')$$, 'invalid agent token');

-- ---- Agent heartbeat -------------------------------------------------------
select pg_temp.check(agent_heartbeat(pg_temp.v('token'))->>'status' = 'active', 'heartbeat with a live token is active');
select pg_temp.check(agent_heartbeat(pg_temp.v('token'))->>'network_id' = 'aaaaaaaa-0000-0000-0000-000000000001',
                     'heartbeat names the paired network');
select pg_temp.check(agent_heartbeat('deadbeef')->>'status' = 'revoked', 'heartbeat with an unknown token says revoked');
select pg_temp.check(agent_heartbeat(null)->>'status' = 'revoked', 'heartbeat with no token says revoked');
select agent_heartbeat(pg_temp.v('token'), '0.3.1');
reset role;
select pg_temp.check((select version from agents where revoked_at is null) = '0.3.1', 'heartbeat records the agent version');
set role anon;
select agent_heartbeat(pg_temp.v('token'));
select agent_heartbeat(pg_temp.v('token'), '');
reset role;
select pg_temp.check((select version from agents where revoked_at is null) = '0.3.1', 'heartbeat without a version keeps it');
set role anon;
reset role;
update agents set last_seen_at = now() - interval '1 hour';
set role anon;
select agent_heartbeat(pg_temp.v('token'));
reset role;
select pg_temp.check((select last_seen_at from agents where revoked_at is null) > now() - interval '1 minute',
                     'heartbeat refreshes last_seen_at');

-- The phone is unseen for 20 minutes, then misses a sync, then comes back.
update devices set last_seen_at = now() - interval '20 minutes' where mac = '34:13:43:00:00:02';
set role anon;
select pg_temp.check((agent_sync(pg_temp.v('token'), '[{"mac":"b8:fb:b3:00:00:01","ip":"10.42.0.1"}]')->>'went_offline')::int = 1,
                     'device unseen past the threshold goes offline');
select pg_temp.check((agent_sync(pg_temp.v('token'), '[{"mac":"b8:fb:b3:00:00:01","ip":"10.42.0.1"}]')->>'went_offline')::int = 0,
                     'an offline device is not reported offline twice');
select agent_sync(pg_temp.v('token'), '[{"mac":"34:13:43:00:00:02","ip":"10.42.0.107"}]');
reset role;

select pg_temp.check(
    (select string_agg(kind, ',' order by id) from device_events)
        = 'new_device,new_device,ip_changed,offline,online',
    'events: 2 new, ip change, offline, back online');
select pg_temp.check((select details->>'to' from device_events where kind = 'ip_changed') = '10.42.0.107/32'
                     or (select details->>'to' from device_events where kind = 'ip_changed') = '10.42.0.107',
                     'ip_changed records the new address');

-- ---- What the owner and other users can see and do ------------------------
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.check((select count(*) from devices) = 2, 'owner sees their devices');
select pg_temp.check((select count(*) from device_events) = 5, 'owner sees their events');
update devices set custom_name = 'Router', is_known = true where mac = 'b8:fb:b3:00:00:01';
select pg_temp.check((select custom_name from devices where mac = 'b8:fb:b3:00:00:01') = 'Router', 'owner can label a device');
select pg_temp.expect_error($$update devices set vendor = 'x'$$, 'permission denied');
select pg_temp.expect_error($$insert into devices (network_id, mac) values ('aaaaaaaa-0000-0000-0000-000000000001', '00:00:00:00:00:01')$$, 'permission denied');
select pg_temp.expect_error($$insert into device_events (network_id, device_id, kind) select network_id, id, 'online' from devices limit 1$$, 'permission denied');

set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select pg_temp.check((select count(*) from networks) = 0, 'other user sees no networks');
select pg_temp.check((select count(*) from devices) = 0, 'other user sees no devices');
select pg_temp.check((select count(*) from device_events) = 0, 'other user sees no events');
update devices set custom_name = 'pwned';
select pg_temp.expect_error($$select create_pairing_code('aaaaaaaa-0000-0000-0000-000000000001')$$, 'network not found');
select pg_temp.expect_error($$insert into networks (cidr, owner_id) values ('10.0.0.0/24', '11111111-1111-1111-1111-111111111111')$$, 'row-level security');
reset role;
select pg_temp.check((select custom_name from devices where mac = 'b8:fb:b3:00:00:01') = 'Router', 'other user could not relabel');

-- ---- New-device alerts ------------------------------------------------------
-- User 1 is Premium (notifications on). The router is known; the phone isn't.
reset role;
create function pg_temp.alert(p_macs text[]) returns int language sql as $$
    select private.queue_new_device_alert('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        array(select id from public.devices where mac::text = any(p_macs)))
$$;
select pg_temp.check(pg_temp.alert(array['34:13:43:00:00:02']) = 0, 'no alert without a registered phone');
insert into push_tokens (user_id, token, platform) values ('11111111-1111-1111-1111-111111111111', 'test-token-1', 'android');
select pg_temp.check(pg_temp.alert(array['34:13:43:00:00:02']) = 1, 'unknown device alerts');
select pg_temp.check(pg_temp.alert(array['b8:fb:b3:00:00:01']) = 0, 'known device does not alert');
-- A phone with a rotated private MAC and the hostname of a known device.
update devices set is_known = true, hostname = 'Pixel-8' where mac = '34:13:43:00:00:02';
insert into devices (network_id, mac, hostname) values
    ('aaaaaaaa-0000-0000-0000-000000000001', '3a:00:00:00:00:03', 'pixel-8'),
    ('aaaaaaaa-0000-0000-0000-000000000001', '3a:00:00:00:00:04', 'stranger'),
    ('aaaaaaaa-0000-0000-0000-000000000001', '34:13:43:00:00:05', 'pixel-8');
select pg_temp.check(pg_temp.alert(array['3a:00:00:00:00:03']) = 0, 'private MAC with a known hostname does not alert');
select pg_temp.check(pg_temp.alert(array['3a:00:00:00:00:04']) = 1, 'private MAC with an unknown hostname alerts');
select pg_temp.check(pg_temp.alert(array['34:13:43:00:00:05']) = 1, 'a real MAC alerts even with a known hostname');
select pg_temp.check(pg_temp.alert(array['3a:00:00:00:00:03', '3a:00:00:00:00:04', '34:13:43:00:00:05']) = 2, 'alert counts only the unsuppressed devices');
update entitlements set status = 'expired';
select pg_temp.check(pg_temp.alert(array['3a:00:00:00:00:04']) = 0, 'no alerts without notifications in the plan');
update entitlements set status = 'active';
set role anon;
select pg_temp.check((agent_sync(pg_temp.v('token'), '[{"mac":"b8:fb:b3:00:00:01","ip":"10.42.0.1"},{"mac":"00:11:22:00:00:06","ip":"10.42.0.60"}]')->>'alerted')::int = 1,
                     'a sync with a new device on a known network alerts');
reset role;
delete from devices where mac in ('3a:00:00:00:00:03', '3a:00:00:00:00:04', '34:13:43:00:00:05', '00:11:22:00:00:06');
update devices set is_known = false, hostname = 'phone' where mac = '34:13:43:00:00:02';

-- ---- Limits on what an agent can write ---------------------------------------
-- The caller's offline threshold is clamped: a negative one would flip every
-- device offline.
set role anon;
select pg_temp.check((agent_sync(pg_temp.v('token'), '[]', '-1 day')->>'went_offline')::int = 0,
                     'a negative offline threshold is clamped');
reset role;
-- Fill the network to the 4096-device cap.
insert into devices (network_id, mac)
select 'aaaaaaaa-0000-0000-0000-000000000001', ('0a' || lpad(to_hex(i), 10, '0'))::macaddr
from generate_series(1, 4096 - (select count(*) from devices where network_id = 'aaaaaaaa-0000-0000-0000-000000000001')) i;
set role anon;
select pg_temp.check(agent_sync(pg_temp.v('token'), '[{"mac":"0e:00:00:00:00:99"},{"mac":"b8:fb:b3:00:00:01","ip":"10.42.0.1"}]')
                     @> '{"devices": 1, "new_devices": 0, "capped": 1}', 'a full network refuses new devices but updates known ones');
reset role;
select pg_temp.check(not exists (select 1 from devices where mac = '0e:00:00:00:00:99'), 'the capped device was not stored');
delete from devices where mac::text like '0a:%';
delete from push_tokens where token = 'test-token-1';

-- ---- Plan limits on monitored networks ------------------------------------
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into networks (id, cidr) values
    ('aaaaaaaa-0000-0000-0000-000000000002', '192.168.1.0/24'),
    ('aaaaaaaa-0000-0000-0000-000000000003', '192.168.2.0/24');
insert into vars select 'code2', create_pairing_code('aaaaaaaa-0000-0000-0000-000000000002')->>'code';
-- Unredeemed codes don't count, so a third network's code can still be made...
insert into vars select 'code3', create_pairing_code('aaaaaaaa-0000-0000-0000-000000000003')->>'code';
reset role;
set role anon;
select claim_pairing_code(pg_temp.v('code2'), 'second');
-- ...but redeeming it is checked against the plan again.
select pg_temp.expect_error(format($$select claim_pairing_code(%L, 'third')$$, pg_temp.v('code3')), 'plan_limit');
reset role;
select pg_temp.check((select count(*) from agents where revoked_at is null) = 2, 'premium keeps at most 2 monitored networks');
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.expect_error($$select create_pairing_code('aaaaaaaa-0000-0000-0000-000000000003')$$, 'plan_limit');
select pg_temp.check(create_pairing_code('aaaaaaaa-0000-0000-0000-000000000001') ? 'code', 're-pairing an already monitored network is allowed');
reset role;

-- ---- Revocation and lapsed subscriptions ----------------------------------
update entitlements set period_ends_at = now() - interval '1 day';
set role anon;
select pg_temp.expect_error(format($$select agent_sync(%L, '[]')$$, pg_temp.v('token')), 'subscription_required');
reset role;
update entitlements set period_ends_at = now() + interval '30 days';

set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select revoke_agent(id) from agents where network_id = 'aaaaaaaa-0000-0000-0000-000000000001';
reset role;
set role anon;
select pg_temp.expect_error(format($$select agent_sync(%L, '[]')$$, pg_temp.v('token')), 'invalid agent token');
select pg_temp.check(agent_heartbeat(pg_temp.v('token'))->>'status' = 'revoked', 'heartbeat after revoke says revoked');
select pg_temp.expect_error($$select prune_history()$$, 'permission denied');
select pg_temp.expect_error($$select plan_for('11111111-1111-1111-1111-111111111111')$$, 'permission denied');
reset role;

-- ---- Retention -------------------------------------------------------------
update plans set history_days = 7 where code = 'premium';
update device_events set created_at = now() - interval '8 days' where kind = 'new_device';
select prune_history();
select pg_temp.check((select count(*) from device_events) = 3, 'prune drops events older than the plan keeps');

-- ---- Agent install instructions by email -----------------------------------
set role anon;
select pg_temp.expect_error($$select email_agent_instructions('linux')$$, 'permission denied');
reset role;
-- User 1 has no email yet, like an anonymous install.
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.expect_error($$select email_agent_instructions('linux')$$, 'account_required');
reset role;
update auth.users set email = 'agent-test@example.invalid' where id = '11111111-1111-1111-1111-111111111111';
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.expect_error($$select email_agent_instructions('macos')$$, 'unknown platform');
select pg_temp.check(email_agent_instructions('linux')->>'sent_to' = 'agent-test@example.invalid', 'instructions go to the account address');
select email_agent_instructions('raspberry_pi');
select email_agent_instructions('nas');
select pg_temp.expect_error($$select email_agent_instructions('linux')$$, 'rate_limited');
select pg_temp.expect_error($$select * from email_sends$$, 'permission denied');
reset role;
select pg_temp.check((select count(*) from email_sends) = 3, 'refused sends are not logged');
update email_sends set sent_at = now() - interval '8 days';
select prune_history();
select pg_temp.check((select count(*) from email_sends) = 0, 'prune drops week-old email sends');

-- ---- Account deletion ------------------------------------------------------
set role anon;
select pg_temp.expect_error($$select delete_account()$$, 'permission denied');
reset role;

set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select claim_scan();
insert into networks (id, cidr, gateway_ip) values
    ('bbbbbbbb-0000-0000-0000-000000000002', '192.168.1.0/24', '192.168.1.1');
insert into push_tokens (token, platform) values ('test-token-2', 'android');
reset role;
-- A real account: the goodbye email is attempted, and never blocks deletion.
update auth.users set email = 'goodbye-test@example.invalid' where id = '22222222-2222-2222-2222-222222222222';
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select delete_account();
reset role;

select pg_temp.check(not exists (select 1 from auth.users where id = '22222222-2222-2222-2222-222222222222'), 'delete_account removes the user');
select pg_temp.check(not exists (select 1 from scan_usage where user_id = '22222222-2222-2222-2222-222222222222')
    and not exists (select 1 from networks where owner_id = '22222222-2222-2222-2222-222222222222')
    and not exists (select 1 from push_tokens where user_id = '22222222-2222-2222-2222-222222222222'), 'delete_account removes their data');
select pg_temp.check(exists (select 1 from auth.users where id = '11111111-1111-1111-1111-111111111111')
    and exists (select 1 from networks where owner_id = '11111111-1111-1111-1111-111111111111'), 'other accounts are untouched');

reset role;
rollback;
select 'ALL SCHEMA TESTS PASSED' as result;
