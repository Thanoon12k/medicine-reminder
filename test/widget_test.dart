import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_reminder_app/core/format.dart';
import 'package:medicine_reminder_app/models/models.dart';

void main() {
  group('تنسيق الأرقام والأوقات', () {
    test('الأرقام العربية', () {
      Fmt.arabicDigits = true;
      expect(Fmt.n(2026), '٢٠٢٦');
      Fmt.arabicDigits = false;
      expect(Fmt.n(2026), '2026');
    });

    test('تنسيق الوقت', () {
      Fmt.arabicDigits = false;
      expect(Fmt.time(8 * 60 + 30), '8:30 صباحاً');
      expect(Fmt.time(20 * 60), '8:00 ليلاً');
      expect(Fmt.time(0), '12:00 ليلاً');
    });

    test('تخزين وقراءة التاريخ', () {
      final DateTime d = DateTime(2026, 8, 20);
      expect(Fmt.storeDate(d), '2026-08-20');
      expect(Fmt.parseDate('2026-08-20'), d);
    });
  });

  group('جدول الدواء', () {
    test('أيام الأسبوع والمدة', () {
      final Medicine m = Medicine(
        patientId: 1,
        name: 'دواء',
        startDate: '2026-08-17', // الاثنين
        durationDays: 3,
        times: <int>[480, 1200],
        weekdaysMask: 127,
      );
      expect(m.activeOnDay(DateTime(2026, 8, 17)), isTrue);
      expect(m.activeOnDay(DateTime(2026, 8, 19)), isTrue);
      expect(m.activeOnDay(DateTime(2026, 8, 20)), isFalse); // بعد انتهاء المدة
      expect(m.activeOnDay(DateTime(2026, 8, 16)), isFalse); // قبل البداية
    });

    test('أيام محددة فقط', () {
      final Medicine m = Medicine(
        patientId: 1,
        name: 'دواء',
        startDate: '2026-08-01',
        weekdaysMask: 1, // الاثنين فقط
      );
      expect(m.activeOnDay(DateTime(2026, 8, 17)), isTrue); // اثنين
      expect(m.activeOnDay(DateTime(2026, 8, 18)), isFalse); // ثلاثاء
    });

    test('حساب الأيام المتبقية من المخزون', () {
      final Medicine m = Medicine(
        patientId: 1,
        name: 'دواء',
        dose: 2,
        times: <int>[480, 1200],
        totalUnits: 40,
        remainingUnits: 20,
      );
      expect(m.daysLeftByStock, 5);
      expect(m.takenUnits, 20);
    });
  });
}
