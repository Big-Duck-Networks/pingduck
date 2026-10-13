import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../core/theme/pingduck_colors.dart';
import '../../core/theme/pingduck_theme.dart';
import '../../core/widgets/pd_widgets.dart';
import 'account_auth.dart';

enum _Step { signIn, signUp, confirm, forgot, reset }

/// Email and password sign-in, account creation (confirmed by clicking an
/// emailed link) and password reset (by emailed code). Google, and Apple on iOS, are shown but not wired
/// up yet. Pops with true once signed in.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.startWithSignUp = false, this.lead});

  /// Opens on Create account instead of Sign in.
  final bool startWithSignUp;

  /// Why an account is being asked for, shown above the form.
  final String? lead;

  static const minPassword = 8;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> with WidgetsBindingObserver {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  late var _step = widget.startWithSignUp ? _Step.signUp : _Step.signIn;
  bool _busy = false, _showPassword = false, _checking = false, _finished = false;

  /// Field problems, shown under the form. Server results are toasts.
  String? _error;

  /// While waiting on the confirmation link: checks every few seconds, since
  /// the link may be opened on another device while this screen is up.
  Timer? _watch;
  static const watchInterval = Duration(seconds: 5);

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  AccountAuth get _auth => ref.read(accountAuthProvider);
  String get _emailText => _email.text.trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Coming back from the browser (or the "Open PingDuck" link) is the usual
  /// moment the link has just been clicked.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _step == _Step.confirm) _checkConfirmed(quiet: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _go(_Step step) {
    _watch?.cancel();
    if (step == _Step.confirm) _watch = Timer.periodic(watchInterval, (_) => _checkConfirmed(quiet: true));
    setState(() {
      _step = step;
      _error = null;
      _code.clear();
      if (step == _Step.reset) _password.clear();
    });
  }

  /// Toasts on the app-wide messenger, so ones shown just before [_done]
  /// stay up on the screen we return to.
  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: error ? PingDuckColors.critical : null),
      );
  }

  /// Once only: the timer and app resume can both see the link clicked, and
  /// the screen stays mounted while it pops, so a second pop would close the
  /// app's home screen and leave it black.
  void _done(String message) {
    if (!mounted || _finished) return;
    _finished = true;
    _watch?.cancel();
    _toast(message);
    Navigator.of(context).pop(true);
  }

  /// Checks the fields [_step] needs; returns false after showing why not.
  bool _valid({bool email = true, bool password = false, bool newPassword = false, bool code = false}) {
    String? error;
    if (email && !_emailShape.hasMatch(_emailText)) {
      error = 'Enter a valid email address.';
    } else if (password && _password.text.isEmpty) {
      error = 'Enter your password.';
    } else if (newPassword && _password.text.length < SignInScreen.minPassword) {
      error = 'Use at least ${SignInScreen.minPassword} characters for your password.';
    } else if (code && _code.text.trim().length < 6) {
      error = 'Enter the code from the email.';
    }
    if (error != null) setState(() => _error = error);
    return error == null;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      _toast(error: true, switch (e.code) {
        'invalid_credentials' => 'Wrong email or password.',
        'email_exists' || 'user_already_exists' => 'That email already has an account. Sign in instead.',
        'otp_expired' => 'That code is wrong or has expired. Check it, or send a new one.',
        'same_password' => 'Choose a password different from your current one.',
        'over_email_send_rate_limit' || 'over_request_rate_limit' => 'Too many attempts. Wait a minute and try again.',
        'email_address_invalid' => 'That email address can’t receive mail.',
        _ => e.message,
      });
    } catch (_) {
      _toast('Couldn’t reach the server. Check your connection and try again.', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _signIn() async {
    if (!_valid(password: true)) return;
    await _run(() async {
      await _auth.signIn(_emailText, _password.text);
      _done('Signed in');
    });
  }

  Future<void> _signUp() async {
    if (!_valid(newPassword: true)) return;
    final resend = _step == _Step.confirm;
    await _run(() async {
      final needsLink = await _auth.startSignUp(_emailText, _password.text);
      if (!needsLink) return _done('Account created. You’re signed in.');
      _toast(resend ? 'Sent a new link to $_emailText' : 'Confirmation link sent to $_emailText');
      if (!resend) _go(_Step.confirm);
    });
  }

  /// [quiet] checks (timer, app resume) say nothing until the link is clicked.
  Future<void> _checkConfirmed({bool quiet = false}) async {
    if (_busy || _checking) return;
    if (quiet) {
      _checking = true;
      try {
        if (await _auth.completeSignUp(_emailText, _password.text)) _done('Email confirmed. You’re signed in.');
      } catch (_) {}
      _checking = false;
      return;
    }
    await _run(() async {
      if (await _auth.completeSignUp(_emailText, _password.text)) {
        _done('Email confirmed. You’re signed in.');
      } else {
        _toast('Not confirmed yet. Tap the link in the email we sent to $_emailText.');
      }
    });
  }

  Future<void> _sendReset() async {
    if (!_valid()) return;
    final resend = _step == _Step.reset;
    await _run(() async {
      await _auth.sendPasswordReset(_emailText);
      _toast(resend ? 'Sent a new code to $_emailText' : 'Code sent to $_emailText');
      if (!resend) _go(_Step.reset);
    });
  }

  Future<void> _reset() async {
    if (!_valid(code: true, newPassword: true)) return;
    await _run(() async {
      await _auth.finishPasswordReset(_emailText, _code.text.trim(), _password.text);
      _done('Password changed. You’re signed in.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final (title, panel, icon) = switch (_step) {
      _Step.signIn => ('SIGN IN', 'Welcome back', Icons.login),
      _Step.signUp => ('CREATE ACCOUNT', 'New account', Icons.person_add_alt),
      _Step.confirm => ('CREATE ACCOUNT', 'Check your email', Icons.mark_email_unread_outlined),
      _Step.forgot || _Step.reset => ('RESET PASSWORD', 'Reset password', Icons.lock_reset),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: PdText.labelLg),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.lead != null) ...[
              Text(widget.lead!, style: PdText.bodyMd),
              const SizedBox(height: 16),
            ],
            PdPanel(
              title: panel,
              icon: icon,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._fields(),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: PdText.bodySm.copyWith(color: PingDuckColors.critical)),
                  ],
                ],
              ),
            ),
            if (_step == _Step.signIn || _step == _Step.signUp) ...[
              const SizedBox(height: 16),
              const _SocialButtons(),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_step == _Step.signIn ? 'New to PingDuck?' : 'Already have an account?', style: PdText.bodySm),
                  TextButton(
                    onPressed: _busy ? null : () => _go(_step == _Step.signIn ? _Step.signUp : _Step.signIn),
                    child: Text(_step == _Step.signIn ? 'CREATE ACCOUNT' : 'SIGN IN'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _fields() => switch (_step) {
    _Step.signIn => [
      _emailField(),
      const SizedBox(height: 10),
      _passwordField(newPassword: false, onSubmitted: _signIn),
      const SizedBox(height: 12),
      PdButton(
        label: _busy ? 'Signing in…' : 'Sign in',
        icon: Icons.login,
        style: PdButtonStyle.primary,
        onPressed: _busy ? null : _signIn,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: _busy ? null : () => _go(_Step.forgot), child: const Text('FORGOT PASSWORD?')),
      ),
    ],
    _Step.signUp => [
      Text('Your plan and today’s scans carry over. Devices and notes stay on this phone.', style: PdText.bodySm),
      const SizedBox(height: 12),
      _emailField(),
      const SizedBox(height: 10),
      _passwordField(newPassword: true, onSubmitted: _signUp),
      const SizedBox(height: 12),
      PdButton(
        label: _busy ? 'Creating…' : 'Create account',
        icon: Icons.person_add_alt,
        style: PdButtonStyle.primary,
        onPressed: _busy ? null : _signUp,
      ),
    ],
    _Step.confirm => [
      Text(
        'We sent a link to $_emailText. Tap it to confirm your email, on this phone or any other device. '
        'This screen finishes on its own once you do.',
        style: PdText.bodySm,
      ),
      const SizedBox(height: 12),
      PdButton(
        label: _busy ? 'Checking…' : 'I’ve confirmed',
        icon: Icons.check,
        style: PdButtonStyle.primary,
        onPressed: _busy ? null : _checkConfirmed,
      ),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        children: [
          TextButton(onPressed: _busy ? null : () => _go(_Step.signUp), child: const Text('CHANGE EMAIL')),
          TextButton(onPressed: _busy ? null : _signUp, child: const Text('RESEND LINK')),
        ],
      ),
    ],
    _Step.forgot => [
      Text('We’ll email you a code to set a new password.', style: PdText.bodySm),
      const SizedBox(height: 12),
      _emailField(onSubmitted: _sendReset),
      const SizedBox(height: 12),
      PdButton(
        label: _busy ? 'Sending…' : 'Email me a code',
        icon: Icons.send_outlined,
        style: PdButtonStyle.primary,
        onPressed: _busy ? null : _sendReset,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: _busy ? null : () => _go(_Step.signIn), child: const Text('BACK TO SIGN IN')),
      ),
    ],
    _Step.reset => [
      Text('Enter the code we sent to $_emailText and choose a new password.', style: PdText.bodySm),
      const SizedBox(height: 12),
      _codeField(onSubmitted: null),
      const SizedBox(height: 10),
      _passwordField(newPassword: true, onSubmitted: _reset),
      const SizedBox(height: 12),
      PdButton(
        label: _busy ? 'Saving…' : 'Set password',
        icon: Icons.check,
        style: PdButtonStyle.primary,
        onPressed: _busy ? null : _reset,
      ),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        children: [
          TextButton(onPressed: _busy ? null : () => _go(_Step.forgot), child: const Text('CHANGE EMAIL')),
          TextButton(onPressed: _busy ? null : _sendReset, child: const Text('RESEND CODE')),
        ],
      ),
    ],
  };

  Widget _emailField({VoidCallback? onSubmitted}) => TextField(
    key: const Key('email'),
    controller: _email,
    enabled: !_busy,
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email],
    autocorrect: false,
    textInputAction: onSubmitted == null ? TextInputAction.next : TextInputAction.send,
    decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com'),
    onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
  );

  Widget _passwordField({required bool newPassword, required VoidCallback onSubmitted}) => TextField(
    key: const Key('password'),
    controller: _password,
    enabled: !_busy,
    obscureText: !_showPassword,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [newPassword ? AutofillHints.newPassword : AutofillHints.password],
    textInputAction: TextInputAction.done,
    decoration: InputDecoration(
      labelText: newPassword ? 'New password' : 'Password',
      helperText: newPassword ? 'At least ${SignInScreen.minPassword} characters' : null,
      suffixIcon: IconButton(
        tooltip: _showPassword ? 'Hide password' : 'Show password',
        icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        onPressed: () => setState(() => _showPassword = !_showPassword),
      ),
    ),
    onSubmitted: (_) => onSubmitted(),
  );

  Widget _codeField({required VoidCallback? onSubmitted}) => TextField(
    key: const Key('code'),
    controller: _code,
    enabled: !_busy,
    autofocus: true,
    keyboardType: TextInputType.number,
    autofillHints: const [AutofillHints.oneTimeCode],
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
    textInputAction: onSubmitted == null ? TextInputAction.next : TextInputAction.done,
    style: PdText.headlineMd.copyWith(letterSpacing: 6),
    decoration: const InputDecoration(labelText: 'Code', hintText: '123456'),
    onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
  );
}

/// Shown so people know they're coming; neither is set up yet. Apple only
/// on iOS, where it must ship alongside any other social sign-in.
class _SocialButtons extends StatelessWidget {
  const _SocialButtons();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (Theme.of(context).platform == TargetPlatform.iOS) ...[
        const PdButton(label: 'Continue with Apple', icon: Icons.apple),
        const SizedBox(height: 8),
      ],
      const PdButton(label: 'Continue with Google', icon: Icons.g_mobiledata),
      const SizedBox(height: 4),
      Text('Coming soon', textAlign: TextAlign.center, style: PdText.bodySm),
    ],
  );
}
