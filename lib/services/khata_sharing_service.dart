import 'package:share_plus/share_plus.dart';
import 'package:whatsapp_share_plus/whatsapp_share_plus.dart';

class KhataSharingService {
  static String normalizePhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length == 10) digits = '91$digits';
    return digits;
  }

  static Future<void> share({
    required String text,
    String? phone,
    List<String> files = const [],
  }) async {
    final validFiles = files
        .where((path) => path.trim().isNotEmpty)
        .where((path) => XFile(path).path.isNotEmpty)
        .toSet()
        .toList();
    final target = phone == null ? '' : normalizePhone(phone);

    if (target.isNotEmpty) {
      try {
        if (await WhatsAppShare.isInstalled()) {
          await WhatsAppShare.share(
            text: text,
            phone: target,
            files: validFiles.map(ShareFile.fromPath).toList(),
          );
          return;
        }
      } catch (_) {
        // Fall back to Android's regular share sheet if WhatsApp cannot handle it.
      }
    }

    if (validFiles.isEmpty) {
      await Share.share(text);
    } else {
      await Share.shareXFiles(
        validFiles.map(XFile.new).toList(),
        text: text,
      );
    }
  }
}
