import 'package:flutter_test/flutter_test.dart';
import 'package:khata/services/history_projection.dart';

void main() {
  group('HistoryProjection', () {
    test('keeps original record date when a later payment updates the record', () {
      final entries = HistoryProjection.build(
        hisabs: [
          {
            'id': 'bill-1',
            'title': 'Fertilizer',
            'category': 'Khet',
            'amount': '50000',
            'date': '2026-11-27T10:00:00',
            'updatedAt': '2026-11-30T14:00:00',
            'payments': [
              {
                'amount': 20000,
                'direction': 'Diya',
                'date': '2026-11-28T12:00:00',
                'balanceAfter': 30000,
              },
            ],
          },
        ],
        khet: const [],
        members: const [],
        products: const [],
      );

      final original = entries.singleWhere((entry) => entry.title == 'Fertilizer');
      final payment = entries.singleWhere((entry) => entry.title == 'Payment · Fertilizer');
      expect(original.date, DateTime(2026, 11, 27, 10));
      expect(payment.date, DateTime(2026, 11, 28, 12));
      expect(payment.subtitle, contains('₹20000'));
      expect(payment.subtitle, contains('Remaining ₹30000'));
    });

    test('shows person-to-person payments with person, amount and saved date once', () {
      final entries = HistoryProjection.build(
        hisabs: [
          {
            'id': 'person-payment-1',
            'title': 'Person payment · Paise liye',
            'paymentKind': 'PERSON_PAYMENT',
            'entryType': 'PAYMENT',
            'personName': 'Abhi',
            'category': 'Khet',
            'direction': 'RECEIVED',
            'amount': '30000',
            'balanceAfter': 10000,
            'date': '2026-11-28T19:40:00',
          },
        ],
        khet: const [],
        members: const [],
        products: const [],
      );

      expect(entries, hasLength(1));
      expect(entries.single.title, contains('Abhi'));
      expect(entries.single.title, contains('आपको पैसे मिले'));
      expect(entries.single.subtitle, contains('₹30000'));
      expect(entries.single.date, DateTime(2026, 11, 28, 19, 40));
    });

    test('classifies purchase payments as KHET and shows absolute paid amount', () {
      final entries = HistoryProjection.build(
        hisabs: const [],
        khet: [
          {
            'id': 'vendor-payment-1',
            'type': 'KHET_PURCHASE_PAYMENT',
            'vendorName': 'Shop',
            'direction': 'Diya',
            'amount': 1500,
            'balanceAfter': 3500,
            'date': '2026-11-28T15:00:00',
          },
        ],
        members: const [],
        products: const [],
      );

      expect(entries, hasLength(1));
      expect(entries.single.type, 'KHET');
      expect(entries.single.title, 'दुकानदार को भुगतान');
      expect(entries.single.subtitle, contains('₹1500'));
      expect(entries.single.date, DateTime(2026, 11, 28, 15));
    });

    test('uses parent date instead of inventing today when payment date is absent', () {
      final entries = HistoryProjection.build(
        hisabs: [
          {
            'id': 'bill-2',
            'title': 'Old bill',
            'category': 'Khet',
            'amount': '1000',
            'date': '2026-11-20T09:00:00',
            'payments': [{'amount': 200, 'direction': 'Diya'}],
          },
        ],
        khet: const [],
        members: const [],
        products: const [],
      );

      final payment = entries.singleWhere((entry) => entry.title == 'Payment · Old bill');
      expect(payment.date, DateTime(2026, 11, 20, 9));
    });

    test('includes water cash payments, water exchange and work settlement by activity date', () {
      final entries = HistoryProjection.build(
        hisabs: const [],
        khet: [
          {
            'id': 'pani-1',
            'type': 'PANI',
            'contact': 'Abhi',
            'wellType': 'Tubewell',
            'date': '2026-11-27T10:00:00',
            'waterCashPaymentHistory': [
              {
                'amount': 500,
                'direction': 'Diya',
                'date': '2026-11-28T11:00:00',
                'balanceBefore': 600,
                'balanceAfter': 100,
              },
              {
                'amount': 0,
                'direction': 'WorkSettlement',
                'date': '2026-11-29T12:00:00',
                'balanceBefore': 100,
                'balanceAfter': 0,
                'note': 'Khet mein hal chalwaya',
              },
            ],
            'waterExchangeHistory': [
              {
                'minutes': 30,
                'date': '2026-11-28T13:00:00',
                'balanceBefore': 60,
                'balanceAfter': 30,
                'note': 'Pani ka badla',
              },
            ],
          },
        ],
        members: const [],
        products: const [],
      );

      final waterPayment = entries.singleWhere((entry) => entry.title.startsWith('Water payment'));
      final workSettlement = entries.singleWhere((entry) => entry.title.startsWith('Work settlement'));
      final waterExchange = entries.singleWhere((entry) => entry.title.startsWith('Water settlement'));

      expect(waterPayment.type, 'PANI');
      expect(waterPayment.title, contains('Abhi · Tubewell'));
      expect(waterPayment.subtitle, contains('₹500'));
      expect(waterPayment.date, DateTime(2026, 11, 28, 11));
      expect(workSettlement.subtitle, contains('Khet mein hal chalwaya'));
      expect(workSettlement.date, DateTime(2026, 11, 29, 12));
      expect(waterExchange.subtitle, contains('30 min'));
      expect(waterExchange.date, DateTime(2026, 11, 28, 13));
    });
    test('backdated entry sorts by the time it was entered, but displays its backdated date', () {
      final entries = HistoryProjection.build(
        hisabs: [
          {
            'id': 'backdated',
            'title': 'Old work entered today',
            'date': '2026-11-20T08:00:00',
            'createdAt': '2026-11-30T19:00:00',
            'amount': 100,
          },
          {
            'id': 'recent',
            'title': 'Earlier entry today',
            'date': '2026-11-30T18:00:00',
            'createdAt': '2026-11-30T18:00:00',
            'amount': 200,
          },
        ],
        khet: const [],
        members: const [],
        products: const [],
      );
      expect(entries.first.title, 'Old work entered today');
      expect(entries.first.date, DateTime(2026, 11, 20, 8));
      expect(entries.first.sortDate, DateTime(2026, 11, 30, 19));
    });

  });
}
