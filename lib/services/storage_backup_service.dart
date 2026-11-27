import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageBackupService {
  StorageBackupService._();

  static final StorageBackupService instance = StorageBackupService._();

  static const _folderKey = 'khata_folder';
  static const _senderKey = 'khata_sender';
  static const _databaseName = 'khata_database.json';
  static const defaultFolder = '/storage/emulated/0/KHATA';
  static const categories = <String>[
    'hisabs',
    'khet',
    'contacts',
    'members',
    'products',
    'plots',
  ];

  Directory? _root;
  final Map<String, List<Map<String, dynamic>>> _data = {};
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Directory get root => _root ?? Directory(defaultFolder);
  String get folderPath => root.path;
  String senderName = 'Ravi';

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    senderName = prefs.getString(_senderKey) ?? 'Ravi';
    final savedPath = prefs.getString(_folderKey) ?? defaultFolder;
    _root = Directory(savedPath);
    if (Platform.isAndroid &&
        !(await Permission.manageExternalStorage.status).isGranted) {
      await Permission.manageExternalStorage.request();
    }
    try {
      await _ensureFolders();
    } on FileSystemException {
      final appDir = await getApplicationDocumentsDirectory();
      _root = Directory(p.join(appDir.path, 'KHATA'));
      await _ensureFolders();
    }

    final db = File(p.join(root.path, _databaseName));
    if (await db.exists()) {
      final decoded = jsonDecode(await db.readAsString());
      if (decoded is Map<String, dynamic>) {
        for (final category in categories) {
          final items = decoded[category];
          if (items is List) {
            _data[category] = items
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
          }
        }
      }
    }

    for (final category in categories) {
      _data.putIfAbsent(category, () => []);
    }
    _seedDefaultPlots();
    _ensurePlotOwnership();
    await _save();
  }

  void _seedDefaultPlots() {
    final plots = _data.putIfAbsent('plots', () => []);
    if (plots.isNotEmpty) return;
    const initialNumbers = <String, String>{
      '0-1': 'J', '0-2': 'S',
      '1-1': '3', '1-2': '5',
      '2-1': '2', '2-2': '4',
      '3-1': '1', '3-2': 'C',
    };
    const myPlotPositions = <String>{
      '1-1', '1-2', '2-1', '2-2', '3-1',
    };
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        final position = '$row-$column';
        plots.add({
          'id': 'plot-$row-$column',
          'row': row,
          'column': column,
          'number': initialNumbers[position] ?? '',
          'name': '',
          'isMine': myPlotPositions.contains(position),
        });
      }
    }
  }

  void _ensurePlotOwnership() {
    final myPlotIds = <String>{
      'plot-1-1', // 3
      'plot-1-2', // 5
      'plot-2-1', // 2
      'plot-2-2', // 4
      'plot-3-1', // 1
    };
    for (final plot in _data['plots'] ?? const <Map<String, dynamic>>[]) {
      plot.putIfAbsent('isMine', () => myPlotIds.contains(plot['id']));
    }
  }

  Future<void> _ensureFolders() async {
    await root.create(recursive: true);
    for (final name in [
      'Photos',
      'VoiceNotes',
      'CallRecordings',
      'KhetPhotos',
      'Documents',
    ]) {
      await Directory(p.join(root.path, name)).create(recursive: true);
    }
  }

  List<Map<String, dynamic>> records(String category) =>
      List.unmodifiable(_data[category] ?? const []);

  Future<void> addRecord(String category, Map<String, dynamic> record) async {
    if (!categories.contains(category)) {
      throw ArgumentError.value(category, 'category', 'Unknown data collection');
    }
    _data.putIfAbsent(category, () => []).insert(0, record);
    await _save();
  }

  Future<void> updateRecord(
    String category,
    String id,
    Map<String, dynamic> updated,
  ) async {
    final rows = _data[category];
    if (rows == null) return;
    final index = rows.indexWhere((item) => item['id'] == id);
    if (index < 0) return;
    rows[index] = updated;
    await _save();
  }

  Future<String> keepFile(
    String sourcePath, {
    required String folder,
    String? filename,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Selected file no longer exists', sourcePath);
    }
    final destinationFolder = Directory(p.join(root.path, folder));
    await destinationFolder.create(recursive: true);
    final safeName = (filename ?? p.basename(sourcePath))
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final destination = p.join(
      destinationFolder.path,
      '${DateTime.now().microsecondsSinceEpoch}_$safeName',
    );
    return (await source.copy(destination)).path;
  }

  Future<void> setFolder(String path) async {
    if (path.trim().isEmpty) throw ArgumentError('Folder path cannot be empty');
    final prefs = await SharedPreferences.getInstance();
    final oldRoot = root;
    final newRoot = Directory(path.trim());
    await newRoot.create(recursive: true);
    final oldPath = p.normalize(oldRoot.absolute.path);
    final newPath = p.normalize(newRoot.absolute.path);
    final previousData = {
      for (final entry in _data.entries)
        entry.key: entry.value.map((row) => Map<String, dynamic>.from(row)).toList(),
    };
    if (oldPath != newPath && await oldRoot.exists()) {
      final entities =
          await oldRoot.list(recursive: true, followLinks: false).toList();
      for (final entity in entities) {
        if (entity is File) {
          if (p.isWithin(oldPath, newPath) &&
              p.isWithin(newPath, p.normalize(entity.absolute.path))) {
            continue;
          }
          final relative = p.relative(entity.path, from: oldRoot.path);
          final destination = File(p.join(newRoot.path, relative));
          await destination.parent.create(recursive: true);
          if (!await destination.exists()) await entity.copy(destination.path);
        }
      }
    }
    _root = newRoot;
    try {
      await _ensureFolders();
      if (oldPath != newPath) {
        for (final rows in _data.values) {
          for (var index = 0; index < rows.length; index++) {
            rows[index] = _replaceRootPaths(rows[index], oldPath, newPath);
          }
        }
      }
      await _save();
      if (!await prefs.setString(_folderKey, newRoot.path)) {
        throw StateError('Could not persist the KHATA folder setting');
      }
    } catch (_) {
      _root = oldRoot;
      _data
        ..clear()
        ..addAll(previousData);
      rethrow;
    }
  }

  Map<String, dynamic> _replaceRootPaths(
    Map<String, dynamic> record,
    String oldPath,
    String newPath,
  ) {
    dynamic replace(dynamic value) {
      if (value is String &&
          (value == oldPath || value.startsWith('$oldPath${p.separator}'))) {
        return p.join(newPath, p.relative(value, from: oldPath));
      }
      if (value is List) {
        return value.map(replace).toList();
      }
      if (value is Map<String, dynamic>) {
        return value.map((key, nested) {
          final updatedKey = key == oldPath ||
                  key.startsWith('$oldPath${p.separator}')
              ? p.join(newPath, p.relative(key, from: oldPath))
              : key;
          return MapEntry(updatedKey, replace(nested));
        });
      }
      return value;
    }

    return replace(record) as Map<String, dynamic>;
  }

  Future<void> setSenderName(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw ArgumentError('Sender name cannot be empty');
    final previousName = senderName;
    senderName = normalized;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_senderKey, senderName)) {
      senderName = previousName;
      throw StateError('Could not persist the sender name');
    }
  }

  Future<void> _save() async {
    final file = File(p.join(root.path, _databaseName));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_data), flush: true);
    revision.value++;
  }

  Future<void> _requireStoragePermission() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      final result = await Permission.manageExternalStorage.request();
      if (!result.isGranted) {
        throw FileSystemException(
          'Storage permission is required to use the selected backup folder',
        );
      }
    }
  }

  Future<File> createBackupZip() async {
    await _requireStoragePermission();
    await _save();
    final archive = Archive();
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: root.path);
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      }
    }
    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) throw StateError('Unable to create backup archive');
    final temp = await getTemporaryDirectory();
    final zip = File(p.join(temp.path, 'KHATA_Backup.zip'));
    return zip.writeAsBytes(bytes, flush: true);
  }

  Future<void> restoreBackupZip(String zipPath) async {
    await _requireStoragePermission();
    final archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final rootPath = p.normalize(root.absolute.path);
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final target = p.normalize(p.join(rootPath, file.name));
      if (!p.isWithin(rootPath, target)) {
        throw const FormatException('Backup contains an invalid file path');
      }
      final output = File(target);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(file.content as List<int>, flush: true);
    }
    await _loadDatabase();
  }

  Future<void> _loadDatabase() async {
    final file = File(p.join(root.path, _databaseName));
    if (!await file.exists()) return;
    final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    for (final category in categories) {
      _data[category] = (decoded[category] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    for (final category in categories) {
      _data.putIfAbsent(category, () => []);
    }
    _seedDefaultPlots();
    _ensurePlotOwnership();
    revision.value++;
  }

  Future<void> backupToDrive() async {
    final zip = await createBackupZip();
    final token = await _driveToken();
    final boundary = 'khata-${DateTime.now().microsecondsSinceEpoch}';
    final metadata = jsonEncode({'name': 'KHATA_Backup.zip'});
    final bytes = await zip.readAsBytes();
    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '$metadata\r\n--$boundary\r\n'
          'Content-Type: application/zip\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));
    final response = await http.post(
      Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body.takeBytes(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Google Drive backup failed (${response.statusCode})');
    }
  }

  Future<void> restoreFromDrive() async {
    final token = await _driveToken();
    final listResponse = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "name = 'KHATA_Backup.zip' and trashed = false",
        'orderBy': 'modifiedTime desc',
        'pageSize': '1',
        'fields': 'files(id,name)',
      }),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (listResponse.statusCode != 200) {
      throw HttpException(
        'Could not find Drive backup (${listResponse.statusCode})',
      );
    }
    final files =
        (jsonDecode(listResponse.body) as Map<String, dynamic>)['files'] as List;
    if (files.isEmpty) throw StateError('No KHATA_Backup.zip found in Drive');
    final id = (files.first as Map<String, dynamic>)['id'] as String;
    final download = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files/$id', {'alt': 'media'}),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (download.statusCode != 200) {
      throw HttpException('Drive restore failed (${download.statusCode})');
    }
    final temp = await getTemporaryDirectory();
    final zip = File(p.join(temp.path, 'KHATA_Backup.zip'));
    await zip.writeAsBytes(download.bodyBytes, flush: true);
    await restoreBackupZip(zip.path);
  }

  Future<String> _driveToken() async {
    final signIn = GoogleSignIn(
      scopes: const ['https://www.googleapis.com/auth/drive.file'],
    );
    final account = await signIn.signIn();
    if (account == null) throw StateError('Google sign-in was cancelled');
    final token = (await account.authentication).accessToken;
    if (token == null) throw StateError('Google did not provide an access token');
    return token;
  }

  Future<String?> pickFolder() => FilePicker.platform.getDirectoryPath();
}
