import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// تشغيل نغمة المنبه من داخل التطبيق (MediaPlayer أصلي على مسار المنبه).
///
/// السبب: بعض الأنظمة — MIUI تحديداً — تكتم صوت الإشعار عندما يفتح
/// full-screen intent شاشة كاملة، فيبقى الاهتزاز فقط. تطبيقات المنبه
/// والاتصال تشغّل صوتها بنفسها لهذا السبب، وهذا ما نفعله هنا.
class AlarmAudio {
  AlarmAudio._();

  static const MethodChannel _channel = MethodChannel('dawaii/alarm');

  static bool playing = false;

  /// يبدأ الرنين ويكرّره حتى [stop].
  static Future<void> start({bool vibrate = true}) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('start', <String, Object?>{
        'vibrate': vibrate,
      });
      playing = ok ?? false;
    } catch (e) {
      playing = false;
      debugPrint('تعذّر تشغيل صوت المنبه: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (e) {
      debugPrint('تعذّر إيقاف صوت المنبه: $e');
    }
    playing = false;
  }
}
