import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // F-09 — must come AFTER the Android plugin, and after the Flutter one so
    // the flavors it resolves google-services.json against already exist.
    id("com.google.gms.google-services")
}

// T-55: release signing reads path/passwords from android/key.properties
// (git-ignored; the keystores live OUTSIDE the repo — permanent rule 1). The
// file carries per-flavor entries: `dev.*` points at the dedicated sideload
// keystore, `prod.*` at the PRODUCT's upload keystore (F-54) — the Play package
// only accepts that upload signature (stage-0 finding), so the two must never
// swap. Both now live in `~/keystores/`: the upload key spent its life inside
// `entrelares-app/store/`, which T-56 archived, and a publishing key cannot
// depend on a clone nobody keeps any more (moved 25/08/2026).
val keyPropertiesFile = rootProject.file("key.properties")
val hasKeyProperties = keyPropertiesFile.exists()
val keyProperties = Properties().apply {
    if (hasKeyProperties) {
        FileInputStream(keyPropertiesFile).use { load(it) }
    }
}

android {
    namespace = "com.entrelares.entrelares_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // minSdk 26: the product's locked floor (same as the console pilot).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeyProperties) {
            for (flavor in listOf("dev", "prod")) {
                create(flavor) {
                    storeFile = file(keyProperties.getProperty("$flavor.storeFile"))
                    storePassword = keyProperties.getProperty("$flavor.storePassword")
                    keyAlias = keyProperties.getProperty("$flavor.keyAlias")
                    keyPassword = keyProperties.getProperty("$flavor.keyPassword")
                }
            }
        }
    }

    // Stage 3 (T-53): environments are BUILD VARIANTS — the Supabase singleton
    // initializes once per process (pilot lesson 8), so there is no runtime
    // switcher by construction. Every build now REQUIRES --flavor.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            // The spike id, DIFFERENT from the Play package on purpose: the
            // dev APK coexists with the store-installed app on the owner's
            // device (and its launcher label tells them apart).
            applicationId = "com.entrelares.flutter"
            manifestPlaceholders["appName"] = "Entrelares Dev"
            if (hasKeyProperties) {
                signingConfig = signingConfigs.getByName("dev")
            }
        }
        create("prod") {
            dimension = "env"
            // The Play package — stage 0 proved it accepts a Flutter build
            // with the same upload signature (the prod.* keystore in
            // key.properties MUST be the product's upload keystore).
            applicationId = "com.entrelares.app"
            manifestPlaceholders["appName"] = "Entrelares"
            if (hasKeyProperties) {
                signingConfig = signingConfigs.getByName("prod")
            }
        }
    }

    buildTypes {
        release {
            // Release signing comes from the FLAVOR (per-flavor keystores,
            // T-55); debug builds keep the default debug keystore via the
            // debug build type. No fallback: a release APK signed with this
            // machine's debug keys would force the device to uninstall (and
            // lose local data) to accept any other build — pilot lesson 2.2.
        }
    }
}

// Fail fast: without key.properties a release build would come out unsigned
// (flavors carry no signingConfig), which only surfaces at install time.
if (!hasKeyProperties) {
    tasks.configureEach {
        if (name.contains("Release")) {
            doFirst {
                throw GradleException(
                    "key.properties not found at ${keyPropertiesFile.path} — " +
                        "release builds require the T-55 keystores. " +
                        "See README 'Assinatura (release)'."
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
