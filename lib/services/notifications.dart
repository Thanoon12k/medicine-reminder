import 'dart:convert';

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

  // ملاحظة: إعدادات القناة (الصوت، الأهمية، الاهتزاز) تُثبَّت عند أول إنشاء
  // ولا يمكن تغييرها بعدها، لذلك نرفع رقم النسخة عند كل تغيير.
  static const String alarmChannelId = 'dawaii_alarm_v3';
  static const String quietChannelId = 'dawaii_quiet_v3';

  /// هل نجح تحميل نغمة المنبه المرفقة؟ إن فشلت نستعمل نغمة الجهاز الافتراضية
  /// بدل أن تتعطّل كل التنبيهات.
  static bool alarmSoundOk = true;

  /// نغمة المنبه المرفقة داخل التطبيق (res/raw/alarm_tone.wav).
  /// لا نعتمد على نغمة الإشعار الافتراضية لأنها قد تكون «بلا صوت» في الجهاز.
  static const RawResourceAndroidNotificationSound alarmSound =
      RawResourceAndroidNotificationSound('alarm_tone');

  /// أقصى عدد إشعارات مجدولة في وقت واحد (حد النظام ٥٠٠).
  static const int maxScheduled = 380;

  /// نطاق معرّفات إشعارات التأجيل.
  static const int _snoozeIdBase = 900000;

  static bool _ready = false;

  /// هل نجحت تهيئة التنبيهات؟ إن كانت false يعمل التطبيق بدون تذكير.
  static bool get isReady => _ready;

  /// آخر خطأ حدث أثناء التهيئة (يُعرض في شاشة الإعدادات).
  static String? initError;

  /// اسم أيقونة الإشعار التي قبلها النظام فعلياً.
  static String? activeIcon;

  /// نجرّب أكثر من صيغة للأيقونة: بعض الأجهزة/الإصدارات لا تقبل بعضها،
  /// وفشل الأيقونة يجب ألّا يمنع التطبيق من العمل.
  static const List<String> _iconCandidates = <String>[
    'ic_notification',
    '@drawable/ic_notification',
    'ic_launcher',
    '@mipmap/ic_launcher',
  ];

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// تهيئة المنبهات والقنوات. لا ترمي استثناءً أبداً — تسجّل الخطأ وتكمل.
  static Future<void> init({
    required void Function(AlarmPayload payload, String? actionId) onResponse,
  }) async {
    if (_ready) return;

    try {
      _initTimezone();
    } catch (e) {
      debugPrint('تعذّر ضبط المنطقة الزمنية: $e');
    }

    void handle(NotificationResponse response) {
      final AlarmPayload? payload = AlarmPayload.decode(response.payload);
      if (payload != null) onResponse(payload, response.actionId);
    }

    Object? lastError;
    for (final String icon in _iconCandidates) {
      try {
        await _plugin.initialize(
          settings: InitializationSettings(
            android: AndroidInitializationSettings(icon),
          ),
          onDidReceiveNotificationResponse: handle,
        );
        activeIcon = icon;
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        debugPrint('تعذّر استعمال أيقونة الإشعار «$icon»: $e');
      }
    }

    if (lastError != null) {
      initError = '$lastError';
      debugPrint('فشلت تهيئة التنبيهات نهائياً: $lastError');
      return;
    }

    try {
      await _createChannels();
    } catch (e) {
      initError = '$e';
      debugPrint('تعذّر إنشاء قنوات الإشعارات: $e');
    }

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

    // تنظيف قنوات النسخ القديمة.
    for (final String old in <String>[
      'dawaii_alarm_v1',
      'dawaii_quiet_v1',
      'dawaii_alarm_v2',
      'dawaii_quiet_v2',
    ]) {
      try {
        await android.deleteNotificationChannel(channelId: old);
      } catch (_) {}
    }

    Future<void> createAlarmChannel({required bool withSound}) =>
        android.createNotificationChannel(
          AndroidNotificationChannel(
            alarmChannelId,
            'منبه الدواء',
            description: 'تنبيه قوي بصوت مستمر عند موعد الدواء',
            importance: Importance.max,
            playSound: true,
            sound: withSound ? alarmSound : null,
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

    // إن لم تُحزَّم نغمة المنبه مع التطبيق لأي سبب، لا نُسقِط التنبيهات كلها —
    // نرجع إلى نغمة الجهاز الافتراضية.
    try {
      await createAlarmChannel(withSound: true);
      alarmSoundOk = true;
    } catch (e) {
      alarmSoundOk = false;
      initError = 'نغمة المنبه المرفقة غير متاحة، سيُستعمل صوت الجهاز. ($e)';
      debugPrint('تعذّر استعمال نغمة المنبه المرفقة: $e');
      await createAlarmChannel(withSound: false);
    }

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
            sound: alarmSoundOk ? alarmSound : null,
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

  static String _title(DoseGroup g, String patientName) {
    if (g.medicines.length == 1) {
      final String name = g.medicines.first.name;
      return patientName.isEmpty
          ? 'موعد الدواء: $name'
          : 'موعد دواء $patientName: $name';
    }
    return patientName.isEmpty
        ? 'موعد ${g.medicines.length} أدوية'
        : 'موعد أدوية $patientName (${g.medicines.length})';
  }

  static String _body(DoseGroup g, DateTime at) {
    if (g.medicines.length == 1) {
      final Medicine m = g.medicines.first;
      return '${Fmt.countUnit(m.dose, m.unit)} — الساعة ${Fmt.timeOf(at)}';
    }
    return '${g.names} — الساعة ${Fmt.timeOf(at)}';
  }

  // ------------------------- الجدولة -------------------------

  /// يلغي كل المواعيد المجدولة ويعيد بناءها من جديد.
  ///
  /// [groups] مجموعة واحدة لكل (مريض + وقت): كل أدوية المريض المستحقّة في
  /// نفس اللحظة تُنبَّه بتنبيه واحد بدل تنبيه لكل دواء.
  static Future<void> rescheduleAll({
    required List<DoseGroup> groups,
    required Map<int, String> patientNames,
    required List<Snooze> snoozes,
    required Map<int, Medicine> medicinesById,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {
      // بعض الأجهزة القديمة لا تدعم هذه الدالة.
    }

    final DateTime now = DateTime.now();
    int id = 1;

    for (final DoseGroup g in groups) {
      if (id > maxScheduled) break;
      if (!g.time.isAfter(now.add(const Duration(seconds: 5)))) continue;
      await _scheduleGroup(
        id: id,
        group: g,
        patientName: patientNames[g.patientId] ?? '',
        at: g.time,
        scheduledKey: g.scheduledAt,
      );
      id++;
    }

    // إعادة جدولة التأجيلات المسجّلة، مجمّعة أيضاً حسب (مريض + موعد أصلي).
    final Map<String, List<Snooze>> snoozeGroups = <String, List<Snooze>>{};
    for (final Snooze s in snoozes) {
      if (!medicinesById.containsKey(s.medicineId)) continue;
      final DateTime fire = DateTime.fromMillisecondsSinceEpoch(s.fireAt);
      if (!fire.isAfter(now)) continue;
      snoozeGroups
          .putIfAbsent('${s.patientId}_${s.fireAt}', () => <Snooze>[])
          .add(s);
    }

    int snoozeIndex = 0;
    for (final List<Snooze> list in snoozeGroups.values) {
      if (snoozeIndex > 40) break;
      final List<Medicine> meds = list
          .map((Snooze s) => medicinesById[s.medicineId]!)
          .toList();
      final Snooze first = list.first;
      final DateTime fire = DateTime.fromMillisecondsSinceEpoch(first.fireAt);
      await _scheduleGroup(
        id: _snoozeIdBase + snoozeIndex,
        group: DoseGroup(
          patientId: first.patientId,
          time: fire,
          medicines: meds,
        ),
        patientName: patientNames[first.patientId] ?? '',
        at: fire,
        // نحتفظ بالموعد الأصلي حتى تُسجَّل الجرعة في مكانها الصحيح.
        scheduledKey: first.scheduledAt,
      );
      snoozeIndex++;
    }
  }

  static Future<void> _scheduleGroup({
    required int id,
    required DoseGroup group,
    required String patientName,
    required DateTime at,
    required int scheduledKey,
  }) async {
    try {
      final AlarmPayload payload = AlarmPayload(
        medicineId: group.medicines.length == 1
            ? (group.medicines.first.id ?? 0)
            : 0,
        patientId: group.patientId,
        scheduledAt: scheduledKey,
        notificationId: id,
      );
      await _plugin.zonedSchedule(
        id: id,
        title: _title(group, patientName),
        body: _body(group, at),
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: _details(alarm: group.alarmMode),
        androidScheduleMode: group.alarmMode
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
      sound: (alarm && alarmSoundOk) ? alarmSound : null,
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
