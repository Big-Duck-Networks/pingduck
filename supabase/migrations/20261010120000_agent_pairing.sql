-- Agent pairing over the LAN (docs/ROADMAP.md Phase 4, "Agent pairing").
--
-- The app finds an unpaired agent on the LAN, gets a code from
-- create_pairing_code and hands it to the agent, which redeems it itself with
-- claim_pairing_code. This migration adds what that flow still needs:
--
--   agent_heartbeat           the agent checks in every minute, keeps
--                             last_seen_at fresh and learns when the owner has
--                             revoked it.
--   email_agent_instructions  "Email me these steps" in the app: sends the
--                             install steps for one platform to the account's
--                             own address, at most 3 an hour.
--
-- The email goes out through pg_net and Resend like the goodbye email
-- (20261008120000_goodbye_email.sql) and is skipped with a warning where
-- pg_net or the Vault key is missing. The HTML is
-- supabase/email-templates/agent_instructions.html; regenerate the function
-- below after editing it.

-- ---------------------------------------------------------------------------
-- Heartbeat
-- ---------------------------------------------------------------------------

-- Called by the agent with the anon key. Answers 'revoked' rather than
-- raising for an unknown or revoked token, so the agent can tell "unpair
-- yourself" apart from a server or network error.
create function public.agent_heartbeat(p_token text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_agent public.agents;
begin
    update public.agents set last_seen_at = now()
    where token_hash = extensions.digest(coalesce(p_token, ''), 'sha256') and revoked_at is null
    returning * into v_agent;
    if v_agent.id is null then
        return jsonb_build_object('status', 'revoked');
    end if;
    return jsonb_build_object('status', 'active', 'agent_id', v_agent.id, 'network_id', v_agent.network_id);
end
$$;

revoke execute on function public.agent_heartbeat(text) from public;
grant execute on function public.agent_heartbeat(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Install instructions by email
-- ---------------------------------------------------------------------------

-- Emails sent on a user's request, for rate limiting. RPC access only.
create table public.email_sends (
    user_id uuid not null references auth.users on delete cascade,
    kind    text not null,
    sent_at timestamptz not null default now()
);
create index email_sends_user_kind_time_idx on public.email_sends (user_id, kind, sent_at desc);
alter table public.email_sends enable row level security;
revoke all on public.email_sends from anon, authenticated;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create function private.send_agent_instructions_email(p_email text, p_platform text)
returns void
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
    v_key   text;
    v_title text;
    v_steps text;
    v_pre   constant text := '<pre style="margin:8px 0 0;padding:10px;background:#f1f3f5;border:1px solid #e2e5e8;font-family:Menlo,Consolas,monospace;font-size:12px;line-height:18px;white-space:pre-wrap;word-break:break-all;">';
    v_run   constant text := 'docker run -d --name pingduck-agent --restart unless-stopped \
  --net=host --cap-add=NET_RAW --cap-add=NET_ADMIN \
  -v pingduck:/var/lib/pingduck \
  ghcr.io/big-duck-networks/pingduck-agent:latest';
    v_html  text;
begin
    if to_regproc('net.http_post') is null or to_regclass('vault.decrypted_secrets') is null then
        raise warning 'agent instructions email skipped: pg_net or vault not available';
        return;
    end if;
    execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'resend_api_key'$q$ into v_key;
    if v_key is null then
        raise warning 'agent instructions email skipped: no resend_api_key in vault';
        return;
    end if;

    -- Keep these steps in step with AgentPlatform in the app
    -- (pingduck_app/lib/features/agent/domain/agent_platform.dart) and with
    -- agent/compose.yaml.
    case p_platform
    when 'linux' then
        v_title := 'LINUX OR PROXMOX';
        v_steps := '<ol style="margin:0;padding-left:20px;">'
            || '<li style="margin:8px 0;">Open a terminal on the box: any 64-bit Linux machine or Proxmox VM with Docker.</li>'
            || '<li style="margin:8px 0;">Run:' || v_pre || v_run || '</pre></li>'
            || '</ol>';
    when 'raspberry_pi' then
        v_title := 'RASPBERRY PI';
        v_steps := '<ol style="margin:0;padding-left:20px;">'
            || '<li style="margin:8px 0;">Use 64-bit Raspberry Pi OS on a Pi 3, 4 or 5.</li>'
            || '<li style="margin:8px 0;">Install Docker:' || v_pre || 'curl -fsSL https://get.docker.com | sh</pre></li>'
            || '<li style="margin:8px 0;">Run:' || v_pre || 'sudo ' || v_run || '</pre></li>'
            || '</ol>';
    when 'nas' then
        v_title := 'SYNOLOGY / QNAP NAS';
        v_steps := '<ol style="margin:0;padding-left:20px;">'
            || '<li style="margin:8px 0;">Open Container Manager (Synology) or Container Station (QNAP).</li>'
            || '<li style="margin:8px 0;">Create a project (an application on QNAP) from this compose file:' || v_pre
            || 'services:
  pingduck-agent:
    image: ghcr.io/big-duck-networks/pingduck-agent:latest
    network_mode: host
    cap_add: [NET_RAW, NET_ADMIN]
    volumes: [pingduck:/var/lib/pingduck]
    restart: unless-stopped
volumes:
  pingduck:</pre></li>'
            || '</ol>';
    end case;

    v_html := replace(replace($html$
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>Set up your PingDuck agent</title>
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
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:#f8f9fa;">A few steps to put a PingDuck agent on your network.</div>

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
      <div style="font-family:'Space Grotesk','Helvetica Neue',Arial,sans-serif;font-size:11px;line-height:14px;font-weight:600;letter-spacing:0.66px;color:#475569;">MONITORING UNIT &middot; {{platform}}</div>
      <h1 style="margin:8px 0 12px;font-family:'Space Grotesk','Helvetica Neue',Arial,sans-serif;font-size:28px;line-height:34px;font-weight:700;letter-spacing:-0.56px;color:#111827;">Set up your PingDuck agent</h1>
      <p style="margin:0;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:15px;line-height:23px;color:#111827;">The agent runs in one container on an always-on box. It finds the devices your phone can't see and keeps watching when you're away.</p>
    </td></tr>

    <!-- Steps: a panel with the keyline border and hard offset shadow -->
    <tr><td class="pad" style="padding:24px 32px 8px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border:2px solid #111827;background:#ffffff;box-shadow:4px 4px 0 0 #111827;">
        <tr><td style="padding:16px 20px 4px;">
          <div style="font-family:'Space Grotesk','Helvetica Neue',Arial,sans-serif;font-size:11px;line-height:14px;font-weight:600;letter-spacing:0.66px;color:#475569;">ON THE BOX</div>
        </td></tr>
        <tr><td style="padding:4px 20px 16px;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:14px;line-height:21px;color:#111827;">
          {{steps}}
        </td></tr>
      </table>
    </td></tr>

    <!-- Then the phone -->
    <tr><td class="pad" style="padding:24px 32px 32px;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:15px;line-height:23px;color:#111827;">
      Then open PingDuck on a phone on the same Wi-Fi and tap <strong>Find my agent</strong>. The app finds the agent and activates it. There's no code to copy.
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:20px;background:#f1f3f5;border:1px solid #e2e5e8;">
        <tr><td style="padding:14px 16px;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:13px;line-height:19px;color:#475569;">
          <strong style="color:#111827;">App can't find it?</strong> Check the container is running (<code>docker ps</code>), that it uses host networking, and that the phone isn't on a guest Wi-Fi. If the box is on another VLAN, tap <strong>Use a pairing code</strong> in the app.
        </td></tr>
      </table>
    </td></tr>

    <!-- Footer -->
    <tr><td class="pad" style="padding:18px 32px;border-top:1px solid #e2e5e8;background:#f8f9fa;font-family:Inter,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;font-size:12px;line-height:18px;color:#475569;">
      Sent because you asked PingDuck to email these steps.<br>
      Questions? <a href="mailto:support@pingduck.app" style="color:#2563eb;">support@pingduck.app</a> &middot; <a href="https://pingduck.app/privacy" style="color:#2563eb;">Privacy</a><br>
      <span style="color:#94a3b8;">PingDuck by Big Duck Networks, a Webcap Media Group company. Made on Long Island.</span>
    </td></tr>

  </table>

</td></tr>
</table>
</body>
</html>
$html$, '{{platform}}', v_title), '{{steps}}', v_steps);

    execute $q$select net.http_post(
        url     := 'https://api.resend.com/emails',
        headers := jsonb_build_object('Authorization', 'Bearer ' || $1, 'Content-Type', 'application/json'),
        body    := jsonb_build_object(
            'from', 'PingDuck <hello@pingduck.app>',
            'to', jsonb_build_array($2),
            'subject', 'Set up your PingDuck agent',
            'html', $3))$q$
        using v_key, p_email, v_html;
exception when others then
    raise warning 'agent instructions email failed: %', sqlerrm;
end;
$fn$;

revoke execute on function private.send_agent_instructions_email(text, text) from public, anon, authenticated;

create function public.email_agent_instructions(p_platform text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_user  uuid := auth.uid();
    v_email text;
begin
    select email into v_email from auth.users
    where id = v_user and not coalesce(is_anonymous, false) and email is not null;
    if v_email is null then
        raise exception 'account_required' using errcode = '28000';
    end if;
    if p_platform is null or p_platform not in ('linux', 'raspberry_pi', 'nas') then
        raise exception 'unknown platform' using errcode = '22023';
    end if;
    if (select count(*) from public.email_sends
        where user_id = v_user and kind = 'agent_instructions' and sent_at > now() - interval '1 hour') >= 3 then
        raise exception 'rate_limited: try again later' using errcode = 'P0001';
    end if;

    insert into public.email_sends (user_id, kind) values (v_user, 'agent_instructions');
    perform private.send_agent_instructions_email(v_email, p_platform);
    return jsonb_build_object('sent_to', v_email);
end
$$;

revoke execute on function public.email_agent_instructions(text) from public, anon;
grant execute on function public.email_agent_instructions(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Retention: also trim the email log
-- ---------------------------------------------------------------------------

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
$$;

notify pgrst, 'reload schema';
