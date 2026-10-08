/// Supabase project the app talks to. The publishable key is meant to ship in
/// the app: RLS and the RPCs decide what it can do. Override both with
/// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...`
/// to point a build at another project.
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://rumwtzzyrhzudguolasq.supabase.co',
);

const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_eWbf9jGpxBWQ6t7Vtz8r5A_mWfdmVrK',
);

/// Where an email confirmation link lands. The page there offers a
/// pingduck://auth-callback link back into the app, which works on any device.
/// Must be in the project's Redirect URLs allow list.
const confirmEmailRedirect = 'https://pingduck.app/confirmed';
