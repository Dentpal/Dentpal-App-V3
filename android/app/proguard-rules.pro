# ========================================
# Google ML Kit - Text Recognition
# ========================================
# Keep all ML Kit classes and their native methods
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }

# Keep Google Play Services classes used by ML Kit
-keep class com.google.android.gms.** { *; }
-keep interface com.google.android.gms.** { *; }

# Keep ML Kit Text Recognition specifically
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }

# Keep Face Detection
-keep class com.google.mlkit.vision.face.** { *; }

# ========================================
# Google Play Services - Dynamic Features
# ========================================
# ML Kit uses dynamic module loading
-keep class com.google.android.gms.dynamite.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ========================================
# Native Methods
# ========================================
# Keep native methods used by ML Kit
-keepclasseswithmembernames class * {
    native <methods>;
}

# ========================================
# Suppress Warnings
# ========================================
# Suppress warnings for optional ML Kit language support we don't use
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Suppress TensorFlow warnings (not used, but ML Kit internally references it)
-dontwarn org.tensorflow.lite.**

# ========================================
# Optimization Settings
# ========================================
# Don't optimize ML Kit classes - they need exact implementation
-keep,allowobfuscation,allowoptimization class com.google.mlkit.** { *; }

# Keep annotations used by ML Kit
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ========================================
# Camera and Image Processing
# ========================================
# Keep classes used for camera image processing
-keep class androidx.camera.** { *; }
-keep interface androidx.camera.** { *; }

# Keep CameraX implementation classes
-keep class io.flutter.plugins.camerax.** { *; }
-keep class io.flutter.plugins.camera.** { *; }

# Keep image processing utilities that handle buffer conversions
-keepclassmembers class io.flutter.plugins.camerax.ImageProxyUtils {
    public *;
}

# Keep native buffer handling methods
-keepclassmembers class * {
    native <methods>;
}

# Preserve line numbers for debugging camera issues
-keepattributes SourceFile,LineNumberTable