import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shows the Android notification permission state and gives the user a
/// direct way to request it again or open the system App Info settings.
class AureonPermissionsPage extends StatefulWidget {
  const AureonPermissionsPage({super.key});

  @override
  State<AureonPermissionsPage> createState() => _AureonPermissionsPageState();
}

class _AureonPermissionsPageState extends State<AureonPermissionsPage>
    with WidgetsBindingObserver {
  PermissionStatus? _notificationStatus;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!Platform.isAndroid) {
      if (mounted) {
        setState(() => _message = 'Android runtime permissions are not used on this platform.');
      }
      return;
    }
    try {
      final status = await Permission.notification.status;
      if (mounted) {
        setState(() {
          _notificationStatus = status;
          _message = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not read permission status: $error');
      }
    }
  }

  Future<void> _requestNotification() async {
    if (!Platform.isAndroid || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final status = await Permission.notification.request();
      if (!mounted) return;
      setState(() {
        _notificationStatus = status;
        _message = status.isGranted
            ? 'Notifications are enabled.'
            : status.isPermanentlyDenied
                ? 'Permission was denied. Enable notifications from Android App Settings.'
                : 'Notifications remain disabled. You can enable them at any time.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not request notification permission: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openSettings() async {
    try {
      final opened = await openAppSettings();
      if (!opened && mounted) {
        setState(() => _message = 'Android could not open AUREON App Info settings.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not open Android settings: $error');
      }
    }
  }

  String get _notificationLabel {
    final status = _notificationStatus;
    if (!Platform.isAndroid) return 'Not applicable';
    if (status == null) return 'Checking…';
    if (status.isGranted) return 'Allowed';
    if (status.isPermanentlyDenied) return 'Denied — enable in Settings';
    if (status.isRestricted) return 'Restricted by system';
    return 'Not allowed';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final granted = _notificationStatus?.isGranted == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
      children: [
        Text('App Permissions',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          'Review permissions used by AUREON. Android controls sensitive access and always lets you deny it.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: Icon(
              granted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
              color: granted ? Colors.green : scheme.primary,
            ),
            title: const Text('Notifications'),
            subtitle: Text('Status: $_notificationLabel\nUpload, download and important activity alerts'),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Refresh permission status',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!granted && Platform.isAndroid)
          FilledButton.icon(
            onPressed: _busy ? null : _requestNotification,
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(_busy ? 'Checking…' : 'Allow Notifications'),
          ),
        OutlinedButton.icon(
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Open Android App Info'),
        ),
        const SizedBox(height: 12),
        Card(
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Files and folders are selected through Android’s system file picker. AUREON does not request broad storage access just to browse or upload files. Internet and network-state access are normal Android permissions and do not show an Allow/Deny popup.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 10),
          Text(_message!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ],
    );
  }
}
