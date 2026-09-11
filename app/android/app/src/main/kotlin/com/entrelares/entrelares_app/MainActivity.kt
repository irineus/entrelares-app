package com.entrelares.entrelares_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSwapChannel()
    }

    /**
     * F-09 — the notification channel the push payload names.
     *
     * This is the failure that looks like nothing at all: on Android 8+ a
     * message whose `channel_id` does not exist on the device is dropped by the
     * system WITHOUT an error. FCM reports the send as delivered, the server
     * logs a success, and no notification ever appears — so the bug reads as
     * "push does not work" with every layer claiming it does.
     *
     * Created here rather than from Dart because it must exist before the first
     * message arrives, including a message that arrives while the app is dead:
     * creating a channel is idempotent, so running it on every launch costs
     * nothing and removes the ordering question entirely. The IMPORTANCE is
     * HIGH: a swap request is time-critical by nature (the whole reason F-09
     * exists), and DEFAULT would deny it the heads-up display.
     *
     * The user-visible name is PT-BR on purpose. It is rendered by Android's
     * own Settings screen, which the app does not localize — U-13 governs what
     * the app draws, and this string belongs to the OS.
     */
    private fun createSwapChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "entrelares_swaps",
            "Trocas e combinados",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Solicitações de troca, respostas e avisos de prazo."
        }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }
}
