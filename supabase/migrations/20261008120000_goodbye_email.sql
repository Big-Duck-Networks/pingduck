-- Emails a goodbye ("Sorry to see you go") when a signed-in account deletes
-- itself. delete_account reads the address before deleting the user, then
-- queues the email through pg_net to Resend's API. pg_net sends only after
-- the transaction commits, so a failed deletion sends nothing, and a failed
-- email never blocks a deletion. Anonymous users have no address and get no
-- email.
--
-- Needs the Resend API key in Vault, added once by hand (not in git):
--   select vault.create_secret('re_...', 'resend_api_key');
-- Without it, or without pg_net (the plain Postgres in run_tests.sh), the
-- email is skipped with a warning.
--
-- The HTML is supabase/email-templates/account_deleted.html; edit that file
-- and regenerate this function from it.

do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_net') then
        create extension if not exists pg_net with schema extensions;
    end if;
end $$;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.send_goodbye_email(p_email text)
returns void
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
    v_key text;
begin
    if to_regproc('net.http_post') is null or to_regclass('vault.decrypted_secrets') is null then
        raise warning 'goodbye email skipped: pg_net or vault not available';
        return;
    end if;
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'resend_api_key'$q$ into v_key;
    if v_key is null then
        raise warning 'goodbye email skipped: no resend_api_key in vault';
        return;
    end if;
    execute $q$select net.http_post(
        url     := 'https://api.resend.com/emails',
        headers := jsonb_build_object('Authorization', 'Bearer ' || $1, 'Content-Type', 'application/json'),
        body    := jsonb_build_object(
            'from', 'PingDuck <hello@pingduck.app>',
            'to', jsonb_build_array($2),
            'subject', 'Your PingDuck account is deleted',
            'html', $3))$q$
        using v_key, p_email, $html$<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>Your PingDuck account is deleted</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600&family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet">
<style>
  body { margin: 0; padding: 0; background: #f8f9fa; }
  a { color: #2563eb; }
  @media (max-width: 600px) {
    .shell { width: 100% !important; }
    .pad { padding-left: 20px !important; padding-right: 20px !important; }
  }
</style>
</head>
<body style="margin:0;padding:0;background:#f8f9fa;">
<!-- Inbox preview line -->
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:#f8f9fa;">Your account and the data we held for it are gone. Here is what is left on your side.</div>

<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f8f9fa;">
<tr><td align="center" style="padding:32px 12px;">

  <table role="presentation" class="shell" width="560" cellpadding="0" cellspacing="0" border="0" style="width:560px;max-width:560px;background:#ffffff;border:1px solid #cbd2d9;">

    <!-- Header: the app bar -->
    <tr><td class="pad" style="padding:20px 32px;border-bottom:1px solid #e2e5e8;">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
        <td style="padding-right:12px;vertical-align:middle;">
          <img src="https://pingduck.app/icon.png" width="40" height="40" alt="PingDuck" style="display:block;border:0;border-radius:20px;">
        </td>
        <td style="vertical-align:middle;">
          <div style="font-family:'Space Grotesk','Helvetica Neue',Arial,sans-serif;font-size:20px;line-height:22px;font-weight:700;letter-spacing:0.5px;color:#059669;">PINGDUCK</div>
          <div style="font-family:'Space Grotesk','Helvetica Neue',Arial,sans-serif;font-size:10px;line-height:14px;font-weight:600;letter-spacing:2.4px;color:#475569;">LAN RECON</div>
        </td>
      </tr></table>
    </td></tr>

    <!-- Body -->
    <tr><td class="pad" style="padding:32px 32px 8px;">
      <div style="font-family:'Space Grotesk','Helvetica Neue',Arial,sans-serif;font-size:11px;line-height:14px;font-weight:600;letter-spacing:0.66px;color:#475569;">ACCOUNT &middot; DELETED</div>
      <h1 style="margin:8px 0 12px;font-family:'Space Grotesk','Helvetica Neue',Arial,sans-serif;font-size:28px;line-height:34px;font-weight:700;letter-spacing:-0.56px;color:#111827;">Sorry to see you go</h1>
      <p style="margin:0;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:15px;line-height:23px;color:#111827;">Your PingDuck account is deleted. We removed it from our servers, along with your email address, plan and scan history.</p>
    </td></tr>

    <!-- What's left: a panel with the keyline border and hard offset shadow -->
    <tr><td class="pad" style="padding:24px 32px 8px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:2px solid #111827;background:#ffffff;box-shadow:4px 4px 0 0 #111827;">
        <tr><td style="padding:16px 20px 4px;">
          <div style="font-family:'Space Grotesk','Helvetica Neue',Arial,sans-serif;font-size:11px;line-height:14px;font-weight:600;letter-spacing:0.66px;color:#475569;">STILL ON YOUR SIDE</div>
        </td></tr>
        <tr><td style="padding:8px 20px 6px;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:14px;line-height:21px;color:#111827;">
          <strong>Your phone.</strong> Devices, names and notes stay in the app until you tap <strong>Clear device inventory</strong> or uninstall PingDuck.
        </td></tr>
        <tr><td style="padding:6px 20px 16px;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:14px;line-height:21px;color:#111827;">
          <strong>Subscriptions.</strong> Apple and Google bill these, not us. If you had one, cancel it in the App Store or Google Play so you aren&rsquo;t charged again.
        </td></tr>
      </table>
    </td></tr>

    <!-- Come back / feedback -->
    <tr><td class="pad" style="padding:24px 32px 32px;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:15px;line-height:23px;color:#111827;">
      You can keep scanning without an account, or create a new one any time.
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:20px;background:#f1f3f5;border:1px solid #e2e5e8;">
        <tr><td style="padding:14px 16px;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:13px;line-height:19px;color:#475569;">
          <strong style="color:#111827;">Did something make you leave?</strong> We read every note. Tell us at <a href="mailto:support@pingduck.app" style="color:#2563eb;">support@pingduck.app</a>.
        </td></tr>
      </table>
    </td></tr>

    <!-- Footer -->
    <tr><td class="pad" style="padding:18px 32px;border-top:1px solid #e2e5e8;background:#f8f9fa;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:12px;line-height:18px;color:#475569;">
      Sent because the PingDuck account for this address was deleted. This is the last email we&rsquo;ll send it.<br>
      Questions? <a href="mailto:support@pingduck.app" style="color:#2563eb;">support@pingduck.app</a> &middot; <a href="https://pingduck.app/privacy" style="color:#2563eb;">Privacy</a><br>
      <span style="color:#94a3b8;">PingDuck by Big Duck Networks, a Webcap Media Group company. Made on Long Island.</span>
    </td></tr>

  </table>

</td></tr>
</table>
</body>
</html>$html$;
exception when others then
    raise warning 'goodbye email failed: %', sqlerrm;
end;
$fn$;

revoke execute on function private.send_goodbye_email(text) from public, anon, authenticated;

create or replace function public.delete_account()
returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_user  uuid := auth.uid();
    v_email text;
begin
    if v_user is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;
    select email into v_email from auth.users where id = v_user and not coalesce(is_anonymous, false);
    delete from auth.users where id = v_user;
    if v_email is not null then
        perform private.send_goodbye_email(v_email);
    end if;
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

notify pgrst, 'reload schema';
