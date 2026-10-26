package app.webcap.pingduck

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Android filters inbound multicast (mDNS, SSDP) to save power unless
        // an app holds this lock. The scanner holds it only while scanning.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pingduck/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        val lock = multicastLock ?: (applicationContext
                            .getSystemService(Context.WIFI_SERVICE) as WifiManager)
                            .createMulticastLock("pingduck-scan")
                            .apply { setReferenceCounted(false) }
                            .also { multicastLock = it }
                        lock.acquire()
                        result.success(null)
                    }
                    "release" -> {
                        multicastLock?.takeIf { it.isHeld }?.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pingduck/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWifiSettings" -> {
                        openWifiSettings()
                        result.success(null)
                    }
                    "shareText" -> {
                        val text = call.argument<String>("text") ?: ""
                        val sendIntent = Intent().apply {
                            action = Intent.ACTION_SEND
                            putExtra(Intent.EXTRA_TEXT, text)
                            type = "text/plain"
                        }
                        val shareIntent = Intent.createChooser(sendIntent, null)
                        startActivity(shareIntent)
                        result.success(null)
                    }
                    // Per app signing key and device; survives a reinstall. The
                    // server counts Free scans by its hash (claim_scan).
                    "deviceId" -> result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
                    else -> result.notImplemented()
                }
            }
    }

    private fun openWifiSettings() {
        // Android 10+ shows an in-app Wi-Fi panel; older versions open Settings.
        val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Settings.Panel.ACTION_WIFI
                     else Settings.ACTION_WIFI_SETTINGS
        startActivity(Intent(action))
    }

    override fun onDestroy() {
        multicastLock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
