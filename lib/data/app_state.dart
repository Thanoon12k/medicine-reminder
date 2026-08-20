import 'package:flutter/foundation.dart';

import '../core/format.dart';
import '../models/models.dart';
import '../services/notifications.dart';
import 'db.dart';

/// حالة التطبيق بالكامل — مصدر واحد للبيانات، محلي ١٠٠٪.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  final AppDb _db = AppDb.instance;

  List<Patient> patients = <Patient>[];
  List<Medicine> medicines = <Medicine>[];

  /// سجل جرعات المريض الحالي (الأحدث أولاً).
  List<DoseLog> patientLogs = <DoseLog>[];

  final Map<String, DoseLog> _logIndex = <String, DoseLog>{};

  int? currentPatientId;
  bool loaded = false;

  // ------------------------- الإعدادات -------------------------
  bool arabicDigits = true;
  int snoozeMinutes = 10;
  double textScale = 1.0;
  bool defaultAlarmMode = true;

  /// مفتاح آخر جرعة أُضيفت — لتشغيل حركة سقوط الحبة داخل العلبة.
  String? lastDropKey;

  Patient? get currentPatient {
    if (patients.isEmpty) return null;
    for (final Patient p in patients) {
      if (p.id == currentPatientId) return p;
    }
    return patients.first;
  }

  List<Medicine> get currentMedicines {
    final int? pid = currentPatient?.id;
    if (pid == null) return <Medicine>[];
    return medicines.where((Medicine m) => m.patientId == pid).toList();
  }

  Map<int, String> get patientNames => <int, String>{
    for (final Patient p in patients)
      if (p.id != null) p.id!: p.name,
  };

  Map<int, Medicine> get medicinesById => <int, Medicine>{
    for (final Medicine m in medicines)
      if (m.id != null) m.id!: m,
  };

  Medicine? medicineById(int id) {
    for (final Medicine m in medicines) {
      if (m.id == id) return m;
    }
    return null;
  }

  Patient? patientById(int id) {
    for (final Patient p in patients) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ------------------------- التحميل -------------------------

  Future<void> load() async {
    final Map<String, String> settings = await _db.allSettings();
    arabicDigits = (settings['arabic_digits'] ?? '1') == '1';
    snoozeMinutes = int.tryParse(settings['snooze_minutes'] ?? '10') ?? 10;
    textScale = double.tryParse(settings['text_scale'] ?? '1.0') ?? 1.0;
    defaultAlarmMode = (settings['default_alarm'] ?? '1') == '1';
    currentPatientId = int.tryParse(settings['current_patient'] ?? '');
    Fmt.arabicDigits = arabicDigits;

    patients = await _db.patients();
    medicines = await _db.medicines();
    if (currentPatientId == null && patients.isNotEmpty) {
      currentPatientId = patients.first.id;
    }
    await _loadLogs();
    await _db.purgeOldSnoozes();
    loaded = true;
    notifyListeners();
    await reschedule();
  }

  Future<void> _loadLogs() async {
    final int? pid = currentPatient?.id;
    _logIndex.clear();
    if (pid == null) {
      patientLogs = <DoseLog>[];
      return;
    }
    patientLogs = await _db.logsForPatient(pid);
    for (final DoseLog log in patientLogs) {
      _logIndex['${log.medicineId}_${log.scheduledAt}'] = log;
    }
  }

  Future<void> _refresh() async {
    patients = await _db.patients();
    medicines = await _db.medicines();
    await _loadLogs();
    notifyListeners();
  }

  // ------------------------- المرضى -------------------------

  Future<void> setCurrentPatient(int id) async {
    currentPatientId = id;
    await _db.setSetting('current_patient', '$id');
    await _loadLogs();
    notifyListeners();
  }

  Future<int> addPatient(String name, int colorIndex) async {
    final int id = await _db.insertPatient(
      Patient(name: name.trim(), colorIndex: colorIndex),
    );
    patients = await _db.patients();
    currentPatientId ??= id;
    await _db.setSetting('current_patient', '${currentPatientId ?? id}');
    notifyListeners();
    return id;
  }

  Future<void> updatePatient(Patient patient) async {
    await _db.updatePatient(patient);
    await _refresh();
    await reschedule();
  }

  Future<void> deletePatient(int id) async {
    await _db.deletePatient(id);
    patients = await _db.patients();
    medicines = await _db.medicines();
    if (currentPatientId == id) {
      currentPatientId = patients.isNotEmpty ? patients.first.id : null;
      await _db.setSetting('current_patient', '${currentPatientId ?? ''}');
    }
    await _loadLogs();
    notifyListeners();
    await reschedule();
  }

  // ------------------------- الأدوية -------------------------

  Future<void> saveMedicine(Medicine m) async {
    if (m.id == null) {
      await _db.insertMedicine(m);
    } else {
      await _db.updateMedicine(m);
    }
    await _refresh();
    await reschedule();
  }

  Future<void> deleteMedicine(int id) async {
    await _db.deleteMedicine(id);
    await _refresh();
    await reschedule();
  }

  /// إضافة كمية جديدة إلى مخزون الدواء (تعبئة).
  Future<void> refill(Medicine m, int units) async {
    final Medicine updated = m.copyWith(
      totalUnits: m.totalUnits + units,
      remainingUnits: m.remainingUnits + units,
    );
    await _db.updateMedicine(updated);
    await _refresh();
    await reschedule();
  }

  // ------------------------- المواعيد -------------------------

  DoseLog? logFor(int medicineId, DateTime scheduled) =>
      _logIndex['${medicineId}_${scheduled.millisecondsSinceEpoch}'];

  /// كل مواعيد يوم معيّن للمريض الحالي، مرتبة حسب الوقت.
  List<DoseOccurrence> occurrencesForDay(DateTime day, {int? patientId}) {
    final int? pid = patientId ?? currentPatient?.id;
    if (pid == null) return <DoseOccurrence>[];
    final List<DoseOccurrence> out = <DoseOccurrence>[];
    for (final Medicine m in medicines) {
      if (m.patientId != pid) continue;
      if (!m.activeOnDay(day)) continue;
      for (final int minutes in m.times) {
        final DateTime t = DateTime(
          day.year,
          day.month,
          day.day,
          minutes ~/ 60,
          minutes % 60,
        );
        out.add(
          DoseOccurrence(
            medicine: m,
            time: t,
            log: m.id == null ? null : logFor(m.id!, t),
          ),
        );
      }
    }
    out.sort((DoseOccurrence a, DoseOccurrence b) => a.time.compareTo(b.time));
    return out;
  }

  /// مواعيد اليوم للمريض الحالي.
  List<DoseOccurrence> get todayOccurrences =>
      occurrencesForDay(DateTime.now());

  /// أقرب موعد قادم اليوم لم يُؤخذ بعد.
  DoseOccurrence? get nextDose {
    final DateTime now = DateTime.now();
    for (final DoseOccurrence o in todayOccurrences) {
      if (o.isPending && o.time.isAfter(now)) return o;
    }
    return null;
  }

  // ------------------------- تسجيل الجرعات -------------------------

  Future<void> takeDose(Medicine m, DateTime scheduled) async {
    if (m.id == null) return;
    final DoseLog log = DoseLog(
      medicineId: m.id!,
      patientId: m.patientId,
      scheduledAt: scheduled.millisecondsSinceEpoch,
      takenAt: DateTime.now().millisecondsSinceEpoch,
      status: DoseStatus.taken,
      amount: m.dose,
      form: m.form,
      colorIndex: m.colorIndex,
      medName: m.name,
    );
    await _db.upsertLog(log);
    if (m.totalUnits > 0) {
      final double left = m.remainingUnits - m.dose;
      await _db.setRemaining(m.id!, left < 0 ? 0 : left);
    }
    await _db.clearSnoozeFor(m.id!, scheduled.millisecondsSinceEpoch);
    lastDropKey = '${m.id}_${scheduled.millisecondsSinceEpoch}';
    await _refresh();
    await reschedule();
  }

  Future<void> skipDose(Medicine m, DateTime scheduled) async {
    if (m.id == null) return;
    await _db.upsertLog(
      DoseLog(
        medicineId: m.id!,
        patientId: m.patientId,
        scheduledAt: scheduled.millisecondsSinceEpoch,
        takenAt: DateTime.now().millisecondsSinceEpoch,
        status: DoseStatus.skipped,
        amount: m.dose,
        form: m.form,
        colorIndex: m.colorIndex,
        medName: m.name,
      ),
    );
    await _db.clearSnoozeFor(m.id!, scheduled.millisecondsSinceEpoch);
    await _refresh();
    await reschedule();
  }

  /// تراجع عن تسجيل جرعة.
  Future<void> undoDose(Medicine m, DateTime scheduled) async {
    if (m.id == null) return;
    final DoseLog? existing = logFor(m.id!, scheduled);
    await _db.deleteLog(m.id!, scheduled.millisecondsSinceEpoch);
    if (existing != null && existing.isTaken && m.totalUnits > 0) {
      await _db.setRemaining(m.id!, m.remainingUnits + existing.amount);
    }
    if (lastDropKey == '${m.id}_${scheduled.millisecondsSinceEpoch}') {
      lastDropKey = null;
    }
    await _refresh();
    await reschedule();
  }

  Future<void> snoozeDose(Medicine m, DateTime scheduled, {int? minutes}) async {
    if (m.id == null) return;
    final int mins = minutes ?? snoozeMinutes;
    await _db.clearSnoozeFor(m.id!, scheduled.millisecondsSinceEpoch);
    await _db.addSnooze(
      Snooze(
        medicineId: m.id!,
        patientId: m.patientId,
        scheduledAt: scheduled.millisecondsSinceEpoch,
        fireAt: DateTime.now()
            .add(Duration(minutes: mins))
            .millisecondsSinceEpoch,
      ),
    );
    await reschedule();
    notifyListeners();
  }

  // ------------------------- الإحصاءات -------------------------

  /// الجرعات المأخوذة (لعرضها داخل العلبة).
  List<DoseLog> takenLogs({DateTime? month}) {
    Iterable<DoseLog> list = patientLogs.where((DoseLog l) => l.isTaken);
    if (month != null) {
      list = list.where((DoseLog l) {
        final DateTime t = l.takenTime;
        return t.year == month.year && t.month == month.month;
      });
    }
    final List<DoseLog> out = list.toList();
    out.sort((DoseLog a, DoseLog b) => a.takenAt.compareTo(b.takenAt));
    return out;
  }

  /// عدد الأيام المتتالية التي أُخذت فيها كل الجرعات.
  int get streakDays {
    int streak = 0;
    DateTime day = Fmt.dateOnly(DateTime.now());
    for (int i = 0; i < 120; i++) {
      final List<DoseOccurrence> list = occurrencesForDay(day);
      if (list.isEmpty) {
        if (i == 0) {
          day = day.subtract(const Duration(days: 1));
          continue;
        }
        break;
      }
      final bool all = list.every((DoseOccurrence o) => o.isTaken);
      final bool anyFuture = list.any(
        (DoseOccurrence o) => o.time.isAfter(DateTime.now()),
      );
      if (all) {
        streak++;
      } else if (i == 0 && anyFuture) {
        // اليوم لم ينتهِ بعد — لا نكسر السلسلة.
      } else {
        break;
      }
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ------------------------- إعادة الجدولة -------------------------

  Future<void> reschedule({int daysAhead = 10}) async {
    try {
      await _db.purgeOldSnoozes();
      final DateTime now = DateTime.now();
      final List<({Medicine medicine, DateTime time})> upcoming =
          <({Medicine medicine, DateTime time})>[];

      for (int d = 0; d < daysAhead; d++) {
        final DateTime day = Fmt.dateOnly(now.add(Duration(days: d)));
        for (final Medicine m in medicines) {
          if (m.id == null) continue;
          if (!m.activeOnDay(day)) continue;
          if (m.totalUnits > 0 && m.remainingUnits <= 0) continue;
          for (final int minutes in m.times) {
            final DateTime t = DateTime(
              day.year,
              day.month,
              day.day,
              minutes ~/ 60,
              minutes % 60,
            );
            if (!t.isAfter(now)) continue;
            upcoming.add((medicine: m, time: t));
          }
        }
      }
      upcoming.sort((a, b) => a.time.compareTo(b.time));

      await NotificationService.rescheduleAll(
        occurrences: upcoming,
        patientNames: patientNames,
        snoozes: await _db.snoozes(),
        medicinesById: medicinesById,
      );
    } catch (e) {
      debugPrint('تعذّرت إعادة الجدولة: $e');
    }
  }

  // ------------------------- تعديل الإعدادات -------------------------

  Future<void> setArabicDigits(bool value) async {
    arabicDigits = value;
    Fmt.arabicDigits = value;
    await _db.setSetting('arabic_digits', value ? '1' : '0');
    notifyListeners();
  }

  Future<void> setSnoozeMinutes(int value) async {
    snoozeMinutes = value;
    await _db.setSetting('snooze_minutes', '$value');
    notifyListeners();
  }

  Future<void> setTextScale(double value) async {
    textScale = value;
    await _db.setSetting('text_scale', '$value');
    notifyListeners();
  }

  /// تحديث الواجهة (يُستدعى عند عودة التطبيق للمقدمة).
  void refreshUi() => notifyListeners();

  Future<void> setDefaultAlarmMode(bool value) async {
    defaultAlarmMode = value;
    await _db.setSetting('default_alarm', value ? '1' : '0');
    notifyListeners();
  }
}

final AppState appState = AppState.instance;
