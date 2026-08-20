import '../core/format.dart';

/// شكل الدواء.
enum MedForm { capsule, tablet, syrup, injection, drops }

extension MedFormInfo on MedForm {
  String get label {
    switch (this) {
      case MedForm.capsule:
        return 'كبسولة';
      case MedForm.tablet:
        return 'حبة (قرص)';
      case MedForm.syrup:
        return 'شراب';
      case MedForm.injection:
        return 'إبرة';
      case MedForm.drops:
        return 'قطرة';
    }
  }

  /// وحدة الجرعة الافتراضية.
  String get unit {
    switch (this) {
      case MedForm.capsule:
        return 'كبسولة';
      case MedForm.tablet:
        return 'حبة';
      case MedForm.syrup:
        return 'ملعقة';
      case MedForm.injection:
        return 'إبرة';
      case MedForm.drops:
        return 'نقطة';
    }
  }

  /// اسم مخزون الدواء (الكمية المتبقية).
  String get stockUnit {
    switch (this) {
      case MedForm.syrup:
        return 'ملعقة';
      default:
        return unit;
    }
  }
}

MedForm formFromIndex(int i) =>
    MedForm.values[i.clamp(0, MedForm.values.length - 1)];

/// المريض.
class Patient {
  Patient({
    this.id,
    required this.name,
    this.colorIndex = 0,
    this.note = '',
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final int? id;
  final String name;
  final int colorIndex;
  final String note;
  final int createdAt;

  Patient copyWith({int? id, String? name, int? colorIndex, String? note}) =>
      Patient(
        id: id ?? this.id,
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        note: note ?? this.note,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'name': name,
    'color_index': colorIndex,
    'note': note,
    'created_at': createdAt,
  };

  static Patient fromMap(Map<String, Object?> m) => Patient(
    id: m['id'] as int?,
    name: (m['name'] as String?) ?? '',
    colorIndex: (m['color_index'] as int?) ?? 0,
    note: (m['note'] as String?) ?? '',
    createdAt: (m['created_at'] as int?) ?? 0,
  );
}

/// الدواء وجدول أخذه.
class Medicine {
  Medicine({
    this.id,
    required this.patientId,
    required this.name,
    this.form = MedForm.tablet,
    this.colorIndex = 0,
    this.dose = 1,
    this.unit = 'حبة',
    this.totalUnits = 0,
    this.remainingUnits = 0,
    String? startDate,
    this.durationDays = 0,
    this.times = const <int>[480],
    this.weekdaysMask = 127,
    this.alarmMode = true,
    this.notes = '',
    this.active = true,
    int? createdAt,
  }) : startDate = startDate ?? Fmt.storeDate(DateTime.now()),
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final int? id;
  final int patientId;
  final String name;
  final MedForm form;
  final int colorIndex;

  /// كمية الجرعة الواحدة (مثلاً حبتان = 2).
  final double dose;

  /// وحدة الجرعة (حبة، ملعقة، نقطة ...).
  final String unit;

  /// إجمالي الكمية في الكورس العلاجي (لعرض الشريط).
  final int totalUnits;

  /// المتبقي حالياً.
  final double remainingUnits;

  /// تاريخ البدء بصيغة yyyy-MM-dd.
  final String startDate;

  /// مدة الكورس بالأيام، صفر = مستمر بدون نهاية.
  final int durationDays;

  /// أوقات الأخذ بالدقائق من منتصف الليل.
  final List<int> times;

  /// أيام الأسبوع المفعّلة (بت لكل يوم، الاثنين = 1).
  final int weekdaysMask;

  /// منبه قوي بصوت مستمر أم إشعار هادئ.
  final bool alarmMode;

  final String notes;
  final bool active;
  final int createdAt;

  DateTime get start => Fmt.parseDate(startDate);

  DateTime? get endDate => durationDays > 0
      ? start.add(Duration(days: durationDays - 1))
      : null;

  bool get finished => durationDays > 0 && DateTime.now().isAfter(
    endDate!.add(const Duration(days: 1)),
  );

  int get takenUnits {
    final int t = (totalUnits - remainingUnits).round();
    return t < 0 ? 0 : t;
  }

  /// عدد الجرعات في اليوم الواحد.
  int get dosesPerDay => times.length;

  /// كم يوماً تكفي الكمية المتبقية.
  int get daysLeftByStock {
    final double perDay = dose * times.length;
    if (perDay <= 0) return 0;
    return (remainingUnits / perDay).floor();
  }

  bool activeOnDay(DateTime day) {
    if (!active) return false;
    final DateTime d = Fmt.dateOnly(day);
    final DateTime s = Fmt.dateOnly(start);
    if (d.isBefore(s)) return false;
    if (durationDays > 0) {
      final DateTime e = Fmt.dateOnly(s.add(Duration(days: durationDays - 1)));
      if (d.isAfter(e)) return false;
    }
    final int bit = 1 << (d.weekday - 1);
    return (weekdaysMask & bit) != 0;
  }

  Medicine copyWith({
    int? id,
    int? patientId,
    String? name,
    MedForm? form,
    int? colorIndex,
    double? dose,
    String? unit,
    int? totalUnits,
    double? remainingUnits,
    String? startDate,
    int? durationDays,
    List<int>? times,
    int? weekdaysMask,
    bool? alarmMode,
    String? notes,
    bool? active,
  }) => Medicine(
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    name: name ?? this.name,
    form: form ?? this.form,
    colorIndex: colorIndex ?? this.colorIndex,
    dose: dose ?? this.dose,
    unit: unit ?? this.unit,
    totalUnits: totalUnits ?? this.totalUnits,
    remainingUnits: remainingUnits ?? this.remainingUnits,
    startDate: startDate ?? this.startDate,
    durationDays: durationDays ?? this.durationDays,
    times: times ?? this.times,
    weekdaysMask: weekdaysMask ?? this.weekdaysMask,
    alarmMode: alarmMode ?? this.alarmMode,
    notes: notes ?? this.notes,
    active: active ?? this.active,
    createdAt: createdAt,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'patient_id': patientId,
    'name': name,
    'form': form.index,
    'color_index': colorIndex,
    'dose': dose,
    'unit': unit,
    'total_units': totalUnits,
    'remaining_units': remainingUnits,
    'start_date': startDate,
    'duration_days': durationDays,
    'times': times.join(','),
    'weekdays': weekdaysMask,
    'alarm': alarmMode ? 1 : 0,
    'notes': notes,
    'active': active ? 1 : 0,
    'created_at': createdAt,
  };

  static Medicine fromMap(Map<String, Object?> m) {
    final String rawTimes = (m['times'] as String?) ?? '';
    final List<int> times = rawTimes
        .split(',')
        .where((String e) => e.trim().isNotEmpty)
        .map((String e) => int.tryParse(e.trim()) ?? 0)
        .toList();
    times.sort();
    return Medicine(
      id: m['id'] as int?,
      patientId: (m['patient_id'] as int?) ?? 0,
      name: (m['name'] as String?) ?? '',
      form: formFromIndex((m['form'] as int?) ?? 1),
      colorIndex: (m['color_index'] as int?) ?? 0,
      dose: ((m['dose'] as num?) ?? 1).toDouble(),
      unit: (m['unit'] as String?) ?? 'حبة',
      totalUnits: (m['total_units'] as int?) ?? 0,
      remainingUnits: ((m['remaining_units'] as num?) ?? 0).toDouble(),
      startDate: (m['start_date'] as String?) ?? Fmt.storeDate(DateTime.now()),
      durationDays: (m['duration_days'] as int?) ?? 0,
      times: times.isEmpty ? <int>[480] : times,
      weekdaysMask: (m['weekdays'] as int?) ?? 127,
      alarmMode: ((m['alarm'] as int?) ?? 1) == 1,
      notes: (m['notes'] as String?) ?? '',
      active: ((m['active'] as int?) ?? 1) == 1,
      createdAt: (m['created_at'] as int?) ?? 0,
    );
  }
}

/// حالة الجرعة المسجّلة.
class DoseStatus {
  static const int taken = 0;
  static const int skipped = 1;
}

/// سجل جرعة (مأخوذة أو متجاوَزة).
class DoseLog {
  DoseLog({
    this.id,
    required this.medicineId,
    required this.patientId,
    required this.scheduledAt,
    required this.takenAt,
    required this.status,
    required this.amount,
    required this.form,
    required this.colorIndex,
    required this.medName,
  });

  final int? id;
  final int medicineId;
  final int patientId;
  final int scheduledAt;
  final int takenAt;
  final int status;
  final double amount;
  final MedForm form;
  final int colorIndex;
  final String medName;

  DateTime get scheduledTime => DateTime.fromMillisecondsSinceEpoch(scheduledAt);
  DateTime get takenTime => DateTime.fromMillisecondsSinceEpoch(takenAt);
  bool get isTaken => status == DoseStatus.taken;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'medicine_id': medicineId,
    'patient_id': patientId,
    'scheduled_at': scheduledAt,
    'taken_at': takenAt,
    'status': status,
    'amount': amount,
    'form': form.index,
    'color_index': colorIndex,
    'med_name': medName,
  };

  static DoseLog fromMap(Map<String, Object?> m) => DoseLog(
    id: m['id'] as int?,
    medicineId: (m['medicine_id'] as int?) ?? 0,
    patientId: (m['patient_id'] as int?) ?? 0,
    scheduledAt: (m['scheduled_at'] as int?) ?? 0,
    takenAt: (m['taken_at'] as int?) ?? 0,
    status: (m['status'] as int?) ?? 0,
    amount: ((m['amount'] as num?) ?? 1).toDouble(),
    form: formFromIndex((m['form'] as int?) ?? 1),
    colorIndex: (m['color_index'] as int?) ?? 0,
    medName: (m['med_name'] as String?) ?? '',
  );
}

/// موعد جرعة محسوب (غير مخزَّن).
class DoseOccurrence {
  DoseOccurrence({required this.medicine, required this.time, this.log});

  final Medicine medicine;
  final DateTime time;
  final DoseLog? log;

  bool get isTaken => log != null && log!.status == DoseStatus.taken;
  bool get isSkipped => log != null && log!.status == DoseStatus.skipped;
  bool get isPending => log == null;

  bool get isLate =>
      isPending && DateTime.now().isAfter(time.add(const Duration(minutes: 20)));

  int get key => time.millisecondsSinceEpoch;
}

/// مجموعة أدوية لنفس المريض في نفس اللحظة — تنبيه واحد لها كلها.
///
/// بدون التجميع كان كل دواء يُطلق منبهاً منفصلاً، فتتزاحم أربع شاشات
/// وأربعة أصوات، ويضيع تسجيل بقية الجرعات عند الاستجابة لواحد منها.
class DoseGroup {
  DoseGroup({
    required this.patientId,
    required this.time,
    required this.medicines,
  });

  final int patientId;
  final DateTime time;
  final List<Medicine> medicines;

  /// يكفي أن يكون دواء واحد منبهاً قوياً ليصير التنبيه قوياً.
  bool get alarmMode => medicines.any((Medicine m) => m.alarmMode);

  int get scheduledAt => time.millisecondsSinceEpoch;

  String get key => '${patientId}_$scheduledAt';

  /// أسماء الأدوية مفصولة بفواصل — تُستعمل في نص الإشعار والنطق.
  String get names => medicines.map((Medicine m) => m.name).join('، ');
}

/// تأجيل مسجَّل (يُعاد جدولته بعد إعادة تشغيل الهاتف).
class Snooze {
  Snooze({
    this.id,
    required this.medicineId,
    required this.patientId,
    required this.scheduledAt,
    required this.fireAt,
  });

  final int? id;
  final int medicineId;
  final int patientId;
  final int scheduledAt;
  final int fireAt;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'medicine_id': medicineId,
    'patient_id': patientId,
    'scheduled_at': scheduledAt,
    'fire_at': fireAt,
  };

  static Snooze fromMap(Map<String, Object?> m) => Snooze(
    id: m['id'] as int?,
    medicineId: (m['medicine_id'] as int?) ?? 0,
    patientId: (m['patient_id'] as int?) ?? 0,
    scheduledAt: (m['scheduled_at'] as int?) ?? 0,
    fireAt: (m['fire_at'] as int?) ?? 0,
  );
}
