import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/pill_art.dart';

class MedicineFormScreen extends StatefulWidget {
  const MedicineFormScreen({super.key, required this.patientId, this.existing});

  final int patientId;
  final Medicine? existing;

  @override
  State<MedicineFormScreen> createState() => _MedicineFormScreenState();
}

class _MedicineFormScreenState extends State<MedicineFormScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.existing?.notes ?? '',
  );

  late MedForm _form = widget.existing?.form ?? MedForm.tablet;
  late int _colorIndex =
      widget.existing?.colorIndex ??
      (appState.currentMedicines.length % kPillColors.length);
  late double _dose = widget.existing?.dose ?? 1;
  late String _unit = widget.existing?.unit ?? MedForm.tablet.unit;
  late int _totalUnits = widget.existing?.totalUnits ?? 0;
  late DateTime _start = widget.existing?.start ?? DateTime.now();
  late int _durationDays = widget.existing?.durationDays ?? 0;
  late List<int> _times = List<int>.from(widget.existing?.times ?? <int>[480]);
  late int _weekdays = widget.existing?.weekdaysMask ?? 127;
  late bool _alarm = widget.existing?.alarmMode ?? appState.defaultAlarmMode;

  static const List<String> _units = <String>[
    'حبة',
    'كبسولة',
    'ملعقة',
    'مل',
    'نقطة',
    'إبرة',
    'كيس',
    'بخة',
  ];

  static const List<int> _durations = <int>[0, 3, 5, 7, 10, 14, 30, 90];

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      _snack('اكتب اسم الدواء أولاً');
      return;
    }
    if (_times.isEmpty) {
      _snack('أضف وقتاً واحداً على الأقل');
      return;
    }
    if (_weekdays == 0) {
      _snack('اختر يوماً واحداً على الأقل من أيام الأسبوع');
      return;
    }

    final List<int> times = List<int>.from(_times)..sort();

    double remaining;
    if (_isEdit) {
      final int oldTotal = widget.existing!.totalUnits;
      final double oldRemaining = widget.existing!.remainingUnits;
      remaining = _totalUnits == oldTotal
          ? oldRemaining
          : (oldRemaining + (_totalUnits - oldTotal));
      if (remaining < 0) remaining = 0;
      if (remaining > _totalUnits) remaining = _totalUnits.toDouble();
    } else {
      remaining = _totalUnits.toDouble();
    }

    final Medicine medicine = Medicine(
      id: widget.existing?.id,
      patientId: widget.patientId,
      name: name,
      form: _form,
      colorIndex: _colorIndex,
      dose: _dose,
      unit: _unit,
      totalUnits: _totalUnits,
      remainingUnits: remaining,
      startDate: Fmt.storeDate(_start),
      durationDays: _durationDays,
      times: times,
      weekdaysMask: _weekdays,
      alarmMode: _alarm,
      notes: _notes.text.trim(),
      active: widget.existing?.active ?? true,
      createdAt: widget.existing?.createdAt,
    );

    await appState.saveMedicine(medicine);
    if (mounted) Navigator.pop(context);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(_isEdit ? 'تعديل الدواء' : 'دواء جديد')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: <Widget>[
              _preview(),
              const SizedBox(height: 18),

              const SectionTitle('اسم الدواء'),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  hintText: 'مثال: باراسيتامول ٥٠٠',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
              ),

              const SectionTitle('شكل الدواء'),
              _formPicker(),

              const SectionTitle('اللون'),
              _colorPicker(),

              const SectionTitle('الجرعة في كل مرة'),
              Row(
                children: <Widget>[
                  Expanded(
                    child: NumberStepper(
                      value: _dose,
                      min: 0.5,
                      max: 20,
                      step: 0.5,
                      onChanged: (num v) => setState(() => _dose = v.toDouble()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _unitPicker()),
                ],
              ),

              const SectionTitle('أوقات الأخذ'),
              _timesEditor(),

              const SectionTitle('أيام الأسبوع'),
              _weekdayPicker(),

              const SectionTitle('مدة الكورس'),
              _durationPicker(),

              const SectionTitle('الكمية المتوفرة (اختياري)'),
              SoftCard(
                child: Column(
                  children: <Widget>[
                    const Text(
                      'كم حبة عندك؟ سيظهر الشريط وتنقص حبة كلما أخذت جرعة.',
                      style: TextStyle(fontSize: 16, color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                    NumberStepper(
                      value: _totalUnits,
                      min: 0,
                      max: 500,
                      step: 1,
                      suffix: _totalUnits == 0 ? 'بدون تحديد' : _form.stockUnit,
                      onChanged: (num v) =>
                          setState(() => _totalUnits = v.toInt()),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: <int>[10, 20, 30, 60]
                          .map(
                            (int v) => ActionChip(
                              label: Text(
                                Fmt.n(v),
                                style: const TextStyle(fontSize: 17),
                              ),
                              onPressed: () => setState(() => _totalUnits = v),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),

              const SectionTitle('نوع التنبيه'),
              _alarmPicker(),

              const SectionTitle('ملاحظات (اختياري)'),
              TextField(
                controller: _notes,
                maxLines: 3,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  hintText: 'مثال: بعد الأكل مباشرة',
                ),
              ),

              const SizedBox(height: 26),
              BigButton(
                label: 'حفظ الدواء',
                icon: Icons.save_outlined,
                onPressed: _save,
              ),
              if (_isEdit) ...<Widget>[
                const SizedBox(height: 12),
                BigButton(
                  label: 'حذف الدواء',
                  icon: Icons.delete_outline,
                  color: AppColors.redSoft,
                  textColor: AppColors.red,
                  height: 60,
                  onPressed: () async {
                    final bool ok = await confirmAr(
                      context,
                      title: 'حذف الدواء',
                      message:
                          'سيُحذف ${widget.existing!.name} من قائمة الأدوية. '
                          'ستبقى الحبوب التي أخذتها داخل العلبة.',
                      yes: 'حذف',
                      danger: true,
                    );
                    if (!ok) return;
                    await appState.deleteMedicine(widget.existing!.id!);
                    if (mounted) {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      child: Row(
        children: <Widget>[
          PillIcon(form: _form, colorIndex: _colorIndex, size: 74),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _name.text.trim().isEmpty ? 'دواء جديد' : _name.text.trim(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_form.label} • ${Fmt.countUnit(_dose, _unit)} '
                  '• ${Fmt.n(_times.length)} مرة باليوم',
                  style: const TextStyle(fontSize: 16, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formPicker() {
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: MedForm.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int i) {
          final MedForm f = MedForm.values[i];
          return SizedBox(
            width: 108,
            child: ChoiceCard(
              selected: _form == f,
              padding: const EdgeInsets.symmetric(vertical: 10),
              onTap: () => setState(() {
                _form = f;
                _unit = f.unit;
              }),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  PillIcon(form: f, colorIndex: _colorIndex, size: 52),
                  const SizedBox(height: 6),
                  Text(
                    f.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _colorPicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List<Widget>.generate(kPillColors.length, (int i) {
        final bool sel = i == _colorIndex;
        return GestureDetector(
          onTap: () => setState(() => _colorIndex = i),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              border: Border.all(
                color: sel ? AppColors.primary : AppColors.line,
                width: sel ? 3 : 1.6,
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: PillIcon(form: _form, colorIndex: i, size: 40),
          ),
        );
      }),
    );
  }

  Widget _unitPicker() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final String? picked = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (BuildContext context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'وحدة الجرعة',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                ..._units.map(
                  (String u) => ListTile(
                    title: Text(u, style: const TextStyle(fontSize: 20)),
                    trailing: u == _unit
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(context, u),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
        if (picked != null) setState(() => _unit = picked);
      },
      child: Container(
        height: 62,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line, width: 1.6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              _unit,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _timesEditor() {
    final List<int> sorted = List<int>.from(_times)..sort();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ...sorted.map(
            (int t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.alarm,
                    color: AppColors.primary,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final int? picked = await pickTimeAr(context, t);
                        if (picked == null) return;
                        setState(() {
                          _times.remove(t);
                          if (!_times.contains(picked)) _times.add(picked);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          Fmt.time(t),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    iconSize: 28,
                    color: AppColors.red,
                    onPressed: _times.length <= 1
                        ? null
                        : () => setState(() => _times.remove(t)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () async {
              final int suggestion = sorted.isEmpty
                  ? 480
                  : ((sorted.last + 360) % (24 * 60));
              final int? picked = await pickTimeAr(context, suggestion);
              if (picked == null) return;
              if (_times.contains(picked)) {
                _snack('هذا الوقت مضاف من قبل');
                return;
              }
              setState(() => _times.add(picked));
            },
            icon: const Icon(Icons.add_alarm, size: 26),
            label: const Text('إضافة وقت'),
          ),
        ],
      ),
    );
  }

  Widget _weekdayPicker() {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List<Widget>.generate(7, (int i) {
              final int weekday = i + 1;
              final bool on = (_weekdays & (1 << i)) != 0;
              return GestureDetector(
                onTap: () => setState(() => _weekdays ^= (1 << i)),
                child: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? AppColors.primary : const Color(0xFFF1F4FD),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    Fmt.weekdayShort[weekday],
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: on ? Colors.white : AppColors.muted,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _weekdays = 127),
            child: const Text('كل أيام الأسبوع'),
          ),
        ],
      ),
    );
  }

  Widget _durationPicker() {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.event, color: AppColors.primary, size: 26),
              const SizedBox(width: 12),
              const Text('يبدأ من', style: TextStyle(fontSize: 18)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _start,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    locale: const Locale('ar'),
                  );
                  if (picked != null) setState(() => _start = picked);
                },
                child: Text(
                  Fmt.date(_start),
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('المدة', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _durations.map((int d) {
              final bool sel = _durationDays == d;
              return ChoiceCard(
                selected: sel,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                onTap: () => setState(() => _durationDays = d),
                child: Text(
                  d == 0 ? 'مستمر' : '${Fmt.n(d)} يوم',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }).toList(),
          ),
          if (_durationDays > 0) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'ينتهي في ${Fmt.date(_start.add(Duration(days: _durationDays - 1)))}',
              style: const TextStyle(fontSize: 16, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _alarmPicker() {
    return Row(
      children: <Widget>[
        Expanded(
          child: ChoiceCard(
            selected: _alarm,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            onTap: () => setState(() => _alarm = true),
            child: const Column(
              children: <Widget>[
                Icon(Icons.notifications_active, size: 34, color: AppColors.red),
                SizedBox(height: 8),
                Text(
                  'منبه قوي',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'صوت مستمر وشاشة كاملة',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ChoiceCard(
            selected: !_alarm,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            onTap: () => setState(() => _alarm = false),
            child: const Column(
              children: <Widget>[
                Icon(
                  Icons.notifications_none,
                  size: 34,
                  color: AppColors.primary,
                ),
                SizedBox(height: 8),
                Text(
                  'إشعار هادئ',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'صوت قصير مرة واحدة',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
