-- Google Play real-time developer notifications, received directly
-- (supabase/functions/play-rtdn). RevenueCat's webhook needs a paid plan, so
-- Play's own notifications, pushed by Pub/Sub, keep entitlements current:
-- the function asks the Play Developer API for the subscription's state and
-- writes entitlements with source 'play'.
--
-- Play doesn't say which user a purchase belongs to. RevenueCat tags each new
-- purchase with sha256(app user id), our auth.users id, as the obfuscated
-- account id; user_id_for_store_tag finds the user from that tag. Upgrades and
-- plan changes arrive with a new token linked to the old one, so every token
-- seen is remembered in store_purchases.

alter table public.entitlements drop constraint entitlements_source_check;
alter table public.entitlements add constraint entitlements_source_check
    check (source in ('revenuecat', 'play', 'manual'));

-- Purchase token -> user. Written by the function (service role) only.
create table public.store_purchases (
    purchase_token text primary key,
    user_id        uuid not null references auth.users on delete cascade,
    product_id     text not null,
    linked_token   text,
    updated_at     timestamptz not null default now()
);
create index store_purchases_user_idx on public.store_purchases (user_id);

-- One row per notification, for troubleshooting. Kept 30 days.
create table public.store_notifications (
    id                bigint generated always as identity primary key,
    received_at       timestamptz not null default now(),
    message_id        text,
    kind              text not null,
    notification_type int,
    token_ref         text,  -- first 16 hex of sha256(token), never the token
    user_id           uuid references auth.users on delete set null,
    state             text,
    outcome           text not null
);
create index store_notifications_time_idx on public.store_notifications (received_at desc);

alter table public.store_purchases     enable row level security;
alter table public.store_notifications enable row level security;
revoke all on public.store_purchases, public.store_notifications from anon, authenticated;

-- The user whose sha256(id) is p_tag (hex; base64 also accepted), or null.
-- A scan of auth.users, fine at this scale; called once per notification.
create function public.user_id_for_store_tag(p_tag text)
returns uuid
language sql stable security definer set search_path = ''
as $$
    select u.id from auth.users u
    where p_tag is not null
      and (encode(extensions.digest(u.id::text, 'sha256'), 'hex') = lower(p_tag)
           or encode(extensions.digest(u.id::text, 'sha256'), 'base64') = p_tag)
    limit 1
$$;

revoke execute on function public.user_id_for_store_tag(text) from public, anon, authenticated;
grant execute on function public.user_id_for_store_tag(text) to service_role;

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
    delete from public.pairing_codes where expires_at < now();
    delete from public.email_sends where sent_at < now() - interval '7 days';
    delete from public.store_notifications where received_at < now() - interval '30 days';
$$;

notify pgrst, 'reload schema';
