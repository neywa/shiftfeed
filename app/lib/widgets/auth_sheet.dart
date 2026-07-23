/// Modal bottom sheet that drives passwordless magic-link sign-in.
///
/// Two visual states:
///   - `_entering` — collect email and call [UserService.sendMagicLink].
///   - `_sent` — confirmation copy plus resend / change-email actions.
///
/// The sheet listens to [UserService.authStateChanges] and pops with
/// `result = true` the moment a `signedIn` event arrives — that's how the
/// caller (typically [PaywallSheet]) knows it can resume the purchase flow
/// once the deep link is processed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/user_service.dart';
import '../theme/app_theme.dart';

/// The slice of auth behaviour [AuthSheet] depends on. Production uses
/// [_UserServiceAuthActions] (a thin adapter over [UserService.instance]);
/// tests inject a fake so the sheet can be pumped without a live Supabase
/// singleton (mirrors the repo's habit of not testing against it — see
/// `test/nav_tabs_test.dart`).
abstract class AuthSheetActions {
  Stream<AuthState> get authStateChanges;
  Stream<String> get authErrors;
  Future<void> sendMagicLink(String email);
  Future<void> signInWithPassword(String email, String password);

  /// Returns true when a session is active immediately (confirmation off),
  /// false when the account awaits email confirmation.
  Future<bool> signUpWithPassword(String email, String password);
}

/// Default [AuthSheetActions] forwarding to the real [UserService].
class _UserServiceAuthActions implements AuthSheetActions {
  const _UserServiceAuthActions();

  @override
  Stream<AuthState> get authStateChanges =>
      UserService.instance.authStateChanges;

  @override
  Stream<String> get authErrors => UserService.instance.authErrors;

  @override
  Future<void> sendMagicLink(String email) =>
      UserService.instance.sendMagicLink(email);

  @override
  Future<void> signInWithPassword(String email, String password) =>
      UserService.instance.signInWithPassword(email, password);

  @override
  Future<bool> signUpWithPassword(String email, String password) =>
      UserService.instance.signUpWithPassword(email, password);
}

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key, AuthSheetActions? actions})
      : actions = actions ?? const _UserServiceAuthActions();

  /// Injectable auth backend; defaults to the real [UserService] adapter.
  final AuthSheetActions actions;

  // ---- User-visible strings (kept static for easy future l10n) ----

  static const String _kEnterTitle = 'Create your ShiftFeed account';
  static const String _kEnterSubtitle =
      'Enter your email to receive a sign-in link. No password needed.';
  static const String _kEmailLabel = 'Email address';
  static const String _kEmailEmpty = 'Please enter your email.';
  static const String _kEmailInvalid = 'That doesn\'t look like a valid email.';
  static const String _kCtaSend = 'Send sign-in link';
  static const String _kSendingHint =
      "We'll send a one-time link. No password, ever.";

  static const String _kSentTitle = 'Check your inbox';
  static const String _kSentBodyTemplate =
      'We sent a sign-in link to {email}. Tap it to continue — then come '
      'back here to complete your subscription.';
  static const String _kCtaResend = 'Resend link';
  static const String _kCtaChangeEmail = 'Use a different email';
  static const String _kResendConfirm = 'Link resent!';

  // ---- Password path (secondary, revealed on demand) ----

  static const String _kPasswordLabel = 'Password';
  static const String _kPasswordEmpty = 'Please enter your password.';
  static const String _kCtaUsePassword = 'Use password instead';
  static const String _kCtaUseMagicLink = 'Use a sign-in link instead';
  static const String _kCtaSignIn = 'Sign in';
  static const String _kCtaSignUp = 'Create account';
  static const String _kSignUpConfirm =
      'Account created. Check your inbox to confirm your email, then sign in.';

  /// Opens the sheet and returns true when the user has signed in, false
  /// if they dismissed it. [actions] is injectable for tests; production
  /// callers omit it and get the real [UserService] adapter.
  static Future<bool> show(BuildContext context,
      {AuthSheetActions? actions}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AuthSheet(actions: actions),
    );
    return result ?? false;
  }

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

enum _AuthSheetStage { entering, sent }

class _AuthSheetState extends State<AuthSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _AuthSheetStage _stage = _AuthSheetStage.entering;
  bool _busy = false;

  /// When true the entering stage shows the password field and its primary
  /// action becomes sign-in-with-password. Magic link is the default (false).
  bool _passwordMode = false;
  String? _error;
  String? _info;
  String? _resendInfo;
  String _sentToEmail = '';

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _authErrorSub;

  /// Guards against `AuthChangeEvent.signedIn` firing twice for one
  /// sign-in (a known quirk of supabase_flutter v2's PKCE flow). Without
  /// this, the second pop would pop the route underneath the modal —
  /// the home screen — leaving a blank navigator stack.
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _authSub = widget.actions.authStateChanges.listen((state) {
      debugPrint('[AuthSheet] auth state changed: ${state.event}');
      if (!mounted || _popped) return;
      if (state.event == AuthChangeEvent.signedIn) {
        _popped = true;
        _authSub?.cancel();
        debugPrint('[AuthSheet] attempting to pop sheet');
        Navigator.of(context).pop(true);
      }
    });
    _authErrorSub = widget.actions.authErrors.listen((message) {
      debugPrint('[AuthSheet] auth error: $message');
      if (!mounted) return;
      setState(() {
        _stage = _AuthSheetStage.entering;
        _error = message;
        _resendInfo = null;
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _authErrorSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return AuthSheet._kEmailEmpty;
    if (!v.contains('@') || !v.contains('.')) {
      return AuthSheet._kEmailInvalid;
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) return AuthSheet._kPasswordEmpty;
    return null;
  }

  Future<void> _onSend() async {
    if (_busy) return;
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    final email = _emailController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.actions.sendMagicLink(email);
      if (!mounted) return;
      setState(() {
        _stage = _AuthSheetStage.sent;
        _sentToEmail = email;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not send link: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Signs in with the entered email + password. On success the auth stream
  /// emits `signedIn` and the [initState] listener pops the sheet — same exit
  /// path as the magic-link flow, so nothing extra to do here.
  Future<void> _onPasswordSignIn() async {
    if (_busy) return;
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.actions.signInWithPassword(email, password);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not sign in: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Creates an account with the entered email + password. If the project
  /// auto-confirms, a session lands and the listener pops; otherwise we tell
  /// the user to confirm their email.
  Future<void> _onPasswordSignUp() async {
    if (_busy) return;
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final signedIn = await widget.actions.signUpWithPassword(email, password);
      if (!mounted || signedIn) return;
      setState(() => _info = AuthSheet._kSignUpConfirm);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not create account: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _togglePasswordMode() {
    setState(() {
      _passwordMode = !_passwordMode;
      _error = null;
      _info = null;
    });
  }

  Future<void> _onResend() async {
    if (_busy || _sentToEmail.isEmpty) return;
    setState(() {
      _busy = true;
      _resendInfo = null;
    });
    try {
      await UserService.instance.sendMagicLink(_sentToEmail);
      if (!mounted) return;
      setState(() => _resendInfo = AuthSheet._kResendConfirm);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _resendInfo = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetToEntering() {
    setState(() {
      _stage = _AuthSheetStage.entering;
      _resendInfo = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? kSurface : kLightSurface;
    final textPrimary = isDark ? kTextPrimary : kLightTextPrimary;
    final textSecondary = isDark ? kTextSecondary : kLightTextSecondary;
    final textMuted = isDark ? kTextMuted : kLightTextMuted;
    final border = isDark ? kBorder : kLightBorder;

    final media = MediaQuery.of(context);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: border),
      ),
      // `padding.bottom` is 0 inside a fully-working SafeArea, but
      // gesture-nav Androids sometimes leave a small system inset that
      // useSafeArea: true doesn't catch — adding it here keeps the last
      // text button clear of the bottom control bar.
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + media.viewInsets.bottom + media.padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (_stage == _AuthSheetStage.entering)
            _buildEntering(theme, textPrimary, textSecondary, textMuted)
          else
            _buildSent(theme, textPrimary, textSecondary, textMuted),
        ],
      ),
    );
  }

  Widget _buildEntering(
    ThemeData theme,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AuthSheet._kEnterTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AuthSheet._kEnterSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(color: textSecondary),
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: textPrimary),
            cursorColor: kRed,
            decoration: InputDecoration(
              labelText: AuthSheet._kEmailLabel,
              border: const OutlineInputBorder(),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: kRed, width: 1.5),
              ),
            ),
            validator: _validateEmail,
            textInputAction:
                _passwordMode ? TextInputAction.next : TextInputAction.done,
            onFieldSubmitted: _passwordMode ? null : (_) => _onSend(),
          ),
          if (_passwordMode) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(color: textPrimary),
              cursorColor: kRed,
              decoration: InputDecoration(
                labelText: AuthSheet._kPasswordLabel,
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: kRed, width: 1.5),
                ),
              ),
              validator: _validatePassword,
              onFieldSubmitted: (_) => _onPasswordSignIn(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
          if (_info != null) ...[
            const SizedBox(height: 8),
            Text(
              _info!,
              style: AppTextStyles.caption.copyWith(color: textSecondary),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : (_passwordMode ? _onPasswordSignIn : _onSend),
              style: FilledButton.styleFrom(
                backgroundColor: kRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(_passwordMode
                      ? AuthSheet._kCtaSignIn
                      : AuthSheet._kCtaSend),
            ),
          ),
          if (!_passwordMode) ...[
            const SizedBox(height: 8),
            Text(
              AuthSheet._kSendingHint,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(color: textMuted),
            ),
          ],
          if (_passwordMode)
            TextButton(
              onPressed: _busy ? null : _onPasswordSignUp,
              child: Text(
                AuthSheet._kCtaSignUp,
                style: TextStyle(color: textPrimary),
              ),
            ),
          // Secondary toggle: magic link stays the default; this reveals the
          // password path (App Review 2.1(a)) or returns to it.
          TextButton(
            onPressed: _busy ? null : _togglePasswordMode,
            child: Text(
              _passwordMode
                  ? AuthSheet._kCtaUseMagicLink
                  : AuthSheet._kCtaUsePassword,
              style: TextStyle(color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSent(
    ThemeData theme,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
  ) {
    final body = AuthSheet._kSentBodyTemplate.replaceAll(
      '{email}',
      _sentToEmail,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Center(
          child: Icon(
            Icons.mark_email_read_outlined,
            size: 64,
            color: kRed,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          AuthSheet._kSentTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            color: textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: textSecondary),
        ),
        const SizedBox(height: 18),
        TextButton(
          onPressed: _busy ? null : _onResend,
          child: Text(
            AuthSheet._kCtaResend,
            style: TextStyle(color: textPrimary),
          ),
        ),
        if (_resendInfo != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _resendInfo!,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(color: textMuted),
            ),
          ),
        TextButton(
          onPressed: _busy ? null : _resetToEntering,
          child: Text(
            AuthSheet._kCtaChangeEmail,
            style: TextStyle(color: textSecondary),
          ),
        ),
      ],
    );
  }
}
