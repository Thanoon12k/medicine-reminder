import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../models/models.dart';

/// رسم أشكال الأدوية بالكود (بدون أي صور خارجية).
class PillArt {
  const PillArt._();

  /// يرسم شكل الدواء داخل [rect] مع إمكانية الدوران [angle] (بالراديان).
  static void draw(
    Canvas canvas,
    Rect rect,
    MedForm form,
    PillColors colors, {
    double angle = 0,
    double opacity = 1,
    bool shadow = false,
  }) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(angle);
    canvas.translate(-rect.center.dx, -rect.center.dy);

    if (shadow) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(rect.center.dx, rect.bottom - rect.height * 0.06),
          width: rect.width * 0.78,
          height: rect.height * 0.22,
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.07 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    switch (form) {
      case MedForm.capsule:
        _capsule(canvas, rect, colors, opacity);
        break;
      case MedForm.tablet:
        _tablet(canvas, rect, colors, opacity);
        break;
      case MedForm.syrup:
        _syrup(canvas, rect, colors, opacity);
        break;
      case MedForm.injection:
        _injection(canvas, rect, colors, opacity);
        break;
      case MedForm.drops:
        _drop(canvas, rect, colors, opacity);
        break;
    }
    canvas.restore();
  }

  // ------------------------- كبسولة -------------------------

  static void _capsule(Canvas c, Rect r, PillColors col, double o) {
    final double h = math.min(r.height * 0.96, r.width * 0.46);
    final Rect body = Rect.fromCenter(
      center: r.center,
      width: r.width * 0.98,
      height: h,
    );
    final RRect rr = RRect.fromRectAndRadius(body, Radius.circular(h / 2));

    c.save();
    c.clipRRect(rr);
    c.drawRect(
      Rect.fromLTRB(body.left, body.top, body.center.dx + 0.5, body.bottom),
      Paint()..color = col.top.withValues(alpha: o),
    );
    c.drawRect(
      Rect.fromLTRB(body.center.dx - 0.5, body.top, body.right, body.bottom),
      Paint()..color = col.bottom.withValues(alpha: o),
    );
    // ظل داخلي أسفل الكبسولة لإحساس الحجم
    c.drawRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.30 * o),
            Colors.white.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.14 * o),
          ],
          stops: const <double>[0.0, 0.45, 1.0],
        ).createShader(body),
    );
    // حافة الوصلة بين النصفين
    c.drawRect(
      Rect.fromLTWH(body.center.dx - h * 0.06, body.top, h * 0.12, body.height),
      Paint()..color = Colors.black.withValues(alpha: 0.06 * o),
    );
    c.restore();

    // لمعة
    c.drawOval(
      Rect.fromLTWH(
        body.left + body.width * 0.10,
        body.top + h * 0.16,
        body.width * 0.42,
        h * 0.22,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.5 * o),
    );

    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, h * 0.05)
        ..color = Colors.black.withValues(alpha: 0.10 * o),
    );
  }

  // ------------------------- قرص -------------------------

  static void _tablet(Canvas c, Rect r, PillColors col, double o) {
    final double d = math.min(r.width, r.height) * 0.94;
    final Rect body = Rect.fromCenter(center: r.center, width: d, height: d);

    c.drawOval(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.95,
          colors: <Color>[
            Color.lerp(col.bottom, Colors.white, 0.45)!.withValues(alpha: o),
            col.top.withValues(alpha: o),
          ],
        ).createShader(body),
    );

    // خط التقسيم
    c.drawLine(
      Offset(body.center.dx, body.top + d * 0.14),
      Offset(body.center.dx, body.bottom - d * 0.14),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.13 * o)
        ..strokeWidth = math.max(1.0, d * 0.045)
        ..strokeCap = StrokeCap.round,
    );

    // لمعة
    c.drawOval(
      Rect.fromLTWH(
        body.left + d * 0.16,
        body.top + d * 0.12,
        d * 0.36,
        d * 0.22,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55 * o),
    );

    c.drawOval(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, d * 0.045)
        ..color = Colors.black.withValues(alpha: 0.10 * o),
    );
  }

  // ------------------------- شراب -------------------------

  static void _syrup(Canvas c, Rect r, PillColors col, double o) {
    final double w = r.width * 0.66;
    final double h = r.height * 0.96;
    final double cx = r.center.dx;
    final double top = r.center.dy - h / 2;

    // الغطاء
    final RRect cap = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w * 0.28, top, w * 0.56, h * 0.13),
      Radius.circular(h * 0.04),
    );
    c.drawRRect(cap, Paint()..color = col.bottom.withValues(alpha: o));

    // العنق
    c.drawRect(
      Rect.fromLTWH(cx - w * 0.18, top + h * 0.12, w * 0.36, h * 0.10),
      Paint()..color = Color.lerp(col.bottom, Colors.white, 0.3)!
          .withValues(alpha: o),
    );

    // جسم القنينة
    final RRect bottle = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w / 2, top + h * 0.20, w, h * 0.80),
      Radius.circular(w * 0.22),
    );
    c.drawRRect(
      bottle,
      Paint()..color = Colors.white.withValues(alpha: 0.92 * o),
    );

    // السائل
    c.save();
    c.clipRRect(bottle);
    final Rect liquid = Rect.fromLTRB(
      bottle.left,
      top + h * 0.42,
      bottle.right,
      bottle.bottom,
    );
    c.drawRect(
      liquid,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            col.top.withValues(alpha: 0.95 * o),
            Color.lerp(col.top, Colors.black, 0.18)!.withValues(alpha: o),
          ],
        ).createShader(liquid),
    );
    // ملصق أبيض
    c.drawRect(
      Rect.fromLTRB(
        bottle.left,
        top + h * 0.52,
        bottle.right,
        top + h * 0.72,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.85 * o),
    );
    c.restore();

    c.drawRRect(
      bottle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.05)
        ..color = Colors.black.withValues(alpha: 0.12 * o),
    );
  }

  // ------------------------- إبرة -------------------------

  static void _injection(Canvas c, Rect r, PillColors col, double o) {
    final double h = math.min(r.height * 0.5, r.width * 0.34);
    final double cy = r.center.dy;
    final double left = r.left + r.width * 0.04;
    final double right = r.right - r.width * 0.04;
    final double barrelRight = left + (right - left) * 0.72;

    // الإبرة
    c.drawLine(
      Offset(barrelRight, cy),
      Offset(right, cy),
      Paint()
        ..color = const Color(0xFF9AA3BC).withValues(alpha: o)
        ..strokeWidth = math.max(1.5, h * 0.16)
        ..strokeCap = StrokeCap.round,
    );

    // الأسطوانة
    final RRect barrel = RRect.fromRectAndRadius(
      Rect.fromLTRB(left + (right - left) * 0.16, cy - h / 2, barrelRight, cy + h / 2),
      Radius.circular(h * 0.22),
    );
    c.drawRRect(
      barrel,
      Paint()..color = Colors.white.withValues(alpha: 0.95 * o),
    );

    c.save();
    c.clipRRect(barrel);
    final Rect liquid = Rect.fromLTRB(
      barrel.left,
      barrel.top,
      barrel.left + barrel.width * 0.66,
      barrel.bottom,
    );
    c.drawRect(liquid, Paint()..color = col.top.withValues(alpha: 0.9 * o));
    c.restore();

    c.drawRRect(
      barrel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, h * 0.10)
        ..color = Colors.black.withValues(alpha: 0.12 * o),
    );

    // المكبس
    c.drawLine(
      Offset(left, cy),
      Offset(barrel.left, cy),
      Paint()
        ..color = col.bottom.withValues(alpha: o)
        ..strokeWidth = math.max(2.0, h * 0.30)
        ..strokeCap = StrokeCap.round,
    );
    c.drawLine(
      Offset(left, cy - h * 0.55),
      Offset(left, cy + h * 0.55),
      Paint()
        ..color = col.bottom.withValues(alpha: o)
        ..strokeWidth = math.max(2.0, h * 0.20)
        ..strokeCap = StrokeCap.round,
    );
  }

  // ------------------------- قطرة -------------------------

  static void _drop(Canvas c, Rect r, PillColors col, double o) {
    final double size = math.min(r.width, r.height) * 0.94;
    final double rad = size * 0.34;
    final double cx = r.center.dx;
    final double bottom = r.center.dy + size / 2;
    final double top = r.center.dy - size / 2;
    final Offset centre = Offset(cx, bottom - rad);

    final Path path = Path()
      ..moveTo(cx, top)
      ..quadraticBezierTo(
        centre.dx + rad * 1.2,
        centre.dy - rad * 0.6,
        centre.dx + rad,
        centre.dy,
      )
      ..arcToPoint(
        Offset(centre.dx - rad, centre.dy),
        radius: Radius.circular(rad),
        clockwise: true,
      )
      ..quadraticBezierTo(
        centre.dx - rad * 1.2,
        centre.dy - rad * 0.6,
        cx,
        top,
      )
      ..close();

    c.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(col.top, Colors.white, 0.35)!.withValues(alpha: o),
            col.top.withValues(alpha: o),
          ],
        ).createShader(r),
    );
    c.drawOval(
      Rect.fromCenter(
        center: Offset(centre.dx - rad * 0.35, centre.dy - rad * 0.2),
        width: rad * 0.5,
        height: rad * 0.7,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.6 * o),
    );
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, size * 0.04)
        ..color = Colors.black.withValues(alpha: 0.10 * o),
    );
  }
}

/// أيقونة دواء جاهزة للاستعمال في الواجهة.
class PillIcon extends StatelessWidget {
  const PillIcon({
    super.key,
    required this.form,
    required this.colorIndex,
    this.size = 56,
    this.angle = -0.5,
    this.opacity = 1,
  });

  final MedForm form;
  final int colorIndex;
  final double size;
  final double angle;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PillIconPainter(
          form: form,
          colors: pillColorAt(colorIndex),
          angle: angle,
          opacity: opacity,
        ),
      ),
    );
  }
}

class _PillIconPainter extends CustomPainter {
  _PillIconPainter({
    required this.form,
    required this.colors,
    required this.angle,
    required this.opacity,
  });

  final MedForm form;
  final PillColors colors;
  final double angle;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    PillArt.draw(
      canvas,
      Offset.zero & size,
      form,
      colors,
      angle: form == MedForm.capsule || form == MedForm.injection ? angle : 0,
      opacity: opacity,
    );
  }

  @override
  bool shouldRepaint(covariant _PillIconPainter old) =>
      old.form != form ||
      old.colors != colors ||
      old.angle != angle ||
      old.opacity != opacity;
}
