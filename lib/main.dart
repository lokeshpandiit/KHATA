import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/documents_screen.dart';
import 'screens/hisab_screen.dart';
import 'screens/khet_screen.dart';
import 'screens/history_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/storage_backup_service.dart';
import 'services/farm_reminder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageBackupService.instance.initialize();
  await FarmReminderService.initialize();
  runApp(const KhataApp());
}

class KhataApp extends StatelessWidget {
  const KhataApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF176B52);
    return MaterialApp(
      title: 'KHATA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F8F5),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE8ECE8)),
          ),
        ),
      ),
      home: const KhataHome(),
    );
  }
}

class KhataHome extends StatefulWidget {
  const KhataHome({super.key});

  @override
  State<KhataHome> createState() => _KhataHomeState();
}

class _KhataHomeState extends State<KhataHome> {
  int _tab = 0;
  final _storage = StorageBackupService.instance;

  Future<void> _notify(Future<void> Function() task, String success) async {
    try {
      await task();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not complete action: $error')),
        );
      }
    }
  }

  Future<void> _showBackupActions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Back up to Google Drive'),
              onTap: () {
                Navigator.pop(context);
                _notify(_storage.backupToDrive, 'Backup uploaded to Drive');
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('Restore from Google Drive'),
              onTap: () {
                Navigator.pop(context);
                _notify(_storage.restoreFromDrive, 'Backup restored');
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                _showSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSettings() async {
    final folderController = TextEditingController(text: _storage.folderPath);
    final senderController = TextEditingController(text: _storage.senderName);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: senderController,
                decoration: const InputDecoration(labelText: 'Sender name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: folderController,
                decoration: InputDecoration(
                  labelText: 'Local KHATA folder',
                  suffixIcon: IconButton(
                    tooltip: 'Choose folder',
                    icon: const Icon(Icons.folder_open),
                    onPressed: () async {
                      final path = await _storage.pickFolder();
                      if (path != null) {
                        setDialogState(() => folderController.text = path);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Media and khata_database.json are copied to this folder.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await _storage.setFolder(folderController.text);
                  await _storage.setSenderName(senderController.text);
                  if (mounted) Navigator.pop(dialogContext);
                } catch (error) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not save settings: $error')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    folderController.dispose();
    senderController.dispose();
  }

  Future<void> _showFarmSettings() async {
    final prefs = await SharedPreferences.getInstance();
    var from = TimeOfDay(
      hour: prefs.getInt('farm_water_turn_start_hour') ?? 12,
      minute: prefs.getInt('farm_water_turn_start_minute') ?? 0,
    );
    var to = TimeOfDay(
      hour: prefs.getInt('farm_water_turn_end_hour') ?? 13,
      minute: prefs.getInt('farm_water_turn_end_minute') ?? 0,
    );
    final received = TextEditingController(
      text: prefs.getString('pani_received_message') ?? 'Maine {naam} se {minute} minute pani liya. Date: {date}',
    );
    final given = TextEditingController(
      text: prefs.getString('pani_given_message') ?? 'Maine {naam} ko {minute} minute pani diya. Date: {date}',
    );
    String label(TimeOfDay t) => t.format(context);
    Future<TimeOfDay?> pick(TimeOfDay t) => showTimePicker(context: context, initialTime: t);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Settings'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Nahar ki baari ka time', style: TextStyle(fontWeight: FontWeight.w700)),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () async { final v=await pick(from); if(v!=null)setDialogState(()=>from=v); }, child: Text('From: ${label(from)}'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () async { final v=await pick(to); if(v!=null)setDialogState(()=>to=v); }, child: Text('To: ${label(to)}'))),
              ]),
              const SizedBox(height: 16),
              TextField(controller: received, maxLines: 3, decoration: const InputDecoration(labelText: 'Default message — Pani liya', helperText: 'Placeholders: {naam}, {minute}, {date}')),
              const SizedBox(height: 12),
              TextField(controller: given, maxLines: 3, decoration: const InputDecoration(labelText: 'Default message — Pani diya', helperText: 'Placeholders: {naam}, {minute}, {date}')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () async {
              await prefs.setInt('farm_water_turn_start_hour', from.hour);
              await prefs.setInt('farm_water_turn_start_minute', from.minute);
              await prefs.setInt('farm_water_turn_end_hour', to.hour);
              await prefs.setInt('farm_water_turn_end_minute', to.minute);
              await prefs.setString('pani_received_message', received.text.trim());
              await prefs.setString('pani_given_message', given.text.trim());
              if(mounted)Navigator.pop(dialogContext);
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    received.dispose();
    given.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['DASHBOARD', 'HISAB', 'KHET', 'DOCUMENTS', 'HISTORY'];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[_tab],
          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1),
        ),
        actions: [
          IconButton(
            tooltip: 'Farm defaults',
            onPressed: _showFarmSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Backup and restore',
            onPressed: _showBackupActions,
            icon: const Icon(Icons.backup_outlined),
          ),

        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          DashboardScreen(),
          HisabScreen(),
          KhetScreen(),
          DocumentsScreen(),
          HistoryScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'HOME',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'HISAB',
          ),
          NavigationDestination(
            icon: Icon(Icons.agriculture_outlined),
            selectedIcon: Icon(Icons.agriculture),
            label: 'KHET',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy),
            label: 'DOCUMENTS',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'HISTORY',
          ),
        ],
      ),
    );
  }
}
