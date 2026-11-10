import 'package:aureon/src/auth/aureon_account_page.dart';
import 'package:aureon/src/auth/aureon_firebase_auth_service.dart';
import 'package:aureon/src/auth/aureon_backend_profile.dart';
import 'package:aureon/src/files/aureon_files_page.dart';
import 'package:aureon/src/home/aureon_home_page.dart';
import 'package:aureon/src/transfers/aureon_transfers_page.dart';
import 'package:aureon/src/backup/aureon_backup_page.dart';
import 'package:aureon/src/virtual_folders/aureon_virtual_folders_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const AureonApp());

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
    debugShowCheckedModeBanner: false,
    themeMode: _themeMode,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF4F7FB),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF087F70),
        brightness: Brightness.light,
        surface: Colors.white,
      ),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B1020),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF64E6C2),
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
  static const labels = ['Home', 'Files', 'Cloud', 'Transfers', 'Account', 'Settings'];
  static const icons = [Icons.home_outlined, Icons.folder_outlined, Icons.cloud_outlined, Icons.swap_vert, Icons.person_outline, Icons.settings_outlined];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final wide = constraints.maxWidth >= 760;
    return Scaffold(
      body: SafeArea(child: Row(children: [
        if (wide) _sidebar(),
        Expanded(child: _content(wide)),
      ])),
      bottomNavigationBar: wide ? null : NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (value) => setState(() => selected = value),
        destinations: List.generate(labels.length, (i) => NavigationDestination(icon: Icon(icons[i]), label: labels[i])),
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
          Icon(Icons.all_inclusive, color: Color(0xFF64E6C2), size: 30),
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
              onTap: () => setState(() => selected = i),
            ),
          ),
        const Spacer(),
        Divider(color: scheme.outlineVariant),
        Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              child: Icon(_auth.currentUser == null ? Icons.person_outline : Icons.verified_user_outlined,
                color: scheme.primary),
            ),
            title: Text(_auth.currentUser?.email ?? 'Local profile',
              style: const TextStyle(fontSize: 12)),
            subtitle: Text(_auth.currentUser == null ? 'Not signed in' :
              (_auth.currentUser!.emailVerified ? 'Verified account' : 'Verify email'),
              style: const TextStyle(fontSize: 11)),
            onTap: () => setState(() => selected = 4),
          ),
        ),
      ]),
    );
  }

  // Home provides live device storage metrics; Files remains the local file workspace.
  Widget _content(bool wide) {
    switch (selected) {
      case 0:
        return AureonHomePage(
          isDarkMode: widget.themeMode == ThemeMode.dark,
          onThemeChanged: (dark) => widget.onThemeChanged(dark ? ThemeMode.dark : ThemeMode.light),
        );
      case 1:
        return const AureonFilesPage();
      case 2:
        return const AureonVirtualFoldersPage();
      case 3:
        return const AureonTransfersPage();
      case 4:
        return AureonAccountPage(auth: _auth);
      case 5:
        return AureonBackupPage(auth: _auth);
      default:
        return const Center(child: Text('Select a section from the navigation.'));
    }
  }
}

