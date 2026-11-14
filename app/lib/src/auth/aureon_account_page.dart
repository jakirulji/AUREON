import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../network/aureon_network_access.dart';
import 'aureon_firebase_auth_service.dart';
import 'aureon_backend_profile.dart';

class AureonAccountPage extends StatefulWidget {
  const AureonAccountPage({super.key, required this.auth, this.onAuthChanged});

  final AureonFirebaseAuthService auth;
  final VoidCallback? onAuthChanged;

  @override
  State<AureonAccountPage> createState() => _AureonAccountPageState();
}

class _AureonAccountPageState extends State<AureonAccountPage> with WidgetsBindingObserver {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _emailLink = TextEditingController();
  bool _busy = false;
  bool _createMode = false;
  bool _obscure = true;
  bool _duplicateEmail = false;
  String _status = 'Checking saved AUREON session…';
  bool _networkUnavailable = false;
  bool _networkCheckRunning = false;
  bool _restoreInProgress = false;

  bool get _hasStrongPassword =>
      _password.text.length >= 8 &&
      RegExp(r'[A-Z]').hasMatch(_password.text) &&
      RegExp(r'[a-z]').hasMatch(_password.text) &&
      RegExp(r'[0-9]').hasMatch(_password.text) &&
      RegExp(r'[^A-Za-z0-9]').hasMatch(_password.text);

  bool get _passwordsMatch =>
      _confirmPassword.text.isNotEmpty && _password.text == _confirmPassword.text;

  bool get _validUsername =>
      RegExp(r'^[A-Za-z0-9_]{3,24}$').hasMatch(_username.text.trim());

  @override
  void initState() {
    super.initState();
    _username.addListener(_fieldChanged);
    _email.addListener(_fieldChanged);
    _password.addListener(_fieldChanged);
    _confirmPassword.addListener(_fieldChanged);
    WidgetsBinding.instance.addObserver(this);
    _checkNetworkAccess().then((reachable) {
      if (reachable) {
        _restore();
      } else if (mounted) {
        setState(() => _status = 'AUREON cannot reach Firebase. Check your internet connection and this app’s data access.');
        if (AureonNetworkAccess.isAndroid) _showNetworkHelpDialog();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNetworkAccess().then((reachable) {
        if (reachable && mounted && widget.auth.currentUser == null) _restore();
      });
    }
  }

  Future<bool> _checkNetworkAccess() async {
    if (_networkCheckRunning) return !_networkUnavailable;
    _networkCheckRunning = true;
    try {
      final reachable = await AureonNetworkAccess.canReachFirebase();
      if (mounted) setState(() => _networkUnavailable = !reachable);
      return reachable;
    } finally {
      _networkCheckRunning = false;
    }
  }

  Future<void> _showNetworkHelpDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AUREON network access is blocked'),
        content: const Text(
          'AUREON cannot reach Firebase Authentication. Check that your phone has internet access, then check this app’s Mobile data and Background data settings. If Data Saver is enabled, allow unrestricted data access for AUREON. Android requires you to change these switches manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await AureonNetworkAccess.openAppSettings();
              } on PlatformException catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not open app settings: ${error.message ?? error.code}')),
                  );
                }
              } on MissingPluginException {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('App network settings are available on Android.')),
                  );
                }
              }
            },
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open App Settings'),
          ),
        ],
      ),
    );
  }

  void _fieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _emailLink.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openOAuthGuide() async {
    final guide = await rootBundle.loadString('assets/guides/google-drive-oauth-setup.txt');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Google Drive OAuth setup & security'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: SelectableText(guide, style: const TextStyle(fontSize: 12, height: 1.45)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    if (_restoreInProgress) return;
    _restoreInProgress = true;
    try {
      final profile = AureonBackendProfile.shared;
      if (!widget.auth.isConfigured) {
        widget.auth.configureProfile(profile);
      }
      try {
        await widget.auth.restoreSession();
        final user = await widget.auth.reloadUser();
        final bound = profile.bindToUid(user.localId);
        widget.auth.acceptBoundProfile(bound);
        if (mounted) setState(() => _status = 'Signed in as ${user.email}. Connected to AUREON Central Backend.');
      } catch (_) {
        if (mounted) setState(() => _status = 'AUREON Central Backend is ready. Create an account or sign in.');
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'AUREON connection needs attention: $error');
    } finally {
      _restoreInProgress = false;
    }
  }

  Future<AureonBackendProfile> _bindProfile(String uid) async {
    final bound = AureonBackendProfile.shared.bindToUid(uid);
    widget.auth.acceptBoundProfile(bound);
    return bound;
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool requiresNetwork = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (requiresNetwork && !await _checkNetworkAccess()) {
        await _showNetworkHelpDialog();
        return;
      }
      await action();
      widget.onAuthChanged?.call();
    } catch (error) {
      if (mounted) {
        final duplicateEmail = error is AureonFirebaseAuthException &&
            error.code.startsWith('EMAIL_EXISTS');
        final networkFailure = error.toString().contains('SocketException') ||
            error.toString().contains('Failed host lookup') ||
            error.toString().contains('Connection timed out');
        setState(() {
          _duplicateEmail = duplicateEmail;
          _networkUnavailable = networkFailure || _networkUnavailable;
          _status = duplicateEmail
              ? 'Already registered with this email, please'
              : networkFailure
                  ? 'AUREON cannot reach Firebase. Check this app’s data access in Android Settings.'
                  : error.toString();
        });
        if (networkFailure) {
          await _showNetworkHelpDialog();
        } else if (!duplicateEmail) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(() async {
        final email = _email.text.trim();
        final password = _password.text;
        if (email.isEmpty || password.isEmpty) {
          throw StateError('Enter both email and password.');
        }
        if (_createMode) {
          if (!_validUsername) {
            throw StateError('Username must be 3–24 characters and use only letters, numbers or underscore.');
          }
          if (!_hasStrongPassword) {
            throw StateError('Complete every password requirement before creating your account.');
          }
          if (!_passwordsMatch) {
            throw StateError('The two passwords do not match.');
          }
        }
        final session = _createMode
            ? await widget.auth.createAccount(
                email: email,
                password: password,
                displayName: _username.text.trim(),
              )
            : await widget.auth.signIn(email: email, password: password);
        _password.clear();
        _confirmPassword.clear();
        final user = await widget.auth.reloadUser();
        await _bindProfile(user.localId);
        if (mounted) {
          setState(() => _status = _createMode
              ? 'AUREON account created for ${session.user.email}. A verification email has been requested. Verify it, then tap Refresh verification status.'
              : 'Signed in as ${user.email}. AUREON Central Backend is connected. ${user.emailVerified ? "Email verified." : "Verify your email before cloud recovery."}');
        }
      });

  Future<void> _sendPasswordReset() => _run(() async {
        final email = _email.text.trim();
        await widget.auth.sendPasswordResetEmail(email: email);
        if (mounted) {
          setState(() => _status = 'If an AUREON account exists for $email, a password-reset email has been sent. Check your inbox and spam folder.');
        }
      });

  Future<void> _sendPasswordlessLink() => _run(() async {
        final email = _email.text.trim();
        await widget.auth.sendPasswordlessSignInLink(email: email);
        if (mounted) {
          setState(() => _status = 'A sign-in link was sent to $email. Open the email, copy the complete link, then paste it below to finish signing in.');
        }
      });

  Future<void> _completePasswordlessSignIn() => _run(() async {
        final email = _email.text.trim();
        final link = _emailLink.text.trim();
        if (link.isEmpty) throw StateError('Paste the complete sign-in link from your email.');
        final session = await widget.auth.signInWithEmailLink(email: email, emailLink: link);
        final user = await widget.auth.reloadUser();
        await _bindProfile(user.localId);
        _emailLink.clear();
        if (mounted) {
          setState(() => _status = 'Passwordless sign-in completed for ${session.user.email}. AUREON Central Backend is connected. Email link sign-in verified the email address.');
        }
      });

  Future<void> _refreshVerification() => _run(() async {
        final user = await widget.auth.reloadUser();
        // Firebase ID tokens carry the email_verified claim. Force a refresh
        // after lookup so the Worker sees the updated verified claim.
        await widget.auth.getIdToken(forceRefresh: true);
        if (mounted) {
          setState(() => _status =
              '${user.email}: ${user.emailVerified ? "email verified" : "verification still pending"}.');
        }
      });

  Future<void> _resend() => _run(() async {
        await widget.auth.sendVerificationEmail();
        if (mounted) setState(() => _status = 'Verification email sent. Check your inbox and spam folder.');
      });

  Future<void> _reauthenticate() => _run(() async {
        final password = await _askPassword();
        if (password == null) return;
        final session = await widget.auth.reauthenticate(password: password);
        if (mounted) {
          setState(() => _status =
              'Reauthentication completed for ${session.user.email}. The Firebase auth_time is now fresh for protected recovery actions.');
        }
      });

  Future<String?> _askPassword() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm your password'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'AUREON account password'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Reauthenticate'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text('AUREON Master Account',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          'One AUREON identity for your linked cloud accounts, encrypted vault and device sessions.',
          style: TextStyle(color: Color(0xFF9AA8BD)),
        ),
        if (_networkUnavailable) ...[
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF3A2028),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF8A4654)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.wifi_off_rounded, color: Color(0xFFFFA6AE)),
                  SizedBox(width: 9),
                  Expanded(child: Text('Network access needs attention',
                    style: TextStyle(fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 7),
                const Text(
                  'AUREON cannot reach Firebase. Check your internet connection and allow Mobile data and Background data for AUREON in Android App Settings. Return here and the app will check again.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFD7C2C7)),
                ),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () async {
                      try {
                        await AureonNetworkAccess.openAppSettings();
                      } on PlatformException catch (error) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not open app settings: ${error.message ?? error.code}')),
                          );
                        }
                      } on MissingPluginException {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('App network settings are available on Android.')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open App Settings'),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        const SizedBox(height: 10),
        _notice(Icons.cloud_done_outlined, 'AUREON Central Backend', 'Securely connected to the official AUREON Firebase and Cloudflare services. No backend setup is required.'),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openOAuthGuide,
          icon: const Icon(Icons.key_outlined),
          label: const Text('Google Drive OAuth setup & security guide'),
        ),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 10),
        const Text('Master Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (user == null) ...[
          if (_createMode) ...[
            _field(_username, 'Username', keyboardType: TextInputType.name),
            const SizedBox(height: 5),
            const Text(
              '3–24 characters. Letters, numbers and underscore only.',
              style: TextStyle(fontSize: 11, color: Color(0xFF9AA8BD)),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Gmail / Email address',
              hintText: 'example@gmail.com',
              hintStyle: TextStyle(color: Color(0xFF66758D)),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: _createMode ? 'Create password' : 'Password',
              border: const OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _createMode && !_hasStrongPassword
                      ? const Color(0xFFE05260)
                      : const Color(0xFF66758D),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _createMode && !_hasStrongPassword
                      ? const Color(0xFFE05260)
                      : const Color(0xFF64E6C2),
                  width: 1.6,
                ),
              ),
            ),
          ),
          if (_createMode) ...[
            const SizedBox(height: 10),
            _passwordCriteria(),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmPassword,
              obscureText: _obscure,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Confirm password',
                errorText: _confirmPassword.text.isEmpty || _passwordsMatch
                    ? null
                    : 'Passwords do not match',
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: _confirmPassword.text.isNotEmpty && !_passwordsMatch
                        ? const Color(0xFFE05260)
                        : const Color(0xFF66758D),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: _confirmPassword.text.isNotEmpty && !_passwordsMatch
                        ? const Color(0xFFE05260)
                        : const Color(0xFF64E6C2),
                    width: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : () => setState(() {
                  _createMode = false;
                  _duplicateEmail = false;
                  _password.clear();
                  _confirmPassword.clear();
                }),
                child: const Text('Back to sign in'),
              ),
            ),
            FilledButton.icon(
              onPressed: widget.auth.isConfigured &&
                      !_busy &&
                      _validUsername &&
                      _hasStrongPassword &&
                      _passwordsMatch &&
                      _email.text.trim().contains('@')
                  ? _submit
                  : null,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Create AUREON account'),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: widget.auth.isConfigured && !_busy
                      ? _sendPasswordReset
                      : null,
                  child: const Text('Forgot password?'),
                ),
                TextButton(
                  onPressed: widget.auth.isConfigured && !_busy
                      ? () => setState(() {
                          _createMode = true;
                          _duplicateEmail = false;
                          _status = 'Create your AUREON Master Account.';
                        })
                      : null,
                  child: const Text('Create account'),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                label: Text(_obscure ? 'Show password' : 'Hide password'),
              ),
            ),
            FilledButton.icon(
              onPressed: widget.auth.isConfigured && !_busy ? _submit : null,
              icon: const Icon(Icons.login),
              label: const Text('Sign in'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.auth.isConfigured && !_busy
                  ? _sendPasswordlessLink
                  : null,
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('Send passwordless sign-in link'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailLink,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Paste sign-in link from email',
                helperText: 'Use the same email address above. The link is one-time and expires.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: widget.auth.isConfigured && !_busy
                  ? _completePasswordlessSignIn
                  : null,
              icon: const Icon(Icons.login),
              label: const Text('Complete passwordless sign-in'),
            ),
          ],
        ] else ...[
          _notice(
            user.emailVerified ? Icons.verified_user_outlined : Icons.mark_email_unread_outlined,
            user.email,
            user.emailVerified
                ? 'Email verified. Cloud vault operations can use this account.'
                : 'Email verification is required before Cloudflare vault operations.',
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refreshVerification,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh verification status'),
          ),
          if (!user.emailVerified)
            OutlinedButton.icon(
              onPressed: _busy ? null : _resend,
              icon: const Icon(Icons.mark_email_unread_outlined),
              label: const Text('Resend verification email'),
            ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reauthenticate,
            icon: const Icon(Icons.lock_reset),
            label: const Text('Reauthenticate for protected recovery'),
          ),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await widget.auth.signOut();
                      if (mounted) setState(() => _status = 'Signed out locally on this device. Firebase server-side refresh-token revocation is not performed by this action.');
                    }, requiresNetwork: false),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111A2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF26334A)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF64E6C2)),
              const SizedBox(width: 10),
              Expanded(
                child: _duplicateEmail
                    ? Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(_status, style: const TextStyle(fontSize: 12)),
                          InkWell(
                            onTap: _busy ? null : () => setState(() {
                              _createMode = false;
                              _duplicateEmail = false;
                              _password.clear();
                              _status = 'Sign in to your existing AUREON account.';
                            }),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                              child: Text(
                                'login',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8B7CFF),
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const Text('.', style: TextStyle(fontSize: 12)),
                        ],
                      )
                    : Text(_status, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        if (_busy) const Padding(
          padding: EdgeInsets.only(top: 12),
          child: LinearProgressIndicator(),
        ),
      ],
    );
  }

  Widget _passwordCriteria() {
    final password = _password.text;
    final checks = <({String label, bool valid})>[
      (label: 'At least 8 characters', valid: password.length >= 8),
      (label: 'One uppercase letter (A–Z)', valid: RegExp(r'[A-Z]').hasMatch(password)),
      (label: 'One lowercase letter (a–z)', valid: RegExp(r'[a-z]').hasMatch(password)),
      (label: 'One number (0–9)', valid: RegExp(r'[0-9]').hasMatch(password)),
      (label: 'One special character (!@#…)', valid: RegExp(r'[^A-Za-z0-9]').hasMatch(password)),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111A2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _hasStrongPassword
              ? const Color(0xFF64E6C2)
              : const Color(0xFFE05260),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Password requirements',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 7),
          for (final check in checks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    check.valid ? Icons.check_circle : Icons.cancel,
                    size: 15,
                    color: check.valid
                        ? const Color(0xFF64E6C2)
                        : const Color(0xFFE05260),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    check.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: check.valid
                          ? const Color(0xFF64E6C2)
                          : const Color(0xFFE05260),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    TextInputType? keyboardType,
  }) => TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _notice(IconData icon, String title, String body) => Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF26334A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF64E6C2)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(body, style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BD))),
                ],
              ),
            ),
          ],
        ),
      );
}
