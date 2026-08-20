import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/palette.dart';

/// بطاقة بيضاء ناعمة تُستعمل في كل الشاشات.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AppColors.card,
      borderRadius: BorderRadius.circular(radius),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? AppColors.line,
              width: 1.6,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// عنوان قسم بخط كبير.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(
        children: <Widget>[
          Text(
            text,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// زر كبير مناسب لكبار السن.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.primary,
    this.textColor = Colors.white,
    this.height = 68,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          disabledBackgroundColor: AppColors.line,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 28),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// خيار على شكل بطاقة قابلة للاختيار.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEAEDFF) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
              width: selected ? 2.5 : 1.6,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// سؤال تأكيد بسيط.
Future<bool> confirmAr(
  BuildContext context, {
  required String title,
  required String message,
  String yes = 'نعم',
  String no = 'إلغاء',
  bool danger = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(no),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? AppColors.red : AppColors.primary,
            minimumSize: const Size(120, 52),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// مُنتقي وقت بسيط بأزرار كبيرة (مناسب لكبار السن).
Future<int?> pickTimeAr(BuildContext context, int initialMinutes) {
  return showDialog<int>(
    context: context,
    builder: (BuildContext context) => _TimePickerDialog(initial: initialMinutes),
  );
}

class _TimePickerDialog extends StatefulWidget {
  const _TimePickerDialog({required this.initial});
  final int initial;

  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  late int hour24 = (widget.initial ~/ 60) % 24;
  late int minute = widget.initial % 60;

  bool get isPm => hour24 >= 12;

  int get hour12 {
    final int h = hour24 % 12;
    return h == 0 ? 12 : h;
  }

  void _setHour12(int h) {
    final int base = h % 12;
    setState(() => hour24 = isPm ? base + 12 : base);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختر الوقت'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            Fmt.time(hour24 * 60 + minute),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: _Stepper(
                  label: 'الساعة',
                  value: Fmt.n(hour12),
                  onPlus: () => _setHour12(hour12 + 1),
                  onMinus: () => _setHour12(hour12 + 11),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stepper(
                  label: 'الدقيقة',
                  value: Fmt.n(minute.toString().padLeft(2, '0')),
                  onPlus: () => setState(() => minute = (minute + 5) % 60),
                  onMinus: () => setState(() => minute = (minute + 55) % 60),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: ChoiceCard(
                  selected: !isPm,
                  onTap: () => setState(() {
                    if (isPm) hour24 -= 12;
                  }),
                  child: const Center(
                    child: Text(
                      'صباحاً',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChoiceCard(
                  selected: isPm,
                  onTap: () => setState(() {
                    if (!isPm) hour24 += 12;
                  }),
                  child: const Center(
                    child: Text(
                      'مساءً',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(120, 52)),
          onPressed: () => Navigator.pop(context, hour24 * 60 + minute),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onPlus,
    required this.onMinus,
  });

  final String label;
  final String value;
  final VoidCallback onPlus;
  final VoidCallback onMinus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 16, color: AppColors.muted)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line, width: 1.6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              IconButton(
                onPressed: onMinus,
                iconSize: 30,
                icon: const Icon(Icons.remove_circle_outline),
                color: AppColors.primary,
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                onPressed: onPlus,
                iconSize: 30,
                icon: const Icon(Icons.add_circle_outline),
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// عدّاد كمية بسيط بأزرار كبيرة.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 9999,
    this.step = 1,
    this.suffix,
  });

  final num value;
  final ValueChanged<num> onChanged;
  final num min;
  final num max;
  final num step;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line, width: 1.6),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            iconSize: 32,
            color: AppColors.primary,
            onPressed: value - step < min
                ? null
                : () => onChanged(value - step),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Expanded(
            child: Text(
              suffix == null
                  ? Fmt.n(value)
                  : '${Fmt.n(value)} ${suffix!}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            iconSize: 32,
            color: AppColors.primary,
            onPressed: value + step > max
                ? null
                : () => onChanged(value + step),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
