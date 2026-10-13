/// RevenueCat public SDK key for the Play Store app. Like the Supabase
/// publishable key it is meant to ship in the app: it can only read offerings
/// and start purchases, and the server decides entitlements. Override with
/// `--dart-define=REVENUECAT_ANDROID_KEY=goog_...`.
const revenueCatAndroidKey = String.fromEnvironment(
  'REVENUECAT_ANDROID_KEY',
  defaultValue: 'goog_KsxgrYAlLNuevLdpuRbicezPTUR',
);

bool get revenueCatKeySet => revenueCatAndroidKey.startsWith('goog_') && revenueCatAndroidKey != 'goog_REPLACE_ME';

/// The RevenueCat entitlement that maps to the `premium` plan.
const premiumEntitlement = 'premium';

/// Google Play's own subscription page for this app (Manage subscription).
const playSubscriptionsUrl = 'https://play.google.com/store/account/subscriptions?package=app.webcap.pingduck';
