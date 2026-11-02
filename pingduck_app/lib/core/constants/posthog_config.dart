/// PostHog project token for crash reporting and anonymous product analytics.
/// Like the Supabase publishable key and RevenueCat SDK key, it is a write-only
/// ingestion token meant to ship in the app. Override with
/// `--dart-define=POSTHOG_PROJECT_TOKEN=phc_...` (and optionally
/// `--dart-define=POSTHOG_HOST=https://...`). Until a real `phc_` token is set,
/// analytics and crash reporting stay off.
const posthogProjectToken = String.fromEnvironment(
  'POSTHOG_PROJECT_TOKEN',
  defaultValue: 'phc_tuYVFXrmRmPPJUciDe41N7ygqpB5mSBUCsWlgod4rLrd',
);

const posthogHost = String.fromEnvironment(
  'POSTHOG_HOST',
  defaultValue: 'https://us.i.posthog.com',
);

bool get posthogKeySet =>
    posthogProjectToken.startsWith('phc_') && posthogProjectToken != 'phc_REPLACE_ME';

