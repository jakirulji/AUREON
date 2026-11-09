import 'package:flutter/material.dart';

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
  final _profileName = TextEditingController();
  final _firebaseApiKey = TextEditingController();
  final _firebaseProjectId = TextEditingController();
  final _workerUrl = TextEditingController();
  final _profileStore = AureonBackendProfileStore();
  List<AureonBackendProfile> _profiles = const [];
  AureonBackendProfile? _activeProfile;
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
    _profileName.dispose();
    _firebaseApiKey.dispose();
    _firebaseProjectId.dispose();
    _workerUrl.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final profiles = await _profileStore.listProfiles();
      final active = await _profileStore.activeProfile();
      if (active != null) {
        widget.auth.configureProfile(active);
        _activeProfile = active;
        _profileName.text = active.name;
        _firebaseApiKey.text = active.firebaseApiKey;
        _firebaseProjectId.text = active.firebaseProjectId;
        _workerUrl.text = active.workerBaseUrl;
      }
      if (!mounted) return;
      setState(() => _profiles = profiles);
      if (active == null) {
        setState(() => _status = 'Add your own Firebase project and Cloudflare Worker profile. AUREON does not provide a shared default backend.');
        return;
      }
      try {
        await widget.auth.restoreSession();
        final user = await widget.auth.reloadUser();
        final bound = await _bindProfile(user.localId);
        if (mounted) {
          setState(() {
          _activeProfile = bound;
          _status = 'Signed in as ${user.email}. Backend profile “${bound.name}” is bound to this Firebase identity and Worker.';
          });
        }
      } catch (_) {
        if (mounted) setState(() => _status = 'Backend profile “${active.name}” is active. Sign in or create your AUREON account.');
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Backend profile setup needs attention: $error');
    }
  }

  Future<AureonBackendProfile> _bindProfile(String uid) async {
    try {
      final bound = await _profileStore.bindActiveProfile(uid);
      widget.auth.acceptBoundProfile(bound);
      return bound;
    } catch (_) {
      // A profile bound to another Firebase identity must never keep a live
      // session attached to the wrong Worker/backend configuration.
      await widget.auth.signOut();
      rethrow;
    }
  }

  Future<void> _saveBackendProfile() => _run(() async {
    if (widget.auth.currentUser != null) {
      throw StateError('Sign out before changing backend profiles.');
    }
    final profile = await _profileStore.saveProfile(
      name: _profileName.text,
      firebaseApiKey: _firebaseApiKey.text,
      firebaseProjectId: _firebaseProjectId.text,
      workerBaseUrl: _workerUrl.text,
    );
    widget.auth.configureProfile(profile);
    final profiles = await _profileStore.listProfiles();
    if (mounted) {
      setState(() {
      _activeProfile = profile;
      _profiles = profiles;
      _status = 'Backend profile “${profile.name}” saved locally and selected. It will be bound to your Master Account after sign-in.';
      });
    }
  });

  Future<void> _activateBackendProfile(String id) => _run(() async {
    if (widget.auth.currentUser != null) {
      throw StateError('Sign out before switching backend profiles.');
    }
    await _profileStore.activateProfile(id);
    final profile = await _profileStore.activeProfile();
    if (profile == null) throw StateError('Selected backend profile could not be loaded.');
    widget.auth.configureProfile(profile);
    if (mounted) {
      setState(() {
      _activeProfile = profile;
      _profileName.text = profile.name;
      _firebaseApiKey.text = profile.firebaseApiKey;
      _firebaseProjectId.text = profile.firebaseProjectId;
      _workerUrl.text = profile.workerBaseUrl;
      _status = 'Using backend profile “${profile.name}”.';
      });
    }
  });

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
        if (_activeProfile == null || !widget.auth.isConfigured) {
          throw StateError('Save and activate your own Firebase + Cloudflare backend profile first.');
        }
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
        final boundProfile = await _bindProfile(user.localId);
        if (mounted) {
          setState(() => _status = _createMode
              ? 'AUREON account created for ${session.user.email}. A verification email has been requested. Verify it, then tap Refresh verification status.'
              : 'Signed in as ${user.email}. Backend profile “${boundProfile.name}” is identity-bound. ${user.emailVerified ? "Email verified." : "Verify your email before cloud recovery."}');
        }
      });

  Future<void> _sendPasswordlessLink() => _run(() async {
        if (_activeProfile == null || !widget.auth.isConfigured) {
          throw StateError('Save and activate your own Firebase + Cloudflare backend profile first.');
        }
        final email = _email.text.trim();
        await widget.auth.sendPasswordlessSignInLink(email: email);
        if (mounted) {
          setState(() => _status = 'A sign-in link was sent to $email. Open the email, copy the complete link, then paste it below to finish signing in.');
        }
      });

  Future<void> _completePasswordlessSignIn() => _run(() async {
        if (_activeProfile == null || !widget.auth.isConfigured) {
          throw StateError('Save and activate your own Firebase + Cloudflare backend profile first.');
        }
        final email = _email.text.trim();
        final link = _emailLink.text.trim();
        if (link.isEmpty) throw StateError('Paste the complete sign-in link from your email.');
        final session = await widget.auth.signInWithEmailLink(email: email, emailLink: link);
        final user = await widget.auth.reloadUser();
        final boundProfile = await _bindProfile(user.localId);
        _emailLink.clear();
        if (mounted) {
          setState(() => _status = 'Passwordless sign-in completed for ${session.user.email}. Backend profile “${boundProfile.name}” is identity-bound. Email link sign-in verified the email address.');
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
        if (!widget.auth.isConfigured)
          _notice(
            Icons.settings_suggest_outlined,
            'Your own backend profile is required',
            'AUREON has no shared developer-hosted backend. Add your Firebase Web API key, Firebase project ID and your Cloudflare Worker HTTPS URL below. These are client configuration values; never enter service-account JSON, Worker Secrets or private keys.',
          ),
        const SizedBox(height: 18),
        const Text('Your backend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_profiles.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _activeProfile?.id,
            decoration: const InputDecoration(labelText: 'Saved backend profile', border: OutlineInputBorder()),
            items: _profiles.map((profile) => DropdownMenuItem(
              value: profile.id, child: Text(profile.name),
            )).toList(),
            onChanged: _busy || widget.auth.currentUser != null ? null : (id) {
              if (id != null) _activateBackendProfile(id);
            },
          ),
        const SizedBox(height: 10),
        _field(_profileName, 'Profile name (e.g. Personal)'),
        const SizedBox(height: 10),
        _field(_firebaseApiKey, 'Firebase Web API key'),
        const SizedBox(height: 10),
        _field(_firebaseProjectId, 'Firebase project ID'),
        const SizedBox(height: 10),
        _field(_workerUrl, 'Cloudflare Worker HTTPS URL', keyboardType: TextInputType.url),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _busy || widget.auth.currentUser != null ? null : _saveBackendProfile,
          icon: const Icon(Icons.cloud_done_outlined),
          label: const Text('Save & use this backend'),
        ),
        const SizedBox(height: 18),
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
            onPressed: widget.auth.isConfigured && _activeProfile != null && !_busy
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
            onPressed: widget.auth.isConfigured && _activeProfile != null && !_busy
                ? _completePasswordlessSignIn
                : null,
            icon: const Icon(Icons.login),
            label: const Text('Complete passwordless sign-in'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _createMode,
            onChanged: widget.auth.isConfigured && _activeProfile != null && !_busy
                ? (value) => setState(() => _createMode = value)
                : null,
            title: const Text('Create a new AUREON account'),
            subtitle: const Text('Otherwise, sign in to an existing account.'),
          ),
          FilledButton.icon(
            onPressed: widget.auth.isConfigured && _activeProfile != null && !_busy ? _submit : null,
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
  }) =>
      TextField(
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
