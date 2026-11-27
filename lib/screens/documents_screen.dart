import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../services/storage_backup_service.dart';
import '../services/khata_sharing_service.dart';
import '../widgets/khata_widgets.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen>
    with SingleTickerProviderStateMixin {
  final _storage = StorageBackupService.instance;
  late final TabController _tabs;

  List<Map<String, dynamic>> get _members => _storage.records('members');
  List<Map<String, dynamic>> get _products => _storage.records('products');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Family Member'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Member name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final now = DateTime.now();
    try {
      await _storage.addRecord('members', {
        'id': now.microsecondsSinceEpoch.toString(),
        'name': name,
        'documents': <String>[],
        'date': now.toIso8601String(),
      });
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not add member: $error');
    }
  }

  Future<void> _openMember(Map<String, dynamic> member) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemberDocumentsScreen(member: member),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _addProduct() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AddProductScreen()),
    );
    if (added == true && mounted) setState(() {});
  }

  Future<void> _shareProduct(Map<String, dynamic> product) async {
    final paths = <String>[
      ...(product['billPhotos'] as List? ?? const []).whereType<String>(),
      if (product['billPhoto'] is String) product['billPhoto'] as String,
      ...(product['warrantyPhotos'] as List? ?? const []).whereType<String>(),
      if (product['warrantyPhoto'] is String) product['warrantyPhoto'] as String,
    ].toSet().where((path) => File(path).existsSync()).toList();
    await KhataSharingService.share(
      text: [
        'Product - ${product['name']}',
        if ((product['note'] as String? ?? '').isNotEmpty) 'Note: ${product['note']}',
      ].join('\n'),
      files: paths,
    );
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TabBar(
              controller: _tabs,
              tabs: const [Tab(text: 'MEMBER'), Tab(text: 'PRODUCT')],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _membersTab(),
                _productsTab(),
              ],
            ),
          ),
        ],
      );

  Widget _membersTab() => Scaffold(
        backgroundColor: Colors.transparent,
        body: _members.isEmpty
            ? emptyState('No family members', 'Add a member to manage their documents.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                children: _members.map((member) {
                  final docs = (member['documents'] as List? ?? const []).length;
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                      title: Text(member['name'] as String? ?? 'Member'),
                      subtitle: Text('$docs personal document${docs == 1 ? '' : 's'}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openMember(member),
                    ),
                  );
                }).toList(),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addMember,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add Member'),
        ),
      );

  Widget _productsTab() => Scaffold(
        backgroundColor: Colors.transparent,
        body: _products.isEmpty
            ? emptyState('No products', 'Add a purchased product and keep its bill and warranty.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                children: _products.map((product) {
                  final bill = product['billPhoto'] as String?;
                  final warranty = product['warrantyPhoto'] as String?;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product['name'] as String? ?? 'Product',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Share bill and warranty',
                                onPressed: () => _shareProduct(product),
                                icon: const Icon(Icons.share_outlined),
                              ),
                            ],
                          ),
                          if ((product['note'] as String? ?? '').isNotEmpty)
                            Text(product['note'] as String),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            children: [
                              if (bill != null)
                                _productPhoto('Bill', bill),
                              if (warranty != null)
                                _productPhoto('Warranty', warranty),
                            ],
                          ),
                          if (product['date'] is String)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: recordDateTime(product['date'] as String),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addProduct,
          icon: const Icon(Icons.add),
          label: const Text('Add Product'),
        ),
      );

  Widget _productPhoto(String label, String path) => InkWell(
        onTap: () => _preview(path),
        child: Column(
          children: [
            mediaThumbnail(path, size: 78),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );

  void _preview(String path) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(File(path), errorBuilder: (_, __, ___) {
                return const Icon(Icons.broken_image, color: Colors.white, size: 64);
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class MemberDocumentsScreen extends StatefulWidget {
  const MemberDocumentsScreen({required this.member, super.key});

  final Map<String, dynamic> member;

  @override
  State<MemberDocumentsScreen> createState() => _MemberDocumentsScreenState();
}

class _MemberDocumentsScreenState extends State<MemberDocumentsScreen> {
  final _storage = StorageBackupService.instance;
  final _picker = ImagePicker();
  bool _busy = false;

  List<String> get _documents =>
      (widget.member['documents'] as List? ?? const []).cast<String>();

  Future<String?> _askDocumentName() async {
    final controller = TextEditingController(text: 'Aadhaar Card');
    const names = ['Aadhaar Card', 'PAN Card', 'Voter ID', 'Driving Licence', 'Ration Card', 'Passport', 'Other'];
    String selected = 'Aadhaar Card';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Name this document'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Document type'),
              items: names.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
              onChanged: (value) => setDialogState(() {
                selected = value ?? selected;
                if (selected != 'Other') controller.text = selected;
                else controller.clear();
              }),
            ),
            const SizedBox(height: 10),
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Document name')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            }, child: const Text('Continue')),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _addFromCameraOrGallery(ImageSource source) async {
    try {
      final paths = source == ImageSource.gallery
          ? (await _picker.pickMultiImage(imageQuality: 90)).map((image) => image.path).toList()
          : [if (await _picker.pickImage(source: source, imageQuality: 90) case final image?) image.path];
      if (paths.isNotEmpty) await _keepDocuments(paths);
    } catch (error) {
      _error('Could not add document: $error');
    }
  }

  Future<void> _addFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      final paths = (result?.files ?? const []).map((file) => file.path).whereType<String>().toList();
      if (paths.isNotEmpty) await _keepDocuments(paths);
    } catch (error) {
      _error('Could not add document: $error');
    }
  }

  Future<void> _keepDocuments(List<String> paths) async {
    final label = await _askDocumentName();
    if (label == null || label.isEmpty) return;
    setState(() => _busy = true);
    try {
      final documents = [..._documents];
      final labels = Map<String, dynamic>.from(widget.member['documentNames'] as Map? ?? const {});
      for (var i = 0; i < paths.length; i++) {
        final permanent = await _storage.keepFile(paths[i], folder: 'Documents');
        documents.add(permanent);
        labels[permanent] = paths.length == 1 ? label : '$label ${i + 1}';
      }
      final updated = {...widget.member, 'documents': documents, 'documentNames': labels};
      await _storage.updateRecord('members', widget.member['id'] as String, updated);
      if (!mounted) return;
      setState(() {
        widget.member['documents'] = documents;
        widget.member['documentNames'] = labels;
      });
    } catch (error) {
      _error('Could not save document: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareDocument(String path, String label) async {
    await KhataSharingService.share(text: '$label - Personal document', files: [path]);
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.member['name'] as String? ?? 'Member')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _addFromCameraOrGallery(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Camera'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _addFromCameraOrGallery(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addFile,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('File'),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _documents.isEmpty
                  ? emptyState('No documents yet', 'Add this member’s personal documents.')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _documents.length,
                      itemBuilder: (context, index) {
                        final path = _documents[index];
                        final lowerPath = path.toLowerCase();
                        final isImage = ['.jpg', '.jpeg', '.png', '.webp']
                            .any(lowerPath.endsWith);
                        return Card(
                          child: ListTile(
                            leading: isImage
                                ? mediaThumbnail(path, size: 48)
                                : const CircleAvatar(child: Icon(Icons.description_outlined)),
                            title: Text(((widget.member['documentNames'] as Map?)?[path] ?? path.split(Platform.pathSeparator).last).toString()),
                            onTap: isImage ? () => _preview(path) : () => _shareDocument(path, ((widget.member['documentNames'] as Map?)?[path] ?? 'Personal document').toString()),
                            trailing: IconButton(
                              tooltip: 'Share document',
                              icon: const Icon(Icons.share_outlined),
                              onPressed: () => _shareDocument(path, ((widget.member['documentNames'] as Map?)?[path] ?? 'Personal document').toString()),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );

  void _preview(String path) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Document')),
          body: Center(child: InteractiveViewer(child: Image.file(File(path)))),
        ),
      ),
    );
  }
}

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _storage = StorageBackupService.instance;
  final _picker = ImagePicker();
  final _name = TextEditingController();
  final _note = TextEditingController();
  final List<String> _billPhotos = [];
  final List<String> _warrantyPhotos = [];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(bool warranty, ImageSource source) async {
    try {
      final images = source == ImageSource.gallery
          ? await _picker.pickMultiImage(imageQuality: 90)
          : [if (await _picker.pickImage(source: source, imageQuality: 90) case final image?) image];
      final target = warranty ? _warrantyPhotos : _billPhotos;
      for (final image in images) {
        target.add(await _storage.keepFile(image.path, folder: 'Documents'));
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not save product photos: $error');
    }
  }

  Future<void> _pickBillFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
      for (final file in result?.files ?? const []) {
        if (file.path != null) _billPhotos.add(await _storage.keepFile(file.path!, folder: 'Documents'));
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not save bill images: $error');
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _error('Enter a product name');
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await _storage.addRecord('products', {
        'id': now.microsecondsSinceEpoch.toString(),
        'name': _name.text.trim(),
        'note': _note.text.trim(),
        'billPhoto': _billPhotos.isEmpty ? null : _billPhotos.first,
        'billPhotos': _billPhotos,
        'warrantyPhoto': _warrantyPhotos.isEmpty ? null : _warrantyPhotos.first,
        'warrantyPhotos': _warrantyPhotos,
        'date': now.toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _error('Could not save product: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _photoPicker(String title, bool warranty) {
    final paths = warranty ? _warrantyPhotos : _billPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        Wrap(spacing: 8, children: [
          TextButton.icon(onPressed: () => _pick(warranty, ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera')),
          TextButton.icon(onPressed: warranty ? () => _pick(warranty, ImageSource.gallery) : _pickBillFile,
            icon: const Icon(Icons.photo_library_outlined), label: const Text('Add multiple')),
        ]),
        if (paths.isNotEmpty)
          Wrap(spacing: 6, children: paths.map((path) => mediaThumbnail(path, size: 76)).toList()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Add Product')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Product name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 18),
            _photoPicker('Bill Photo', false),
            const SizedBox(height: 14),
            _photoPicker('Warranty Card Photo', true),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save Product'),
            ),
          ],
        ),
      );
}
