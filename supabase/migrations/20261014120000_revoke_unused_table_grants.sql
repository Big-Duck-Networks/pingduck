-- Security review tidy-up (2026-10-13). Supabase's default privileges give
-- anon and authenticated TRUNCATE, TRIGGER and REFERENCES on every table in
-- public. None of the app's roles needs them; PostgREST can't issue them
-- either, but TRUNCATE skips row-level security, so they go. Tables created
-- later revoke everything already (email_sends, store_purchases,
-- store_notifications, device_scans).

revoke truncate, trigger, references on all tables in schema public from anon, authenticated;

-- And for tables created from now on.
alter default privileges in schema public revoke truncate, trigger, references on tables from anon, authenticated;
