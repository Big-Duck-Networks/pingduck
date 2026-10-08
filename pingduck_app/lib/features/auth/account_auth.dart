import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session.dart';

/// Email and password accounts. Creating one upgrades this install's
/// anonymous user in place, so its id (and the scan count tied to it) carries
/// over; the address is confirmed with a code emailed once. Codes rather than
/// links: they need no deep-link setup and can be read on another device.
abstract interface class AccountAuth {
  /// Email of the signed-in account; null while anonymous or signed out.
  String? get email;

  /// [email] now, then on every sign-in, upgrade and sign-out.
  Stream<String?> emailChanges();

  /// Signs in to an existing account; this install's anonymous user is left
  /// behind.
  Future<void> signIn(String email, String password);

  /// Starts turning this install into an account for [email]. Returns true
  /// when a confirmation code was emailed, false when the project confirmed
  /// the address on the spot (and the password is already set).
  Future<bool> startSignUp(String email, String password);

  /// Confirms the address with the emailed [code] and sets the password.
  Future<void> finishSignUp(String email, String code, String password);

  /// Emails a code that lets [finishPasswordReset] set a new password.
  Future<void> sendPasswordReset(String email);

  Future<void> finishPasswordReset(String email, String code, String newPassword);

  Future<void> signOut();

  /// Deletes the account and everything the server holds for it (see the
  /// `delete_account` RPC), then signs out. Data on this device stays.
  Future<void> deleteAccount();
}

class SupabaseAccountAuth implements AccountAuth {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  static String? _emailOf(User? user) => user == null || user.isAnonymous ? null : user.email;

  @override
  String? get email => _emailOf(_auth.currentUser);

  @override
  Stream<String?> emailChanges() async* {
    yield email;
    yield* _auth.onAuthStateChange.map((s) => _emailOf(s.session?.user)).distinct();
  }

  @override
  Future<void> signIn(String email, String password) => _auth.signInWithPassword(email: email, password: password);

  @override
  Future<bool> startSignUp(String email, String password) async {
    await signedInClient();
    // An anonymous user can only set a password once it has a confirmed email.
    final user = (await _auth.updateUser(UserAttributes(email: email))).user;
    if (user?.email != email) return true;
    await _auth.updateUser(UserAttributes(password: password));
    return false;
  }

  @override
  Future<void> finishSignUp(String email, String code, String password) async {
    await _auth.verifyOTP(email: email, token: code, type: OtpType.emailChange);
    await _auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> sendPasswordReset(String email) => _auth.resetPasswordForEmail(email);

  @override
  Future<void> finishPasswordReset(String email, String code, String newPassword) async {
    await _auth.verifyOTP(email: email, token: code, type: OtpType.recovery);
    await _auth.updateUser(UserAttributes(password: newPassword));
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteAccount() async {
    await Supabase.instance.client.rpc('delete_account');
    // The server session died with the user; only the local one is left.
    await _auth.signOut(scope: SignOutScope.local);
  }
}

final accountAuthProvider = Provider<AccountAuth>((ref) => SupabaseAccountAuth());

final accountEmailProvider = StreamProvider<String?>((ref) => ref.watch(accountAuthProvider).emailChanges());
