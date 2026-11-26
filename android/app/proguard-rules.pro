# Flutter Engine & Play Core Deferred Components (optional in Flutter)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**

# TensorFlow Lite / LiteRT
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Google ML Kit (On-device Segmentation & Face Detection)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**

# Google Mobile Ads (AdMob)
-keep class com.google.android.gms.ads.** { *; }
