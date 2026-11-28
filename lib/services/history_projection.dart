class HistoryEntry {
  const HistoryEntry({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.date,
  });

  final String type;
  final String title;
  final String subtitle;
  final DateTime? date;
}

/// Builds a dated activity timeline from the same records used by KHATA ledgers.
/// Payment rows keep their own saved payment date; editing the parent bill must
/// never move an older bill or payment to the parent's latest updatedAt date.
class HistoryProjection {
  static DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static DateTime? _recordDate(Map<String, dynamic> row) =>
      _parseDate(row['date']) ??
      _parseDate(row['createdAt']) ??
      _parseDate(row['updatedAt']);

  static String _value(dynamic value) => (value ?? '').toString().trim();

  static String _minutes(dynamic value) {
    final minutes = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return minutes >= 60
        ? '${minutes ~/ 60} hr ${minutes % 60} min'
        : '$minutes min';
  }

  static String _money(dynamic value) {
    if (value is num) return '₹${value.abs().toStringAsFixed(value % 1 == 0 ? 0 : 2)}';
    final raw = _value(value);
    if (raw.isEmpty) return '';
    final parsed = double.tryParse(raw.replaceAll(',', '').replaceAll('₹', ''));
    if (parsed == null) return '₹$raw';
    return '₹${parsed.abs().toStringAsFixed(parsed % 1 == 0 ? 0 : 2)}';
  }

  static List<HistoryEntry> build({
    required List<Map<String, dynamic>> hisabs,
    required List<Map<String, dynamic>> khet,
    required List<Map<String, dynamic>> members,
    required List<Map<String, dynamic>> products,
  }) {
    final entries = <HistoryEntry>[];

    void addPayments(Map<String, dynamic> record, String type, String title) {
      final rawPayments = record['payments'];
      if (rawPayments is! List) return;
      for (final payment in rawPayments.whereType<Map>()) {
        final amount = payment['amount'];
        final direction = _value(payment['direction']);
        final note = _value(payment['note']);
        final balance = payment['balanceAfter'];
        entries.add(HistoryEntry(
          type: type,
          title: 'Payment · $title',
          subtitle: [
            if (direction.isNotEmpty) direction,
            if (amount != null) _money(amount),
            if (balance != null) 'Remaining ${_money(balance)}',
            if (note.isNotEmpty) note,
          ].where((part) => part.isNotEmpty).join(' · '),
          date: _parseDate(payment['date']) ?? _recordDate(record),
        ));
      }
    }

    for (final record in hisabs) {
      final title = _value(record['title']).isEmpty
          ? _value(record['category'])
          : _value(record['title']);

      // Person-to-person payments are already standalone dated ledger events.
      // Do not add the original payment as well as a synthetic payment child.
      if (record['paymentKind'] == 'PERSON_PAYMENT' ||
          record['entryType'] == 'PAYMENT') {
        final person = _value(record['personName']);
        final paid = record['direction'] == 'PAID';
        entries.add(HistoryEntry(
          type: 'HISAB',
          title: '${paid ? 'आपने पैसे दिए' : 'आपको पैसे मिले'}${person.isEmpty ? '' : ' · $person'}',
          subtitle: [
            if (_money(record['amount']).isNotEmpty) _money(record['amount']),
            if (_value(record['category']).isNotEmpty) _value(record['category']),
            if (record['balanceAfter'] != null)
              'Balance ${_money(record['balanceAfter'])}',
            if (_value(record['note']).isNotEmpty) _value(record['note']),
          ].where((part) => part.isNotEmpty).join(' · '),
          date: _recordDate(record),
        ));
        continue;
      }

      entries.add(HistoryEntry(
        type: 'HISAB',
        title: title.isEmpty ? 'Hisab' : title,
        subtitle: [
          _value(record['category']),
          if (_money(record['amount']).isNotEmpty) _money(record['amount']),
          _value(record['note']),
        ].where((part) => part.isNotEmpty).join(' · '),
        date: _recordDate(record),
      ));
      addPayments(record, 'HISAB', title);
    }

    void addWaterSettlementRows(Map<String, dynamic> record, String title) {
      final cashHistory = record['waterCashPaymentHistory'];
      if (cashHistory is List) {
        for (final payment in cashHistory.whereType<Map>()) {
          final direction = _value(payment['direction']);
          final workSettlement = direction == 'WorkSettlement';
          final amount = payment['amount'];
          final note = _value(payment['note']);
          final balance = payment['balanceAfter'];
          entries.add(HistoryEntry(
            type: 'PANI',
            title: workSettlement ? 'Work settlement · $title' : 'Water payment · $title',
            subtitle: [
              if (workSettlement) 'Khet mein kaam karke settle'
              else if (direction.isNotEmpty) direction,
              if (!workSettlement && amount != null && amount is num && amount.abs() > 0.009)
                _money(amount),
              if (balance != null) 'Remaining ${_money(balance)}',
              if (note.isNotEmpty) note,
            ].where((part) => part.isNotEmpty).join(' · '),
            date: _parseDate(payment['date']) ?? _recordDate(record),
          ));
        }
      }

      final exchangeHistory = record['waterExchangeHistory'];
      if (exchangeHistory is List) {
        for (final exchange in exchangeHistory.whereType<Map>()) {
          final minutes = exchange['minutes'];
          final note = _value(exchange['note']);
          final balance = exchange['balanceAfter'];
          entries.add(HistoryEntry(
            type: 'PANI',
            title: 'Water settlement · $title',
            subtitle: [
              if (minutes != null) _minutes(minutes),
              if (balance != null) 'Remaining $balance min',
              if (note.isNotEmpty) note,
            ].where((part) => part.isNotEmpty).join(' · '),
            date: _parseDate(exchange['date']) ?? _recordDate(record),
          ));
        }
      }
    }

    for (final record in khet) {
      final kind = _value(record['type']);
      final isWater = kind == 'PANI' ||
          kind == 'KUA' ||
          (kind.isEmpty &&
              (record.containsKey('source') || record.containsKey('minutes')));
      if (kind == 'KHET_PURCHASE_PAYMENT') {
        final refunded = _value(record['direction']) == 'Liya';
        final vendor = _value(record['vendorName']);
        final amount = _money(record['amount']);
        entries.add(HistoryEntry(
          type: 'KHET',
          title: refunded ? 'दुकानदार से पैसे वापस मिले' : 'दुकानदार को भुगतान',
          subtitle: [
            if (vendor.isNotEmpty) vendor,
            if (amount.isNotEmpty) amount,
            if (record['balanceAfter'] != null)
              'Remaining ${_money(record['balanceAfter'])}',
            if (_value(record['note']).isNotEmpty) _value(record['note']),
          ].where((part) => part.isNotEmpty).join(' · '),
          date: _recordDate(record),
        ));
        continue;
      }

      final type = isWater ? 'PANI' : 'KHET';
      final contact = _value(record['contact']);
      final source = _value(record['source'] ?? record['wellType'] ?? record['wellSelection']);
      final title = isWater
          ? '${contact.isEmpty ? 'Pani' : contact} · ${source.isEmpty ? (kind == 'KUA' ? 'Kua' : 'Pani') : source}'
          : (_value(record['title']).isEmpty
              ? (kind.isEmpty ? 'Khet entry' : kind)
              : _value(record['title']));
      final minutes = record['minutes'] ?? record['exchangeMinutes'];
      entries.add(HistoryEntry(
        type: type,
        title: title,
        subtitle: isWater
            ? [
                _value(record['direction']),
                if (minutes != null && _minutes(minutes) != '0 min')
                  _minutes(minutes),
                _value(record['note']),
              ].where((part) => part.isNotEmpty).join(' · ')
            : [
                kind,
                if (_money(record['totalAmount'] ?? record['price'] ?? record['amount']).isNotEmpty)
                  _money(record['totalAmount'] ?? record['price'] ?? record['amount']),
                _value(record['note']),
              ].where((part) => part.isNotEmpty).join(' · '),
        date: _recordDate(record),
      ));
      addPayments(record, type, title);
      if (isWater) addWaterSettlementRows(record, title);
    }

    for (final record in members) {
      final documents = (record['documents'] as List? ?? const []).length;
      entries.add(HistoryEntry(
        type: 'DOCUMENTS',
        title: 'Member · ${_value(record['name'])}',
        subtitle: documents == 0 ? 'Member record' : '$documents document(s)',
        date: _recordDate(record),
      ));
    }

    for (final record in products) {
      entries.add(HistoryEntry(
        type: 'DOCUMENTS',
        title: 'Product · ${_value(record['name'])}',
        subtitle: _value(record['note']),
        date: _recordDate(record),
      ));
    }

    entries.sort((a, b) =>
        (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    return entries;
  }
}
