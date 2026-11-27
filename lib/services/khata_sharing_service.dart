import 'package:share_plus/share_plus.dart';
import 'package:whatsapp_share2/whatsapp_share2.dart';

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
    final validFiles = files.where((path) => path.trim().isNotEmpty).toList();
    final target = phone == null ? '' : normalizePhone(phone);

    if (target.isNotEmpty) {
      final installed = await WhatsappShare.isInstalled();
      if (installed == true) {
        if (validFiles.isEmpty) {
          await WhatsappShare.share(phone: target, text: text);
        } else {
          await WhatsappShare.shareFile(
            phone: target,
            text: text,
            filePath: validFiles,
          );
        }
        return;
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
