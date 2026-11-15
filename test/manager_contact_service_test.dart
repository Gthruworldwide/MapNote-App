import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/manager_contact_service.dart';

/// Numbers in the manager sheet are typed by hand in Egypt, so they arrive in
/// several shapes. Getting this wrong dials a wrong number or opens an empty
/// WhatsApp chat, so each form is pinned.
void main() {
  group('normalizePhone', () {
    test('keeps an international prefix and strips separators', () {
      expect(ManagerContactService.normalizePhone('+20 100 123 4567'),
          '+201001234567');
      expect(ManagerContactService.normalizePhone('+20-100-123-4567'),
          '+201001234567');
    });

    test('keeps the local trunk zero', () {
      expect(ManagerContactService.normalizePhone('0100 123 4567'),
          '01001234567');
      expect(ManagerContactService.normalizePhone('(0100) 123-4567'),
          '01001234567');
    });

    test('folds Arabic-Indic digits', () {
      expect(ManagerContactService.normalizePhone('٠١٠٠١٢٣٤٥٦٧'), '01001234567');
      expect(ManagerContactService.normalizePhone('۰۱۰۰۱۲۳۴۵۶۷'), '01001234567');
    });

    test('rejects values with nothing dialable', () {
      expect(ManagerContactService.normalizePhone(null), isNull);
      expect(ManagerContactService.normalizePhone('   '), isNull);
      expect(ManagerContactService.normalizePhone('-'), isNull);
      expect(ManagerContactService.normalizePhone('abc'), isNull);
      expect(ManagerContactService.normalizePhone('12345'), isNull);
    });
  });

  group('normalizeWhatsAppNumber', () {
    test('drops the Egyptian trunk zero and adds the country code', () {
      expect(ManagerContactService.normalizeWhatsAppNumber('01001234567'),
          '201001234567');
    });

    test('leaves an already international number alone', () {
      expect(ManagerContactService.normalizeWhatsAppNumber('+201001234567'),
          '201001234567');
      expect(ManagerContactService.normalizeWhatsAppNumber('00201001234567'),
          '201001234567');
    });

    test('adds the country code to a number typed without the zero', () {
      expect(ManagerContactService.normalizeWhatsAppNumber('1001234567'),
          '201001234567');
    });

    test('rejects values with nothing dialable', () {
      expect(ManagerContactService.normalizeWhatsAppNumber(''), isNull);
      expect(ManagerContactService.normalizeWhatsAppNumber(null), isNull);
    });
  });
}
