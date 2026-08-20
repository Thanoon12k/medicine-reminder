import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../models/models.dart';
import 'pill_art.dart';

/// حبة داخل العلبة.
class JarPill {
  const JarPill(this.form, this.colorIndex);
  final MedForm form;
  final int colorIndex;
}

/// العلبة الزجاجية التي تتجمّع فيها كل حبة أخذها المريض.
class JarView extends StatefulWidget {
  const JarView({
    super.key,
    required this.pills,
    this.dropSignal,
    this.maxDrawn = 150,
    this.emptyText = 'العلبة فارغة\nكل حبة تأخذها ستنزل هنا',
  });

  final List<JarPill> pills;

  /// عند تغيّر هذه القيمة تُشغَّل حركة سقوط آخر حبة.
  final String? dropSignal;

  final int maxDrawn;
  final String emptyText;

  @override
  State<JarView> createState() => _JarViewState();
}

class _JarViewState extends State<JarView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant JarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dropSignal != null &&
        widget.dropSignal != oldWidget.dropSignal) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _JarPainter(
            pills: widget.pills,
            drop: _controller.value,
            maxDrawn: widget.maxDrawn,
          ),
          child: widget.pills.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      widget.emptyText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.6,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : const SizedBox.expand(),
        );
      },
    );
  }
}

class _JarPainter extends CustomPainter {
  _JarPainter({
    required this.pills,
    required this.drop,
    required this.maxDrawn,
  });

  final List<JarPill> pills;
  final double drop;
  final int maxDrawn;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;

    final double lidH = h * 0.095;
    final double bodyTop = lidH * 0.92;
    final double neckW = w * 0.56;
    final double bodyW = w * 0.82;
    final double bottom = h - h * 0.02;
    final double radius = bodyW * 0.26;

    final Path jar = Path()
      ..moveTo(cx - neckW / 2, bodyTop)
      ..lineTo(cx - neckW / 2, bodyTop + h * 0.035)
      ..cubicTo(
        cx - neckW / 2 - w * 0.02,
        bodyTop + h * 0.10,
        cx - bodyW / 2,
        bodyTop + h * 0.09,
        cx - bodyW / 2,
        bodyTop + h * 0.18,
      )
      ..lineTo(cx - bodyW / 2, bottom - radius)
      ..quadraticBezierTo(
        cx - bodyW / 2,
        bottom,
        cx - bodyW / 2 + radius,
        bottom,
      )
      ..lineTo(cx + bodyW / 2 - radius, bottom)
      ..quadraticBezierTo(
        cx + bodyW / 2,
        bottom,
        cx + bodyW / 2,
        bottom - radius,
      )
      ..lineTo(cx + bodyW / 2, bodyTop + h * 0.18)
      ..cubicTo(
        cx + bodyW / 2,
        bodyTop + h * 0.09,
        cx + neckW / 2 + w * 0.02,
        bodyTop + h * 0.10,
        cx + neckW / 2,
        bodyTop + h * 0.035,
      )
      ..lineTo(cx + neckW / 2, bodyTop)
      ..close();

    // زجاج
    canvas.drawPath(
      jar,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.92),
            const Color(0xFFEDF1FB).withValues(alpha: 0.82),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // الحبوب في الداخل
    final Rect inner = Rect.fromLTRB(
      cx - bodyW / 2 + bodyW * 0.06,
      bodyTop + h * 0.20,
      cx + bodyW / 2 - bodyW * 0.06,
      bottom - bodyW * 0.05,
    );
    canvas.save();
    canvas.clipPath(jar);
    _paintPills(canvas, inner);
    canvas.restore();

    // انعكاس الضوء على الزجاج
    canvas.save();
    canvas.clipPath(jar);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - bodyW * 0.42, bodyTop + h * 0.22, w * 0.055, h * 0.5),
        Radius.circular(w * 0.03),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - bodyW * 0.32, bodyTop + h * 0.24, w * 0.022, h * 0.32),
        Radius.circular(w * 0.02),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );
    canvas.restore();

    canvas.drawPath(
      jar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.008)
        ..color = const Color(0xFFC9D2E8),
    );

    // الغطاء
    final RRect lid = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - neckW * 0.62, 0, neckW * 1.24, lidH),
      Radius.circular(lidH * 0.38),
    );
    canvas.drawRRect(
      lid,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFFF2D89A), Color(0xFFC8A24A)],
        ).createShader(lid.outerRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx - neckW * 0.55,
          lidH * 0.18,
          neckW * 0.42,
          lidH * 0.22,
        ),
        Radius.circular(lidH * 0.12),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
    canvas.drawRRect(
      lid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.005)
        ..color = const Color(0xFFB08E3E).withValues(alpha: 0.7),
    );
  }

  void _paintPills(Canvas canvas, Rect inner) {
    final int total = pills.length;
    if (total == 0) return;

    final int drawn = math.min(total, maxDrawn);
    final List<JarPill> visible = pills.sublist(total - drawn);

    // حجم الحبة يتقلّص كلما امتلأت العلبة.
    final double area = inner.width * inner.height * 0.58;
    double cell = math.sqrt(area / drawn);
    cell = cell.clamp(inner.width / 13, inner.width / 3.6);

    final int cols = math.max(1, (inner.width / cell).floor());
    final double rowH = cell * 0.60;

    for (int i = 0; i < visible.length; i++) {
      final JarPill pill = visible[i];
      final int row = i ~/ cols;
      final int col = i % cols;
      final math.Random rnd = math.Random(i * 7919 + 13);

      final double stagger = row.isOdd ? cell * 0.42 : 0;
      double x = inner.left + cell * 0.5 + col * cell + stagger;
      if (x + cell * 0.5 > inner.right) x = inner.right - cell * 0.5;
      double y = inner.bottom - cell * 0.42 - row * rowH;

      x += (rnd.nextDouble() - 0.5) * cell * 0.16;
      y += (rnd.nextDouble() - 0.5) * cell * 0.14;

      final double angle = (rnd.nextDouble() - 0.5) * 2.4;

      double opacity = 1;
      // حركة سقوط آخر حبة
      if (i == visible.length - 1 && drop < 1) {
        final double t = Curves.easeInQuad.transform(drop.clamp(0.0, 1.0));
        final double startY = inner.top - inner.height * 0.35;
        y = startY + (y - startY) * t;
        opacity = math.min(1.0, drop * 3);
      }

      final Rect r = Rect.fromCenter(
        center: Offset(x, y),
        width: cell * 0.94,
        height: cell * 0.94,
      );
      PillArt.draw(
        canvas,
        r,
        pill.form,
        pillColorAt(pill.colorIndex),
        angle: angle,
        opacity: opacity,
        shadow: false,
      );
    }

    if (total > drawn) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '+${total - drawn}',
          style: TextStyle(
            fontSize: math.max(12.0, inner.width * 0.09),
            fontWeight: FontWeight.w800,
            color: AppColors.ink.withValues(alpha: 0.55),
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(
        canvas,
        Offset(inner.center.dx - tp.width / 2, inner.top - tp.height * 0.2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _JarPainter old) =>
      old.pills.length != pills.length || old.drop != drop;
}
