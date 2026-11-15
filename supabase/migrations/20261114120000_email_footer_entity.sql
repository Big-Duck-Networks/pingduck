-- Drops "a Webcap Media Group company" from the footer of the emails the
-- database sends: Big Duck Networks and Webcap Media Group are separate
-- entities, and PingDuck is Big Duck Networks'. The templates in
-- supabase/email-templates/ are updated to match.
--
-- Each function is redefined from its current definition with only the
-- footer line changed, so nothing else in them can drift. CREATE OR REPLACE
-- keeps the existing grants.

do $$
declare
    v_fn  text;
    v_def text;
begin
    foreach v_fn in array array[
        'private.send_goodbye_email(text)',
        'private.send_agent_instructions_email(text, text)'
    ] loop
        v_def := pg_get_functiondef(v_fn::regprocedure);
        if position(', a Webcap Media Group company' in v_def) = 0 then
            raise exception '% has no Webcap footer to remove', v_fn;
        end if;
        execute replace(v_def, ', a Webcap Media Group company', '');
    end loop;
end $$;
