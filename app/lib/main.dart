import 'package:aureon/src/auth/aureon_account_page.dart';
import 'package:aureon/src/auth/aureon_firebase_auth_service.dart';
import 'package:aureon/src/auth/aureon_backend_profile.dart';
import 'package:aureon/src/files/aureon_files_page.dart';
import 'package:aureon/src/home/aureon_home_page.dart';
import 'package:aureon/src/transfers/aureon_transfers_page.dart';
import 'package:aureon/src/backup/aureon_backup_page.dart';
import 'package:aureon/src/virtual_folders/aureon_virtual_folders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/media/aureon_media_viewer.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey<NavigatorState> _aureonNavigatorKey = GlobalKey<NavigatorState>();
const MethodChannel _openWithChannel = MethodChannel('aureon/open_with');

void _openWithPayload(Map<String, dynamic> payload) {
  final kind = payload['kind'] as String?;
  final path = payload['path'] as String?;
  final name = payload['name'] as String? ?? 'Media';
  if (kind == null || path == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final navigator = _aureonNavigatorKey.currentState;
    if (navigator == null) return;
    if (kind == 'image') {
      navigator.push(MaterialPageRoute<void>(builder: (_) => AureonImageViewerPage(
        images: [AureonMediaItem(path: path, title: name)], initialIndex: 0,
      )));
    } else if (kind == 'video' || kind == 'audio') {
      navigator.push(MaterialPageRoute<void>(builder: (_) => AureonMediaViewerPage(
        filePath: path, fileName: name,
        queue: [AureonMediaItem(path: path, title: name)],
        initialIndex: 0, isVideo: kind == 'video',
      )));
    }
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const AureonApp());
}

class AureonApp extends StatefulWidget {
  const AureonApp({super.key});

  @override
  State<AureonApp> createState() => _AureonAppState();
}

class _AureonAppState extends State<AureonApp> {
  static const _themePreferenceKey = 'aureon.theme_mode';
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _restoreTheme();
    _openWithChannel.setMethodCallHandler((call) async {
      if (call.method == 'openWith' && call.arguments is Map) {
        _openWithPayload(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
    _restorePendingOpenWith();
  }

  Future<void> _restorePendingOpenWith() async {
    try {
      final payload = await _openWithChannel.invokeMapMethod<String, dynamic>('getPendingOpenWith');
      if (payload != null) _openWithPayload(payload);
    } catch (_) {
      // Open-with channel is only installed on Android.
    }
  }

  Future<void> _restoreTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_themePreferenceKey);
      if (!mounted || saved == null) return;
      setState(() => _themeMode = saved == 'light' ? ThemeMode.light : ThemeMode.dark);
    } catch (_) {
      // Keep the premium dark default if local preferences are unavailable.
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themePreferenceKey, mode == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {
      // The selected theme remains active for this app session.
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AUREON',
    navigatorKey: _aureonNavigatorKey,
    debugShowCheckedModeBanner: false,
    themeMode: _themeMode,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF4F6FC),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6755D9),
        brightness: Brightness.light,
        surface: Colors.white,
      ),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF090F20),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8B7CFF),
        brightness: Brightness.dark,
        surface: const Color(0xFF111A2E),
      ),
    ),
    home: AureonHome(
      themeMode: _themeMode,
      onThemeChanged: _setThemeMode,
    ),
  );
}

class AureonHome extends StatefulWidget {
  const AureonHome({super.key, required this.themeMode, required this.onThemeChanged});
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  @override
  State<AureonHome> createState() => _AureonHomeState();
}

class _AureonHomeState extends State<AureonHome> {
  final _auth = AureonFirebaseAuthService();
  int selected = 0;
  String? _fileCategory;

  @override
  void initState() {
    super.initState();
    _auth.configureProfile(AureonBackendProfile.shared);
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      await _auth.restoreSession();
      final user = await _auth.reloadUser();
      _auth.acceptBoundProfile(AureonBackendProfile.shared.bindToUid(user.localId));
      if (mounted) setState(() {});
    } catch (_) {
      // First launch or temporary network issue; Account page offers sign-in.
    }
  }

  static const labels = ['Home', 'Browse', 'Cloud', 'Settings'];
  static const icons = [
    Icons.home_outlined,
    Icons.folder_outlined,
    Icons.cloud_outlined,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final wide = constraints.maxWidth >= 760;
    return PopScope<Object?>(
      canPop: selected == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selected != 0 && mounted) {
          setState(() {
            selected = 0;
            _fileCategory = null;
          });
        }
      },
      child: Scaffold(
        body: SafeArea(child: Row(children: [
          if (wide) _sidebar(),
          Expanded(child: _content()),
        ])),
        bottomNavigationBar: wide ? null : NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (value) => setState(() {
            selected = value;
            if (value == 1) _fileCategory = null;
          }),
          destinations: List.generate(labels.length,
            (i) => NavigationDestination(icon: Icon(icons[i]), label: labels[i])),
        ),
      ),
    );
  });

  Widget _sidebar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 230,
      padding: const EdgeInsets.fromLTRB(18, 24, 12, 18),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.all_inclusive, color: Color(0xFF8B7CFF), size: 30),
          SizedBox(width: 10),
          Text('AUREON', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 40, top: 6),
          child: Text('YOUR DIGITAL UNIVERSE',
            style: TextStyle(fontSize: 9, letterSpacing: 1.2, color: scheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 34),
        for (var i = 0; i < labels.length; i++)
          Material(
            color: Colors.transparent,
            child: ListTile(
              dense: true,
              selected: selected == i,
              selectedTileColor: scheme.primaryContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: Icon(icons[i], color: selected == i ? scheme.primary : scheme.onSurfaceVariant),
              title: Text(labels[i], style: TextStyle(fontSize: 13,
                color: selected == i ? scheme.onPrimaryContainer : scheme.onSurface)),
              onTap: () => setState(() {
                selected = i;
                if (i == 1) _fileCategory = null;
              }),
            ),
          ),
        const Spacer(),
        Divider(color: scheme.outlineVariant),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: scheme.secondaryContainer,
            child: Icon(_auth.currentUser == null ? Icons.person_outline : Icons.verified_user_outlined,
              color: scheme.primary),
          ),
          title: Text(_auth.currentUser?.email ?? 'Local profile', style: const TextStyle(fontSize: 12)),
          subtitle: Text(_auth.currentUser == null ? 'Not signed in' :
            (_auth.currentUser!.emailVerified ? 'Verified account' : 'Verify email'),
            style: const TextStyle(fontSize: 11)),
          onTap: _openAccount,
        ),
      ]),
    );
  }

  void _openAccount() => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('AUREON Account')),
      body: AureonAccountPage(auth: _auth),
    ),
  ));

  void _openBackup() => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: AureonBackupPage(auth: _auth),
    ),
  ));

  Widget _settingsPage() {
    final dark = widget.themeMode == ThemeMode.dark;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('Personalize and manage your AUREON experience.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 20),
        Card(child: SwitchListTile(
          secondary: Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: scheme.primary),
          title: const Text('Dark appearance'),
          subtitle: Text(dark ? 'Dark theme is enabled' : 'Light theme is enabled'),
          value: dark,
          onChanged: (value) => widget.onThemeChanged(value ? ThemeMode.dark : ThemeMode.light),
        )),
        const SizedBox(height: 10),
        Card(child: ListTile(
          leading: Icon(Icons.person_outline_rounded, color: scheme.primary),
          title: const Text('AUREON Account'),
          subtitle: const Text('Sign in and manage your account'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _openAccount,
        )),
        Card(child: ListTile(
          leading: Icon(Icons.backup_rounded, color: scheme.primary),
          title: const Text('Backup & Restore'),
          subtitle: const Text('Manage backup and recovery'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _openBackup,
        )),
        Card(child: ListTile(
          leading: Icon(Icons.swap_vert_rounded, color: scheme.primary),
          title: const Text('Transfers'),
          subtitle: const Text('View upload and download activity'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Transfers')),
              body: AureonTransfersPage(),
            ),
          )),
        )),
      ],
    );
  }

  Widget _content() {
    switch (selected) {
      case 0:
        return AureonHomePage(
          isDarkMode: widget.themeMode == ThemeMode.dark,
          onBrowseCategory: (category) => setState(() {
            _fileCategory = category;
            selected = 1;
          }),
          onOpenFiles: () => setState(() {
            _fileCategory = null;
            selected = 1;
          }),
          onOpenProfile: () => setState(() => selected = 3),
          onOpenCloud: () => setState(() => selected = 2),
        );
      case 1:
        return AureonFilesPage(initialCategory: _fileCategory);
      case 2:
        return const AureonVirtualFoldersPage();
      case 3:
        return _settingsPage();
      default:
        return const SizedBox.shrink();
    }
  }
}
