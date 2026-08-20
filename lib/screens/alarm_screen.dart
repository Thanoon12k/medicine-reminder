import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../models/models.dart';
import '../services/notifications.dart';
import '../widgets/common.dart';
import '../widgets/pill_art.dart';

/// شاشة المنبه التي تفتح عند موعد الدواء.
class AlarmScreen extends StatefulWidget {
  const AlarmScreen({
    super.key,
    required this.medicineId,
    required this.scheduledAt,
    required this.notificationId,
  });

  final int medicineId;
  final int scheduledAt;
  final int notificationId;

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  bool _busy = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _stopSound() async {
    if (widget.notificationId > 0) {
      await NotificationService.cancel(widget.notificationId);
    } else {
      await NotificationService.cancelAll();
    }
  }

  Future<void> _finish(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _stopSound();
    await action();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final Medicine? m = appState.medicineById(widget.medicineId);
    final DateTime scheduled = DateTime.fromMillisecondsSinceEpoch(
      widget.scheduledAt,
    );

    if (m == null) {
      return AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text(
                    'لم يعد هذا الدواء موجوداً',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 20),
                  BigButton(
                    label: 'إغلاق',
                    onPressed: () async {
                      await _stopSound();
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final Patient? patient = appState.patientById(m.patientId);

    return PopScope(
      canPop: false,
      child: AppBackground(
        colors: const <Color>[Color(0xFFFFF3F3), Color(0xFFF3F1FF)],
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.alarm, color: Colors.white, size: 26),
                        SizedBox(width: 8),
                        Text(
                          'موعد الدواء الآن',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1.08).animate(
                      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                    ),
                    child: PillIcon(
                      form: m.form,
                      colorIndex: m.colorIndex,
                      size: 180,
                    ),
                  ),
                  const SizedBox(height: 26),
                  if (patient != null)
                    Text(
                      patient.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: patientColorAt(patient.colorIndex),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    m.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    Fmt.countUnit(m.dose, m.unit),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Fmt.timeOf(scheduled),
                    style: const TextStyle(
                      fontSize: 20,
                      color: AppColors.muted,
                    ),
                  ),
                  if (m.notes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.amberSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        m.notes,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                  const Spacer(),
                  BigButton(
                    label: 'أخذت الدواء',
                    icon: Icons.check_rounded,
                    color: AppColors.green,
                    height: 78,
                    onPressed: _busy
                        ? null
                        : () => _finish(
                            () => appState.takeDose(m, scheduled),
                          ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 62,
                          child: OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _finish(
                                    () => appState.snoozeDose(m, scheduled),
                                  ),
                            icon: const Icon(Icons.snooze, size: 26),
                            label: Text(
                              'تأجيل ${Fmt.n(appState.snoozeMinutes)} دقيقة',
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 62,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.red,
                              side: const BorderSide(
                                color: Color(0xFFF3C6C7),
                                width: 2,
                              ),
                            ),
                            onPressed: _busy
                                ? null
                                : () => _finish(
                                    () => appState.skipDose(m, scheduled),
                                  ),
                            child: const Text(
                              'تخطّي',
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
