import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/palette.dart';
import 'core/theme.dart';
import 'data/app_state.dart';
import 'models/models.dart';
import 'screens/alarm_screen.dart';
import 'screens/home_screen.dart';
import 'services/notifications.dart';
import 'services/speech.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// نعرض الواجهة فوراً، ثم نهيّئ كل شيء في الخلفية.
/// أي فشل في المنبهات أو قاعدة البيانات يظهر كرسالة واضحة،
/// ولا يترك المستخدم أمام شاشة بيضاء.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedicineApp());
}

// ------------------------- توجيه التنبيهات -------------------------

AlarmPayload? _pendingPayload;
String? _pendingAction;

/// ما يحدث عند الضغط على التنبيه أو أحد أزراره.
Future<void> handleNotificationResponse(
  AlarmPayload payload,
  String? actionId,
) async {
  // إن وصل التنبيه قبل اكتمال التحميل، نحتفظ به وننفّذه بعد الجاهزية.
  if (!appState.loaded) {
    _pendingPayload = payload;
    _pendingAction = actionId;
    return;
  }

  if (appState.currentPatientId != payload.patientId) {
    await appState.setCurrentPatient(payload.patientId);
  }

  final DateTime scheduled = DateTime.fromMillisecondsSinceEpoch(
    payload.scheduledAt,
  );

  // التنبيه الواحد قد يخصّ عدة أدوية لنفس المريض في نفس اللحظة.
  final List<DoseOccurrence> group = appState.occurrencesAt(
    payload.patientId,
    scheduled,
  );
  if (group.isEmpty) return;

  if (actionId == NotifAction.taken) {
    await NotificationService.cancel(payload.notificationId);
    await appState.takeGroup(group);
    return;
  }
  if (actionId == NotifAction.snooze) {
    await NotificationService.cancel(payload.notificationId);
    await appState.snoozeGroup(group);
    return;
  }

  navigatorKey.currentState?.push(
    MaterialPageRoute<void>(
      builder: (_) => AlarmScreen(
        patientId: payload.patientId,
        scheduledAt: payload.scheduledAt,
        notificationId: payload.notificationId,
      ),
    ),
  );
}

// ------------------------- التطبيق -------------------------

enum _Phase { booting, ready, failed }

class MedicineApp extends StatefulWidget {
  const MedicineApp({super.key});

  @override
  State<MedicineApp> createState() => _MedicineAppState();
}

class _MedicineAppState extends State<MedicineApp> with WidgetsBindingObserver {
  _Phase _phase = _Phase.booting;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _boot() async {
    if (_phase == _Phase.failed) {
      setState(() => _phase = _Phase.booting);
    }

    // ١) التنبيهات — فشلها لا يمنع التطبيق من العمل.
    await NotificationService.init(onResponse: handleNotificationResponse);

    // ٢) البيانات — هذه ضرورية، وإن فشلت نُظهر الخطأ.
    try {
      await appState.load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = '$e';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _phase = _Phase.ready);

    // ٣) فحص محرك النطق العربي في الخلفية — لا ننتظره.
    unawaited(Speech.init());

    // ٤) بعد الجاهزية: الأذونات وأي تنبيه فتح التطبيق.
    await _afterReady();
  }

  Future<void> _afterReady() async {
    try {
      final bool notificationsAllowed =
          await NotificationService.notificationsEnabled();
      final bool exactAllowed =
          await NotificationService.exactAlarmsAllowed();
      if (!notificationsAllowed || !exactAllowed) {
        await NotificationService.requestPermissions();
      }
      // load() ran before the permission dialog. Rebuild after Android returns
      // from settings; otherwise all exact schedules rejected at first launch
      // are lost until the user manually reopens the app.
      await appState.reschedule();
    } catch (e) {
      debugPrint('تعذّر طلب الأذونات: $e');
    }

    if (_pendingPayload != null) {
      final AlarmPayload p = _pendingPayload!;
      final String? a = _pendingAction;
      _pendingPayload = null;
      _pendingAction = null;
      await handleNotificationResponse(p, a);
      return;
    }

    try {
      final (AlarmPayload?, String?) launch =
          await NotificationService.launchPayload();
      if (launch.$1 != null) {
        await handleNotificationResponse(launch.$1!, launch.$2);
      }
    } catch (e) {
      debugPrint('تعذّرت قراءة تنبيه الإقلاع: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _phase == _Phase.ready) {
      // Keep the rolling horizon fresh without continuously cancelling it.
      appState.reschedule(force: false);
      appState.refreshUi();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (BuildContext context, Widget? _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'دوائي',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(appState.textScale)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: switch (_phase) {
          _Phase.booting => const _BootScreen(),
          _Phase.failed => _BootErrorScreen(message: _error, onRetry: _boot),
          _Phase.ready => const HomeScreen(),
        },
      ),
    );
  }
}

/// شاشة انتظار قصيرة أثناء فتح قاعدة البيانات.
class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.medication_outlined,
                size: 72,
                color: AppColors.primary,
              ),
              SizedBox(height: 22),
              Text(
                'دوائي',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 26),
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// تظهر بدل الشاشة البيضاء إن فشل تحميل البيانات.
class _BootErrorScreen extends StatelessWidget {
  const _BootErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.error_outline,
                  size: 66,
                  color: AppColors.red,
                ),
                const SizedBox(height: 18),
                const Text(
                  'تعذّر تشغيل التطبيق',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'حدثت مشكلة أثناء فتح بيانات التطبيق.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line, width: 1.6),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      message,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 26),
                    label: const Text(
                      'إعادة المحاولة',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
