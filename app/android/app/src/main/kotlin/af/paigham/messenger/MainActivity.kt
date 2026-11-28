package af.paigham.messenger

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    @SuppressLint("BatteryLife")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "paigham/system").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    // true when Android lets the app run in the background freely
                    "batteryFree" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(Build.VERSION.SDK_INT < 23 || pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "askBattery" -> {
                        startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                        result.success(true)
                    }
                    "notifSettings" -> {
                        val i = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        startActivity(i)
                        result.success(true)
                    }
                    "appSettings" -> {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }
}
