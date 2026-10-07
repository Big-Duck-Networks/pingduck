import 'package:supabase_flutter/supabase_flutter.dart';

/// Signs in anonymously on first use, so a Free install has an identity for
/// its daily scan count before anyone creates an account. Linking an email
/// or Apple/Google later keeps the same user id.
Future<SupabaseClient> signedInClient() async {
  final client = Supabase.instance.client;
  if (client.auth.currentSession == null) await client.auth.signInAnonymously();
  return client;
}
