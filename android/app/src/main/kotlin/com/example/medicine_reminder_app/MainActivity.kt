package com.example.medicine_reminder_app

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * مشغّل صوت المنبه داخل التطبيق.
 *
 * لماذا لا نكتفي بصوت قناة الإشعارات؟ لأن بعض الأنظمة (MIUI مثلاً) تكتم صوت
 * الإشعار عندما يفتح full-screen intent شاشة كاملة، وتتوقّع أن يشغّل التطبيق
 * صوته بنفسه كما تفعل تطبيقات المنبه والاتصال. هذا المشغّل يضمن الصوت
 * على مسار المنبه (USAGE_ALARM) ويكرّره حتى يستجيب المستخدم.
 */
class MainActivity : FlutterActivity() {

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val ok = startAlarm(call.argument<Boolean>("vibrate") ?: true)
                        result.success(ok)
                    }
                    "stop" -> {
                        stopAlarm()
                        result.success(true)
                    }
                    "isPlaying" -> result.success(player?.isPlaying == true)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startAlarm(vibrate: Boolean): Boolean {
        stopAlarm()
        return try {
            val uri = Uri.parse("android.resource://$packageName/${R.raw.alarm_tone}")
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@MainActivity, uri)
                isLooping = true
                setVolume(1.0f, 1.0f)
                prepare()
                start()
            }
            if (vibrate) startVibration()
            true
        } catch (e: Exception) {
            android.util.Log.e("DawaiiAlarm", "تعذّر تشغيل صوت المنبه", e)
            false
        }
    }

    private fun startVibration() {
        try {
            val v = resolveVibrator() ?: return
            vibrator = v
            val pattern = longArrayOf(0, 700, 400, 700, 400, 700, 900)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(pattern, 0)
            }
        } catch (_: Exception) {
        }
    }

    private fun resolveVibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as? Vibrator
        }

    private fun stopAlarm() {
        try {
            player?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (_: Exception) {
        }
        player = null
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        vibrator = null
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "dawaii/alarm"
    }
}
