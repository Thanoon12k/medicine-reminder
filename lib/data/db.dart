import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// قاعدة بيانات محلية على الجهاز فقط — لا تحتاج إنترنت إطلاقاً.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final String dir = await getDatabasesPath();
    final String path = p.join(dir, 'dawaii.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (Database d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database d, int v) async {
        await d.execute('''
          CREATE TABLE patients(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            color_index INTEGER NOT NULL DEFAULT 0,
            note TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL
          )''');

        await d.execute('''
          CREATE TABLE medicines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            patient_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            form INTEGER NOT NULL DEFAULT 1,
            color_index INTEGER NOT NULL DEFAULT 0,
            dose REAL NOT NULL DEFAULT 1,
            unit TEXT NOT NULL DEFAULT 'حبة',
            total_units INTEGER NOT NULL DEFAULT 0,
            remaining_units REAL NOT NULL DEFAULT 0,
            start_date TEXT NOT NULL,
            duration_days INTEGER NOT NULL DEFAULT 0,
            times TEXT NOT NULL DEFAULT '480',
            weekdays INTEGER NOT NULL DEFAULT 127,
            alarm INTEGER NOT NULL DEFAULT 1,
            notes TEXT NOT NULL DEFAULT '',
            active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL
          )''');

        await d.execute('''
          CREATE TABLE dose_logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            medicine_id INTEGER NOT NULL,
            patient_id INTEGER NOT NULL,
            scheduled_at INTEGER NOT NULL,
            taken_at INTEGER NOT NULL,
            status INTEGER NOT NULL DEFAULT 0,
            amount REAL NOT NULL DEFAULT 1,
            form INTEGER NOT NULL DEFAULT 1,
            color_index INTEGER NOT NULL DEFAULT 0,
            med_name TEXT NOT NULL DEFAULT ''
          )''');

        await d.execute(
          'CREATE UNIQUE INDEX idx_dose_unique ON dose_logs(medicine_id, scheduled_at)',
        );
        await d.execute(
          'CREATE INDEX idx_dose_patient ON dose_logs(patient_id, taken_at)',
        );

        await d.execute('''
          CREATE TABLE snoozes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            medicine_id INTEGER NOT NULL,
            patient_id INTEGER NOT NULL,
            scheduled_at INTEGER NOT NULL,
            fire_at INTEGER NOT NULL
          )''');

        await d.execute(
          'CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT NOT NULL)',
        );
      },
    );
  }

  // ------------------------- المرضى -------------------------

  Future<List<Patient>> patients() async {
    final Database d = await db;
    final List<Map<String, Object?>> rows = await d.query(
      'patients',
      orderBy: 'created_at ASC',
    );
    return rows.map(Patient.fromMap).toList();
  }

  Future<int> insertPatient(Patient patient) async {
    final Database d = await db;
    return d.insert('patients', patient.toMap());
  }

  Future<void> updatePatient(Patient patient) async {
    final Database d = await db;
    await d.update(
      'patients',
      patient.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[patient.id],
    );
  }

  Future<void> deletePatient(int id) async {
    final Database d = await db;
    await d.delete('dose_logs', where: 'patient_id = ?', whereArgs: <Object?>[id]);
    await d.delete('snoozes', where: 'patient_id = ?', whereArgs: <Object?>[id]);
    await d.delete('medicines', where: 'patient_id = ?', whereArgs: <Object?>[id]);
    await d.delete('patients', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  // ------------------------- الأدوية -------------------------

  Future<List<Medicine>> medicines() async {
    final Database d = await db;
    final List<Map<String, Object?>> rows = await d.query(
      'medicines',
      orderBy: 'created_at ASC',
    );
    return rows.map(Medicine.fromMap).toList();
  }

  Future<int> insertMedicine(Medicine m) async {
    final Database d = await db;
    return d.insert('medicines', m.toMap());
  }

  Future<void> updateMedicine(Medicine m) async {
    final Database d = await db;
    await d.update(
      'medicines',
      m.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[m.id],
    );
  }

  Future<void> setRemaining(int medicineId, double remaining) async {
    final Database d = await db;
    await d.update(
      'medicines',
      <String, Object?>{'remaining_units': remaining < 0 ? 0 : remaining},
      where: 'id = ?',
      whereArgs: <Object?>[medicineId],
    );
  }

  Future<void> deleteMedicine(int id) async {
    final Database d = await db;
    await d.delete('snoozes', where: 'medicine_id = ?', whereArgs: <Object?>[id]);
    await d.delete('medicines', where: 'id = ?', whereArgs: <Object?>[id]);
    // ملاحظة: تبقى الحبوب المأخوذة داخل العلبة حتى بعد حذف الدواء.
  }

  // ------------------------- سجل الجرعات -------------------------

  /// سجلات جرعات مريض معيّن (الأحدث أولاً).
  Future<List<DoseLog>> logsForPatient(int patientId, {int limit = 2000}) async {
    final Database d = await db;
    final List<Map<String, Object?>> rows = await d.query(
      'dose_logs',
      where: 'patient_id = ?',
      whereArgs: <Object?>[patientId],
      orderBy: 'taken_at DESC',
      limit: limit,
    );
    return rows.map(DoseLog.fromMap).toList();
  }

  /// سجلات الجرعات ضمن فترة زمنية (لبناء قائمة اليوم).
  Future<List<DoseLog>> logsBetween(int fromMs, int toMs) async {
    final Database d = await db;
    final List<Map<String, Object?>> rows = await d.query(
      'dose_logs',
      where: 'scheduled_at >= ? AND scheduled_at <= ?',
      whereArgs: <Object?>[fromMs, toMs],
    );
    return rows.map(DoseLog.fromMap).toList();
  }

  Future<void> upsertLog(DoseLog log) async {
    final Database d = await db;
    await d.insert(
      'dose_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DoseLog?> findLog(int medicineId, int scheduledAt) async {
    final Database d = await db;
    final List<Map<String, Object?>> rows = await d.query(
      'dose_logs',
      where: 'medicine_id = ? AND scheduled_at = ?',
      whereArgs: <Object?>[medicineId, scheduledAt],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DoseLog.fromMap(rows.first);
  }

  Future<void> deleteLog(int medicineId, int scheduledAt) async {
    final Database d = await db;
    await d.delete(
      'dose_logs',
      where: 'medicine_id = ? AND scheduled_at = ?',
      whereArgs: <Object?>[medicineId, scheduledAt],
    );
  }

  // ------------------------- التأجيل -------------------------

  Future<List<Snooze>> snoozes() async {
    final Database d = await db;
    final List<Map<String, Object?>> rows = await d.query('snoozes');
    return rows.map(Snooze.fromMap).toList();
  }

  Future<void> addSnooze(Snooze s) async {
    final Database d = await db;
    await d.insert('snoozes', s.toMap());
  }

  Future<void> clearSnoozeFor(int medicineId, int scheduledAt) async {
    final Database d = await db;
    await d.delete(
      'snoozes',
      where: 'medicine_id = ? AND scheduled_at = ?',
      whereArgs: <Object?>[medicineId, scheduledAt],
    );
  }

  Future<void> purgeOldSnoozes() async {
    final Database d = await db;
    await d.delete(
      'snoozes',
      where: 'fire_at < ?',
      whereArgs: <Object?>[DateTime.now().millisecondsSinceEpoch],
    );
  }

  // ------------------------- الإعدادات -------------------------

  Future<Map<String, String>> allSettings() async {
    final Database d = await db;
    final List<Map<String, Object?>> rows = await d.query('settings');
    return <String, String>{
      for (final Map<String, Object?> r in rows)
        (r['k'] as String): (r['v'] as String),
    };
  }

  Future<void> setSetting(String key, String value) async {
    final Database d = await db;
    await d.insert('settings', <String, Object?>{
      'k': key,
      'v': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
