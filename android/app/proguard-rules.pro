# flutter_webrtc uses reflection and JNI bindings into libwebrtc — keep
# its classes intact under R8/ProGuard minification.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# SQLCipher / sqlite3 native bindings.
-keep class net.zetetic.** { *; }
-keep class org.sqlite.** { *; }
-dontwarn net.zetetic.**

# flutter_secure_storage uses AndroidX Security's EncryptedSharedPreferences.
-keep class androidx.security.crypto.** { *; }

# Keep Flutter plugin registrant classes.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
