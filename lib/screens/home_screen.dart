import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/jar.dart';
import '../widgets/pill_art.dart';
import 'jar_screen.dart';
import 'medicine_detail_screen.dart';
import 'medicine_form_screen.dart';
import 'patients_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // تحديث دوري لعرض «فات الموعد» والوقت المتبقي.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (BuildContext context, Widget? _) {
        final Patient? patient = appState.currentPatient;
        if (patient == null) {
          return const PatientsScreen(firstRun: true);
        }
        final List<DoseOccurrence> today = appState.todayOccurrences;
        final List<DoseLog> taken = appState.takenLogs();
        final List<Medicine> meds = appState.currentMedicines;

        return AppBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'الإعدادات',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
              title: _PatientChip(patient: patient),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.calendar_month_outlined),
                  tooltip: 'العلبة والسجل',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const JarScreen()),
                  ),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MedicineFormScreen(patientId: patient.id!),
                ),
              ),
              icon: const Icon(Icons.add, size: 30),
              label: const Text(
                'إضافة دواء',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            body: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                children: <Widget>[
                  _NextDoseBanner(occurrences: today),
                  const SizedBox(height: 16),
                  _JarCard(taken: taken),
                  const SizedBox(height: 22),
                  SectionTitle(
                    'أدوية اليوم',
                    action: Text(
                      Fmt.relativeDay(DateTime.now()),
                      style: const TextStyle(
                        fontSize: 17,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (meds.isEmpty)
                    const _EmptyMedicines()
                  else if (today.isEmpty)
                    const SoftCard(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'لا توجد جرعات مجدولة اليوم.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 19, color: AppColors.muted),
                        ),
                      ),
                    )
                  else
                    ...today.map(
                      (DoseOccurrence o) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DoseCard(occurrence: o),
                      ),
                    ),
                  if (meds.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    SectionTitle('كل الأدوية (${Fmt.n(meds.length)})'),
                    ...meds.map(
                      (Medicine m) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MedicineRow(medicine: m),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PatientChip extends StatelessWidget {
  const _PatientChip({required this.patient});
  final Patient patient;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const PatientsScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 18,
              backgroundColor: patientColorAt(patient.colorIndex),
              child: Text(
                patient.name.isEmpty ? '؟' : patient.name.substring(0, 1),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                patient.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(Icons.expand_more, size: 26),
          ],
        ),
      ),
    );
  }
}

class _NextDoseBanner extends StatelessWidget {
  const _NextDoseBanner({required this.occurrences});
  final List<DoseOccurrence> occurrences;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final List<DoseOccurrence> late_ = occurrences
        .where((DoseOccurrence o) => o.isLate)
        .toList();
    DoseOccurrence? next;
    for (final DoseOccurrence o in occurrences) {
      if (o.isPending && o.time.isAfter(now)) {
        next = o;
        break;
      }
    }

    if (late_.isNotEmpty) {
      final DoseOccurrence o = late_.first;
      return SoftCard(
        color: AppColors.redSoft,
        borderColor: AppColors.red.withValues(alpha: 0.35),
        child: Row(
          children: <Widget>[
            const Icon(Icons.alarm_on, color: AppColors.red, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    late_.length == 1
                        ? 'فات موعد دواء'
                        : 'فات موعد ${Fmt.n(late_.length)} أدوية',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${o.medicine.name} — ${Fmt.timeOf(o.time)}',
                    style: const TextStyle(fontSize: 17, color: AppColors.ink),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (next == null) {
      final bool allDone =
          occurrences.isNotEmpty &&
          occurrences.every((DoseOccurrence o) => !o.isPending);
      return SoftCard(
        color: allDone ? AppColors.greenSoft : Colors.white,
        borderColor: allDone
            ? AppColors.green.withValues(alpha: 0.35)
            : AppColors.line,
        child: Row(
          children: <Widget>[
            Icon(
              allDone ? Icons.verified_rounded : Icons.wb_sunny_outlined,
              color: allDone ? AppColors.green : AppColors.amber,
              size: 34,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                allDone
                    ? 'أحسنت! أكملت كل جرعات اليوم'
                    : 'لا توجد جرعات قادمة اليوم',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: allDone ? AppColors.green : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final Duration diff = next.time.difference(now);
    final int hours = diff.inHours;
    final int mins = diff.inMinutes % 60;
    final String remaining = hours > 0
        ? 'بعد ${Fmt.n(hours)} ساعة و${Fmt.n(mins)} دقيقة'
        : 'بعد ${Fmt.n(diff.inMinutes)} دقيقة';

    return SoftCard(
      child: Row(
        children: <Widget>[
          PillIcon(
            form: next.medicine.form,
            colorIndex: next.medicine.colorIndex,
            size: 54,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'الجرعة القادمة',
                  style: TextStyle(fontSize: 16, color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  '${next.medicine.name} — ${Fmt.timeOf(next.time)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  remaining,
                  style: const TextStyle(
                    fontSize: 17,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JarCard extends StatelessWidget {
  const _JarCard({required this.taken});
  final List<DoseLog> taken;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final int thisMonth = taken
        .where(
          (DoseLog l) =>
              l.takenTime.year == now.year && l.takenTime.month == now.month,
        )
        .length;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const JarScreen()),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 260,
            child: JarView(
              pills: taken
                  .map((DoseLog l) => JarPill(l.form, l.colorIndex))
                  .toList(),
              dropSignal: appState.lastDropKey,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _JarStat(value: Fmt.n(taken.length), label: 'كل الحبوب'),
              Container(width: 1.5, height: 34, color: AppColors.line),
              _JarStat(value: Fmt.n(thisMonth), label: 'هذا الشهر'),
              Container(width: 1.5, height: 34, color: AppColors.line),
              _JarStat(
                value: Fmt.n(appState.streakDays),
                label: 'أيام متتالية',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JarStat extends StatelessWidget {
  const _JarStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 15, color: AppColors.muted),
        ),
      ],
    );
  }
}

/// بطاقة جرعة واحدة مع زر «أخذت الدواء».
class DoseCard extends StatelessWidget {
  const DoseCard({super.key, required this.occurrence});

  final DoseOccurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final Medicine m = occurrence.medicine;
    final bool taken = occurrence.isTaken;
    final bool skipped = occurrence.isSkipped;
    final bool late_ = occurrence.isLate;

    return SoftCard(
      color: taken
          ? AppColors.greenSoft
          : (late_ ? AppColors.redSoft : Colors.white),
      borderColor: taken
          ? AppColors.green.withValues(alpha: 0.35)
          : (late_ ? AppColors.red.withValues(alpha: 0.35) : AppColors.line),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => MedicineDetailScreen(medicineId: m.id!),
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Opacity(
                opacity: taken || skipped ? 0.45 : 1,
                child: PillIcon(
                  form: m.form,
                  colorIndex: m.colorIndex,
                  size: 56,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      m.name,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        decoration: skipped ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${Fmt.countUnit(m.dose, m.unit)} • ${Fmt.timeOf(occurrence.time)}',
                      style: const TextStyle(
                        fontSize: 17,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (taken)
                const Icon(
                  Icons.check_circle,
                  color: AppColors.green,
                  size: 40,
                )
              else if (skipped)
                const Icon(Icons.cancel, color: AppColors.muted, size: 36),
            ],
          ),
          if (!taken && !skipped) ...<Widget>[
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: BigButton(
                    label: 'أخذت الدواء',
                    icon: Icons.check_rounded,
                    height: 60,
                    color: AppColors.green,
                    onPressed: () async {
                      await appState.takeDose(m, occurrence.time);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('نزلت حبة ${m.name} إلى العلبة'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 60,
                  width: 64,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(64, 60),
                    ),
                    onPressed: () => appState.skipDose(m, occurrence.time),
                    child: const Icon(Icons.close, size: 28),
                  ),
                ),
              ],
            ),
          ] else ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => appState.undoDose(m, occurrence.time),
                icon: const Icon(Icons.undo, size: 22),
                label: const Text('تراجع'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MedicineRow extends StatelessWidget {
  const _MedicineRow({required this.medicine});
  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final bool lowStock =
        medicine.totalUnits > 0 && medicine.daysLeftByStock <= 3;
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => MedicineDetailScreen(medicineId: medicine.id!),
        ),
      ),
      child: Row(
        children: <Widget>[
          PillIcon(
            form: medicine.form,
            colorIndex: medicine.colorIndex,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  medicine.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  medicine.times.map((int t) => Fmt.time(t)).join('  •  '),
                  style: const TextStyle(fontSize: 15, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (medicine.totalUnits > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: lowStock ? AppColors.redSoft : const Color(0xFFEFF2FD),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                Fmt.n(medicine.remainingUnits.round()),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: lowStock ? AppColors.red : AppColors.primary,
                ),
              ),
            ),
          const Icon(Icons.chevron_left, color: AppColors.muted),
        ],
      ),
    );
  }
}

class _EmptyMedicines extends StatelessWidget {
  const _EmptyMedicines();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.medication_liquid_outlined,
            size: 60,
            color: AppColors.primary,
          ),
          const SizedBox(height: 14),
          const Text(
            'لم تُضف أي دواء بعد',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'اضغط «إضافة دواء» في الأسفل لتسجيل أول دواء وأوقاته.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
