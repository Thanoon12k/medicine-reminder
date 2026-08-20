import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../services/notifications.dart';
import '../widgets/common.dart';
import 'patients_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifsOn = true;
  bool _exactOn = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final bool n = await NotificationService.notificationsEnabled();
    final bool e = await NotificationService.exactAlarmsAllowed();
    if (mounted) setState(() {
      _notifsOn = n;
      _exactOn = e;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (BuildContext context, Widget? _) => AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('الإعدادات')),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: <Widget>[
                if (!_notifsOn || !_exactOn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: SoftCard(
                      color: AppColors.amberSoft,
                      borderColor: AppColors.amber.withValues(alpha: 0.4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Row(
                            children: <Widget>[
                              Icon(
                                Icons.warning_amber_rounded,
                                color: AppColors.amber,
                                size: 30,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'التنبيهات غير مفعّلة بالكامل',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'بدون هذه الأذونات قد لا يرن المنبه في وقته.',
                            style: TextStyle(
                              fontSize: 17,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          BigButton(
                            label: 'تفعيل الأذونات',
                            icon: Icons.lock_open,
                            height: 60,
                            color: AppColors.amber,
                            onPressed: () async {
                              await NotificationService.requestPermissions();
                              await _check();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                const SectionTitle('التنبيه'),
                SoftCard(
                  child: Column(
                    children: <Widget>[
                      _SwitchRow(
                        icon: Icons.notifications_active_outlined,
                        title: 'المنبه القوي افتراضياً',
                        subtitle: 'صوت مستمر وشاشة كاملة عند إضافة دواء جديد',
                        value: appState.defaultAlarmMode,
                        onChanged: appState.setDefaultAlarmMode,
                      ),
                      const Divider(height: 26),
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'مدة التأجيل',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <int>[5, 10, 15, 30].map((int v) {
                          final bool sel = appState.snoozeMinutes == v;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceCard(
                                selected: sel,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                onTap: () => appState.setSnoozeMinutes(v),
                                child: Center(
                                  child: Text(
                                    Fmt.n(v),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  NotificationService.showTest(alarm: true),
                              icon: const Icon(Icons.volume_up, size: 24),
                              label: const Text(
                                'تجربة المنبه',
                                style: TextStyle(fontSize: 17),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  NotificationService.showTest(alarm: false),
                              icon: const Icon(
                                Icons.notifications_none,
                                size: 24,
                              ),
                              label: const Text(
                                'تجربة الإشعار',
                                style: TextStyle(fontSize: 17),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SectionTitle('العرض'),
                SoftCard(
                  child: Column(
                    children: <Widget>[
                      _SwitchRow(
                        icon: Icons.pin_outlined,
                        title: 'الأرقام العربية (٠١٢٣)',
                        subtitle: 'أطفئها لعرض الأرقام 0123',
                        value: appState.arabicDigits,
                        onChanged: appState.setArabicDigits,
                      ),
                      const Divider(height: 26),
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'حجم الخط',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          for (final MapEntry<String, double> item
                              in const <String, double>{
                                'عادي': 1.0,
                                'كبير': 1.15,
                                'أكبر': 1.3,
                              }.entries)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: ChoiceCard(
                                  selected:
                                      (appState.textScale - item.value).abs() <
                                      0.01,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  onTap: () =>
                                      appState.setTextScale(item.value),
                                  child: Center(
                                    child: Text(
                                      item.key,
                                      style: TextStyle(
                                        fontSize: 17 * item.value,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SectionTitle('المرضى'),
                SoftCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const PatientsScreen(),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.people_outline,
                        size: 30,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'إدارة المرضى (${Fmt.n(appState.patients.length)})',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_left, color: AppColors.muted),
                    ],
                  ),
                ),

                const SectionTitle('عن التطبيق'),
                const SoftCard(
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 30,
                        color: AppColors.green,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'يعمل بدون إنترنت نهائياً.\n'
                          'كل البيانات محفوظة على هذا الهاتف فقط ولا تُرسل لأي مكان.',
                          style: TextStyle(fontSize: 17, height: 1.6),
                        ),
                      ),
                    ],
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

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 28, color: AppColors.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 15, color: AppColors.muted),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
