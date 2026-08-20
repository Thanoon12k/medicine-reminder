import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// النطق العربي بمحرك الجهاز نفسه — بدون إنترنت.
///
/// الترتيب المعتمد في التطبيق:
///   ١) صوت المنبه المرفق داخل التطبيق يعمل دائماً ويقول «وقت الدواء».
///   ٢) إن كانت اللغة العربية **مثبّتة** في محرك النطق، يُضاف نطق يذكر
///      اسم المريض واسم الدواء والجرعة.
///   ٣) إن لم تكن مثبّتة، لا يحدث شيء إضافي ويبقى الصوت المرفق كافياً.
class Speech {
  Speech._();

  static final FlutterTts _tts = FlutterTts();

  /// هل النطق العربي جاهز للاستعمال؟
  static bool ready = false;

  /// رمز اللغة الذي نجح فعلياً (مثل ar-SA).
  static String? language;

  /// رسالة تُعرض في شاشة الإعدادات.
  static String status = 'لم يُفحص بعد';

  static bool _initialised = false;

  /// نجرّب اللهجات الأقرب أولاً.
  static const List<String> _candidates = <String>[
    'ar-IQ',
    'ar-SA',
    'ar-EG',
    'ar-AE',
    'ar-JO',
    'ar',
  ];

  /// فحص المحرك وتهيئته. لا يرمي استثناءً أبداً.
  static Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(0.45); // بطيء وواضح لكبار السن
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);

      for (final String code in _candidates) {
        bool available = false;
        try {
          available = (await _tts.isLanguageAvailable(code)) == true;
        } catch (_) {}
        if (!available) continue;

        // متاح ≠ مثبّت: بعض الأجهزة تحتاج تنزيل بيانات الصوت مرة واحدة.
        bool installed = true;
        try {
          installed = (await _tts.isLanguageInstalled(code)) == true;
        } catch (_) {
          installed = true; // بعض المحركات لا تدعم هذا الفحص
        }
        if (!installed) continue;

        await _tts.setLanguage(code);
        language = code;
        ready = true;
        status = 'النطق العربي جاهز ($code)';
        return;
      }

      status =
          'لا توجد لغة عربية مثبّتة في محرك النطق.\n'
          'سيُستعمل الصوت المسجّل داخل التطبيق فقط.';
    } catch (e) {
      status = 'محرك النطق غير متاح على هذا الجهاز.';
      debugPrint('تعذّرت تهيئة النطق: $e');
    }
  }

  /// إعادة الفحص (بعد أن يثبّت المستخدم اللغة العربية).
  static Future<void> recheck() async {
    _initialised = false;
    ready = false;
    language = null;
    await init();
  }

  static Future<void> say(String text) async {
    if (!ready) return;
    try {
      await _tts.stop();
      await _tts.speak(text, focus: true);
    } catch (e) {
      debugPrint('تعذّر النطق: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// النص الذي يُنطق عند المنبه — أرقام إنجليزية لأن المحركات تقرؤها أوضح.
  static String sentence({
    required String medicineName,
    required String patientName,
    required double dose,
    required String unit,
  }) {
    final String amount = dose == dose.roundToDouble()
        ? '${dose.toInt()}'
        : '$dose';
    final StringBuffer b = StringBuffer('وقت الدواء');
    if (patientName.trim().isNotEmpty) b.write('، $patientName');
    b.write('، $medicineName، $amount $unit');
    return b.toString();
  }
}
