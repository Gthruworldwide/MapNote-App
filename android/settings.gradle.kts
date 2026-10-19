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
    id("com.android.application") version "9.2.1" apply false
    // Legacy Kotlin Gradle Plugin (KGP). Built-in Kotlin is enabled
    // (`android.builtInKotlin=true` — see android/gradle.properties), so no
    // module applies KGP in the default build; it stays on the classpath only so
    // the conditional `apply plugin: 'kotlin-android'` fallbacks in
    // firebase_* / workmanager_android / the vendored flutter_dynamic_icon_plus
    // still resolve when a build opts back into the legacy path.
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
    id("com.google.gms.google-services") version "4.5.0" apply false
    // Uploads the release mapping/symbol files so Crashlytics can deobfuscate
    // stack traces. Must be applied after the Google Services plugin.
    id("com.google.firebase.crashlytics") version "3.0.8" apply false
}

include(":app")
