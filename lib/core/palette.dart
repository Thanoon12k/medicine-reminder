import 'package:flutter/material.dart';

/// ألوان التطبيق العامة.
class AppColors {
  static const Color bgTop = Color(0xFFEEF3FF);
  static const Color bgBottom = Color(0xFFF9F1FF);
  static const Color primary = Color(0xFF5468FF);
  static const Color primaryDark = Color(0xFF3B4CD6);
  static const Color green = Color(0xFF12A150);
  static const Color greenSoft = Color(0xFFE6F6EC);
  static const Color red = Color(0xFFE0464C);
  static const Color redSoft = Color(0xFFFDECEC);
  static const Color amber = Color(0xFFE8890C);
  static const Color amberSoft = Color(0xFFFFF3E0);
  static const Color ink = Color(0xFF17203F);
  static const Color muted = Color(0xFF6A7290);
  static const Color line = Color(0xFFE3E7F5);
  static const Color card = Colors.white;
}

/// ألوان الأدوية: لكل دواء لونان (أعلى/أسفل الكبسولة).
class PillColors {
  const PillColors(this.name, this.top, this.bottom);
  final String name;
  final Color top;
  final Color bottom;
}

const List<PillColors> kPillColors = <PillColors>[
  PillColors('أحمر', Color(0xFFFF5A5F), Color(0xFFFFC24B)),
  PillColors('أزرق', Color(0xFF4A9BFF), Color(0xFF9AD0FF)),
  PillColors('أخضر', Color(0xFF29C17E), Color(0xFFB8F0D2)),
  PillColors('بنفسجي', Color(0xFF8B5CF6), Color(0xFFD6C4FF)),
  PillColors('وردي', Color(0xFFFF6FA5), Color(0xFFFFC7DC)),
  PillColors('برتقالي', Color(0xFFFF8A3D), Color(0xFFFFD3A8)),
  PillColors('سماوي', Color(0xFF22C4D6), Color(0xFFBDF0F6)),
  PillColors('أصفر', Color(0xFFF5C518), Color(0xFFFFF0B8)),
  PillColors('نيلي', Color(0xFF3F51B5), Color(0xFFB9C1F2)),
  PillColors('عنابي', Color(0xFFC2255C), Color(0xFFF7C2D6)),
  PillColors('زيتوني', Color(0xFF7CB342), Color(0xFFDCEFC4)),
  PillColors('رمادي', Color(0xFF8D97B0), Color(0xFFDDE2EE)),
];

PillColors pillColorAt(int index) => kPillColors[index % kPillColors.length];

/// ألوان بطاقات المرضى.
const List<Color> kPatientColors = <Color>[
  Color(0xFF5468FF),
  Color(0xFF12A150),
  Color(0xFFE8890C),
  Color(0xFF8B5CF6),
  Color(0xFFE0464C),
  Color(0xFF22A7B8),
];

Color patientColorAt(int index) => kPatientColors[index % kPatientColors.length];
