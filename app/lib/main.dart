import 'package:aureon/src/auth/aureon_account_page.dart';
import 'package:aureon/src/auth/aureon_firebase_auth_service.dart';
import 'package:aureon/src/files/aureon_files_page.dart';
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

  Widget _content(bool wide) => selected == 1
      ? const AureonFilesPage()
      : selected == 2
          ? const AureonVirtualFoldersPage()
          : selected == 4
              ? AureonAccountPage(auth: _auth)
              : selected == 5
                  ? AureonBackupPage(auth: _auth)
                  : SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(wide ? 34 : 20, 22, wide ? 34 : 20, 28),
    child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1180),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (!wide) const Icon(Icons.all_inclusive, color: Color(0xFF64E6C2), size: 27),
          if (!wide) const SizedBox(width: 9),
          Expanded(child: Text(selected == 0 ? 'Good evening' : labels[selected], style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700))),
          IconButton(onPressed: () => setState(() => selected = 4), icon: const Icon(Icons.person_outline)),
        ]),
        const SizedBox(height: 5),
        const Text('One place for all your files.', style: TextStyle(color: Color(0xFF9AA8BD))),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: const Color(0xFF302817), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF66512A))),
          child: const Row(children: [
            Icon(Icons.science_outlined, color: Color(0xFFFFD27A)),
            SizedBox(width: 10),
            Expanded(child: Text('Preview build • Sample data only. Real cloud accounts and provider transfers are not connected yet.', style: TextStyle(fontSize: 12, color: Color(0xFFFFE4B0)))),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('Storage overview', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final count = box.maxWidth > 1000 ? 3 : box.maxWidth > 520 ? 2 : 1;
          return GridView.count(
            crossAxisCount: count, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: count == 1 ? 3.1 : count == 2 ? 2.8 : 2.5,
            children: const [
              _StorageCard(icon: Icons.phone_android, name: 'This device', detail: 'Local storage • Not connected', color: Color(0xFF64E6C2)),
              _StorageCard(icon: Icons.cloud_queue, name: 'Cloud accounts', detail: 'No accounts connected', color: Color(0xFF83A9FF)),
              _StorageCard(icon: Icons.sync, name: 'Transfers', detail: 'No active transfers', color: Color(0xFFFFC477)),
            ],
          );
        }),
        const SizedBox(height: 26),
        Row(children: [const Expanded(child: Text('Recent files', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))), TextButton(onPressed: () => setState(() => selected = 1), child: const Text('View files'))]),
        const SizedBox(height: 8),
        _fileRow(Icons.picture_as_pdf_outlined, 'Project brief.pdf', 'Documents • Sample item', '2.4 MB'),
        _fileRow(Icons.image_outlined, 'Workspace photo.jpg', 'Pictures • Sample item', '4.8 MB'),
        _fileRow(Icons.folder_zip_outlined, 'Design assets.zip', 'Archives • Sample item', '18.2 MB'),
        const SizedBox(height: 22),
        const Text('AUREON is being built in testable stages.', style: TextStyle(color: Color(0xFF8492AA), fontSize: 12)),
      ]),
    )),
  );

  Widget _fileRow(IconData icon, String name, String detail, String size) => Container(
    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: const Color(0xFF111A2E), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF202C42))),
    child: Row(children: [
      Icon(icon, color: const Color(0xFF8EA5C5), size: 23), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 3), Text(detail, style: const TextStyle(fontSize: 11, color: Color(0xFF8492AA))),
      ])),
      Text(size, style: const TextStyle(fontSize: 11, color: Color(0xFF9AA8BD))),
      const SizedBox(width: 8), const Icon(Icons.more_horiz, color: Color(0xFF8492AA)),
    ]),
  );
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
