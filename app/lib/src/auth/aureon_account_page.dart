import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
  final _accountRecoveryId = TextEditingController();
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
    _accountRecoveryId.dispose();
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
        _accountRecoveryId.text = _profile!.accountRecoveryId;
        _firebaseApiKey.text = _profile!.firebaseApiKey;
        _firebaseProjectId.text = _profile!.firebaseProjectId;
        _firebaseAuthDomain.text = _profile!.firebaseAuthDomain;
        _firebaseAppId.text = _profile!.firebaseAppId;
        _workerUrl.text = _profile!.workerBaseUrl;
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
            if (mounted) setState(() => _status = 'This saved session does not match this Account Recovery ID. Sign in with the correct Master Account.');
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
          accountRecoveryId: AureonDiscoveryRegistryClient.generateAccountRecoveryId(),
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
          _accountRecoveryId.text = profile.accountRecoveryId;
          _status = 'Your backend configuration is saved on this device. Create/sign in to your Master Account, verify the email, then register the Account Recovery ID.';
          });
        }
      });

  Future<void> _discoverBackend() => _run(() async {
        final id = _accountRecoveryId.text.trim();
        if (id.isEmpty) throw StateError('Enter your AUREON Account Recovery ID.');
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
        final firstRegistration = _profile?.registered != true;
        var id = _profile?.accountRecoveryId ?? AureonDiscoveryRegistryClient.generateAccountRecoveryId();
        AureonBackendProfile? profile;
        for (var attempt = 0; attempt < (firstRegistration ? 5 : 1); attempt++) {
          try {
            profile = await _registry.register(
              auth: widget.auth, accountRecoveryId: id, workerBaseUrl: workerUrl,
              firebaseAuthDomain: config.authDomain, firebaseAppId: config.appId,
              expectedProfileVersion: _profile?.registered == true ? _profile!.profileVersion : null,
            );
            break;
          } on AureonDiscoveryRegistryException catch (error) {
            if (!firstRegistration || error.statusCode != 409 || attempt == 4) rethrow;
            id = AureonDiscoveryRegistryClient.generateAccountRecoveryId();
          }
        }
        if (profile == null) throw StateError('Could not reserve a unique Account Recovery ID. Please retry.');
        if (mounted) {
          setState(() {
            _profile = profile;
            _accountRecoveryId.text = profile!.accountRecoveryId;
            _status = 'Your unique Account Recovery ID is registered. Save it or its QR for new devices.';
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
              throw StateError('This Firebase account does not match the Account Recovery ID. Login was blocked.');
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

  Future<void> _scanDiscoveryQr() async {
    final scannedId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scan AUREON Account Recovery QR'),
        content: SizedBox(width: 320, height: 320, child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: MobileScanner(onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue?.trim();
              if (value != null && value.length >= 22 && value.length <= 128 &&
                  RegExp(r'^[A-Za-z0-9_-]+) {
                Navigator.of(dialogContext).pop(value);
                return;
              }
            }
          }),
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel'))],
      ),
    );
    if (!mounted || scannedId == null) return;
    _accountRecoveryId.text = scannedId;
    await _discoverBackend();
  }

  Future<void> _exportRecoveryIdText() => _run(() async {
        final id = _profile?.accountRecoveryId;
        if (id == null || id.isEmpty) throw StateError('Register an Account Recovery ID first.');
        const header = 'AUREON ACCOUNT RECOVERY ID';
        final contents = '$header\\n\\n$id\\n\\nThis ID is a locator only. It does not authenticate you or unlock your encrypted vault. Keep it separate from your password and vault recovery keys.\\n';
        final saved = await FilePicker.platform.saveFile(
          dialogTitle: 'Save AUREON Account Recovery ID',
          fileName: 'AUREON-Account-Recovery-ID.txt',
          bytes: Uint8List.fromList(utf8.encode(contents)),
        );
        if (mounted) setState(() => _status = saved == null
            ? 'TXT export cancelled.'
            : 'Account Recovery ID TXT exported.');
      });

  Future<void> _exportRecoveryQrPng() => _run(() async {
        final id = _profile?.accountRecoveryId;
        if (id == null || id.isEmpty) throw StateError('Register an Account Recovery ID first.');
        final painter = QrPainter(
          data: id,
          version: QrVersions.auto,
          errorCorrectionLevel: QrErrorCorrectLevel.H,
        );
        final image = await painter.toImageData(1024, format: ui.ImageByteFormat.png);
        if (image == null) throw StateError('Could not render the recovery QR image.');
        final saved = await FilePicker.platform.saveFile(
          dialogTitle: 'Save AUREON Recovery QR',
          fileName: 'AUREON-Account-Recovery-QR.png',
          bytes: image.buffer.asUint8List(),
        );
        if (mounted) setState(() => _status = saved == null
            ? 'QR image export cancelled.'
            : 'Account Recovery QR PNG exported.');
      });

  Future<void> _exportPrintableRecoveryCard() => _run(() async {
        final id = _profile?.accountRecoveryId;
        if (id == null || id.isEmpty) throw StateError('Register an Account Recovery ID first.');
        final document = pw.Document();
        document.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(42),
          build: (context) => pw.Center(
            child: pw.Container(
              width: 430,
              padding: const pw.EdgeInsets.all(28),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blueGrey, width: 1.5),
                borderRadius: pw.BorderRadius.circular(14),
              ),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('AUREON', style: pw.TextStyle(
                    fontSize: 25, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo,
                  )),
                  pw.SizedBox(height: 8),
                  pw.Text('ACCOUNT RECOVERY ID', style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2,
                  )),
                  pw.SizedBox(height: 22),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: id,
                    width: 190,
                    height: 190,
                    drawText: false,
                  ),
                  pw.SizedBox(height: 18),
                  pw.Text(id, textAlign: pw.TextAlign.center, style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold,
                  )),
                  pw.SizedBox(height: 18),
                  pw.Text(
                    'This ID only locates your personal backend configuration. It is not a password and cannot unlock your encrypted vault. A new device must still sign in to the matching Firebase Master Account.',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey800),
                  ),
                  pw.SizedBox(height: 14),
                  pw.Text('Store this card in a secure place.', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
          ),
        ));
        final saved = await FilePicker.platform.saveFile(
          dialogTitle: 'Save printable AUREON Recovery Card',
          fileName: 'AUREON-Account-Recovery-Card.pdf',
          bytes: await document.save(),
        );
        if (mounted) setState(() => _status = saved == null
            ? 'Printable recovery card export cancelled.'
            : 'Printable Account Recovery Card PDF exported.');
      });

  Future<void> _showDiscoveryQr() async {
    final id = _profile?.accountRecoveryId;
    if (id == null || id.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AUREON Account Recovery ID'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: id,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
              const SizedBox(height: 12),
              SelectableText(id, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'This QR contains only a locator. The new device must still sign in to the matching Firebase Master Account.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: id)),
            icon: const Icon(Icons.copy),
            label: const Text('Copy ID'),
          ),
        ],
      ),
    );
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
            'On a new device, enter the Account Recovery ID from a device where AUREON is already configured. The ID finds your public Firebase and Worker configuration; it is not a password.'),
          TextField(controller: _accountRecoveryId, autocorrect: false, decoration: const InputDecoration(
            labelText: 'AUREON Account Recovery ID', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          if (defaultTargetPlatform == TargetPlatform.android)
            OutlinedButton.icon(onPressed: _busy ? null : _scanDiscoveryQr, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan recovery QR')),
          FilledButton.icon(onPressed: _busy ? null : _discoverBackend,
            icon: const Icon(Icons.manage_search), label: const Text('Find my account')),
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
              icon: const Icon(Icons.qr_code_2), label: const Text('Create Account Recovery ID')),
          if (_profile != null)
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AUREON Account Recovery ID', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SelectableText(_profile!.accountRecoveryId, style: const TextStyle(fontSize: 12)),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _showDiscoveryQr,
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Show QR'),
                    ),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(ClipboardData(text: _profile!.accountRecoveryId)),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy ID'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _exportRecoveryIdText,
                      icon: const Icon(Icons.text_snippet_outlined),
                      label: const Text('Export TXT'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _exportRecoveryQrPng,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Export QR'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _exportPrintableRecoveryCard,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Print card'),
                    ),
                  ],
                ),
                Text('Backend profile version ${_profile!.profileVersion}. Save this ID or its QR somewhere safe for new devices.',
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
).hasMatch(value)) {
                Navigator.of(dialogContext).pop(value);
                return;
              }
            }
          }),
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel'))],
      ),
    );
    if (!mounted || scannedId == null) return;
    _accountRecoveryId.text = scannedId;
    await _discoverBackend();
  }

  Future<void> _exportRecoveryIdText() => _run(() async {
        final id = _profile?.accountRecoveryId;
        if (id == null || id.isEmpty) throw StateError('Register an Account Recovery ID first.');
        const header = 'AUREON ACCOUNT RECOVERY ID';
        final contents = '$header\\n\\n$id\\n\\nThis ID is a locator only. It does not authenticate you or unlock your encrypted vault. Keep it separate from your password and vault recovery keys.\\n';
        final saved = await FilePicker.platform.saveFile(
          dialogTitle: 'Save AUREON Account Recovery ID',
          fileName: 'AUREON-Account-Recovery-ID.txt',
          bytes: Uint8List.fromList(utf8.encode(contents)),
        );
        if (mounted) setState(() => _status = saved == null
            ? 'TXT export cancelled.'
            : 'Account Recovery ID TXT exported.');
      });

  Future<void> _exportRecoveryQrPng() => _run(() async {
        final id = _profile?.accountRecoveryId;
        if (id == null || id.isEmpty) throw StateError('Register an Account Recovery ID first.');
        final painter = QrPainter(
          data: id,
          version: QrVersions.auto,
          errorCorrectionLevel: QrErrorCorrectLevel.H,
        );
        final image = await painter.toImageData(1024, format: ui.ImageByteFormat.png);
        if (image == null) throw StateError('Could not render the recovery QR image.');
        final saved = await FilePicker.platform.saveFile(
          dialogTitle: 'Save AUREON Recovery QR',
          fileName: 'AUREON-Account-Recovery-QR.png',
          bytes: image.buffer.asUint8List(),
        );
        if (mounted) setState(() => _status = saved == null
            ? 'QR image export cancelled.'
            : 'Account Recovery QR PNG exported.');
      });

  Future<void> _exportPrintableRecoveryCard() => _run(() async {
        final id = _profile?.accountRecoveryId;
        if (id == null || id.isEmpty) throw StateError('Register an Account Recovery ID first.');
        final document = pw.Document();
        document.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(42),
          build: (context) => pw.Center(
            child: pw.Container(
              width: 430,
              padding: const pw.EdgeInsets.all(28),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blueGrey, width: 1.5),
                borderRadius: pw.BorderRadius.circular(14),
              ),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('AUREON', style: pw.TextStyle(
                    fontSize: 25, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo,
                  )),
                  pw.SizedBox(height: 8),
                  pw.Text('ACCOUNT RECOVERY ID', style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2,
                  )),
                  pw.SizedBox(height: 22),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: id,
                    width: 190,
                    height: 190,
                    drawText: false,
                  ),
                  pw.SizedBox(height: 18),
                  pw.Text(id, textAlign: pw.TextAlign.center, style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold,
                  )),
                  pw.SizedBox(height: 18),
                  pw.Text(
                    'This ID only locates your personal backend configuration. It is not a password and cannot unlock your encrypted vault. A new device must still sign in to the matching Firebase Master Account.',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey800),
                  ),
                  pw.SizedBox(height: 14),
                  pw.Text('Store this card in a secure place.', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
          ),
        ));
        final saved = await FilePicker.platform.saveFile(
          dialogTitle: 'Save printable AUREON Recovery Card',
          fileName: 'AUREON-Account-Recovery-Card.pdf',
          bytes: await document.save(),
        );
        if (mounted) setState(() => _status = saved == null
            ? 'Printable recovery card export cancelled.'
            : 'Printable Account Recovery Card PDF exported.');
      });

  Future<void> _showDiscoveryQr() async {
    final id = _profile?.accountRecoveryId;
    if (id == null || id.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AUREON Account Recovery ID'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: id,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
              const SizedBox(height: 12),
              SelectableText(id, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'This QR contains only a locator. The new device must still sign in to the matching Firebase Master Account.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: id)),
            icon: const Icon(Icons.copy),
            label: const Text('Copy ID'),
          ),
        ],
      ),
    );
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
            'On a new device, enter the Account Recovery ID from a device where AUREON is already configured. The ID finds your public Firebase and Worker configuration; it is not a password.'),
          TextField(controller: _accountRecoveryId, autocorrect: false, decoration: const InputDecoration(
            labelText: 'AUREON Account Recovery ID', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          if (defaultTargetPlatform == TargetPlatform.android)
            OutlinedButton.icon(onPressed: _busy ? null : _scanDiscoveryQr, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan recovery QR')),
          FilledButton.icon(onPressed: _busy ? null : _discoverBackend,
            icon: const Icon(Icons.manage_search), label: const Text('Find my account')),
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
              icon: const Icon(Icons.qr_code_2), label: const Text('Create Account Recovery ID')),
          if (_profile != null)
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AUREON Account Recovery ID', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SelectableText(_profile!.accountRecoveryId, style: const TextStyle(fontSize: 12)),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _showDiscoveryQr,
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Show QR'),
                    ),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(ClipboardData(text: _profile!.accountRecoveryId)),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy ID'),
                    ),
                  ],
                ),
                Text('Backend profile version ${_profile!.profileVersion}. Save this ID or its QR somewhere safe for new devices.',
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
