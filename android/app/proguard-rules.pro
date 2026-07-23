# R8/ProGuard keep rules for the release build (isMinifyEnabled = true).
#
# These are intentionally broad: the app has no secrets to protect via
# obfuscation, so the goal is a smaller APK without breaking the two native
# plugins that load classes reflectively (ML Kit text recognition, camera).
# If a release build crashes or the scan pipeline misbehaves, the fastest
# rollback is `isMinifyEnabled = false` in build.gradle.kts.

# ---- Flutter engine / embedding / plugins ----
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# ---- Google ML Kit text recognition (google_mlkit_text_recognition) ----
# The on-device recognizer pulls in model + native bridge classes that R8
# cannot see are used; keep the ML Kit and GMS vision surfaces.
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-dontwarn com.google.android.gms.**

# ---- camera plugin (CameraX) ----
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**
