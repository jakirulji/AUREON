import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aureon_firebase_auth_service.dart';
import 'aureon_backend_profile_cache.dart';

class AureonAccountPage extends StatefulWidget {
  const AureonAccountPage({super.key, required this.auth});

  final AureonFirebaseAuthService auth;

  @override
  State<AureonAccountPage> createState() => _AureonAccountPageState();
}

class _AureonAccountPageState extends State<AureonAccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _discoveryId = TextEditingController();
  final _firebaseApiKey = TextEditingController(text: const String.fromEnvironment('AUREON_FIREBASE_API_KEY'));
  final _firebaseProjectId = TextEditingController(text: const String.fromEnvironment('AUREON_FIREBASE_PROJECT_ID'));
  final _firebaseAuthDomain = TextEditingController(text: const String.fromEnvironment('AUREON_FIREBASE_AUTH_DOMAIN'));
  final _firebaseAppId = TextEditingController(text: const String.fromEnvironment('AUREON_FIREBASE_APP_ID'));
  final _workerUrl = TextEditingController(text: const String.fromEnvironment('AUREON_CLOUDFLARE_API_URL'));
  final _profileCache = AureonBackendProfileCache();
  final _registry = AureonDiscoveryRegistryClient();
  AureonBackendProfile? _profile;
  bool _busy = false;
  bool _createMode = false;
  bool _obscure = true;
  bool _needsBindingVerification = false;
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
    _discoveryId.dispose();
    _firebaseApiKey.dispose();
    _firebaseProjectId.dispose();
    _firebaseAuthDomain.dispose();
    _firebaseAppId.dispose();
    _workerUrl.dispose();
    _registry.close();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      _profile = await _profileCache.read();
      if (_profile != null) {
        _discoveryId.text = _profile!.discoveryId;
        // Discovery lookup may have happened immediately before the app was
        // closed. Re-arm the owner-binding check after process restart so a
        // cached locator can never silently bypass Firebase issuer + UID
        // verification on the next interactive sign-in.
        _needsBindingVerification = _profile!.registered;
        if (!widget.auth.isConfigured) widget.auth.configure(_profile!.firebaseConfig);
      }
    } catch (_) {
      // A malformed cache is ignored; manual discovery remains available.
    }
    if (!widget.auth.isConfigured) {
      setState(() => _status =
          'Firebase is not configured yet. The app is ready for the owner-provisioned Firebase project; no account or password is required in this preview.');
      return;
    }
    try {
      await widget.auth.restoreSession();
      final user = await widget.auth.reloadUser();
      if (_profile?.registered == true && _needsBindingVerification) {
        try {
          await _registry.verifyBinding(auth: widget.auth, profile: _profile!);
          _needsBindingVerification = false;
        } on AureonDiscoveryRegistryException catch (error) {
          if (error.statusCode == 403) {
            await widget.auth.signOut();
            if (mounted) setState(() => _status = 'This saved session does not match this Discovery ID. Sign in with the correct Master Account.');
            return;
          }
          widget.auth.lockSession();
          if (mounted) setState(() => _status = 'Session is saved, but owner verification is pending. Connect to the internet and retry sign-in; the refresh token has been preserved.');
          return;
        } catch (_) {
          widget.auth.lockSession();
          if (mounted) setState(() => _status = 'Owner verification is temporarily unavailable. The session is locked and its refresh token is preserved; reconnect and sign in again.');
          return;
        }
      }
      if (mounted) {
        setState(() => _status =
            'Signed in as ${user.email}. Email verification: ${user.emailVerified ? "verified" : "pending"}.');
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'No active session. Sign in or create your AUREON account.');
    }
  }



  Future<void> _saveBackendConfiguration() => _run(() async {
        final apiKey = _firebaseApiKey.text.trim();
        final projectId = _firebaseProjectId.text.trim();
        final authDomain = _firebaseAuthDomain.text.trim();
        final appId = _firebaseAppId.text.trim();
        final worker = Uri.tryParse(_workerUrl.text.trim());
        if (apiKey.length < 20 || projectId.isEmpty || authDomain.isEmpty || appId.isEmpty) {
          throw StateError('Enter the Firebase Web API key, project ID, auth domain and app ID.');
        }
        if (worker == null || worker.scheme != 'https' || worker.host.isEmpty ||
            worker.userInfo.isNotEmpty || worker.query.isNotEmpty || worker.fragment.isNotEmpty ||
            (worker.path.isNotEmpty && worker.path != '/')) {
          throw StateError('Enter your Cloudflare Worker HTTPS origin, without a path.');
        }
        final profile = AureonBackendProfile(
          discoveryId: AureonDiscoveryRegistryClient.generateDiscoveryId(),
          firebaseApiKey: apiKey,
          firebaseProjectId: projectId,
          firebaseAuthDomain: authDomain,
          firebaseAppId: appId,
          workerBaseUrl: worker.origin,
          profileVersion: 0,
          registered: false,
        );
        await _profileCache.write(profile);
        widget.auth.configure(profile.firebaseConfig);
        if (mounted) {
          setState(() {
          _profile = profile;
          _discoveryId.text = profile.discoveryId;
          _status = 'Your backend configuration is saved on this device. Create/sign in to your Master Account, verify the email, then register the Discovery ID.';
          });
        }
      });

  Future<void> _discoverBackend() => _run(() async {
        final id = _discoveryId.text.trim();
        if (id.isEmpty) throw StateError('Enter your AUREON Discovery ID.');
        final profile = await _registry.discover(id);
        widget.auth.configure(profile.firebaseConfig);
        if (mounted) {
          setState(() {
          _profile = profile;
          _needsBindingVerification = true;
          _status = 'Backend profile found and saved on this device. Now sign in to your Master Account.';
          });
        }
      });

  Future<void> _registerBackend() => _run(() async {
        final user = widget.auth.currentUser;
        if (user == null || !user.emailVerified) {
          throw StateError('Verify your Master Account email before registering discovery.');
        }
        final workerUrl = _profile?.workerBaseUrl ?? const String.fromEnvironment('AUREON_CLOUDFLARE_API_URL');
        final config = widget.auth.config;
        if (workerUrl.isEmpty || config.authDomain.isEmpty || config.appId.isEmpty) {
          throw StateError('This first-device build needs AUREON_CLOUDFLARE_API_URL, AUREON_FIREBASE_AUTH_DOMAIN and AUREON_FIREBASE_APP_ID.');
        }
        final id = _profile?.discoveryId ?? AureonDiscoveryRegistryClient.generateDiscoveryId();
        final profile = await _registry.register(
          auth: widget.auth, discoveryId: id, workerBaseUrl: workerUrl,
          firebaseAuthDomain: config.authDomain, firebaseAppId: config.appId,
          expectedProfileVersion: _profile?.registered == true ? _profile!.profileVersion : null,
        );
        if (mounted) {
          setState(() {
          _profile = profile;
          _discoveryId.text = profile.discoveryId;
          _status = 'Discovery profile registered. Save this Discovery ID for new devices.';
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
        if (_profile?.registered == true && _needsBindingVerification) {
          try {
            await _registry.verifyBinding(auth: widget.auth, profile: _profile!);
            _needsBindingVerification = false;
          } on AureonDiscoveryRegistryException catch (error) {
            if (error.statusCode == 403) {
              await widget.auth.signOut();
              throw StateError('This Firebase account does not match the Discovery ID. Login was blocked.');
            }
            widget.auth.lockSession();
            throw StateError('Owner verification is temporarily unavailable. Your saved refresh token was preserved; reconnect and sign in again.');
          } catch (_) {
            widget.auth.lockSession();
            throw StateError('Owner verification could not be completed. Your saved refresh token was preserved; reconnect and sign in again.');
          }
        }
        if (mounted) {
          setState(() => _status = _createMode
              ? 'AUREON account created for ${session.user.email}. A verification email has been requested. Verify it, then tap Refresh verification status.'
              : 'Signed in as ${user.email}. ${user.emailVerified ? "Email verified." : "Verify your email before cloud recovery."}');
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
    final needsBackendSetup = !widget.auth.isConfigured || (_profile == null &&
        (widget.auth.config.authDomain.isEmpty || widget.auth.config.appId.isEmpty || _workerUrl.text.trim().isEmpty));
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
        if (needsBackendSetup) ...[
          _notice(Icons.settings_suggest_outlined, 'Find your Master Account backend',
            'On a new device, enter the Discovery ID from a device where AUREON is already configured. The ID finds your public Firebase and Worker configuration; it is not a password.'),
          TextField(controller: _discoveryId, autocorrect: false, decoration: const InputDecoration(
            labelText: 'AUREON Discovery ID', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _busy ? null : _discoverBackend,
            icon: const Icon(Icons.manage_search), label: const Text('Find my backend')),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 10),
          const Text('New to AUREON? Configure your own backend', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _field(_firebaseApiKey, 'Firebase Web API key'),
          const SizedBox(height: 8),
          _field(_firebaseProjectId, 'Firebase project ID'),
          const SizedBox(height: 8),
          _field(_firebaseAuthDomain, 'Firebase auth domain'),
          const SizedBox(height: 8),
          _field(_firebaseAppId, 'Firebase app ID'),
          const SizedBox(height: 8),
          _field(_workerUrl, 'Your Cloudflare Worker HTTPS URL'),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _busy ? null : _saveBackendConfiguration,
            icon: const Icon(Icons.save_outlined), label: const Text('Save my backend configuration')),
          const SizedBox(height: 16),
        ],
        if (user == null && widget.auth.isConfigured) ...[
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
        ] else if (user != null) ...[
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
          if (_profile?.registered != true)
            OutlinedButton.icon(onPressed: _busy ? null : _registerBackend,
              icon: const Icon(Icons.qr_code_2), label: const Text('Create / register Discovery ID')),
          if (_profile != null)
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AUREON Discovery ID', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SelectableText(_profile!.discoveryId, style: const TextStyle(fontSize: 12)),
                Align(alignment: Alignment.centerRight, child: TextButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: _profile!.discoveryId)),
                  icon: const Icon(Icons.copy), label: const Text('Copy ID'))),
                Text('Backend profile version ${_profile!.profileVersion}. Keep this ID for new devices.',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9AA8BD))),
              ]))),
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
