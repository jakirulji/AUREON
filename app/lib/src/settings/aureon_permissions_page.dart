import 'dart:io';

import 'package:aureon_local_files/aureon_local_files.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shows Android permission states and opens the appropriate system UI.
/// All-files access is special app access, not a runtime Allow/Deny dialog.
class AureonPermissionsPage extends StatefulWidget {
  const AureonPermissionsPage({super.key});

  @override
  State<AureonPermissionsPage> createState() => _AureonPermissionsPageState();
}

class _AureonPermissionsPageState extends State<AureonPermissionsPage>
    with WidgetsBindingObserver {
  final AureonLocalFiles _files = AureonLocalFiles();
  PermissionStatus? _notificationStatus;
  bool? _allFilesAccess;
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
        setState(() {
          _message = 'Android permissions are not used on this platform.';
        });
      }
      return;
    }
    try {
      final results = await Future.wait<Object?>([
        Permission.notification.status,
        _files.hasAllFilesAccess(),
      ]);
      if (mounted) {
        setState(() {
          _notificationStatus = results[0] as PermissionStatus;
          _allFilesAccess = results[1] == true;
          _message = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Could not read permission status: $error';
        });
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
        setState(() {
          _message = 'Could not request notification permission: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _requestAllFilesAccess() async {
    if (!Platform.isAndroid || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final granted = await _files.requestAllFilesAccess();
      if (!mounted) return;
      setState(() {
        _allFilesAccess = granted;
        _message = granted
            ? 'All files access is enabled. AUREON can browse shared internal storage.'
            : 'All files access is still off. Enable “Allow access to manage all files” on the Android screen.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Could not open All files access settings: $error';
        });
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
        setState(() {
          _message = 'Android could not open AUREON App Info settings.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Could not open Android settings: $error';
        });
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

  String get _allFilesLabel {
    if (!Platform.isAndroid) return 'Not applicable';
    if (_allFilesAccess == null) return 'Checking…';
    return _allFilesAccess! ? 'Allowed' : 'Not allowed';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notificationGranted = _notificationStatus?.isGranted == true;
    final allFilesGranted = _allFilesAccess == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
      children: [
        Text(
          'App Permissions',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Review the access AUREON uses. Sensitive access is controlled by Android, and you can deny or revoke it at any time.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: Icon(
              allFilesGranted ? Icons.folder_special_outlined : Icons.folder_off_outlined,
              color: allFilesGranted ? Colors.green : scheme.primary,
            ),
            title: const Text('All files access'),
            subtitle: Text(
              'Status: $_allFilesLabel\nBrowse, organize, rename, move and manage shared internal-storage files.',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Refresh permission status',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
        if (!allFilesGranted && Platform.isAndroid)
          FilledButton.icon(
            onPressed: _busy ? null : _requestAllFilesAccess,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(_busy ? 'Opening…' : 'Allow access to manage all files'),
          ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(
              notificationGranted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              color: notificationGranted ? Colors.green : scheme.primary,
            ),
            title: const Text('Notifications'),
            subtitle: Text(
              'Status: $_notificationLabel\nTransfer progress, completion and important activity alerts.',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Refresh permission status',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
        if (!notificationGranted && Platform.isAndroid)
          FilledButton.icon(
            onPressed: _busy ? null : _requestNotification,
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(_busy ? 'Requesting…' : 'Allow Notifications'),
          ),
        const SizedBox(height: 8),
        Card(
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Network access', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text(
                  'Internet and network-state access are normal Android permissions. Android grants them from the app manifest, so they do not have an Allow/Deny popup and are not listed as runtime permissions.',
                  style: TextStyle(fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Why is All files access different? Android treats it as Special App Access. AUREON opens the dedicated Android settings screen; you must turn on “Allow access to manage all files” there. Android may still restrict protected areas such as Android/data and Android/obb, even when this access is enabled.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Open Android App Info'),
        ),
        if (_message != null) ...[
          const SizedBox(height: 10),
          Text(
            _message!,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
