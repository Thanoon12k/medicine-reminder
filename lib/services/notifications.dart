import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/format.dart';
import '../models/models.dart';

/// معرّفات أزرار الإشعار.
class NotifAction {
  static const String taken = 'taken';
  static const String snooze = 'snooze';
}

/// بيانات الجرعة المرفقة مع الإشعار.
class AlarmPayload {
  const AlarmPayload({
    required this.medicineId,
    required this.patientId,
    required this.scheduledAt,
    required this.notificationId,
  });

  final int medicineId;
  final int patientId;
  final int scheduledAt;
  final int notificationId;

  String encode() => jsonEncode(<String, Object?>{
    'm': medicineId,
    'p': patientId,
    't': scheduledAt,
    'n': notificationId,
  });

  static AlarmPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? data = jsonDecode(raw);
      if (data is! Map) return null;
      return AlarmPayload(
        medicineId: (data['m'] as num?)?.toInt() ?? 0,
        patientId: (data['p'] as num?)?.toInt() ?? 0,
        scheduledAt: (data['t'] as num?)?.toInt() ?? 0,
        notificationId: (data['n'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// كل ما يخص التذكير: منبه بصوت مستمر أو إشعار هادئ — كله محلي بدون إنترنت.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String alarmChannelId = 'dawaii_alarm_v1';
  static const String quietChannelId = 'dawaii_quiet_v1';

  /// أقصى عدد إشعارات مجدولة في وقت واحد (حد النظام ٥٠٠).
  static const int maxScheduled = 380;

  /// نطاق معرّفات إشعارات التأجيل.
  static const int _snoozeIdBase = 900000;

  static bool _ready = false;

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// تهيئة المنبهات والقنوات.
  static Future<void> init({
    required void Function(AlarmPayload payload, String? actionId) onResponse,
  }) async {
    if (_ready) return;
    _initTimezone();

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@drawable/ic_notification');

    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final AlarmPayload? payload = AlarmPayload.decode(response.payload);
        if (payload != null) onResponse(payload, response.actionId);
      },
    );

    await _createChannels();
    _ready = true;
  }

  static void _initTimezone() {
    try {
      tzdata.initializeTimeZones();
      final Duration deviceOffset = DateTime.now().timeZoneOffset;

      const List<String> preferred = <String>[
        'Asia/Baghdad',
        'Asia/Riyadh',
        'Asia/Kuwait',
        'Asia/Qatar',
        'Asia/Bahrain',
        'Asia/Dubai',
        'Asia/Muscat',
        'Asia/Aden',
        'Africa/Cairo',
        'Asia/Amman',
        'Asia/Damascus',
        'Asia/Beirut',
        'Asia/Hebron',
        'Africa/Khartoum',
        'Africa/Tripoli',
        'Africa/Tunis',
        'Africa/Algiers',
        'Africa/Casablanca',
        'Asia/Tehran',
        'Europe/Istanbul',
        'Asia/Karachi',
        'Asia/Kolkata',
        'Europe/London',
        'Europe/Berlin',
        'Europe/Paris',
        'America/New_York',
        'America/Chicago',
        'America/Los_Angeles',
      ];

      for (final String name in preferred) {
        final tz.Location? loc = _tryLocation(name);
        if (loc != null && tz.TZDateTime.now(loc).timeZoneOffset == deviceOffset) {
          tz.setLocalLocation(loc);
          return;
        }
      }

      for (final tz.Location loc in tz.timeZoneDatabase.locations.values) {
        if (tz.TZDateTime.now(loc).timeZoneOffset == deviceOffset) {
          tz.setLocalLocation(loc);
          return;
        }
      }
    } catch (e) {
      debugPrint('تعذّر ضبط المنطقة الزمنية: $e');
    }
  }

  static tz.Location? _tryLocation(String name) {
    try {
      return tz.getLocation(name);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _createChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return;

    await android.createNotificationChannel(
      AndroidNotificationChannel(
        alarmChannelId,
        'منبه الدواء',
        description: 'تنبيه قوي بصوت مستمر عند موعد الدواء',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        vibrationPattern: Int64List.fromList(<int>[
          0,
          700,
          400,
          700,
          400,
          700,
        ]),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    await android.createNotificationChannel(
      AndroidNotificationChannel(
        quietChannelId,
        'تذكير هادئ بالدواء',
        description: 'إشعار عادي بصوت قصير عند موعد الدواء',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// طلب كل الأذونات اللازمة للمنبه.
  static Future<bool> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return true;
    bool ok = true;
    try {
      ok = (await android.requestNotificationsPermission()) ?? false;
      await android.requestExactAlarmsPermission();
      await android.requestFullScreenIntentPermission();
    } catch (e) {
      debugPrint('تعذّر طلب الأذونات: $e');
    }
    return ok;
  }

  static Future<bool> notificationsEnabled() async {
    try {
      return (await _android?.areNotificationsEnabled()) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> exactAlarmsAllowed() async {
    try {
      return (await _android?.canScheduleExactNotifications()) ?? true;
    } catch (_) {
      return true;
    }
  }

  // ------------------------- تفاصيل الإشعار -------------------------

  static NotificationDetails _details({required bool alarm}) {
    final AndroidNotificationDetails android = alarm
        ? AndroidNotificationDetails(
            alarmChannelId,
            'منبه الدواء',
            channelDescription: 'تنبيه قوي بصوت مستمر عند موعد الدواء',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: false,
            playSound: true,
            enableVibration: true,
            visibility: NotificationVisibility.public,
            vibrationPattern: Int64List.fromList(<int>[
              0,
              700,
              400,
              700,
              400,
              700,
            ]),
            // FLAG_INSISTENT: يعيد الصوت باستمرار حتى يستجيب المستخدم.
            additionalFlags: Int32List.fromList(<int>[4]),
            // صمّام أمان: يتوقف الرنين تلقائياً بعد دقيقتين.
            timeoutAfter: 120000,
            actions: _actions,
          )
        : AndroidNotificationDetails(
            quietChannelId,
            'تذكير هادئ بالدواء',
            channelDescription: 'إشعار عادي بصوت قصير عند موعد الدواء',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            playSound: true,
            enableVibration: true,
            autoCancel: true,
            visibility: NotificationVisibility.public,
            actions: _actions,
          );
    return NotificationDetails(android: android);
  }

  static const List<AndroidNotificationAction> _actions =
      <AndroidNotificationAction>[
        AndroidNotificationAction(
          NotifAction.taken,
          'أخذت الدواء',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotifAction.snooze,
          'تأجيل',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ];

  static String _title(Medicine m) => 'موعد الدواء: ${m.name}';

  static String _body(Medicine m, String patientName, DateTime at) =>
      '$patientName — ${Fmt.countUnit(m.dose, m.unit)} الساعة ${Fmt.timeOf(at)}';

  // ------------------------- الجدولة -------------------------

  /// يلغي كل المواعيد المجدولة ويعيد بناءها من جديد.
  ///
  /// [occurrences] مرتّبة تصاعدياً حسب الوقت، وتحوي فقط المواعيد المستقبلية.
  static Future<void> rescheduleAll({
    required List<({Medicine medicine, DateTime time})> occurrences,
    required Map<int, String> patientNames,
    required List<Snooze> snoozes,
    required Map<int, Medicine> medicinesById,
  }) async {
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {
      // بعض الأجهزة القديمة لا تدعم هذه الدالة.
    }

    final DateTime now = DateTime.now();
    int id = 1;

    for (final o in occurrences) {
      if (id > maxScheduled) break;
      if (!o.time.isAfter(now.add(const Duration(seconds: 5)))) continue;
      await _scheduleOne(
        id: id,
        medicine: o.medicine,
        patientName: patientNames[o.medicine.patientId] ?? '',
        at: o.time,
        scheduledKey: o.time.millisecondsSinceEpoch,
      );
      id++;
    }

    // إعادة جدولة التأجيلات المسجّلة.
    int snoozeIndex = 0;
    for (final Snooze s in snoozes) {
      final Medicine? m = medicinesById[s.medicineId];
      if (m == null) continue;
      final DateTime fire = DateTime.fromMillisecondsSinceEpoch(s.fireAt);
      if (!fire.isAfter(now)) continue;
      await _scheduleOne(
        id: _snoozeIdBase + snoozeIndex,
        medicine: m,
        patientName: patientNames[m.patientId] ?? '',
        at: fire,
        scheduledKey: s.scheduledAt,
      );
      snoozeIndex++;
      if (snoozeIndex > 40) break;
    }
  }

  static Future<void> _scheduleOne({
    required int id,
    required Medicine medicine,
    required String patientName,
    required DateTime at,
    required int scheduledKey,
  }) async {
    try {
      final AlarmPayload payload = AlarmPayload(
        medicineId: medicine.id ?? 0,
        patientId: medicine.patientId,
        scheduledAt: scheduledKey,
        notificationId: id,
      );
      await _plugin.zonedSchedule(
        id: id,
        title: _title(medicine),
        body: _body(medicine, patientName, at),
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: _details(alarm: medicine.alarmMode),
        androidScheduleMode: medicine.alarmMode
            ? AndroidScheduleMode.alarmClock
            : AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload.encode(),
      );
    } catch (e) {
      debugPrint('تعذّرت جدولة التنبيه: $e');
    }
  }

  /// إلغاء إشعار واحد (عند الضغط على «أخذت الدواء»).
  static Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('تعذّر إلغاء التنبيه: $e');
    }
  }

  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// تنبيه تجريبي فوري لاختبار الصوت (يختفي وحده بعد ١٥ ثانية).
  static Future<void> showTest({required bool alarm}) async {
    final AndroidNotificationDetails android = AndroidNotificationDetails(
      alarm ? alarmChannelId : quietChannelId,
      alarm ? 'منبه الدواء' : 'تذكير هادئ بالدواء',
      importance: alarm ? Importance.max : Importance.high,
      priority: alarm ? Priority.max : Priority.high,
      category: alarm
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      audioAttributesUsage: alarm
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
      timeoutAfter: 15000,
      additionalFlags: alarm ? Int32List.fromList(<int>[4]) : null,
    );
    await _plugin.show(
      id: 999999,
      title: 'تجربة التنبيه',
      body: alarm
          ? 'هكذا سيرن المنبه عند موعد الدواء'
          : 'هكذا سيظهر التذكير الهادئ',
      notificationDetails: NotificationDetails(android: android),
      payload: '',
    );
  }

  /// هل فُتح التطبيق بسبب ضغط المستخدم على تنبيه؟
  static Future<(AlarmPayload?, String?)> launchPayload() async {
    try {
      final NotificationAppLaunchDetails? details = await _plugin
          .getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) {
        return (null, null);
      }
      final NotificationResponse? response = details.notificationResponse;
      return (AlarmPayload.decode(response?.payload), response?.actionId);
    } catch (_) {
      return (null, null);
    }
  }
}
