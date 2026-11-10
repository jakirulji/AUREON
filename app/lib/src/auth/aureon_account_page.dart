import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'aureon_firebase_auth_service.dart';
import 'aureon_backend_profile.dart';

class AureonAccountPage extends StatefulWidget {
  const AureonAccountPage({super.key, required this.auth});

  final AureonFirebaseAuthService auth;

  @override
  State<AureonAccountPage> createState() => _AureonAccountPageState();
}

class _AureonAccountPageState extends State<AureonAccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailLink = TextEditingController();
  bool _busy = false;
  bool _createMode = false;
  bool _obscure = true;
  String _status = 'Checking saved AUREON session…';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailLink.dispose();
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
    }
  }

  Future<AureonBackendProfile> _bindProfile(String uid) async {
    final bound = AureonBackendProfile.shared.bindToUid(uid);
    widget.auth.acceptBoundProfile(bound);
    return bound;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _status = error.toString());
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
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
        _password.clear();
        final session = _createMode
            ? await widget.auth.createAccount(email: email, password: password)
            : await widget.auth.signIn(email: email, password: password);
        final user = await widget.auth.reloadUser();
        await _bindProfile(user.localId);
        if (mounted) {
          setState(() => _status = _createMode
              ? 'AUREON account created for ${session.user.email}. A verification email has been requested. Verify it, then tap Refresh verification status.'
              : 'Signed in as ${user.email}. AUREON Central Backend is connected. ${user.emailVerified ? "Email verified." : "Verify your email before cloud recovery."}');
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
        final boundProfile = await _bindProfile(user.localId);
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
          _field(_email, 'Email address', keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _field(_password, 'Password', obscure: _obscure),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              label: Text(_obscure ? 'Show password' : 'Hide password'),
            ),
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
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _createMode,
            onChanged: widget.auth.isConfigured && !_busy
                ? (value) => setState(() => _createMode = value)
                : null,
            title: const Text('Create a new AUREON account'),
            subtitle: const Text('Otherwise, sign in to an existing account.'),
          ),
          FilledButton.icon(
            onPressed: widget.auth.isConfigured && !_busy ? _submit : null,
            icon: Icon(_createMode ? Icons.person_add_alt_1 : Icons.login),
            label: Text(_createMode ? 'Create account' : 'Sign in'),
          ),
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
                    }),
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
              Expanded(child: Text(_status, style: const TextStyle(fontSize: 12))),
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
