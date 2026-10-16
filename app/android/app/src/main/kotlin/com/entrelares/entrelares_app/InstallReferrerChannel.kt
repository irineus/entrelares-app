package com.entrelares.entrelares_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * F-80 PR 2 — the Install Referrer string Play kept for this install.
 *
 * The Dart side (`lib/services/install_referrer.dart`) asks ONLY while
 * `feature.referral` is on and only where a family is being founded; this
 * class answers the raw string (`utm_source=…&ref=…`) or null, and parses
 * nothing — the rule that reads the code is `ReferralRules` in the core
 * package, with tests.
 *
 * Every failure is a null, never an error: a sideloaded build, a device
 * without the Play Store, a service that is busy or disconnects mid-call.
 * The reply is sent exactly once (the connection can report a setup result
 * AND a disconnect) and always on the main thread, as the Flutter engine
 * requires.
 */
class InstallReferrerChannel(private val context: Context) {
    companion object {
        const val CHANNEL = "app.entrelares/install_referrer"
        const val READ = "read"
    }

    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == READ) read(result) else result.notImplemented()
        }
    }

    private fun read(result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        fun reply(value: String?) {
            if (replied.compareAndSet(false, true)) {
                main.post { result.success(value) }
            }
        }

        val client: InstallReferrerClient
        try {
            client = InstallReferrerClient.newBuilder(context.applicationContext).build()
        } catch (ignored: Throwable) {
            reply(null)
            return
        }

        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    val referrer = if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                        try {
                            client.installReferrer.installReferrer
                        } catch (ignored: Throwable) {
                            null
                        }
                    } else {
                        null
                    }
                    reply(referrer)
                    try {
                        client.endConnection()
                    } catch (ignored: Throwable) {
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    reply(null)
                }
            })
        } catch (ignored: Throwable) {
            reply(null)
        }
    }
}
