import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Processes android/app/google-services.json into the app's resources.
    // Must be applied after com.android.application.
    id("com.google.gms.google-services")
    // Deobfuscates Crashlytics stack traces. Must be applied after the Google
    // Services plugin.
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing credentials
// ---------------------------------------------------------------------------
//
// Read from `android/key.properties` — a file that is **gitignored** (see the
// root `.gitignore` and `android/.gitignore`). It holds the upload
// keystore's passwords and must never be committed.
//
// Both the keystore and this file are produced by
// `tool/create_upload_keystore.ps1`, which a developer on a new machine runs
// once: they are not synced between machines, by design.
//
// `storeFile` is resolved relative to *this* module (`android/app/`), which
// is why the property holds a bare file name.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

/**
 * Reads a mandatory entry from `key.properties`.
 *
 * Failing here with a readable message beats a `ClassCastException` from a
 * `null` further down, or — worse — a release bundle that silently falls back
 * to an unusable signing identity.
 */
fun requiredKeystoreKey(name: String): String =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException(
            "android/key.properties is missing the '$name' entry. " +
                "Regenerate it with: powershell -File tool/create_upload_keystore.ps1",
        )

android {
    namespace = "com.routenote.routenote"
    // Pin the platform API explicitly: receive_sharing_intent 1.9.0 (needed for
    // built-in Kotlin) compiles against API 37, and AGP requires consumers to
    // compile against at least the same API level. `maxOf` keeps us at Flutter's
    // default if a future Flutter release raises it further.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.routenote.routenote"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // local_auth and quick_actions require API 24+.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // `maybeCreate` keeps this idempotent: AGP may already expose a
        // "release" signing config, and creating it twice would fail the build.
        maybeCreate("release").apply {
            if (hasReleaseKeystore) {
                keyAlias = requiredKeystoreKey("keyAlias")
                keyPassword = requiredKeystoreKey("keyPassword")
                storeFile = file(requiredKeystoreKey("storeFile"))
                storePassword = requiredKeystoreKey("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Signed with the upload keystore whenever `android/key.properties`
            // exists. Without it the build falls back to the debug key so that
            // a fresh clone can still produce a runnable release build; such a
            // bundle is rejected by Play, which is the intended signal.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "android/key.properties not found — the release build is signed " +
                        "with the DEBUG key. Run tool/create_upload_keystore.ps1 " +
                        "before shipping.",
                )
                signingConfigs.getByName("debug")
            }

            // R8 code shrinking plus resource shrinking.
            //
            // The Flutter Gradle plugin already turns both on for app builds and
            // contributes the matching ProGuard rules (the Android defaults, the
            // engine rules, and this module's `proguard-rules.pro`). They are
            // pinned explicitly here so the release build type never depends on
            // that default and so the intent is visible in the project file.
            isMinifyEnabled = true
            isShrinkResources = true

            // Safety net: R8 without rule files silently strips code that is
            // only reached by reflection — the Flutter plugin registrant and
            // the JNI bridge, among others. The Flutter plugin has already
            // contributed its files by the time this block runs, so an empty
            // list means something is wrong with the plugin setup. Refuse to
            // build rather than ship a bundle that fails at runtime.
            if (proguardFiles.isEmpty()) {
                throw GradleException(
                    "R8 is enabled for the release build but no ProGuard rule files " +
                        "are configured. The Flutter Gradle plugin normally contributes " +
                        "them; check that dev.flutter.flutter-gradle-plugin is applied.",
                )
            }
        }
    }
}

dependencies {
    // Import the Firebase BoM: it pins compatible versions for every Firebase
    // Android library below, so no explicit versions are needed there.
    implementation(platform("com.google.firebase:firebase-bom:35.0.0"))

    // Firebase SDKs used by the app (versions pinned by the BoM above):
    // Crashlytics for crash/ANR reporting, Analytics for breadcrumb logs.
    // https://firebase.google.com/docs/crashlytics/android/get-started#add-sdk
    implementation("com.google.firebase:firebase-crashlytics")
    implementation("com.google.firebase:firebase-analytics")

    // https://firebase.google.com/docs/android/setup#available-libraries
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
