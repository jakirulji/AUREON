import 'package:aureon/src/auth/aureon_account_page.dart';
import 'package:aureon/src/auth/aureon_firebase_auth_service.dart';
import 'package:aureon/src/auth/aureon_backend_profile.dart';
import 'package:aureon/src/files/aureon_files_page.dart';
import 'package:aureon/src/transfers/aureon_transfers_page.dart';
import 'package:aureon/src/backup/aureon_backup_page.dart';
import 'package:aureon/src/virtual_folders/aureon_virtual_folders_page.dart';
import 'package:flutter/material.dart';

void main() => runApp(const AureonApp());

class AureonApp extends StatelessWidget {
  const AureonApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AUREON',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B1020),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF64E6C2), brightness: Brightness.dark, surface: const Color(0xFF111A2E)),
    ),
    home: const AureonHome(),
  );
}

class AureonHome extends StatefulWidget {
  const AureonHome({super.key});
  @override
  State<AureonHome> createState() => _AureonHomeState();
}

class _AureonHomeState extends State<AureonHome> {
  final _auth = AureonFirebaseAuthService();
  int selected = 0;
  final _backendProfiles = AureonBackendProfileStore();

  @override
  void initState() {
    super.initState();
    _restoreBackendProfile();
  }

  Future<void> _restoreBackendProfile() async {
    try {
      final profile = await _backendProfiles.activeProfile();
      if (profile != null && mounted) {
        _auth.configureProfile(profile);
        try {
          await _auth.restoreSession();
          final user = await _auth.reloadUser();
          try {
            final bound = await _backendProfiles.bindActiveProfile(user.localId);
            _auth.acceptBoundProfile(bound);
          } catch (_) {
            await _auth.signOut();
          }
        } catch (_) {
          // Temporary network failures must not erase the saved refresh token.
        }
      }
    } catch (_) {
      // The Account page presents a repairable profile-registry error.
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

  Widget _sidebar() => Container(
    width: 230,
    padding: const EdgeInsets.fromLTRB(18, 24, 12, 18),
    decoration: const BoxDecoration(color: Color(0xFF0E1628), border: Border(right: BorderSide(color: Color(0xFF202C42)))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.all_inclusive, color: Color(0xFF64E6C2), size: 30), SizedBox(width: 10), Text('AUREON', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 2))]),
      const Padding(padding: EdgeInsets.only(left: 40, top: 6), child: Text('YOUR DIGITAL UNIVERSE', style: TextStyle(fontSize: 9, letterSpacing: 1.2, color: Color(0xFF8492AA)))),
      const SizedBox(height: 34),
      for (var i = 0; i < labels.length; i++)
        Material(
          color: Colors.transparent,
          child: ListTile(
            dense: true,
            selected: selected == i,
            selectedTileColor: const Color(0xFF18352F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            leading: Icon(icons[i], color: selected == i ? const Color(0xFF64E6C2) : const Color(0xFF9AA8BD)),
            title: Text(labels[i], style: TextStyle(fontSize: 13, color: selected == i ? const Color(0xFF64E6C2) : const Color(0xFFCBD4E2))),
            onTap: () => setState(() => selected = i),
          ),
        ),
      const Spacer(),
      const Divider(color: Color(0xFF26334A)),
      Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(backgroundColor: const Color(0xFF243A4A), child: Icon(_auth.currentUser == null ? Icons.person_outline : Icons.verified_user_outlined, color: const Color(0xFF64E6C2))),
          title: Text(_auth.currentUser?.email ?? 'Local profile', style: const TextStyle(fontSize: 12)),
          subtitle: Text(_auth.currentUser == null ? 'Not signed in' : (_auth.currentUser!.emailVerified ? 'Verified account' : 'Verify email'), style: const TextStyle(fontSize: 11)),
          onTap: () => setState(() => selected = 4),
        ),
      ),
    ]),
  );

  // Home is the live local-files workspace, not a sample-data dashboard.
  // The Files navigation entry opens the same workspace for discoverability.
  Widget _content(bool wide) {
    switch (selected) {
      case 0:
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

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.icon, required this.name, required this.detail, required this.color});
  final IconData icon;
  final String name;
  final String detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFF111A2E), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF202C42))),
    child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
      const SizedBox(width: 12),
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 4), Text(detail, style: const TextStyle(fontSize: 11, color: Color(0xFF8492AA))),
      ])),
    ]),
  );
}
