import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../models/models.dart';
import '../widgets/blister.dart';
import '../widgets/common.dart';
import '../widgets/jar.dart';
import '../widgets/pill_art.dart';
import 'home_screen.dart';
import 'medicine_form_screen.dart';

class MedicineDetailScreen extends StatelessWidget {
  const MedicineDetailScreen({super.key, required this.medicineId});

  final int medicineId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (BuildContext context, Widget? _) {
        final Medicine? m = appState.medicineById(medicineId);
        if (m == null) {
          return const AppBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(child: Text('حُذف هذا الدواء')),
            ),
          );
        }

        final List<DoseLog> logs = appState.patientLogs
            .where((DoseLog l) => l.medicineId == medicineId && l.isTaken)
            .toList()
          ..sort((DoseLog a, DoseLog b) => a.takenAt.compareTo(b.takenAt));

        final List<DoseOccurrence> today = appState.todayOccurrences
            .where((DoseOccurrence o) => o.medicine.id == medicineId)
            .toList();

        return AppBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text(m.name, overflow: TextOverflow.ellipsis),
              actions: <Widget>[
                IconButton(
                  iconSize: 28,
                  tooltip: 'تعديل',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => MedicineFormScreen(
                        patientId: m.patientId,
                        existing: m,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: <Widget>[
                  _Header(medicine: m),
                  const SizedBox(height: 18),

                  const SectionTitle('الحبوب المتبقية'),
                  BlisterStrip(
                    form: m.form,
                    colorIndex: m.colorIndex,
                    total: m.totalUnits,
                    remaining: m.remainingUnits,
                  ),
                  if (m.totalUnits > 0) ...<Widget>[
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _Stat(
                            value: Fmt.n(m.remainingUnits.round()),
                            label: 'المتبقي',
                            color: AppColors.primary,
                          ),
                        ),
                        Expanded(
                          child: _Stat(
                            value: Fmt.n(m.takenUnits),
                            label: 'المأخوذ',
                            color: AppColors.green,
                          ),
                        ),
                        Expanded(
                          child: _Stat(
                            value: Fmt.n(m.daysLeftByStock),
                            label: 'يكفي أيام',
                            color: m.daysLeftByStock <= 3
                                ? AppColors.red
                                : AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _refillDialog(context, m),
                      icon: const Icon(Icons.add_box_outlined, size: 26),
                      label: const Text('تعبئة كمية جديدة'),
                    ),
                  ],

                  const SectionTitle('جرعات اليوم'),
                  if (today.isEmpty)
                    const SoftCard(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'لا توجد جرعة من هذا الدواء اليوم.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, color: AppColors.muted),
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

                  const SectionTitle('ما أخذته من هذا الدواء'),
                  SoftCard(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    child: Column(
                      children: <Widget>[
                        SizedBox(
                          height: 230,
                          child: JarView(
                            pills: logs
                                .map(
                                  (DoseLog l) =>
                                      JarPill(l.form, l.colorIndex),
                                )
                                .toList(),
                            dropSignal: appState.lastDropKey,
                            emptyText:
                                'لم تأخذ جرعة من هذا الدواء بعد.\nكل جرعة ستنزل هنا.',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'مجموع الجرعات المأخوذة: ${Fmt.n(logs.length)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SectionTitle('التفاصيل'),
                  SoftCard(
                    child: Column(
                      children: <Widget>[
                        _DetailRow(
                          icon: Icons.schedule,
                          label: 'الأوقات',
                          value: m.times
                              .map((int t) => Fmt.time(t))
                              .join('  •  '),
                        ),
                        _DetailRow(
                          icon: Icons.medication_outlined,
                          label: 'الجرعة',
                          value: Fmt.countUnit(m.dose, m.unit),
                        ),
                        _DetailRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'البداية',
                          value: Fmt.date(m.start),
                        ),
                        _DetailRow(
                          icon: Icons.event_available_outlined,
                          label: 'المدة',
                          value: m.durationDays == 0
                              ? 'مستمر'
                              : '${Fmt.n(m.durationDays)} يوم — ينتهي ${Fmt.date(m.endDate!)}',
                        ),
                        _DetailRow(
                          icon: Icons.view_week_outlined,
                          label: 'الأيام',
                          value: _weekdaysText(m.weekdaysMask),
                        ),
                        _DetailRow(
                          icon: m.alarmMode
                              ? Icons.notifications_active
                              : Icons.notifications_none,
                          label: 'التنبيه',
                          value: m.alarmMode
                              ? 'منبه قوي بصوت مستمر'
                              : 'إشعار هادئ',
                        ),
                        if (m.notes.isNotEmpty)
                          _DetailRow(
                            icon: Icons.sticky_note_2_outlined,
                            label: 'ملاحظات',
                            value: m.notes,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _weekdaysText(int mask) {
  if (mask == 127) return 'كل الأيام';
  final List<String> names = <String>[];
  for (int i = 0; i < 7; i++) {
    if ((mask & (1 << i)) != 0) names.add(Fmt.weekdayNames[i + 1]);
  }
  return names.isEmpty ? '—' : names.join('، ');
}

Future<void> _refillDialog(BuildContext context, Medicine m) async {
  int amount = 30;
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => AlertDialog(
        title: const Text('تعبئة كمية جديدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'الكمية الحالية: ${Fmt.n(m.remainingUnits.round())} ${m.form.stockUnit}',
              style: const TextStyle(fontSize: 18, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            NumberStepper(
              value: amount,
              min: 1,
              max: 500,
              step: 1,
              suffix: m.form.stockUnit,
              onChanged: (num v) => setState(() => amount = v.toInt()),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <int>[10, 20, 30, 60]
                  .map(
                    (int v) => ActionChip(
                      label: Text(Fmt.n(v), style: const TextStyle(fontSize: 17)),
                      onPressed: () => setState(() => amount = v),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 52)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إضافة'),
          ),
        ],
      ),
    ),
  );
  if (ok == true) await appState.refill(m, amount);
}

class _Header extends StatelessWidget {
  const _Header({required this.medicine});
  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      child: Row(
        children: <Widget>[
          PillIcon(
            form: medicine.form,
            colorIndex: medicine.colorIndex,
            size: 82,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  medicine.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${medicine.form.label} • ${Fmt.countUnit(medicine.dose, medicine.unit)} '
                  '• ${Fmt.n(medicine.times.length)} مرة باليوم',
                  style: const TextStyle(fontSize: 17, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: color,
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 24, color: AppColors.primary),
          const SizedBox(width: 12),
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(fontSize: 17, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
