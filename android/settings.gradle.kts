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
    id("com.android.application") version "9.0.1" apply false
    // Legacy Kotlin Gradle Plugin (KGP). Kept on the classpath because the app
    // and its plugins still build through AGP 9's legacy Kotlin path while
    // `android.builtInKotlin=false` (see android/gradle.properties). Required by
    // flutter_dynamic_icon_plus and receive_sharing_intent until they migrate;
    // remove it once every plugin uses AGP's built-in Kotlin.
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
    id("com.google.gms.google-services") version "4.5.0" apply false
    // Uploads the release mapping/symbol files so Crashlytics can deobfuscate
    // stack traces. Must be applied after the Google Services plugin.
    id("com.google.firebase.crashlytics") version "3.0.8" apply false
}

include(":app")
