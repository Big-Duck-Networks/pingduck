-- Released builds, for the website's download links (2026-11-14).
--
-- release-windows.yml records each Windows release here once its GitHub
-- release exists: version, build, the direct GitHub download link, SHA-256,
-- size, notes. pingduck.app reads the current one through
-- current_app_release('windows') with the publishable key, for the /agent
-- button and pingduck.app/download/windows.
--
-- Writing needs a release token, not the service-role key: CI can record
-- releases and nothing else. Only the token's SHA-256 is stored. Set it up
-- once (the token itself goes in the repo secret RELEASE_RECORD_TOKEN):
--   insert into private.release_keys (sha256, label)
--   values (encode(sha256(convert_to('<token>', 'UTF8')), 'hex'), 'github actions');
--
-- Roll back a bad release by withdrawing it; the previous one becomes
-- current again:
--   update public.app_releases set withdrawn_at = now() where tag = 'desktop-v1.0.2';

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.release_keys (
    sha256     text primary key check (sha256 ~ '^[0-9a-f]{64}$'),
    label      text not null default '',
    created_at timestamptz not null default now()
);

create table public.app_releases (
    id            bigint generated always as identity primary key,
    platform      text not null check (platform in ('windows')),
    version       text not null check (version ~ '^\d+\.\d+\.\d+$'),
    build         integer not null check (build > 0),
    tag           text not null unique check (length(tag) <= 64),
    -- Only ever a file on this repo's releases.
    url           text not null check (url like 'https://github.com/Big-Duck-Networks/pingduck/releases/download/%'),
    sha256        text not null check (sha256 ~ '^[0-9a-f]{64}$'),
    size_bytes    bigint not null check (size_bytes > 0),
    notes         text not null default '' check (length(notes) <= 4000),
    minimum_build integer not null default 0 check (minimum_build >= 0),
    signed        boolean not null,
    commit_sha    text check (commit_sha ~ '^[0-9a-f]{40}$'),
    published_at  timestamptz not null default now(),
    withdrawn_at  timestamptz,
    unique (platform, version),
    unique (platform, build)
);

alter table public.app_releases enable row level security;
revoke all on public.app_releases from anon, authenticated;

create index app_releases_current on public.app_releases (platform, build desc) where withdrawn_at is null;

-- The newest release that isn't withdrawn, or null. Public: it's what the
-- download page shows.
create or replace function public.current_app_release(p_platform text)
returns jsonb
language sql stable security definer set search_path = ''
as $$
    select jsonb_build_object(
        'platform', r.platform,
        'version', r.version,
        'build', r.build,
        'tag', r.tag,
        'url', r.url,
        'sha256', r.sha256,
        'size', r.size_bytes,
        'notes', r.notes,
        'minimumBuild', r.minimum_build,
        'signed', r.signed,
        'publishedAt', r.published_at)
    from public.app_releases r
    where r.platform = p_platform and r.withdrawn_at is null
    order by r.build desc
    limit 1
$$;

revoke execute on function public.current_app_release(text) from public;
grant execute on function public.current_app_release(text) to anon, authenticated;

-- Called by CI with the release token. Re-running for the same version
-- (a retried workflow) updates that row instead of failing.
create or replace function public.record_app_release(
    p_token         text,
    p_platform      text,
    p_version       text,
    p_build         integer,
    p_tag           text,
    p_url           text,
    p_sha256        text,
    p_size          bigint,
    p_notes         text,
    p_minimum_build integer,
    p_signed        boolean,
    p_commit_sha    text default null
)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
begin
    if p_token is null or not exists (
        select 1 from private.release_keys
        where sha256 = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
    ) then
        raise exception 'invalid release token' using errcode = '42501';
    end if;

    insert into public.app_releases
        (platform, version, build, tag, url, sha256, size_bytes, notes, minimum_build, signed, commit_sha)
    values
        (p_platform, p_version, p_build, p_tag, p_url, lower(p_sha256), p_size,
         coalesce(p_notes, ''), coalesce(p_minimum_build, 0), p_signed, nullif(p_commit_sha, ''))
    on conflict (platform, version) do update set
        build = excluded.build, tag = excluded.tag, url = excluded.url, sha256 = excluded.sha256,
        size_bytes = excluded.size_bytes, notes = excluded.notes, minimum_build = excluded.minimum_build,
        signed = excluded.signed, commit_sha = excluded.commit_sha,
        published_at = now(), withdrawn_at = null;

    return public.current_app_release(p_platform);
end
$$;

revoke execute on function public.record_app_release(text, text, text, integer, text, text, text, bigint, text, integer, boolean, text) from public;
grant execute on function public.record_app_release(text, text, text, integer, text, text, text, bigint, text, integer, boolean, text) to anon;
