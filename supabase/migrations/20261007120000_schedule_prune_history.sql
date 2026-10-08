-- Runs prune_history() daily at 04:00 UTC: trims device_events past each
-- plan's history_days, scan_usage older than a week, and expired pairing
-- codes. Safe to re-run: cron.schedule replaces a job with the same name.
-- Skipped where pg_cron is not available (the plain Postgres used by
-- supabase/tests/run_tests.sh).

do $$
begin
    if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        raise notice 'pg_cron not available; prune_history is not scheduled';
        return;
    end if;
    create extension if not exists pg_cron with schema pg_catalog;
    grant usage on schema cron to postgres;
    grant all privileges on all tables in schema cron to postgres;
    perform cron.schedule('prune-history', '0 4 * * *', 'select public.prune_history()');
end $$;
