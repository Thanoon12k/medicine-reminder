import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'data/app_state.dart';
import 'models/models.dart';
import 'screens/alarm_screen.dart';
import 'screens/home_screen.dart';
import 'services/notifications.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init(onResponse: handleNotificationResponse);
  await appState.load();
  runApp(const MedicineApp());
}

/// ما يحدث عند الضغط على التنبيه أو أحد أزراره.
Future<void> handleNotificationResponse(
  AlarmPayload payload,
  String? actionId,
) async {
  final Medicine? medicine = appState.medicineById(payload.medicineId);
  if (medicine == null) return;

  if (appState.currentPatientId != payload.patientId) {
    await appState.setCurrentPatient(payload.patientId);
  }

  final DateTime scheduled = DateTime.fromMillisecondsSinceEpoch(
    payload.scheduledAt,
  );

  if (actionId == NotifAction.taken) {
    await NotificationService.cancel(payload.notificationId);
    await appState.takeDose(medicine, scheduled);
    return;
  }
  if (actionId == NotifAction.snooze) {
    await NotificationService.cancel(payload.notificationId);
    await appState.snoozeDose(medicine, scheduled);
    return;
  }

  navigatorKey.currentState?.push(
    MaterialPageRoute<void>(
      builder: (_) => AlarmScreen(
        medicineId: payload.medicineId,
        scheduledAt: payload.scheduledAt,
        notificationId: payload.notificationId,
      ),
    ),
  );
}

class MedicineApp extends StatefulWidget {
  const MedicineApp({super.key});

  @override
  State<MedicineApp> createState() => _MedicineAppState();
}

class _MedicineAppState extends State<MedicineApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _afterFirstFrame() async {
    // طلب أذونات التنبيه إن لم تكن مفعّلة.
    final bool enabled = await NotificationService.notificationsEnabled();
    if (!enabled) {
      await NotificationService.requestPermissions();
    }

    // إن فُتح التطبيق بسبب تنبيه، نعرض شاشة المنبه.
    final (AlarmPayload?, String?) launch =
        await NotificationService.launchPayload();
    if (launch.$1 != null) {
      await handleNotificationResponse(launch.$1!, launch.$2);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      appState.reschedule();
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
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(appState.textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
