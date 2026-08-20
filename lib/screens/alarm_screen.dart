import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../models/models.dart';
import '../services/alarm_audio.dart';
import '../services/notifications.dart';
import '../services/speech.dart';
import '../widgets/common.dart';
import '../widgets/pill_art.dart';

/// شاشة المنبه — تعرض **كل** أدوية المريض المستحقّة في نفس اللحظة.
///
/// سابقاً كان لكل دواء منبه منفصل، فتتزاحم عدة شاشات وأصوات، وتضيع
/// بقية الجرعات دون تسجيل عند الاستجابة لواحد منها.
class AlarmScreen extends StatefulWidget {
  const AlarmScreen({
    super.key,
    required this.patientId,
    required this.scheduledAt,
    required this.notificationId,
  });

  final int patientId;
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

  DateTime get _scheduled =>
      DateTime.fromMillisecondsSinceEpoch(widget.scheduledAt);

  List<DoseOccurrence> get _group =>
      appState.occurrencesAt(widget.patientId, _scheduled);

  @override
  void initState() {
    super.initState();
    // نشغّل الصوت بأنفسنا: صوت الإشعار يُكتم على بعض الأجهزة عند فتح
    // الشاشة الكاملة، فيبقى الاهتزاز وحده.
    AlarmAudio.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startVoice());
  }

  @override
  void dispose() {
    AlarmAudio.stop();
    Speech.stop();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _startVoice() async {
    if (!appState.voiceEnabled || !Speech.ready) return;
    final List<DoseOccurrence> list = _group;
    if (list.isEmpty) return;
    final Patient? patient = appState.patientById(widget.patientId);

    final StringBuffer b = StringBuffer('وقت الدواء');
    if (patient != null && patient.name.trim().isNotEmpty) {
      b.write('، ${patient.name}');
    }
    for (final DoseOccurrence o in list) {
      b.write('، ${o.medicine.name}');
    }
    final String text = b.toString();

    await Future<void>.delayed(const Duration(milliseconds: 1600));
    for (int i = 0; i < 5; i++) {
      if (!mounted || _busy) return;
      await Speech.say(text);
      if (!mounted || _busy) return;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  Future<void> _stopSound() async {
    await AlarmAudio.stop();
    // نلغي هذا التنبيه فقط — cancelAll كان يلغي منبهات المرضى الآخرين
    // في نفس اللحظة دون تسجيل جرعاتهم.
    if (widget.notificationId > 0) {
      await NotificationService.cancel(widget.notificationId);
    }
  }

  /// إنهاء المنبه كاملاً ثم عرض منبه مريض آخر إن وُجد في نفس اللحظة.
  Future<void> _finish(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await Speech.stop();
    await _stopSound();
    await action();
    if (!mounted) return;

    final ({int patientId, DateTime time})? next = appState.pendingGroupAfter(
      excludePatientId: widget.patientId,
      time: _scheduled,
    );

    final NavigatorState nav = Navigator.of(context);
    if (next != null) {
      // مريض آخر له دواء في نفس الوقت — نعرض منبهه بعد هذا.
      nav.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AlarmScreen(
            patientId: next.patientId,
            scheduledAt: next.time.millisecondsSinceEpoch,
            notificationId: 0,
          ),
        ),
      );
      return;
    }
    // مهم: maybePop لا يعمل هنا لأن PopScope(canPop:false) يرفضه.
    if (nav.canPop()) {
      nav.pop();
    } else {
      setState(() => _busy = false);
    }
  }

  /// تسجيل دواء واحد من المجموعة دون إغلاق الشاشة.
  Future<void> _takeOne(DoseOccurrence o) async {
    await appState.takeDose(o.medicine, o.time);
    if (!mounted) return;
    if (_group.every((DoseOccurrence e) => !e.isPending)) {
      await _finish(() async {});
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (BuildContext context, Widget? _) {
        final List<DoseOccurrence> list = _group;
        final Patient? patient = appState.patientById(widget.patientId);

        if (list.isEmpty) return _empty(context);

        final bool single = list.length == 1;

        return PopScope(
          canPop: false,
          child: AppBackground(
            colors: const <Color>[Color(0xFFFFF3F3), Color(0xFFF3F1FF)],
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                  child: Column(
                    children: <Widget>[
                      _banner(list.length),
                      const SizedBox(height: 14),
                      if (patient != null)
                        Text(
                          patient.name,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: patientColorAt(patient.colorIndex),
                          ),
                        ),
                      Text(
                        Fmt.timeOf(_scheduled),
                        style: const TextStyle(
                          fontSize: 19,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: single
                            ? _singleView(list.first)
                            : _listView(list),
                      ),
                      const SizedBox(height: 12),
                      _actions(list, single),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _banner(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.alarm, color: Colors.white, size: 26),
          const SizedBox(width: 8),
          Text(
            count == 1
                ? 'موعد الدواء الآن'
                : 'موعد ${Fmt.n(count)} أدوية الآن',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _singleView(DoseOccurrence o) {
    final Medicine m = o.medicine;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.08).animate(
            CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
          ),
          child: PillIcon(form: m.form, colorIndex: m.colorIndex, size: 160),
        ),
        const SizedBox(height: 22),
        Text(
          m.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          Fmt.countUnit(m.dose, m.unit),
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
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
      ],
    );
  }

  Widget _listView(List<DoseOccurrence> list) {
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int i) {
        final DoseOccurrence o = list[i];
        final Medicine m = o.medicine;
        final bool done = !o.isPending;
        return SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: done ? AppColors.greenSoft : Colors.white,
          borderColor: done
              ? AppColors.green.withValues(alpha: 0.4)
              : AppColors.line,
          child: Row(
            children: <Widget>[
              Opacity(
                opacity: done ? 0.45 : 1,
                child: PillIcon(
                  form: m.form,
                  colorIndex: m.colorIndex,
                  size: 50,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      m.name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      Fmt.countUnit(m.dose, m.unit),
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.muted,
                      ),
                    ),
                    if (m.notes.isNotEmpty)
                      Text(
                        m.notes,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.amber,
                        ),
                      ),
                  ],
                ),
              ),
              if (done)
                const Icon(Icons.check_circle, color: AppColors.green, size: 38)
              else
                SizedBox(
                  height: 52,
                  width: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    onPressed: _busy ? null : () => _takeOne(o),
                    child: const Icon(Icons.check, size: 28),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _actions(List<DoseOccurrence> list, bool single) {
    final int remaining = list.where((DoseOccurrence o) => o.isPending).length;
    return Column(
      children: <Widget>[
        BigButton(
          label: single
              ? 'أخذت الدواء'
              : 'أخذت الكل (${Fmt.n(remaining)})',
          icon: Icons.check_rounded,
          color: AppColors.green,
          height: 74,
          onPressed: _busy ? null : () => _finish(() => appState.takeGroup(list)),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _finish(() => appState.snoozeGroup(list)),
                  icon: const Icon(Icons.snooze, size: 24),
                  label: Text(
                    'تأجيل ${Fmt.n(appState.snoozeMinutes)} دقيقة',
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 58,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: const BorderSide(color: Color(0xFFF3C6C7), width: 2),
                  ),
                  onPressed: _busy
                      ? null
                      : () => _finish(() => appState.skipGroup(list)),
                  child: const Text('تخطّي', style: TextStyle(fontSize: 17)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
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
                  'لا توجد جرعة مستحقّة الآن',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                BigButton(
                  label: 'إغلاق',
                  onPressed: () async {
                    await _stopSound();
                    if (!context.mounted) return;
                    final NavigatorState nav = Navigator.of(context);
                    if (nav.canPop()) nav.pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
