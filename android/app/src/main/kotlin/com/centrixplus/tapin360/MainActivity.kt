package com.centrixplus.tapin360

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingUid: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeLaunchTag" -> {
                        result.success(pendingUid)
                        pendingUid = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNfcSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                        }
                        result.success(null)
                    }
                    // Spec §14: hardware ID for device binding (IMEI is not readable).
                    "getAndroidId" -> result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    )
                    "cameraPermission" -> result.success(
                        checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                    )
                    else -> result.notImplemented()
                }
            }
        pendingUid = consumeUid(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uid = consumeUid(intent) ?: return
        channel?.invokeMethod("launchTag", uid)
    }

    /** UID of the tag that started/resumed us, then marks the intent used so a
     *  recreated activity (e.g. rotation) does not report the same tap twice. */
    private fun consumeUid(intent: Intent?): String? {
        if (intent == null || intent.action != NfcAdapter.ACTION_NDEF_DISCOVERED) return null
        val tag: Tag? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(NfcAdapter.EXTRA_TAG, Tag::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(NfcAdapter.EXTRA_TAG)
        }
        intent.action = Intent.ACTION_MAIN
        return tag?.id?.joinToString("") { "%02X".format(it) }
    }

    companion object {
        const val CHANNEL = "nfc_attendance/launch_tag"
        const val SYSTEM_CHANNEL = "nfc_attendance/system"
    }
}
