import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../models/models.dart';
import 'pill_art.dart';

/// شريط الدواء: كل جيب فيه حبة، وكلما أخذ المريض جرعة يُفتح جيب.
class BlisterStrip extends StatelessWidget {
  const BlisterStrip({
    super.key,
    required this.form,
    required this.colorIndex,
    required this.total,
    required this.remaining,
    this.maxPockets = 80,
  });

  final MedForm form;
  final int colorIndex;
  final int total;
  final double remaining;
  final int maxPockets;

  @override
  Widget build(BuildContext context) {
    final int totalUnits = total <= 0 ? 0 : total;
    if (totalUnits == 0) {
      return const _NoStockHint();
    }

    final int left = remaining.ceil().clamp(0, totalUnits);
    final int used = totalUnits - left;

    if (totalUnits > maxPockets) {
      return _CompactStock(total: totalUnits, remaining: left, colorIndex: colorIndex);
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double width = c.maxWidth;
        // نحاول جعل عدد الأعمدة ١٠ ثم نقلّل إن كان الشريط قصيراً.
        int cols = math.min(10, math.max(4, totalUnits));
        double cell = (width - 24) / cols;
        while (cell > 62 && cols < 10) {
          cols++;
          cell = (width - 24) / cols;
        }
        cell = cell.clamp(26.0, 62.0);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[Color(0xFFF3F5FB), Color(0xFFE4E9F5)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD5DCEC), width: 2),
          ),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: List<Widget>.generate(totalUnits, (int i) {
              // الجيوب المفتوحة أولاً (من بداية الشريط).
              final bool filled = i >= used;
              return _Pocket(
                size: cell,
                filled: filled,
                form: form,
                colorIndex: colorIndex,
              );
            }),
          ),
        );
      },
    );
  }
}

class _Pocket extends StatefulWidget {
  const _Pocket({
    required this.size,
    required this.filled,
    required this.form,
    required this.colorIndex,
  });

  final double size;
  final bool filled;
  final MedForm form;
  final int colorIndex;

  @override
  State<_Pocket> createState() => _PocketState();
}

class _PocketState extends State<_Pocket> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _Pocket oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filled && !widget.filled) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        return SizedBox(
          width: widget.size,
          height: widget.size * 1.18,
          child: CustomPaint(
            painter: _PocketPainter(
              filled: widget.filled,
              form: widget.form,
              colors: pillColorAt(widget.colorIndex),
              t: _c.value,
            ),
          ),
        );
      },
    );
  }
}

class _PocketPainter extends CustomPainter {
  _PocketPainter({
    required this.filled,
    required this.form,
    required this.colors,
    required this.t,
  });

  final bool filled;
  final MedForm form;
  final PillColors colors;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect pocket = RRect.fromRectAndRadius(
      rect.deflate(1.5),
      Radius.circular(size.width * 0.34),
    );

    if (filled) {
      canvas.drawRRect(
        pocket,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Colors.white.withValues(alpha: 0.95),
              const Color(0xFFE7ECF7),
            ],
          ).createShader(rect),
      );
      final Rect pillRect = rect.deflate(size.width * 0.16);
      PillArt.draw(
        canvas,
        pillRect,
        form,
        colors,
        angle: form == MedForm.capsule ? -math.pi / 2 : 0,
      );
      // لمعة القبة البلاستيكية
      canvas.drawRRect(
        pocket,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Colors.white.withValues(alpha: 0.42),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const <double>[0.0, 0.55],
          ).createShader(rect),
      );
      canvas.drawRRect(
        pocket,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFCBD4E6),
      );
    } else {
      // جيب مفتوح: رقاقة ممزّقة
      final double pop = 1 - Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.scale(1 + pop * 0.15);
      canvas.translate(-size.width / 2, -size.height / 2);

      canvas.drawRRect(
        pocket,
        Paint()..color = const Color(0xFFD3DAEA).withValues(alpha: 0.85),
      );
      canvas.drawRRect(
        pocket.deflate(size.width * 0.12),
        Paint()..color = const Color(0xFFB9C2D8).withValues(alpha: 0.9),
      );

      final Paint tear = Paint()
        ..color = const Color(0xFF98A3BF)
        ..strokeWidth = math.max(1.4, size.width * 0.06)
        ..strokeCap = StrokeCap.round;
      final double cx = size.width / 2;
      final double cy = size.height / 2;
      final double s = size.width * 0.20;
      canvas.drawLine(Offset(cx - s, cy - s), Offset(cx + s, cy + s), tear);
      canvas.drawLine(Offset(cx + s, cy - s), Offset(cx - s, cy + s), tear);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PocketPainter old) =>
      old.filled != filled || old.t != t || old.colors != colors;
}

/// عرض مختصر عندما تكون الكمية كبيرة جداً.
class _CompactStock extends StatelessWidget {
  const _CompactStock({
    required this.total,
    required this.remaining,
    required this.colorIndex,
  });

  final int total;
  final int remaining;
  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final double ratio = total == 0 ? 0 : remaining / total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5FB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD5DCEC), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'المتبقي ${Fmt.n(remaining)} من ${Fmt.n(total)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 18,
              backgroundColor: const Color(0xFFDDE3F0),
              valueColor: AlwaysStoppedAnimation<Color>(
                pillColorAt(colorIndex).top,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoStockHint extends StatelessWidget {
  const _NoStockHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.info_outline, color: AppColors.amber, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'لم تُدخل كمية الدواء، لذلك لا يظهر الشريط. عدّل الدواء وأضف الكمية.',
              style: TextStyle(fontSize: 17, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
