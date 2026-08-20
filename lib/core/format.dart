/// تنسيق الأرقام والتواريخ والأوقات بالعربية.
class Fmt {
  /// هل تُعرض الأرقام بالصيغة العربية (٠١٢٣) أم الإنجليزية (0123).
  static bool arabicDigits = true;

  static const List<String> _ar = <String>[
    '٠',
    '١',
    '٢',
    '٣',
    '٤',
    '٥',
    '٦',
    '٧',
    '٨',
    '٩',
  ];

  /// تحويل أي رقم إلى نص بالأرقام المختارة.
  static String n(Object value) {
    String s = value is double
        ? (value == value.roundToDouble()
              ? value.toInt().toString()
              : value.toString())
        : value.toString();
    if (!arabicDigits) return s;
    final StringBuffer b = StringBuffer();
    for (final int code in s.runes) {
      if (code >= 48 && code <= 57) {
        b.write(_ar[code - 48]);
      } else {
        b.writeCharCode(code);
      }
    }
    return b.toString();
  }

  static const List<String> monthNames = <String>[
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
  ];

  /// أسماء أيام الأسبوع، الفهرس ١ = الاثنين (مثل DateTime.weekday).
  static const List<String> weekdayNames = <String>[
    '',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  /// أسماء مختصرة لأيام الأسبوع للأزرار.
  static const List<String> weekdayShort = <String>[
    '',
    'ن',
    'ث',
    'ر',
    'خ',
    'ج',
    'س',
    'ح',
  ];

  /// جزء اليوم: صباحاً / ظهراً / مساءً / ليلاً.
  static String dayPart(int hour) {
    if (hour < 5) return 'ليلاً';
    if (hour < 12) return 'صباحاً';
    if (hour < 17) return 'ظهراً';
    if (hour < 20) return 'مساءً';
    return 'ليلاً';
  }

  /// تنسيق وقت مثل: ٨:٣٠ صباحاً
  static String time(int minutesOfDay) {
    final int h = (minutesOfDay ~/ 60) % 24;
    final int m = minutesOfDay % 60;
    int h12 = h % 12;
    if (h12 == 0) h12 = 12;
    final String mm = m.toString().padLeft(2, '0');
    return '${n(h12)}:${n(mm)} ${dayPart(h)}';
  }

  static String timeOf(DateTime t) => time(t.hour * 60 + t.minute);

  /// تنسيق تاريخ مثل: الخميس ٢٠ آب ٢٠٢٦
  static String date(DateTime d) =>
      '${weekdayNames[d.weekday]} ${n(d.day)} ${monthNames[d.month - 1]} ${n(d.year)}';

  /// تاريخ قصير: ٢٠ آب
  static String dateShort(DateTime d) => '${n(d.day)} ${monthNames[d.month - 1]}';

  /// نص نسبي بسيط: اليوم / أمس / غداً / التاريخ.
  static String relativeDay(DateTime d) {
    final DateTime today = dateOnly(DateTime.now());
    final int diff = dateOnly(d).difference(today).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == -1) return 'أمس';
    if (diff == 1) return 'غداً';
    return date(d);
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// تحويل التاريخ إلى نص للتخزين: yyyy-MM-dd
  static String storeDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime parseDate(String s) {
    final List<String> p = s.split('-');
    if (p.length != 3) return dateOnly(DateTime.now());
    return DateTime(
      int.tryParse(p[0]) ?? 2026,
      int.tryParse(p[1]) ?? 1,
      int.tryParse(p[2]) ?? 1,
    );
  }

  /// صيغة مبسطة للعدد مع الوحدة: «٣ حبة» ← «٣ حبة» (واضحة لكبار السن).
  static String countUnit(num count, String unit) => '${n(count)} $unit';
}
