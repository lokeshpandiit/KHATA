import 'package:flutter_contacts/flutter_contacts.dart';

class ContactPickerService {
  static Future<Map<String, String>?> pickPhoneContact() async {
    final permission =
        await FlutterContacts.permissions.request(PermissionType.read);
    if (permission != PermissionStatus.granted) {
      throw StateError('Contacts permission was not granted');
    }

    final contact = await FlutterContacts.native.showPicker(
      properties: {ContactProperty.phone},
    );
    if (contact == null) return null;
    final phone = contact.phones
        .map((item) => item.number.trim())
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    if (phone.isEmpty) {
      throw StateError('Selected contact does not have a phone number');
    }
    return {
      'name': (contact.displayName ?? '').trim().isEmpty
          ? 'Unknown contact'
          : (contact.displayName ?? '').trim(),
      'phone': phone,
    };
  }
}
