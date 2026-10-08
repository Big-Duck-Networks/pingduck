# Auth email templates

Supabase Auth emails in the app's design (white canvas, carbon ink, keyline
panel with the hard offset shadow, Space Grotesk labels). Each file is the
whole message body: paste it into **Authentication → Emails → Templates** in
the Supabase dashboard, with the subject below.

| File | Dashboard template | Subject | Sent when |
| --- | --- | --- | --- |
| `email_change.html` | Change Email Address | `Confirm your PingDuck email` | Creating an account. The app upgrades its anonymous user by adding an email, which Supabase treats as an email change, so this is the sign-up email. |
| `recovery.html` | Reset Password | `Your PingDuck password reset code` | Forgot password. |

The app never sends Confirm signup, Magic Link or Invite, so those stay as
they are.

`account_deleted.html` ("Sorry to see you go", subject `Your PingDuck account
is deleted`) is not a dashboard template. Supabase Auth has no deletion email,
so `delete_account` sends it itself through pg_net and Resend's API (see
`migrations/20261008120000_goodbye_email.sql`, which embeds this file; after
editing it, regenerate that function). It needs the Resend API key in Vault:
`select vault.create_secret('re_...', 'resend_api_key');`.

Sign-up is confirmed by link: `email_change.html` links `{{ .ConfirmationURL }}`,
which confirms the address and redirects to `https://pingduck.app/confirmed`
(the app passes it as `emailRedirectTo`). That page has an Open PingDuck button
(`pingduck://auth-callback`) back into the app, and the app also notices the
confirmation by itself. Add `https://pingduck.app/confirmed` to
**Authentication → URL Configuration → Redirect URLs** and set the Site URL to
`https://pingduck.app`, or Supabase falls back to the Site URL.

Password reset stays a code (`{{ .Token }}` in `recovery.html`): a reset link
opened on another device would have no way back into the app.

They also use `{{ .NewEmail }}` (email_change) and `{{ .Email }}` (recovery).
"Expires in 1 hour" matches the project's Email OTP Expiration (3600 s); change
both together.

The logo loads from `https://pingduck.app/icon.png` (the website's
`public/icon.png`). Web fonts load where the mail client allows (Apple Mail,
iOS); Gmail and Outlook fall back to Helvetica/Arial and system fonts.

To preview, replace the `{{ ... }}` placeholders with sample values and open
the file in a browser.
