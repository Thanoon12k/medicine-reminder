import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../models/models.dart';
import '../widgets/common.dart';

class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key, this.firstRun = false});

  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (BuildContext context, Widget? _) {
        final List<Patient> patients = appState.patients;
        return AppBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              automaticallyImplyLeading: !firstRun,
              title: Text(firstRun ? 'أهلاً بك' : 'المرضى'),
            ),
            body: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: <Widget>[
                  if (firstRun) ...<Widget>[
                    const SoftCard(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: <Widget>[
                          Icon(
                            Icons.medication_outlined,
                            size: 64,
                            color: AppColors.primary,
                          ),
                          SizedBox(height: 14),
                          Text(
                            'تطبيق التذكير بالدواء',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'يعمل بدون إنترنت نهائياً.\n'
                            'ابدأ بإضافة اسم المريض، ثم أضف أدويته وأوقاتها، '
                            'وكل حبة تأخذها ستنزل في العلبة.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              color: AppColors.muted,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  ...patients.map(
                    (Patient p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PatientCard(patient: p),
                    ),
                  ),
                  const SizedBox(height: 8),
                  BigButton(
                    label: patients.isEmpty ? 'إضافة أول مريض' : 'إضافة مريض',
                    icon: Icons.person_add_alt_1,
                    onPressed: () => _editPatient(context, null),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.patient});
  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final bool selected = appState.currentPatient?.id == patient.id;
    final int medCount = appState.medicines
        .where((Medicine m) => m.patientId == patient.id)
        .length;
    final List<DoseOccurrence> today = appState.occurrencesForDay(
      DateTime.now(),
      patientId: patient.id,
    );
    final int done = today.where((DoseOccurrence o) => o.isTaken).length;

    return SoftCard(
      borderColor: selected ? AppColors.primary : AppColors.line,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () async {
        await appState.setCurrentPatient(patient.id!);
        if (context.mounted) Navigator.maybePop(context);
      },
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 28,
            backgroundColor: patientColorAt(patient.colorIndex),
            child: Text(
              patient.name.isEmpty ? '؟' : patient.name.substring(0, 1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  patient.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  today.isEmpty
                      ? '${Fmt.n(medCount)} دواء'
                      : '${Fmt.n(medCount)} دواء • اليوم ${Fmt.n(done)} من ${Fmt.n(today.length)}',
                  style: const TextStyle(fontSize: 16, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (selected)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 28,
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 28),
            onSelected: (String value) async {
              if (value == 'edit') {
                await _editPatient(context, patient);
              } else if (value == 'delete') {
                final bool ok = await confirmAr(
                  context,
                  title: 'حذف المريض',
                  message:
                      'سيُحذف ${patient.name} مع كل أدويته وسجل جرعاته. هل أنت متأكد؟',
                  yes: 'حذف',
                  danger: true,
                );
                if (ok) await appState.deletePatient(patient.id!);
              }
            },
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'edit',
                child: Text('تعديل الاسم', style: TextStyle(fontSize: 18)),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(
                  'حذف',
                  style: TextStyle(fontSize: 18, color: AppColors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _editPatient(BuildContext context, Patient? existing) async {
  final TextEditingController controller = TextEditingController(
    text: existing?.name ?? '',
  );
  int colorIndex = existing?.colorIndex ?? appState.patients.length;

  final bool? saved = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => AlertDialog(
        title: Text(existing == null ? 'مريض جديد' : 'تعديل المريض'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                hintText: 'اسم المريض',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List<Widget>.generate(kPatientColors.length, (int i) {
                final bool sel = i == colorIndex % kPatientColors.length;
                return GestureDetector(
                  onTap: () => setState(() => colorIndex = i),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: kPatientColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? AppColors.ink : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: sel
                        ? const Icon(Icons.check, color: Colors.white, size: 26)
                        : null,
                  ),
                );
              }),
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
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );

  if (saved == true) {
    final String name = controller.text.trim();
    if (name.isEmpty) return;
    if (existing == null) {
      final int id = await appState.addPatient(name, colorIndex);
      await appState.setCurrentPatient(id);
    } else {
      await appState.updatePatient(
        existing.copyWith(name: name, colorIndex: colorIndex),
      );
    }
  }
  controller.dispose();
}
