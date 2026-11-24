package com.entrelares.entrelares_app

import android.app.Activity
import android.os.Handler
import android.os.Looper
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * F-73 / T-60 — Google's In-App Review, by the app's own channel.
 *
 * The pub.dev `in_app_review` plugin (2.0.12, its latest) still applies
 * `kotlin-android`, and Flutter 3.50 warns that future versions will refuse to
 * build an app with such a plugin. Its Android half is two calls into Play's
 * review library, so the app carries them itself — the same move F-80 made for
 * the Install Referrer (InstallReferrerChannel.kt).
 *
 * The Dart side (`lib/services/review_prompt_service.dart`, PlayInAppReviewer)
 * asks only on the Android production store build, behind every floor in
 * `ReviewPromptRules`; it treats any failure as "no review this time".
 *
 *   * `isAvailable` — whether Play can hand out a review flow on this device
 *     now (a missing Play Store or a sideload answers false). Never an error.
 *   * `requestReview` — asks for the flow and launches it. Play says nothing
 *     about whether the sheet appeared or the reader reviewed — by design, so
 *     the app cannot gate anything on it — so success is a null either way;
 *     only a flow Play refused to hand out is an error.
 *
 * Each reply is sent exactly once and on the main thread, as the engine
 * requires.
 */
class InAppReviewChannel(private val activity: Activity) {
    companion object {
        const val CHANNEL = "app.entrelares/in_app_review"
        const val IS_AVAILABLE = "isAvailable"
        const val REQUEST_REVIEW = "requestReview"
    }

    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                IS_AVAILABLE -> isAvailable(Once(result))
                REQUEST_REVIEW -> requestReview(Once(result))
                else -> result.notImplemented()
            }
        }
    }

    private fun isAvailable(result: Once) {
        try {
            ReviewManagerFactory.create(activity.applicationContext)
                .requestReviewFlow()
                .addOnCompleteListener { task -> result.success(task.isSuccessful) }
        } catch (ignored: Throwable) {
            result.success(false)
        }
    }

    private fun requestReview(result: Once) {
        try {
            val manager = ReviewManagerFactory.create(activity.applicationContext)
            manager.requestReviewFlow().addOnCompleteListener { request ->
                if (!request.isSuccessful) {
                    result.error("unavailable", "Play did not hand out a review flow")
                    return@addOnCompleteListener
                }
                try {
                    manager.launchReviewFlow(activity, request.result)
                        .addOnCompleteListener { result.success(null) }
                } catch (ignored: Throwable) {
                    result.error("launch", "the review flow did not launch")
                }
            }
        } catch (ignored: Throwable) {
            result.error("unavailable", "Play's review library is not reachable")
        }
    }

    /** One reply per call, always posted to the main thread. */
    private inner class Once(private val result: MethodChannel.Result) {
        private val replied = AtomicBoolean(false)

        fun success(value: Any?) {
            if (replied.compareAndSet(false, true)) main.post { result.success(value) }
        }

        fun error(code: String, message: String) {
            if (replied.compareAndSet(false, true)) main.post { result.error(code, message, null) }
        }
    }
}
