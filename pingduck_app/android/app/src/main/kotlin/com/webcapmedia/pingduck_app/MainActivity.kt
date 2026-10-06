package com.webcapmedia.pingduck_app

import android.content.Context
import android.net.wifi.WifiManager
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
    }

    override fun onDestroy() {
        multicastLock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
