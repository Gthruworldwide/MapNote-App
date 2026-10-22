# App-specific R8 rules for the release build.
#
# The Flutter Gradle plugin contributes the Android default rules
# (`proguard-android-optimize.txt`), the engine rules
# (`flutter_proguard_rules.pro`) and this file to the release build type.
#
# Everything below covers a dependency that is reached **by reflection**, which
# R8 cannot trace on its own. Each rule is therefore load-bearing: without it
# the release build compiles cleanly and then fails at runtime.

# --- Flutter plugin registration -------------------------------------------
# The engine registers the app's plugins reflectively:
#
#   Class.forName("io.flutter.plugins.GeneratedPluginRegistrant")
#       .getDeclaredMethod("registerWith", FlutterEngine.class)
#       .invoke(null, engine);
#
# Neither the class name nor the method name is a static reference, so R8 has
# no way to see them. Without this rule the release build would start with no
# plugins registered at all — every method channel silently dead.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# --- Tink, via flutter_secure_storage ---------------------------------------
# `flutter_secure_storage` can store the encrypted vault's key material with
# Google Tink, whose shaded Protobuf Javalite runtime reads its fields
# reflectively. Tink ships this exact rule in `META-INF/proguard/protobuf.pro`;
# repeating it here keeps the vault readable even if that packaged file is not
# picked up from the dependency.
#
# The pinned `flutter_secure_storage` release does not currently reach Tink on
# Android (R8 drops it entirely), so this rule costs nothing today. It is here
# so that a future version which *does* use Tink cannot silently lose the
# vault's key material to the shrinker.
-keepclassmembers class * extends com.google.crypto.tink.shaded.protobuf.GeneratedMessageLite {
    <fields>;
}

# --- JNI bridge (jni / jni_flutter) -----------------------------------------
# `PortProxyBuilder` resolves its proxy interfaces with `Class.forName`, so
# those names have to survive obfuscation.
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
