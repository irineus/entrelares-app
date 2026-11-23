pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // T-60: 9.3.3, not the 3.50.1 template's 9.3.1 — 9.3.1's lint dies on the
    // JavaDoc of in_app_purchase_android and firebase_core (NoSuchMethodError
    // in JavaDocParser) and takes every release build (qa-preview, the Play
    // bundle) with it. The debug build never runs lintVital, so only a release
    // build shows it.
    id("com.android.application") version "9.3.3" apply false
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
    // F-09: reads the per-flavor google-services.json (src/dev, src/prod) and
    // generates the Firebase resource values the messaging SDK initializes from.
    // Both files are PUBLIC client config — the secret half of F-09 is the
    // service account, and that one never leaves the Supabase secret store.
    id("com.google.gms.google-services") version "4.4.3" apply false
}

include(":app")
