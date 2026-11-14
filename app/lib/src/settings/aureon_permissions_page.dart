import 'dart:io';

import 'package:aureon_local_files/aureon_local_files.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

/// Displays real Android access states and links to the system-controlled screens.
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
  bool? _batteryExempt;
  bool? _canInstall;
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
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _message = 'Android-specific permissions are not used on this platform.');
      return;
    }
    try {
      final values = await Future.wait<Object?>([
        Permission.notification.status,
        _files.hasAllFilesAccess(),
        _files.hasBatteryOptimizationExemption(),
        _files.canInstallPackages(),
      ]);
      if (!mounted) return;
      setState(() {
        _notificationStatus = values[0] as PermissionStatus;
        _allFilesAccess = values[1] == true;
        _batteryExempt = values[2] == true;
        _canInstall = values[3] == true;
        _message = null;
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not read Android access status: $error');
    }
  }

  Future<void> _runAction(Future<void> Function() action, String successMessage) async {
    if (!Platform.isAndroid || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
      if (mounted) setState(() => _message = successMessage);
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not open the Android permission screen: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestNotification() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await Permission.notification.request();
      if (mounted) {
        setState(() {
          _notificationStatus = status;
          _message = status.isGranted
              ? 'Notifications are enabled.'
              : 'Notifications remain disabled. You can enable them in Android App Info.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not request notifications: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _status(bool? value) => value == null ? 'Checking…' : value ? 'Allowed' : 'Not allowed';

  String get _notificationLabel {
    final status = _notificationStatus;
    if (status == null) return 'Checking…';
    if (status.isGranted) return 'Allowed';
    if (status.isPermanentlyDenied) return 'Denied — enable in Settings';
    if (status.isRestricted) return 'Restricted by system';
    return 'Not allowed';
  }

  Widget _accessCard({
    required IconData icon,
    required String title,
    required String status,
    required String description,
    required String actionLabel,
    required VoidCallback onAction,
    bool granted = false,
    bool showAction = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: granted ? Colors.green : scheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(status, style: TextStyle(
                color: granted ? Colors.green : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              )),
            ]),
            const SizedBox(height: 7),
            Text(description, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4)),
            if (showAction) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : onAction,
                icon: const Icon(Icons.settings_outlined),
                label: Text(_busy ? 'Opening…' : actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notificationGranted = _notificationStatus?.isGranted == true;
    final allFilesGranted = _allFilesAccess == true;
    final batteryExempt = _batteryExempt == true;
    final canInstall = _canInstall == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
      children: [
        Text('App Permissions', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'AUREON shows the actual Android status for sensitive access. Android controls the final Allow/Deny decision; you can revoke access at any time.',
          style: TextStyle(fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 18),
        _accessCard(
          icon: Icons.folder_special_outlined,
          title: 'All files access',
          status: _status(_allFilesAccess),
          description: 'Browse, organize, copy, move, rename and manage shared internal-storage files. Android may still protect Android/data and Android/obb.',
          actionLabel: 'Manage all files access',
          onAction: () => _runAction(() async { await _files.requestAllFilesAccess(); }, 'Returned from All files access settings.'),
          granted: allFilesGranted,
          showAction: !allFilesGranted,
        ),
        _accessCard(
          icon: Icons.notifications_active_outlined,
          title: 'Notifications',
          status: _notificationLabel,
          description: 'Transfer progress, completion, scheduled-task and important activity alerts.',
          actionLabel: 'Allow notifications',
          onAction: _requestNotification,
          granted: notificationGranted,
          showAction: !notificationGranted,
        ),
        _accessCard(
          icon: Icons.battery_saver_outlined,
          title: 'Battery optimization exemption',
          status: _status(_batteryExempt),
          description: 'Optional. Exemption can reduce Doze interruptions for long-running work, but increases battery use. Android may still apply manufacturer-specific background limits.',
          actionLabel: 'Open battery optimization prompt',
          onAction: () => _runAction(
            _files.requestBatteryOptimizationExemption,
            'Battery optimization settings opened. Return here to refresh the status.',
          ),
          granted: batteryExempt,
          showAction: !batteryExempt,
        ),
        _accessCard(
          icon: Icons.install_mobile_outlined,
          title: 'Install unknown apps',
          status: _status(_canInstall),
          description: 'Allows AUREON to open APK files with Android Package Installer. Android will show a separate confirmation before an app is installed.',
          actionLabel: 'Allow APK installation',
          onAction: () => _runAction(
            _files.requestInstallPackagesAccess,
            'Install unknown apps settings opened. Return here to refresh the status.',
          ),
          granted: canInstall,
          showAction: !canInstall,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('Automatically granted manifest permissions', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text(
                'Internet, network-state, foreground data-sync service, wake lock and reboot rescheduling are declared for their corresponding features. Android treats these as normal or service permissions, not ordinary Allow/Deny runtime prompts.',
                style: TextStyle(fontSize: 12, height: 1.45),
              ),
            ]),
          ),
        ),
        OutlinedButton.icon(
          onPressed: openAppSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Open Android App Info'),
        ),
        IconButton(
          tooltip: 'Refresh permission status',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ],
    );
  }
}
